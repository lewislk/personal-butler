//
//  SegmentedPill.swift
//  分段切换 pill（原型待办、纪念日、日程复用）
//

import SwiftUI

struct SegmentedPill<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    var background: Color = Color(hex: 0xF0F2F5)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = item.value }
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: selection == item.value ? .semibold : .medium))
                        .foregroundStyle(selection == item.value ? AppColorTheme.text : AppColorTheme.textSub)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == item.value ? .white : .clear)
                                .shadow(color: selection == item.value ? .black.opacity(0.06) : .clear,
                                        radius: 2, x: 0, y: 1)
                        )
                        // 未选中态 fill 是 .clear，SwiftUI 默认不对透明像素做命中测试，
                        // 会导致点击非中心区域落空；显式 contentShape 把整段扩成可点击区域
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// 小号 pill（在 TodoCard 头部使用，白底透明容器）
struct MiniSegmentedPill<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = item.value }
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: selection == item.value ? .semibold : .medium))
                        .foregroundStyle(selection == item.value ? AppColorTheme.text : AppColorTheme.textSub)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == item.value ? .white : .clear)
                                .shadow(color: selection == item.value ? .black.opacity(0.06) : .clear,
                                        radius: 2, x: 0, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
