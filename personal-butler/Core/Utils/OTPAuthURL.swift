//
//  OTPAuthURL.swift
//  otpauth://totp/... URL 解析
//
//  Google Authenticator 迁移 URL（otpauth-migration://）暂不支持。
//

import Foundation

struct OTPAuthURL {
    let issuer: String       // 服务商（如 GitHub）
    let accountName: String  // 账号名（如 user@example.com）
    let secretBase32: String // TOTP 密钥（Base32）
    let period: Int          // 步长秒
    let digits: Int          // 位数

    /// 解析 `otpauth://totp/Issuer:account?secret=XXX&issuer=Issuer&period=30&digits=6`
    /// 兼容：
    ///  - label 中 `Issuer:account` 与 query 里 `issuer=` 二选一或同时存在
    ///  - label 前带一个 `/`（URLComponents.path 会以 `/` 起头）
    ///  - `%20` / `%3A` 等百分号编码
    ///  - 未指定 period / digits 时回退默认 30 / 6
    static func parse(_ raw: String) -> OTPAuthURL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "otpauth",
              (comps.host?.lowercased() == "totp") else { return nil }

        let items = comps.queryItems ?? []
        func q(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name.lowercased() }?.value
        }

        guard let secretRaw = q("secret"), !secretRaw.isEmpty else { return nil }
        // Base32 只允许 A-Z / 2-7 / = 填充；把可能出现的空格 / 小写归一
        let secret = secretRaw
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        // label = comps.path 去掉起首的 "/"
        let label = comps.path.hasPrefix("/") ? String(comps.path.dropFirst()) : comps.path
        var issuerFromLabel: String?
        var account = label
        if let colonIdx = label.firstIndex(of: ":") {
            issuerFromLabel = String(label[..<colonIdx])
            account = String(label[label.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
        }

        let issuer = (q("issuer") ?? issuerFromLabel ?? "").trimmingCharacters(in: .whitespaces)
        let period = q("period").flatMap { Int($0) } ?? 30
        let digits = q("digits").flatMap { Int($0) } ?? 6

        return OTPAuthURL(issuer: issuer.isEmpty ? "未命名" : issuer,
                          accountName: account,
                          secretBase32: secret,
                          period: period,
                          digits: digits)
    }
}
