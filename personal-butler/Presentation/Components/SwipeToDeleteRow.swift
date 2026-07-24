//
//  SwipeToDeleteRow.swift
//  左滑删除通用组件（ScrollView 场景下的手写实现，模拟系统 UITableView 交互）
//
//  同一时刻仅一行处于展开态，由父视图通过一个 `openSwipeId` 状态 + 每行的 `isOpen`
//  Binding 实现互斥；父视图在空白点击 / 视图切换时把 `openSwipeId` 置 nil 即可整片收起。
//

import SwiftUI

struct SwipeToDeleteRow<Content: View>: View {
    @Binding var isOpen: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    /// 删除按钮区域宽度（圆形图标 + 左右呼吸间距）
    private let actionWidth: CGFloat = 68
    /// 圆形按钮直径
    private let iconDiameter: CGFloat = 44

    /// 当前展示的水平位移（负值 = 向左露出按钮）。用 @State 而非 @GestureState，
    /// 让手势结束后的回弹和外部触发的收起共享一条动画曲线，避免快速滑多行时的跳变残影。
    @State private var offset: CGFloat = 0
    /// 是否已判定为横向手势（避免与 ScrollView 纵向滚动打架）
    @State private var isHorizontalDrag: Bool = false
    /// 记录手势起点时的静态位移，防止连续拖动累计误差
    @State private var dragStart: CGFloat = 0

    private var openOffset: CGFloat { -actionWidth }

    /// 行左滑时的淡灰选中背景色：随位移线性从白色渐变到浅灰（systemGray6 #F2F2F7），
    /// 展开态定格在浅灰，视觉参考 iOS 通讯录的 pressed / swiped 反馈。
    private var rowBackgroundColor: Color {
        let progress = min(1, abs(offset) / actionWidth)
        // #F2F2F7 (systemGray6) 的 RGB
        let target = (r: 242.0 / 255.0, g: 242.0 / 255.0, b: 247.0 / 255.0)
        let r = 1 - (1 - target.r) * progress
        let g = 1 - (1 - target.g) * progress
        let b = 1 - (1 - target.b) * progress
        return Color(red: r, green: g, blue: b)
    }

    /// 灰色选中层的圆角随位移淡入（未滑动时 0，展开态 12pt）——
    /// 让内容行看起来像一枚"被拖出来的胶囊"，参考 iOS 通讯录左滑效果
    private var rowCornerRadius: CGFloat {
        let progress = min(1, abs(offset) / actionWidth)
        return 12 * progress
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // 后面的删除按钮：位移露出多少就跟着显示多少，图标随进度渐显 / 缩放
            Button {
                onDelete()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 59/255, blue: 48/255))  // systemRed #FF3B30
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: iconDiameter, height: iconDiameter)
                .frame(width: actionWidth, alignment: .center)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .opacity(min(1, abs(offset) / (actionWidth * 0.6)))
                .scaleEffect(min(1, 0.6 + abs(offset) / actionWidth * 0.4))
            }
            .buttonStyle(.plain)
            // 按钮宽度固定，通过位移把它从右边"推"出来
            .offset(x: max(0, actionWidth + offset))

            // 前面的内容行
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    // 内层（紧贴内容）：随位移淡入的圆角灰胶囊，横向留 6pt 呼吸让圆角看得见
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(rowBackgroundColor)
                        .padding(.horizontal, 6)
                )
                .background(
                    // 外层（铺满整行）：白色底色，防止圆角外沿露出下方的红色删除按钮
                    Color.white
                )
                .contentShape(Rectangle())
                .offset(x: offset)
                .onTapGesture {
                    if offset < 0 {
                        // 已展开时，点击行本身先收起，不触发编辑
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            offset = 0
                        }
                        isOpen = false
                    } else {
                        onTap()
                    }
                }
                // 用 simultaneousGesture 而非 .gesture：
                // .gesture 会独占手势，导致外层 ScrollView 的纵向滚动被拦截
                // （即便在垂直方向早退，SwiftUI 也已把手势判给了本行）；
                // simultaneous 允许纵向 pan 继续冒泡给 ScrollView，同时保留横向左滑识别。
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            // 首次进入 onChanged 时判定方向；判定为纵向就整段忽略
                            if !isHorizontalDrag {
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    isHorizontalDrag = true
                                    dragStart = offset
                                } else {
                                    return
                                }
                            }
                            let raw = dragStart + value.translation.width
                            // 允许拖过一点（橡皮筋感），但夹到 [-actionWidth * 1.15, 0]
                            offset = max(-actionWidth * 1.15, min(0, raw))
                        }
                        .onEnded { value in
                            defer { isHorizontalDrag = false }
                            guard isHorizontalDrag else { return }
                            let dx = value.translation.width
                            let willOpen: Bool
                            if isOpen {
                                willOpen = dx <= actionWidth / 2
                            } else {
                                willOpen = dx < -actionWidth / 2
                            }
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                offset = willOpen ? openOffset : 0
                            }
                            if willOpen != isOpen {
                                isOpen = willOpen
                            }
                        }
                )
        }
        .clipped()
        // 外部（父视图关掉另一行 / 切视图 / 点空白）改动 isOpen 时，补一次动画对齐位移
        .onChange(of: isOpen) { _, newValue in
            let target: CGFloat = newValue ? openOffset : 0
            guard offset != target else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                offset = target
            }
        }
    }
}
