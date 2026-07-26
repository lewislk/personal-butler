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

    // 位置字段（全 Optional，兼容老数据；latitude / longitude 视为整体）
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?

    init(id: UUID = UUID(), name: String, emoji: String = "🍽️",
         rating: Int = 4, tags: [String] = [], remark: String = "",
         date: Date = .init(), category: FoodCategory = .chinese,
         placeName: String? = nil, address: String? = nil,
         latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.rating = rating
        self.tagsRaw = tags.joined(separator: ",")
        self.remark = remark
        self.date = date
        self.categoryRaw = category.rawValue
        self.placeName = placeName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    var tags: [String] {
        tagsRaw.split(separator: ",").map { String($0) }
    }

    var category: FoodCategory { FoodCategory(rawValue: categoryRaw) ?? .chinese }

    /// 经纬度成对齐备才视为"有位置"
    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// 列表 / 卡片单行位置展示优先级：正式地址 → POI 名称
    var displayLocation: String? { address ?? placeName }
}
