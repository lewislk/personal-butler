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

    init(id: UUID = UUID(), title: String, remark: String = "",
         startDate: Date, endDate: Date? = nil, isAllDay: Bool = false,
         reminderMinutesBefore: Int? = nil,
         colorTag: ScheduleColorTag = .blue, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.remark = remark
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.reminderMinutesBefore = reminderMinutesBefore
        self.colorTagRaw = colorTag.rawValue
        self.isCompleted = isCompleted
    }

    var colorTag: ScheduleColorTag { ScheduleColorTag(rawValue: colorTagRaw) ?? .blue }
}
