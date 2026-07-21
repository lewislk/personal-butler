//
//  TodoItemRow.swift
//  待办条目 · 原型对齐
//

import SwiftUI

struct TodoItemRow: View {
    let name: String
    let source: String
    let timeLabel: String
    var urgent: Bool = false
    var isDone: Bool = false
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(isDone ? AppColorTheme.primary : Color(hex: 0xC4C7CC), lineWidth: 1.5)
                        .background(Circle().fill(isDone ? AppColorTheme.primary : .clear))
                        .frame(width: 20, height: 20)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14))
                    .foregroundStyle(isDone ? Color(hex: 0xB0B4BA) : AppColorTheme.text)
                    .strikethrough(isDone, color: Color(hex: 0xB0B4BA))
                Text("来源 · \(source)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
            }
            Spacer(minLength: 8)
            Text(timeLabel)
                .font(.system(size: 12))
                .foregroundStyle(urgent ? AppColorTheme.danger : AppColorTheme.textSub)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
