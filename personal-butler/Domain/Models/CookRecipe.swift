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
    var ingredients: String   // 多行
    var steps: String         // 多行
    var tips: String

    init(id: UUID = UUID(), name: String, emoji: String = "🍲",
         difficulty: CookDifficulty = .easy, minutes: Int = 30,
         category: CookCategory = .home,
         ingredients: String = "", steps: String = "", tips: String = "") {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.difficultyRaw = difficulty.rawValue
        self.minutes = minutes
        self.categoryRaw = category.rawValue
        self.ingredients = ingredients
        self.steps = steps
        self.tips = tips
    }

    var difficulty: CookDifficulty { CookDifficulty(rawValue: difficultyRaw) ?? .easy }
    var category: CookCategory { CookCategory(rawValue: categoryRaw) ?? .home }
}
