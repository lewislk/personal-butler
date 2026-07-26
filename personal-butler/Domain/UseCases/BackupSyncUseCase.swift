//
//  BackupSyncUseCase.swift
//  组装 / 解析同步 JSON、局域网 HTTP 请求（骨架）
//

import Foundation
import SwiftData

@MainActor
final class BackupSyncUseCase {
    let context: ModelContext
    init(context: ModelContext) { self.context = context }

    /// 组装完整同步包（SwiftData + Keychain 敏感数据）
    func buildPayload() throws -> SyncPayload {
        let meta = SyncMeta(deviceId: AppSyncConfig.deviceID,
                            syncTimestamp: Int64(Date().timeIntervalSince1970),
                            appVersion: "1.0.0",
                            dataVersion: 5)

        let todos = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let schedules = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
        let annis = (try? context.fetch(FetchDescriptor<Anniversary>())) ?? []
        let pwds = (try? context.fetch(FetchDescriptor<PasswordAccount>())) ?? []
        let otps = (try? context.fetch(FetchDescriptor<OTPAccount>())) ?? []
        let foods = (try? context.fetch(FetchDescriptor<FoodRecord>())) ?? []
        let recipes = (try? context.fetch(FetchDescriptor<CookRecipe>())) ?? []
        let carts = (try? context.fetch(FetchDescriptor<CookCart>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let modules = (try? context.fetch(FetchDescriptor<AppModule>())) ?? []

        let data = SyncData(
            todoList: todos.map {
                SyncTodoDTO(id: $0.id.uuidString, name: $0.name,
                            source: $0.sourceRaw,
                            dueDate: $0.dueDate?.timeIntervalSince1970,
                            isDone: $0.isDone,
                            createdAt: $0.createdAt.timeIntervalSince1970,
                            taskType: $0.taskTypeRaw,
                            recipeId: $0.recipeId?.uuidString,
                            expectedIngredients: $0.expectedIngredients.isEmpty ? nil : $0.expectedIngredients,
                            checkedIngredients: $0.checkedIngredients.isEmpty ? nil : $0.checkedIngredients)
            },
            scheduleList: schedules.map {
                SyncScheduleDTO(id: $0.id.uuidString, title: $0.title,
                                remark: $0.remark,
                                startDate: $0.startDate.timeIntervalSince1970,
                                endDate: $0.endDate?.timeIntervalSince1970,
                                isAllDay: $0.isAllDay,
                                reminderMinutesBefore: $0.reminderMinutesBefore,
                                colorTag: $0.colorTagRaw,
                                isCompleted: $0.isCompleted,
                                isDemo: $0.isDemo)
            },
            anniversaryList: annis.map {
                SyncAnniDTO(id: $0.id.uuidString, name: $0.name,
                            date: $0.date.timeIntervalSince1970,
                            isLunar: $0.isLunar, type: $0.typeRaw,
                            reminderDaysBefore: $0.reminderDaysBefore,
                            emoji: $0.emoji, isDemo: $0.isDemo)
            },
            passwordList: pwds.map {
                SyncPasswordDTO(id: $0.id.uuidString, platform: $0.platform,
                                account: $0.account, typeText: $0.typeText,
                                category: $0.categoryRaw,
                                passwordPlain: KeychainManager.load($0.passwordKeychainKey) ?? "",
                                updatedAt: $0.updatedAt.timeIntervalSince1970,
                                isDemo: $0.isDemo)
            },
            otpList: otps.map {
                SyncOTPDTO(id: $0.id.uuidString, issuer: $0.issuer,
                           accountName: $0.accountName,
                           secretPlain: KeychainManager.load($0.secretKeychainKey) ?? "",
                           period: $0.period, digits: $0.digits, order: $0.order,
                           isDemo: $0.isDemo)
            },
            foodRecordList: foods.map {
                SyncFoodDTO(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                            rating: $0.rating, tags: $0.tags, remark: $0.remark,
                            date: $0.date.timeIntervalSince1970, category: $0.categoryRaw,
                            placeName: $0.placeName, address: $0.address,
                            latitude: $0.latitude, longitude: $0.longitude,
                            iconImageBase64: $0.iconImage?.base64EncodedString(),
                            isDemo: $0.isDemo)
            },
            cookRecipeList: recipes.map {
                SyncRecipeDTO(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                              difficulty: $0.difficultyRaw, minutes: $0.minutes,
                              category: $0.categoryRaw,
                              ingredientsLegacyRaw: $0.ingredientsLegacyRaw,
                              ingredients: $0.ingredients.sorted { $0.order < $1.order }
                                  .map { SyncIngredientDTO(id: $0.id.uuidString,
                                                            name: $0.name, amount: $0.amount,
                                                            order: $0.order) },
                              steps: $0.steps, tips: $0.tips,
                              iconImageBase64: $0.iconImage?.base64EncodedString(),
                              isDemo: $0.isDemo)
            },
            cartList: carts.map {
                SyncCartDTO(id: $0.id.uuidString,
                            recipeId: $0.recipe?.id.uuidString ?? "",
                            servings: $0.servings,
                            addedAt: $0.addedAt.timeIntervalSince1970)
            },
            noteList: notes.map {
                SyncNoteDTO(id: $0.id.uuidString, title: $0.title, content: $0.content,
                            tag: $0.tag,
                            createdAt: $0.createdAt.timeIntervalSince1970,
                            updatedAt: $0.updatedAt.timeIntervalSince1970,
                            isDemo: $0.isDemo)
            },
            appModuleList: modules.map {
                SyncModuleDTO(id: $0.id, name: $0.name, tag: $0.tag,
                              iconSystemName: $0.iconSystemName,
                              order: $0.order, comingSoon: $0.comingSoon)
            },
            setting: [:]
        )
        return SyncPayload(syncMeta: meta, data: data)
    }

    // MARK: - 网络（局域网 HTTP，无外网访问）

    /// 与服务端约定的错误码（`middleware/auth.go` · `Code*`）。
    /// 只在这里集中列出，避免各调用点散布魔法数字。
    enum ServerCode {
        static let ok             = 0
        static let headerMissing  = 1001
        static let tokenInvalid   = 1002
        static let jsonParseError = 1003
        static let storeFailed    = 2001
        static let noBackup       = 2002
        static let syncInProgress = 2003
        static let internalErr    = 5000
    }

    enum SyncError: Error, LocalizedError {
        case serverEmpty
        case network(String)
        case decode
        /// 服务端返回 code=2003：同一 device 已有一次 upload/clear 事务在跑。
        /// 客户端应提示用户"上一次同步还在进行"，稍后重试。
        case inProgress
        /// 服务端返回 code=2002：该 device 尚未在服务端有过 upload 记录。
        /// 常见于首次使用、切换到新设备、或用户主动 clear 过之后。
        case noBackup
        /// 其它非零 code 的兜底：透传服务端 msg，方便排障。
        case server(code: Int, msg: String)
        var errorDescription: String? {
            switch self {
            case .serverEmpty: return "请先配置同步服务器地址"
            case .network(let m): return "网络错误：\(m)"
            case .decode: return "服务端返回数据无法解析"
            case .inProgress: return "上一次同步还在进行，请稍后重试"
            case .noBackup: return "服务器上还没有该设备的备份，请先上传一次"
            case .server(let code, let msg): return "服务端错误（\(code)）：\(msg)"
            }
        }
    }

    /// 统一响应包装：所有 /sync/* 接口都遵循 `{code, msg, data?}`。
    private struct APIResp<T: Decodable>: Decodable {
        var code: Int
        var msg: String
        var data: T?
    }
    /// data 无意义（upload / clear）时用这个占位。
    private struct Empty: Decodable {}

    private func makeRequest(path: String, method: String, timeout: TimeInterval = 25) throws -> URLRequest {
        guard !AppSyncConfig.host.isEmpty else { throw SyncError.serverEmpty }
        let url = URL(string: "http://\(AppSyncConfig.host):\(AppSyncConfig.defaultPort)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppSyncConfig.deviceID, forHTTPHeaderField: "X-Device-ID")
        req.setValue(AppSyncConfig.token, forHTTPHeaderField: "X-Sync-Token")
        return req
    }

    /// 把服务端 `{code, msg, data}` 里的 code 翻译成对应的 SyncError。
    /// code == 0 直接返回 data（可能为 nil，由调用方决定是否算错）。
    private func decodeResponse<T: Decodable>(_ data: Data, as _: T.Type) throws -> APIResp<T> {
        guard let wrap = try? JSONDecoder().decode(APIResp<T>.self, from: data) else {
            throw SyncError.decode
        }
        switch wrap.code {
        case ServerCode.ok:
            return wrap
        case ServerCode.syncInProgress:
            throw SyncError.inProgress
        case ServerCode.noBackup:
            throw SyncError.noBackup
        default:
            throw SyncError.server(code: wrap.code, msg: wrap.msg)
        }
    }

    /// 上传完整 SyncPayload 到服务端。
    ///
    /// **图片体积评估**：每张 512px JPEG 0.7 ≈ 30-60KB，base64 后膨胀 33%。
    /// 几十张美食 / 菜谱图片很容易让 payload 上到几 MB；25s 默认超时在弱
    /// WiFi 信号下不够稳，这里固定 180s 给传输留足余量。
    ///
    /// **进度回调**：`progress` 在主线程之外的 URLSession delegate 队列触发，
    /// 调用方应自行切回主线程更新 UI（用 `Task { @MainActor in ... }` 即可）。
    /// 不传 progress 时退化为 fire-and-forget 的等价语义。
    ///
    /// **不破坏同步契约**：URL / Header / Body 格式都不变，仅传输方式
    /// 从 `URLSession.data(for:)` 换成 `URLSession.upload(for:from:delegate:)`，
    /// 服务端无感知。
    func upload(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let payload = try buildPayload()
        let body = try JSONEncoder().encode(payload)
        var req = try makeRequest(path: "/sync/upload", method: "POST", timeout: 180)
        // 显式带 Content-Length：部分服务端 / 反代（如 nginx）需要它来识别请求体，
        // URLSession.upload(for:from:) 会自动设置，这里只是双保险。
        req.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        let delegate = ProgressDelegate(onProgress: progress)
        let (data, _) = try await URLSession.shared.upload(for: req, from: body, delegate: delegate)
        _ = try decodeResponse(data, as: Empty.self)
    }

    /// 通用进度 delegate：同时覆盖上传（didSendBodyData）和下载（didReceiveData / didFinishCollecting）。
    ///
    /// 用 NSObject 子类而非 actor，是因为 URLSession delegate 协议要求 Objective-C 兼容类型。
    ///
    /// **下载进度注意事项**：
    /// - `didReceiveData` 是 URLSessionDataDelegate 的方法，仅当响应带 `Content-Length` 时
    ///   `totalBytesExpectedToReceive` 才 > 0；服务端默认 JSON 响应 Gin 会自动设置 Content-Length，
    ///   所以本场景能正常拿到 fraction。
    /// - 若服务端开了 chunked transfer encoding（gzip / stream），totalBytesExpectedToReceive
    ///   会是 -1，fraction 计算会被 `guard` 跳过，UI 退化为"恢复中…"无百分比状态（不会崩）。
    private final class ProgressDelegate: NSObject, URLSessionDataDelegate {
        let onProgress: (@Sendable (Double) -> Void)?

        init(onProgress: (@Sendable (Double) -> Void)?) {
            self.onProgress = onProgress
        }

        // 上传：URLSessionTaskDelegate
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64,
                        totalBytesExpectedToSend: Int64) {
            guard totalBytesExpectedToSend > 0, let onProgress else { return }
            let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            onProgress(min(max(fraction, 0), 1))
        }

        // 下载：URLSessionDataDelegate
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive data: Data) {
            // 用 task.countOfBytesReceived + task.countOfBytesExpectedToReceive 而不是
            // 累加 data.count，避免和系统内部缓冲计数冲突。
            let received = max(dataTask.countOfBytesReceived, 0)
            let expected = dataTask.countOfBytesExpectedToReceive
            guard expected > 0, let onProgress else { return }
            let fraction = Double(received) / Double(expected)
            onProgress(min(max(fraction, 0), 1))
        }
    }

    func download(progress: (@Sendable (Double) -> Void)? = nil) async throws -> SyncPayload {
        // 与 upload 同步：图片 base64 嵌入 JSON 后体积同样会上到几 MB。
        // 25s 在弱 WiFi / 蜂窝热点下不够稳，提到 180s 与 upload 对齐。
        let req = try makeRequest(path: "/sync/download", method: "GET", timeout: 180)
        let delegate = ProgressDelegate(onProgress: progress)
        let (data, _) = try await URLSession.shared.data(for: req, delegate: delegate)
        let wrap = try decodeResponse(data, as: SyncPayload.self)
        guard let payload = wrap.data else { throw SyncError.decode }
        return payload
    }

    /// 覆盖式恢复到本地：先清空所有 @Model（含关联的 Keychain 敏感项），再按 payload 批量重建。
    ///
    /// 语义对齐服务端 `/sync/upload`（DELETE + INSERT）。整个过程在同一个
    /// `ModelContext` 事务里，最后一次 `context.save()`；中途抛错则 `context.rollback()`
    /// 回滚 SwiftData 变更。
    ///
    /// **autosave 保护**：restore 期间关闭 `context.autosaveEnabled`，避免 clear 完 SwiftUI
    /// 让出主线程时 autosave 提前落盘导致 rollback 撤不回。整个 restore 结束再恢复原值。
    ///
    /// **Keychain 处理**：
    /// - 恢复前遍历本地 `PasswordAccount` / `OTPAccount`，收集其 Keychain key（不立即删，等 save 成功后再清）
    /// - 恢复时按 CLAUDE.md §5 规范生成新的 `pwd.<uuid>` / `otp.<uuid>` key，UUID 直接复用 @Model.id 保证幂等
    /// - 若中途失败，已写入的 Keychain 项由 `newKeychainKeys` 记录，回滚时一并清理；旧 Keychain 不动，保留可用
    ///
    /// **未同步的项目**：`AppSetting` 目前未纳入 `SyncPayload.setting`（AGENTS.md §7），
    /// restore 也不动它，保留本地设置。
    func restore(_ payload: SyncPayload) throws {
        // 1. 收集要清理的 Keychain key（在 delete SwiftData 前拿到，否则数据没了就找不着 key 了）
        let existingPwds = (try? context.fetch(FetchDescriptor<PasswordAccount>())) ?? []
        let existingOTPs = (try? context.fetch(FetchDescriptor<OTPAccount>())) ?? []
        let oldKeychainKeys: [String] =
            existingPwds.map { $0.passwordKeychainKey }
            + existingOTPs.map { $0.secretKeychainKey }

        // 2. 追踪本次 restore 新写入的 Keychain key，出错时反向清理
        var newKeychainKeys: [String] = []

        // 3. 关闭 autosave，保证 clear + rebuild 是原子的
        let originalAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = originalAutosave }

        do {
            // 4. 清空所有可同步的 @Model（不动 AppSetting）
            try clearAllSyncedEntities()

            // 5. 按 payload 重建
            try rebuild(from: payload.data, newKeychainKeys: &newKeychainKeys)

            // 6. 提交
            try context.save()

            // 7. save 成功后再删旧 Keychain key（保证恢复失败时旧密码还能用）
            oldKeychainKeys.forEach { KeychainManager.delete($0) }
        } catch {
            // 回滚 SwiftData 变更
            context.rollback()
            // 已经写进 Keychain 的新 key 反向清掉
            newKeychainKeys.forEach { KeychainManager.delete($0) }
            throw error
        }
    }

    /// 清空所有参与同步的 @Model；不含 AppSetting（未纳入同步契约）。
    ///
    /// **不用 `context.delete(model:)` 批量删除** —— 那是绕过 context pending queue 的直接
    /// 落存储操作，`context.rollback()` 撤不回；一旦 rebuild 中途抛错，用户数据会永久丢失。
    /// 逐条 `context.delete(obj)` 走 context 事务，save 前的任何 throw 都能被 rollback 干净撤销。
    /// 数据量级（几百~几千条）下开销可忽略。
    private func clearAllSyncedEntities() throws {
        try deleteAll(FetchDescriptor<TodoItem>())
        try deleteAll(FetchDescriptor<ScheduleEvent>())
        try deleteAll(FetchDescriptor<Anniversary>())
        try deleteAll(FetchDescriptor<PasswordAccount>())
        try deleteAll(FetchDescriptor<OTPAccount>())
        try deleteAll(FetchDescriptor<FoodRecord>())
        try deleteAll(FetchDescriptor<CookIngredient>())
        try deleteAll(FetchDescriptor<CookCart>())
        try deleteAll(FetchDescriptor<CookRecipe>())
        try deleteAll(FetchDescriptor<Note>())
        try deleteAll(FetchDescriptor<AppModule>())
    }

    private func deleteAll<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws {
        let objects = try context.fetch(descriptor)
        objects.forEach { context.delete($0) }
    }

    /// 按 SyncData 各 list 反序列化并 insert 到 context。
    /// Keychain 敏感明文先写 Keychain，把新 key 记入 `newKeychainKeys` 供出错回滚。
    private func rebuild(from data: SyncData, newKeychainKeys: inout [String]) throws {
        for x in data.todoList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            let m = TodoItem(
                id: uuid, name: x.name,
                source: TodoSource(rawValue: x.source) ?? .manual,
                dueDate: x.dueDate.map { Date(timeIntervalSince1970: $0) },
                isDone: x.isDone,
                createdAt: Date(timeIntervalSince1970: x.createdAt)
            )
            // v4 新字段（Optional，旧服务端可能不带）
            if let tt = x.taskType, let type = TodoTaskType(rawValue: tt) {
                m.taskTypeRaw = type.rawValue
            }
            if let rid = x.recipeId, let rUUID = UUID(uuidString: rid) {
                m.recipeId = rUUID
            }
            if let exp = x.expectedIngredients {
                m.expectedIngredientsRaw = exp.joined(separator: ",")
            }
            if let chk = x.checkedIngredients {
                m.checkedIngredientsRaw = chk.joined(separator: ",")
            }
            context.insert(m)
        }

        for x in data.scheduleList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            let m = ScheduleEvent(
                id: uuid, title: x.title, remark: x.remark,
                startDate: Date(timeIntervalSince1970: x.startDate),
                endDate: x.endDate.map { Date(timeIntervalSince1970: $0) },
                isAllDay: x.isAllDay,
                reminderMinutesBefore: x.reminderMinutesBefore,
                colorTag: ScheduleColorTag(rawValue: x.colorTag) ?? .blue,
                isCompleted: x.isCompleted,
                isDemo: x.isDemo ?? false
            )
            context.insert(m)
        }

        for x in data.anniversaryList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            let m = Anniversary(
                id: uuid, name: x.name,
                date: Date(timeIntervalSince1970: x.date),
                isLunar: x.isLunar,
                type: AnniversaryType(rawValue: x.type) ?? .yearly,
                reminderDaysBefore: x.reminderDaysBefore,
                emoji: x.emoji, isDemo: x.isDemo ?? false
            )
            context.insert(m)
        }

        for x in data.passwordList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            // Keychain key 规范：pwd.<uuid>，UUID 直接复用 @Model.id，保证幂等（同一记录多次恢复不产生孤儿 key）
            let key = "pwd." + uuid.uuidString
            KeychainManager.save(x.passwordPlain, for: key)
            newKeychainKeys.append(key)
            let m = PasswordAccount(
                id: uuid, platform: x.platform, account: x.account,
                typeText: x.typeText,
                category: PasswordCategory(rawValue: x.category) ?? .custom,
                passwordKeychainKey: key,
                updatedAt: Date(timeIntervalSince1970: x.updatedAt),
                isDemo: x.isDemo ?? false
            )
            context.insert(m)
        }

        for x in data.otpList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            let key = "otp." + uuid.uuidString
            KeychainManager.save(x.secretPlain, for: key)
            newKeychainKeys.append(key)
            let m = OTPAccount(
                id: uuid, issuer: x.issuer, accountName: x.accountName,
                secretKeychainKey: key,
                period: x.period, digits: x.digits, order: x.order,
                isDemo: x.isDemo ?? false
            )
            context.insert(m)
        }

        for x in data.foodRecordList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            // 解 base64 → Data；解码失败视为无图片（保留 emoji 兜底显示）
            let iconData: Data? = {
                guard let b64 = x.iconImageBase64, !b64.isEmpty else { return nil }
                return Data(base64Encoded: b64)
            }()
            let m = FoodRecord(
                id: uuid, name: x.name, emoji: x.emoji,
                rating: x.rating, tags: x.tags, remark: x.remark,
                date: Date(timeIntervalSince1970: x.date),
                category: FoodCategory(rawValue: x.category) ?? .chinese,
                placeName: x.placeName, address: x.address,
                latitude: x.latitude, longitude: x.longitude,
                iconImage: iconData, isDemo: x.isDemo ?? false
            )
            context.insert(m)
        }

        // 先建 recipe → ingredients，再单独建 cart（避免 cart 引用未建好的 recipe）
        var recipeMap: [String: CookRecipe] = [:]
        for x in data.cookRecipeList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            let iconData: Data? = {
                guard let b64 = x.iconImageBase64, !b64.isEmpty else { return nil }
                return Data(base64Encoded: b64)
            }()
            let m = CookRecipe(
                id: uuid, name: x.name, emoji: x.emoji,
                difficulty: CookDifficulty(rawValue: x.difficulty) ?? .easy,
                minutes: x.minutes,
                category: CookCategory(rawValue: x.category) ?? .home,
                ingredientsLegacyRaw: x.ingredientsLegacyRaw,
                steps: x.steps, tips: x.tips,
                iconImage: iconData, isDemo: x.isDemo ?? false
            )
            context.insert(m)
            recipeMap[x.id] = m
            for ing in x.ingredients {
                guard let ingUUID = UUID(uuidString: ing.id) else { continue }
                let im = CookIngredient(id: ingUUID, name: ing.name,
                                        amount: ing.amount, order: ing.order)
                im.recipe = m
                context.insert(im)
            }
        }

        // 重建 CookCart（依赖 recipeMap）
        if let carts = data.cartList {
            for c in carts {
                guard let cUUID = UUID(uuidString: c.id) else { continue }
                let recipe = recipeMap[c.recipeId]
                let cm = CookCart(id: cUUID, recipe: recipe,
                                  servings: c.servings,
                                  addedAt: Date(timeIntervalSince1970: c.addedAt))
                context.insert(cm)
            }
        }

        for x in data.noteList {
            guard let uuid = UUID(uuidString: x.id) else { continue }
            let m = Note(
                id: uuid, title: x.title, content: x.content, tag: x.tag,
                createdAt: Date(timeIntervalSince1970: x.createdAt),
                updatedAt: Date(timeIntervalSince1970: x.updatedAt),
                isDemo: x.isDemo ?? false
            )
            context.insert(m)
        }

        for x in data.appModuleList {
            // AppModule.id: String（稳定标识），直接用
            let m = AppModule(
                id: x.id, name: x.name, tag: x.tag,
                iconSystemName: x.iconSystemName,
                order: x.order, comingSoon: x.comingSoon
            )
            context.insert(m)
        }

        // AppSetting 未纳入同步契约（AGENTS.md §7），跳过
    }
}
