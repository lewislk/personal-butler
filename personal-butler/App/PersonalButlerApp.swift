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

        let elapsed = Date().timeIntervalSince(start)
        let minShow: TimeInterval = 0.5
        if elapsed < minShow {
            try? await Task.sleep(nanoseconds: UInt64((minShow - elapsed) * 1_000_000_000))
        }

        modelContainer = container
    }
}
