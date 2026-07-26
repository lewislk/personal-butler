//
//  Anniversary.swift
//

import Foundation
import SwiftData

enum AnniversaryType: String, Codable, CaseIterable {
    case yearly       // 每年重复
    case cumulative   // 累计天数

    var label: String {
        switch self {
        case .yearly: return "每年重复"
        case .cumulative: return "累计天数"
        }
    }
}

@Model
final class Anniversary {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: Date
    var isLunar: Bool
    var typeRaw: String
    var reminderDaysBefore: Int?
    var emoji: String
    /// 是否为首次安装时灌入的 Demo 数据；用户自添的为 false。
    var isDemo: Bool

    init(id: UUID = UUID(), name: String, date: Date, isLunar: Bool = false,
         type: AnniversaryType = .yearly, reminderDaysBefore: Int? = 7,
         emoji: String = "🎉", isDemo: Bool = false) {
        self.id = id
        self.name = name
        self.date = date
        self.isLunar = isLunar
        self.typeRaw = type.rawValue
        self.reminderDaysBefore = reminderDaysBefore
        self.emoji = emoji
        self.isDemo = isDemo
    }

    var type: AnniversaryType { AnniversaryType(rawValue: typeRaw) ?? .yearly }
}
