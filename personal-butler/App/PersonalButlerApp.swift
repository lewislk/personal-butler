//
//  PersonalButlerApp.swift
//  私人管家 主入口
//

import SwiftUI
import SwiftData

@main
struct PersonalButlerApp: App {
    @StateObject private var env = AppEnvironment()

    /// ModelContainer 延迟到 bootstrap 里异步创建，避免首启建库/迁移
    /// 时同步阻塞 App 属性初始化 → SwiftUI 主 Scene 迟迟拿不到首帧，
    /// 用户看到的是系统 UILaunchScreen（若未配置就是白屏）而不是 LaunchView。
    @State private var modelContainer: ModelContainer?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let container = modelContainer {
                    RootView()
                        .environmentObject(env)
                        .environment(\.locale, .init(identifier: "zh-Hans"))
                        .tint(AppColorTheme.primary)
                        .modelContainer(container)
                        .transition(.opacity)
                } else {
                    LaunchView()
                        .environment(\.locale, .init(identifier: "zh-Hans"))
                        .transition(.opacity)
                        .task {
                            await bootstrap()
                        }
                }
            }
            .animation(.easeOut(duration: 0.5), value: modelContainer == nil)
        }
    }

    /// 冷启初始化：SwiftData 建库/迁移 + SeedData 首启灌数据。
    /// 全部走后台任务，SwiftUI 首帧可以立即渲染 LaunchView。
    /// 保底展示 0.5s，避免二次启动 bootstrap 秒完导致切换太生硬。
    ///
    /// **v2→v3 迁移策略**：
    /// - 挂载 `FoodRecordMigrationPlan` 尝试正常迁移
    /// - 失败（rating Int→Double 类型变更无法自动完成）时清库重建
    ///   （spec 明确"存量数据强转，不考虑迁移"）
    @MainActor
    private func bootstrap() async {
        let start = Date()

        let container: ModelContainer = await Task.detached(priority: .userInitiated) {
            let schema = Schema([
                TodoItem.self,
                ScheduleEvent.self,
                Anniversary.self,
                PasswordAccount.self,
                OTPAccount.self,
                FoodRecord.self,
                CookRecipe.self,
                CookIngredient.self,
                CookCart.self,
                Note.self,
                AppModule.self,
                AppSetting.self
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

            // 尝试正常迁移
            if let ok = try? ModelContainer(
                for: schema,
                migrationPlan: FoodRecordMigrationPlan.self,
                configurations: [config]
            ) {
                return ok
            }

            // Fallback：清除本地 store 后重建
            // 定位默认 SwiftData store 文件并删除；SwiftData 会在下一次
            // ModelContainer 初始化时新建空库
            let fm = FileManager.default
            if let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil, create: false) {
                // SwiftData 默认 store 文件名为 default.store（含 -shm / -wal 附属文件）
                for name in ["default.store", "default.store-shm", "default.store-wal"] {
                    let url = appSupport.appendingPathComponent(name)
                    try? fm.removeItem(at: url)
                }
            }

            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("SwiftData 初始化失败（清库后重建仍失败）: \(error)")
            }
        }.value

        SeedData.ensureSeeded(in: container.mainContext)
        migrateKeychainToSwiftData(context: container.mainContext)
        migrateCookIngredients(context: container.mainContext)
        cleanupFinishedCookTasks(context: container.mainContext)

        let elapsed = Date().timeIntervalSince(start)
        let minShow: TimeInterval = 0.5
        if elapsed < minShow {
            try? await Task.sleep(nanoseconds: UInt64((minShow - elapsed) * 1_000_000_000))
        }

        modelContainer = container
    }

    /// 旧版 CookRecipe.ingredients 是多行文本 String。
    /// v4 起改为结构化 [CookIngredient] 关系，旧字段保留为 ingredientsLegacyRaw。
    /// 此函数把旧多行文本按行解析为 CookIngredient（整行作为 name，不强行解析数量/单位）。
    /// 幂等：仅对 ingredients 关系为空且 ingredientsLegacyRaw 非空的 recipe 执行；
    /// 迁移成功后清空 ingredientsLegacyRaw，避免下次冷启时把用户已删除的食材"复活"。
    @MainActor
    private func migrateCookIngredients(context: ModelContext) {
        let recipes = (try? context.fetch(FetchDescriptor<CookRecipe>())) ?? []
        var changed = false
        for r in recipes {
            guard r.ingredients.isEmpty, !r.ingredientsLegacyRaw.isEmpty else { continue }
            let lines = r.ingredientsLegacyRaw.split(separator: "\n")
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let ing = CookIngredient(name: trimmed, order: i)
                ing.recipe = r
                context.insert(ing)
            }
            r.ingredientsLegacyRaw = ""
            changed = true
        }
        if changed { try? context.save() }
    }

    /// 清理已完成的烹饪任务（prep / cook）：完成日期早于今天的，启动时删除。
    /// 判断依据：taskType != .none && isDone && dueDate < 今天起点。
    /// 当天完成的不删（让用户能在主页看到完成状态）；第二天冷启时清理。
    @MainActor
    private func cleanupFinishedCookTasks(context: ModelContext) {
        let todos = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let todayStart = Date().startOfDay
        var changed = false
        for t in todos {
            guard t.taskType != .none,
                  t.isDone,
                  let due = t.dueDate,
                  due < todayStart else { continue }
            context.delete(t)
            changed = true
        }
        if changed { try? context.save() }
    }

    /// 一次性迁移：把 Keychain 里的密码明文 / TOTP 密钥搬到 SwiftData 新字段。
    ///
    /// 背景：v5 之前密码明文 / OTP 密钥只存 Keychain，SwiftData 只存 key。
    /// 同步时 `buildPayload` 现取 Keychain，一旦 Keychain 因模拟器重置 / restore
    /// 写空串等原因返回 nil，上传的 `passwordPlain` 就变成空串，服务端 GORM
    /// 零值跳过落 NULL，download 又把空串写回 Keychain，形成自循环空值。
    ///
    /// 改造后明文直接落 SwiftData，Keychain 不再参与同步链路。本函数在冷启时
    /// 把老用户 Keychain 里的明文回填到新字段，幂等：`passwordPlain` 已有值则跳过。
    @MainActor
    private func migrateKeychainToSwiftData(context: ModelContext) {
        var migratedKeys: [String] = []
        var changed = false

        let pwds = (try? context.fetch(FetchDescriptor<PasswordAccount>())) ?? []
        for p in pwds {
            guard p.passwordPlain.isEmpty, !p.passwordKeychainKey.isEmpty else { continue }
            if let plain = KeychainManager.load(p.passwordKeychainKey), !plain.isEmpty {
                p.passwordPlain = plain
                migratedKeys.append(p.passwordKeychainKey)
                changed = true
            }
        }

        let otps = (try? context.fetch(FetchDescriptor<OTPAccount>())) ?? []
        for o in otps {
            guard o.secretPlain.isEmpty, !o.secretKeychainKey.isEmpty else { continue }
            if let secret = KeychainManager.load(o.secretKeychainKey), !secret.isEmpty {
                o.secretPlain = secret
                migratedKeys.append(o.secretKeychainKey)
                changed = true
            }
        }

        if changed { try? context.save() }
        // 迁移成功后清理 Keychain 旧条目，避免残留孤儿密钥
        migratedKeys.forEach { KeychainManager.delete($0) }
    }
}
