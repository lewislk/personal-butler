//
//  AppColorTheme.swift
//  全局主题色（严格对齐原型图）
//

import SwiftUI

enum AppColorTheme {
    static let primary   = Color(hex: 0x4A86E8)          // 主色
    static let text      = Color(hex: 0x1D1D1F)          // 文字主色
    static let textSub   = Color(hex: 0x757575)          // 文字次要
    static let bg        = Color(hex: 0xF5F7FA)          // 卡片底色
    static let border    = Color(hex: 0xECEEF2)          // 分割线
    static let danger    = Color(hex: 0xE55757)
    static let success   = Color(hex: 0x48BB78)
    static let warn      = Color(hex: 0xE58A32)

    static let cardShadow = Color.black.opacity(0.06)
}
