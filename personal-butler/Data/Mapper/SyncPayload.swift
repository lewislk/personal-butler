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
}

struct SyncAnniDTO: Codable {
    var id: String
    var name: String
    var date: Double
    var isLunar: Bool
    var type: String
    var reminderDaysBefore: Int?
    var emoji: String
}

struct SyncPasswordDTO: Codable {
    var id: String
    var platform: String
    var account: String
    var typeText: String
    var category: String
    var passwordPlain: String     // 同步时随包携带明文（仅局域网内网）
    var updatedAt: Double
}

struct SyncOTPDTO: Codable {
    var id: String
    var issuer: String
    var accountName: String
    var secretPlain: String
    var period: Int
    var digits: Int
    var order: Int
}

struct SyncFoodDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var rating: Int
    var tags: [String]
    var remark: String
    var date: Double
    var category: String
}

struct SyncRecipeDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var difficulty: String
    var minutes: Int
    var category: String
    var ingredients: String
    var steps: String
    var tips: String
}

struct SyncNoteDTO: Codable {
    var id: String
    var title: String
    var content: String
    var tag: String
    var createdAt: Double
    var updatedAt: Double
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
