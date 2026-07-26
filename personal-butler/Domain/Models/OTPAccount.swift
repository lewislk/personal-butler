//
//  OTPAccount.swift
//

import Foundation
import SwiftData

@Model
final class OTPAccount {
    @Attribute(.unique) var id: UUID
    var issuer: String        // 服务商，如 GitHub
    var accountName: String   // 邮箱/账号
    var secretKeychainKey: String  // TOTP 密钥仅存 Keychain
    var period: Int
    var digits: Int
    var order: Int
    /// 是否为首次安装时灌入的 Demo 数据；用户自添的为 false。
    var isDemo: Bool

    init(id: UUID = UUID(), issuer: String, accountName: String,
         secretKeychainKey: String, period: Int = 30, digits: Int = 6, order: Int = 0,
         isDemo: Bool = false) {
        self.id = id
        self.issuer = issuer
        self.accountName = accountName
        self.secretKeychainKey = secretKeychainKey
        self.period = period
        self.digits = digits
        self.order = order
        self.isDemo = isDemo
    }
}
