//
//  SwipeToDeleteRow.swift
//  左滑删除通用组件（ScrollView 场景下的实现，模拟系统 UITableView 交互）
//
//  同一时刻仅一行处于展开态，由父视图通过一个 `openSwipeId` 状态 + 每行的 `isOpen`
//  Binding 实现互斥；父视图在空白点击 / 视图切换时把 `openSwipeId` 置 nil 即可整片收起。
//
//  ⚠️ 实现方式：横向 ScrollView + 自定义吸附，**不要**改回 DragGesture。
//  历史上本组件用 `DragGesture(minimumDistance: 8)` + 方向判定实现左滑，
//  但只要手势被本行识别，外层纵向 ScrollView 的 pan 就再也拿不回来，
//  导致所有列表页（笔记/纪念日/日程/美食/密码）整页无法上下滚动。
//  `.gesture` → `.simultaneousGesture` 也救不回来：SwiftUI 在 onChanged 触发前
//  就已把手势判给本行，onChanged 里对纵向早退为时已晚。
//  改用横向 ScrollView 后，内外两层滚动方向正交，系统天然互不抢手势。
//

import SwiftUI

/// 左滑吸附行为：松手后只停在「完全收起(0)」或「完全展开(actionWidth)」两个位置，
/// 过半即展开，模拟 UITableView 的左滑手感。
private struct SwipeSnapBehavior: ScrollTargetBehavior {
    let actionWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = target.rect.minX > actionWidth / 2 ? actionWidth : 0
    }
}

struct SwipeToDeleteRow<Content: View>: View {
    @Binding var isOpen: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    /// 删除按钮区域宽度（圆形图标 + 左右呼吸间距）
    private let actionWidth: CGFloat = 68
    /// 圆形按钮直径
    private let iconDiameter: CGFloat = 44

    /// 横向滚动位置，用于父视图收起 / 删除后的程序化复位
    @State private var scrollPos = ScrollPosition(edge: .leading)
    /// 当前左滑进度 0...1，驱动灰底与圆角的渐变
    @State private var progress: CGFloat = 0

    /// 行左滑时的淡灰选中背景色：随位移线性从白色渐变到浅灰（systemGray6 #F2F2F7），
    /// 展开态定格在浅灰，视觉参考 iOS 通讯录的 pressed / swiped 反馈。
    private var rowBackgroundColor: Color {
        // #F2F2F7 (systemGray6) 的 RGB
        let target = (r: 242.0 / 255.0, g: 242.0 / 255.0, b: 247.0 / 255.0)
        return Color(red: 1 - (1 - target.r) * progress,
                     green: 1 - (1 - target.g) * progress,
                     blue: 1 - (1 - target.b) * progress)
    }

    /// 灰色选中层的圆角随位移淡入（未滑动时 0，展开态 12pt）——
    /// 让内容行看起来像一枚"被拖出来的胶囊"，参考 iOS 通讯录左滑效果
    private var rowCornerRadius: CGFloat { 12 * progress }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                // 内容行：撑满容器宽度，左滑时被推出去露出后面的删除按钮
                content()
                    .containerRelativeFrame(.horizontal)
                    .background(
                        // 内层（紧贴内容）：随位移淡入的圆角灰胶囊，横向留 6pt 呼吸让圆角看得见
                        RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                            .fill(rowBackgroundColor)
                            .padding(.horizontal, 6)
                    )
                    .background(Color.white)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOpen {
                            // 已展开时，点击行本身先收起，不触发编辑
                            close()
                        } else {
                            onTap()
                        }
                    }

                // 删除按钮：图标随进度渐显 / 缩放
                Button {
                    onDelete()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(red: 1.0, green: 59 / 255, blue: 48 / 255))  // systemRed #FF3B30
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: iconDiameter, height: iconDiameter)
                    .frame(width: actionWidth, alignment: .center)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .opacity(min(1, progress / 0.6))
                    .scaleEffect(0.6 + progress * 0.4)
                }
                .buttonStyle(.plain)
            }
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(SwipeSnapBehavior(actionWidth: actionWidth))
        .scrollPosition($scrollPos)
        .background(Color.white)
        // 跟随实际滚动偏移更新渐变进度
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            min(1, max(0, geo.contentOffset.x / actionWidth))
        } action: { _, newValue in
            progress = newValue
        }
        // 用户手动滑到位后，回写展开态给父视图（实现同一时刻仅一行展开）
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.x > actionWidth / 2
        } action: { _, opened in
            if isOpen != opened { isOpen = opened }
        }
        // 外部（父视图关掉另一行 / 切视图 / 点空白）改动 isOpen 时，补一次动画对齐位移
        .onChange(of: isOpen) { _, newValue in
            guard newValue != (progress > 0.5) else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                scrollPos.scrollTo(x: newValue ? actionWidth : 0)
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            scrollPos.scrollTo(x: 0)
        }
        isOpen = false
    }
}
