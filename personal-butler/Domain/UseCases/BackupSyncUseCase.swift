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
                            dataVersion: 1)

        let todos = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let schedules = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
        let annis = (try? context.fetch(FetchDescriptor<Anniversary>())) ?? []
        let pwds = (try? context.fetch(FetchDescriptor<PasswordAccount>())) ?? []
        let otps = (try? context.fetch(FetchDescriptor<OTPAccount>())) ?? []
        let foods = (try? context.fetch(FetchDescriptor<FoodRecord>())) ?? []
        let recipes = (try? context.fetch(FetchDescriptor<CookRecipe>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let modules = (try? context.fetch(FetchDescriptor<AppModule>())) ?? []

        let data = SyncData(
            todoList: todos.map {
                SyncTodoDTO(id: $0.id.uuidString, name: $0.name,
                            source: $0.sourceRaw,
                            dueDate: $0.dueDate?.timeIntervalSince1970,
                            isDone: $0.isDone,
                            createdAt: $0.createdAt.timeIntervalSince1970)
            },
            scheduleList: schedules.map {
                SyncScheduleDTO(id: $0.id.uuidString, title: $0.title,
                                remark: $0.remark,
                                startDate: $0.startDate.timeIntervalSince1970,
                                endDate: $0.endDate?.timeIntervalSince1970,
                                isAllDay: $0.isAllDay,
                                reminderMinutesBefore: $0.reminderMinutesBefore,
                                colorTag: $0.colorTagRaw,
                                isCompleted: $0.isCompleted)
            },
            anniversaryList: annis.map {
                SyncAnniDTO(id: $0.id.uuidString, name: $0.name,
                            date: $0.date.timeIntervalSince1970,
                            isLunar: $0.isLunar, type: $0.typeRaw,
                            reminderDaysBefore: $0.reminderDaysBefore,
                            emoji: $0.emoji)
            },
            passwordList: pwds.map {
                SyncPasswordDTO(id: $0.id.uuidString, platform: $0.platform,
                                account: $0.account, typeText: $0.typeText,
                                category: $0.categoryRaw,
                                passwordPlain: KeychainManager.load($0.passwordKeychainKey) ?? "",
                                updatedAt: $0.updatedAt.timeIntervalSince1970)
            },
            otpList: otps.map {
                SyncOTPDTO(id: $0.id.uuidString, issuer: $0.issuer,
                           accountName: $0.accountName,
                           secretPlain: KeychainManager.load($0.secretKeychainKey) ?? "",
                           period: $0.period, digits: $0.digits, order: $0.order)
            },
            foodRecordList: foods.map {
                SyncFoodDTO(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                            rating: $0.rating, tags: $0.tags, remark: $0.remark,
                            date: $0.date.timeIntervalSince1970, category: $0.categoryRaw)
            },
            cookRecipeList: recipes.map {
                SyncRecipeDTO(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                              difficulty: $0.difficultyRaw, minutes: $0.minutes,
                              category: $0.categoryRaw, ingredients: $0.ingredients,
                              steps: $0.steps, tips: $0.tips)
            },
            noteList: notes.map {
                SyncNoteDTO(id: $0.id.uuidString, title: $0.title, content: $0.content,
                            tag: $0.tag,
                            createdAt: $0.createdAt.timeIntervalSince1970,
                            updatedAt: $0.updatedAt.timeIntervalSince1970)
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

    enum SyncError: Error, LocalizedError {
        case serverEmpty
        case network(String)
        case decode
        var errorDescription: String? {
            switch self {
            case .serverEmpty: return "请先配置同步服务器地址"
            case .network(let m): return "网络错误：\(m)"
            case .decode: return "服务端返回数据无法解析"
            }
        }
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard !AppSyncConfig.host.isEmpty else { throw SyncError.serverEmpty }
        let url = URL(string: "http://\(AppSyncConfig.host):\(AppSyncConfig.defaultPort)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppSyncConfig.deviceID, forHTTPHeaderField: "X-Device-ID")
        req.setValue(AppSyncConfig.token, forHTTPHeaderField: "X-Sync-Token")
        return req
    }

    func upload() async throws {
        let payload = try buildPayload()
        var req = try makeRequest(path: "/sync/upload", method: "POST")
        req.httpBody = try JSONEncoder().encode(payload)
        _ = try await URLSession.shared.data(for: req)
    }

    func download() async throws -> SyncPayload {
        let req = try makeRequest(path: "/sync/download", method: "GET")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Wrap: Codable { var code: Int; var msg: String; var data: SyncPayload? }
        guard let wrap = try? JSONDecoder().decode(Wrap.self, from: data),
              let payload = wrap.data else { throw SyncError.decode }
        return payload
    }

    /// 覆盖式恢复到本地
    func restore(_ payload: SyncPayload) throws {
        // 简化实现：这里仅示范，MVP 版本不做真正覆盖以避免误删。
        // 生产可先清空后按批插入。
        _ = payload
        try context.save()
    }
}
