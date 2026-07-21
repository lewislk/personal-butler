//
//  FoodRecord.swift
//

import Foundation
import SwiftData

enum FoodCategory: String, Codable, CaseIterable {
    case all, hotpot, milktea, chinese, japanese, coffee

    var label: String {
        switch self {
        case .all: return "全部"
        case .hotpot: return "火锅"
        case .milktea: return "奶茶"
        case .chinese: return "中餐"
        case .japanese: return "日料"
        case .coffee: return "咖啡"
        }
    }
}

@Model
final class FoodRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var rating: Int
    var tagsRaw: String       // 逗号分隔
    var remark: String
    var date: Date
    var categoryRaw: String

    init(id: UUID = UUID(), name: String, emoji: String = "🍽️",
         rating: Int = 4, tags: [String] = [], remark: String = "",
         date: Date = .init(), category: FoodCategory = .chinese) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.rating = rating
        self.tagsRaw = tags.joined(separator: ",")
        self.remark = remark
        self.date = date
        self.categoryRaw = category.rawValue
    }

    var tags: [String] {
        tagsRaw.split(separator: ",").map { String($0) }
    }

    var category: FoodCategory { FoodCategory(rawValue: categoryRaw) ?? .chinese }
}
