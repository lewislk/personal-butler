//
//  CookCart.swift
//  烹饪车项（用户加车未提交）
//

import Foundation
import SwiftData

@Model
final class CookCart {
    @Attribute(.unique) var id: UUID
    var recipe: CookRecipe?           // 多对一
    var servings: Int                 // 份数，默认 1
    var addedAt: Date

    init(id: UUID = UUID(), recipe: CookRecipe?, servings: Int = 1,
         addedAt: Date = .init()) {
        self.id = id
        self.recipe = recipe
        self.servings = servings
        self.addedAt = addedAt
    }
}
