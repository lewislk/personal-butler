//
//  LaunchView.swift
//  启动过渡页：首启完成 SeedData 等一次性初始化前展示，避免主页白屏。
//  由 PersonalButlerApp 控制显隐；完成后由外层淡入切到 RootView。
//

import SwiftUI

struct LaunchView: View {
    /// 呼吸动画状态（logo 轻微缩放，暗示"正在准备"）
    @State private var breathing = false

    var body: some View {
        ZStack {
            // 主色 → 白 的柔和渐变背景，与主页色调一致
            LinearGradient(
                colors: [
                    AppColorTheme.primary.opacity(0.10),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Logo：圆角方块 + SF Symbol，与 AppIcon 视觉呼应
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppColorTheme.primary)
                        .frame(width: 96, height: 96)
                        .shadow(color: AppColorTheme.primary.opacity(0.25),
                                radius: 16, x: 0, y: 8)

                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 46, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(breathing ? 1.03 : 1.0)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: breathing
                )

                VStack(spacing: 6) {
                    Text("私人管家")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColorTheme.text)
                    Text("你的生活，尽在掌握")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColorTheme.textSub)
                }

                Spacer()

                // 底部加载指示
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColorTheme.primary)
                    Text("正在准备中…")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColorTheme.textSub)
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear { breathing = true }
    }
}

#Preview {
    LaunchView()
}
