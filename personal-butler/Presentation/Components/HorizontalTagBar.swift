//
//  HorizontalTagBar.swift
//  横向筛选标签（密码分类、美食分类、菜谱分类通用）
//

import SwiftUI

struct HorizontalTagBar: View {
    let items: [String]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedIndex = idx }
                    } label: {
                        Text(item)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .foregroundStyle(selectedIndex == idx ? .white : AppColorTheme.textSub)
                            .background(
                                Capsule().fill(selectedIndex == idx ? AppColorTheme.primary : AppColorTheme.bg)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
