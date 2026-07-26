//
//  ScheduleEvent.swift
//

import Foundation
import SwiftData

enum ScheduleColorTag: String, Codable, CaseIterable {
    case blue, green, orange
}

@Model
final class ScheduleEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var remark: String
    var startDate: Date
    var endDate: Date?
    var isAllDay: Bool
    var reminderMinutesBefore: Int?
    var colorTagRaw: String
    var isCompleted: Bool
    /// 是否为首次安装时灌入的 Demo 数据；用户自添的为 false。
    /// 「我的 → 清理Demo数据」只删除 isDemo==true 的记录。
    var isDemo: Bool

    init(id: UUID = UUID(), title: String, remark: String = "",
         startDate: Date, endDate: Date? = nil, isAllDay: Bool = false,
         reminderMinutesBefore: Int? = nil,
         colorTag: ScheduleColorTag = .blue, isCompleted: Bool = false,
         isDemo: Bool = false) {
        self.id = id
        self.title = title
        self.remark = remark
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.reminderMinutesBefore = reminderMinutesBefore
        self.colorTagRaw = colorTag.rawValue
        self.isCompleted = isCompleted
        self.isDemo = isDemo
    }

    var colorTag: ScheduleColorTag { ScheduleColorTag(rawValue: colorTagRaw) ?? .blue }
}
