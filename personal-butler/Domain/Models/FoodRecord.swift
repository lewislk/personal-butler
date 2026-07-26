//
//  FoodRecord.swift
//

import Foundation
import SwiftData

enum FoodCategory: String, Codable, CaseIterable {
    case all, hotpot, milktea, chinese, western, streetfood, japanese, coffee

    var label: String {
        switch self {
        case .all: return "全部"
        case .hotpot: return "火锅"
        case .milktea: return "奶茶"
        case .chinese: return "中餐"
        case .western: return "西餐"
        case .streetfood: return "大排档"
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
    var rating: Double        // 半星支持：0.0..5.0，step 0.5；iconImage 缺失时 emoji 作为兜底
    var tagsRaw: String       // 逗号分隔
    var remark: String
    var date: Date
    var updatedAt: Date       // 创建/更新时间戳；列表排序用，新增字段带默认值兼容旧数据
    var categoryRaw: String

    // 位置字段（全 Optional）
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?

    // 图片图标（可选）：走 external storage，SQLite 只存引用
    @Attribute(.externalStorage) var iconImage: Data?

    /// 是否为首次安装时灌入的 Demo 数据；用户自添的为 false。
    var isDemo: Bool

    init(id: UUID = UUID(), name: String, emoji: String = "🍽️",
         rating: Double = 4.0, tags: [String] = [], remark: String = "",
         date: Date = .init(), category: FoodCategory = .chinese,
         placeName: String? = nil, address: String? = nil,
         latitude: Double? = nil, longitude: Double? = nil,
         iconImage: Data? = nil, isDemo: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.rating = rating
        self.tagsRaw = tags.joined(separator: ",")
        self.remark = remark
        self.date = date
        self.updatedAt = date
        self.categoryRaw = category.rawValue
        self.placeName = placeName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.iconImage = iconImage
        self.isDemo = isDemo
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
