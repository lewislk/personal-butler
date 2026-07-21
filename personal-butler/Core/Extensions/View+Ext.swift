//
//  View+Ext.swift
//

import SwiftUI

extension View {
    /// 通用卡片外观（纯白 + 极轻阴影 + 12px 圆角）
    func card(padding: CGFloat = 16, corner: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color(hex: 0xF0F2F5), lineWidth: 1)
            )
            .shadow(color: AppColorTheme.cardShadow, radius: 4, x: 0, y: 2)
    }

    /// 只做卡片风格但不加 padding（子视图自己控制布局）
    func plainCard(corner: CGFloat = 12) -> some View {
        self.background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color(hex: 0xF0F2F5), lineWidth: 1)
            )
            .shadow(color: AppColorTheme.cardShadow, radius: 4, x: 0, y: 2)
    }
}
