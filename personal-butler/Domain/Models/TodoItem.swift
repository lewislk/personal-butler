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

/// 任务类型：普通 / 准备食材 / 烹饪
enum TodoTaskType: String, Codable, CaseIterable {
    case none   // 普通待办（含日程/纪念日/手动/旧 cook 待办）
    case prep   // 准备食材
    case cook   // 烹饪
    var label: String {
        switch self {
        case .none: return ""
        case .prep: return "准备"
        case .cook: return "烹饪"
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

    // v4 新增字段（都带默认值/Optional，兼容旧数据）
    var taskTypeRaw: String = TodoTaskType.none.rawValue
    var recipeId: UUID? = nil
    /// prep 任务应有食材名称列表，逗号分隔，提交时冻结
    var expectedIngredientsRaw: String = ""
    /// prep 任务已勾选食材名称列表，逗号分隔
    var checkedIngredientsRaw: String = ""

    init(id: UUID = UUID(), name: String, source: TodoSource = .manual,
         dueDate: Date? = nil, isDone: Bool = false, createdAt: Date = .init(),
         taskType: TodoTaskType = .none,
         recipeId: UUID? = nil,
         expectedIngredients: [String] = [],
         checkedIngredients: [String] = []) {
        self.id = id
        self.name = name
        self.sourceRaw = source.rawValue
        self.dueDate = dueDate
        self.isDone = isDone
        self.createdAt = createdAt
        self.taskTypeRaw = taskType.rawValue
        self.recipeId = recipeId
        self.expectedIngredientsRaw = expectedIngredients.joined(separator: ",")
        self.checkedIngredientsRaw = checkedIngredients.joined(separator: ",")
    }

    var source: TodoSource { TodoSource(rawValue: sourceRaw) ?? .manual }
    var taskType: TodoTaskType { TodoTaskType(rawValue: taskTypeRaw) ?? .none }

    /// 应有食材名称列表（按 expectedIngredientsRaw split 得到）
    var expectedIngredients: [String] {
        expectedIngredientsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 已勾选食材名称列表
    var checkedIngredients: [String] {
        checkedIngredientsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
