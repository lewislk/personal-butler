//
//  TodoItem.swift
//

import Foundation
import SwiftData

/// 待办来源：日程 / 纪念日 / 烹饪
enum TodoSource: String, Codable, CaseIterable {
    case schedule
    case anniversary
    case cook
    case manual
    var label: String {
        switch self {
        case .schedule: return "日程"
        case .anniversary: return "纪念日"
        case .cook: return "烹饪"
        case .manual: return "手动"
        }
    }
}

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var sourceRaw: String
    var dueDate: Date?
    var isDone: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, source: TodoSource = .manual,
         dueDate: Date? = nil, isDone: Bool = false, createdAt: Date = .init()) {
        self.id = id
        self.name = name
        self.sourceRaw = source.rawValue
        self.dueDate = dueDate
        self.isDone = isDone
        self.createdAt = createdAt
    }

    var source: TodoSource { TodoSource(rawValue: sourceRaw) ?? .manual }
}
