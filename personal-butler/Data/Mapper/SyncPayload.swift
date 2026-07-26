//
//  SyncPayload.swift
//  同步 JSON 数据结构（对齐 CLAUDE.md §四）
//

import Foundation

struct SyncMeta: Codable {
    var deviceId: String
    var syncTimestamp: Int64
    var appVersion: String
    var dataVersion: Int
}

struct SyncTodoDTO: Codable {
    var id: String
    var name: String
    var source: String
    var dueDate: Double?
    var isDone: Bool
    var createdAt: Double
    // v4 新增字段
    var taskType: String?
    var recipeId: String?
    var expectedIngredients: [String]?
    var checkedIngredients: [String]?
}

struct SyncScheduleDTO: Codable {
    var id: String
    var title: String
    var remark: String
    var startDate: Double
    var endDate: Double?
    var isAllDay: Bool
    var reminderMinutesBefore: Int?
    var colorTag: String
    var isCompleted: Bool
    // v5 新增：标记首启 Demo 数据，客户端「清理Demo数据」按钮按此过滤
    var isDemo: Bool?
}

struct SyncAnniDTO: Codable {
    var id: String
    var name: String
    var date: Double
    var isLunar: Bool
    var type: String
    var reminderDaysBefore: Int?
    var emoji: String
    // v5 新增
    var isDemo: Bool?
}

struct SyncPasswordDTO: Codable {
    var id: String
    var platform: String
    var account: String
    var typeText: String
    var category: String
    var passwordPlain: String     // 同步时随包携带明文（仅局域网内网）
    var updatedAt: Double
    // v5 新增
    var isDemo: Bool?
}

struct SyncOTPDTO: Codable {
    var id: String
    var issuer: String
    var accountName: String
    var secretPlain: String
    var period: Int
    var digits: Int
    var order: Int
    // v5 新增
    var isDemo: Bool?
}

struct SyncFoodDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var rating: Double            // v3：Int→Double；Codable 天然兼容整数 JSON 解码为 Double
    var tags: [String]
    var remark: String
    var date: Double
    var category: String
    // v2 位置字段
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    // v3 图片图标（base64 编码的 JPEG bytes；nil = 未设置）
    var iconImageBase64: String?
    // v5 新增
    var isDemo: Bool?
}

struct SyncIngredientDTO: Codable {
    var id: String
    var name: String
    var amount: String
    var order: Int
}

struct SyncCartDTO: Codable {
    var id: String
    var recipeId: String
    var servings: Int
    var addedAt: Double
}

struct SyncRecipeDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var difficulty: String
    var minutes: Int
    var category: String
    var ingredientsLegacyRaw: String
    var ingredients: [SyncIngredientDTO]
    var steps: String
    var tips: String
    var iconImageBase64: String?
    // v5 新增
    var isDemo: Bool?
}

struct SyncNoteDTO: Codable {
    var id: String
    var title: String
    var content: String
    var tag: String
    var createdAt: Double
    var updatedAt: Double
    // v5 新增
    var isDemo: Bool?
}

struct SyncModuleDTO: Codable {
    var id: String
    var name: String
    var tag: String
    var iconSystemName: String
    var order: Int
    var comingSoon: Bool
}

struct SyncData: Codable {
    var todoList: [SyncTodoDTO]
    var scheduleList: [SyncScheduleDTO]
    var anniversaryList: [SyncAnniDTO]
    var passwordList: [SyncPasswordDTO]
    var otpList: [SyncOTPDTO]
    var foodRecordList: [SyncFoodDTO]
    var cookRecipeList: [SyncRecipeDTO]
    var cartList: [SyncCartDTO]?
    var noteList: [SyncNoteDTO]
    var appModuleList: [SyncModuleDTO]
    var setting: [String: String]
}

struct SyncPayload: Codable {
    var syncMeta: SyncMeta
    var data: SyncData
}

struct SyncResponse<T: Codable>: Codable {
    var code: Int
    var msg: String
    var data: T?
}
