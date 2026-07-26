//
//  CookRecipe.swift
//

import Foundation
import SwiftData

enum CookCategory: String, Codable, CaseIterable {
    case all, home, noodle, soup, dessert

    var label: String {
        switch self {
        case .all: return "全部菜谱"
        case .home: return "家常菜"
        case .noodle: return "面食"
        case .soup: return "汤羹"
        case .dessert: return "甜品"
        }
    }
}

enum CookDifficulty: String, Codable, CaseIterable {
    case easy, medium, hard
    var label: String {
        switch self {
        case .easy: return "简单"
        case .medium: return "中等"
        case .hard: return "进阶"
        }
    }
}

@Model
final class CookRecipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var difficultyRaw: String
    var minutes: Int
    var categoryRaw: String

    /// 旧版多行文本食材字段（迁移用，不删；新代码请用 `ingredients: [CookIngredient]`）
    var ingredientsLegacyRaw: String
    /// 结构化食材（与 CookIngredient 一对多）
    @Relationship(deleteRule: .cascade) var ingredients: [CookIngredient]
    /// 烹饪车项（与 CookCart 一对多；删除菜谱时 cascade 删除车项）
    @Relationship(deleteRule: .cascade) var cartItems: [CookCart]

    var steps: String         // 多行
    var tips: String

    /// 图片图标（JPEG 二进制，与 FoodRecord 一致）
    @Attribute(.externalStorage) var iconImage: Data?

    init(id: UUID = UUID(), name: String, emoji: String = "🍲",
         difficulty: CookDifficulty = .easy, minutes: Int = 30,
         category: CookCategory = .home,
         ingredientsLegacyRaw: String = "",
         ingredients: [CookIngredient] = [],
         cartItems: [CookCart] = [],
         steps: String = "", tips: String = "",
         iconImage: Data? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.difficultyRaw = difficulty.rawValue
        self.minutes = minutes
        self.categoryRaw = category.rawValue
        self.ingredientsLegacyRaw = ingredientsLegacyRaw
        self.ingredients = ingredients
        self.cartItems = cartItems
        self.steps = steps
        self.tips = tips
        self.iconImage = iconImage
    }

    var difficulty: CookDifficulty { CookDifficulty(rawValue: difficultyRaw) ?? .easy }
    var category: CookCategory { CookCategory(rawValue: categoryRaw) ?? .home }
}
