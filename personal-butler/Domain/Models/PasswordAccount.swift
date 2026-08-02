//
//  PasswordAccount.swift
//

import Foundation
import SwiftData

enum PasswordCategory: String, Codable, CaseIterable {
    case social, office, finance, custom

    var label: String {
        switch self {
        case .social: return "社交"
        case .office: return "办公"
        case .finance: return "金融"
        case .custom: return "自定义"
        }
    }
}

@Model
final class PasswordAccount {
    @Attribute(.unique) var id: UUID
    var platform: String
    var account: String
    var typeText: String      // 展示辅文（例："社交 · 常用"）
    var categoryRaw: String
    /// 密码明文。App 不连外网（仅局域网同步），明文直接落 SwiftData，不再走 Keychain。
    var passwordPlain: String
    /// 历史 Keychain key，已废弃保留兼容；新数据写空串即可。
    var passwordKeychainKey: String
    var updatedAt: Date
    /// 是否为首次安装时灌入的 Demo 数据；用户自添的为 false。
    var isDemo: Bool

    init(id: UUID = UUID(), platform: String, account: String,
         typeText: String = "", category: PasswordCategory = .social,
         passwordPlain: String = "", passwordKeychainKey: String = "",
         updatedAt: Date = .init(), isDemo: Bool = false) {
        self.id = id
        self.platform = platform
        self.account = account
        self.typeText = typeText
        self.categoryRaw = category.rawValue
        self.passwordPlain = passwordPlain
        self.passwordKeychainKey = passwordKeychainKey
        self.updatedAt = updatedAt
        self.isDemo = isDemo
    }

    var category: PasswordCategory { PasswordCategory(rawValue: categoryRaw) ?? .custom }
}
