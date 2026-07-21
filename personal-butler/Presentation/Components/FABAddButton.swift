//
//  FABAddButton.swift
//  右下角圆形悬浮按钮
//

import SwiftUI

struct FABAddButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: UIConstant.fabSize, height: UIConstant.fabSize)
                .background(
                    Circle().fill(AppColorTheme.primary)
                        .shadow(color: AppColorTheme.primary.opacity(0.4), radius: 10, x: 0, y: 6)
                )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }
}
