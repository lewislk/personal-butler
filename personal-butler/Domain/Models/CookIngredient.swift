//
//  CookIngredient.swift
//  菜谱食材子模型（标准化录入）
//

import Foundation
import SwiftData

@Model
final class CookIngredient {
    @Attribute(.unique) var id: UUID
    var recipe: CookRecipe?           // 多对一反向关系
    var name: String                  // "番茄"
    var amount: String                // "2 个" — 数量与单位合并
    var order: Int                    // 录入顺序，列表稳定排序
    var createdAt: Date

    init(id: UUID = UUID(), name: String, amount: String = "", order: Int = 0,
         createdAt: Date = .init()) {
        self.id = id
        self.name = name
        self.amount = amount
        self.order = order
        self.createdAt = createdAt
    }
}
