//
//  ScheduleView.swift
//  日程管理
//

import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleEvent.startDate) private var events: [ScheduleEvent]
    @State private var mode: Int = 0  // 0 日 / 1 月
    @State private var showCreate = false
    @State private var editingEvent: ScheduleEvent?
    @State private var pendingDelete: ScheduleEvent?
    /// 当前处于展开态（已左滑露出删除按钮）的日程 id；同一时刻最多一个
    @State private var openSwipeId: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    SegmentedPill(items: [(0, "日视图"), (1, "月视图")], selection: $mode)
                        .padding(.horizontal, 16).padding(.vertical, 16)

                    if mode == 0 {
                        dayView
                    } else {
                        monthView
                    }
                    Spacer(minLength: 80)
                }
            }
            .background(Color.white)
            // 点击任何空白区收起已展开的滑动行
            .simultaneousGesture(
                TapGesture().onEnded {
                    if openSwipeId != nil {
                        openSwipeId = nil
                    }
                }
            )
            // 切视图时也顺手收起
            .onChange(of: mode) { _, _ in openSwipeId = nil }

            FABAddButton { showCreate = true }
        }
        .navigationTitle("日程管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) {
            EditScheduleSheet(event: nil)
        }
        .sheet(item: $editingEvent) { e in
            EditScheduleSheet(event: e)
        }
        .alert("删除该日程？",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let e = pendingDelete {
                    context.delete(e)
                    try? context.save()
                }
                pendingDelete = nil
                openSwipeId = nil
            }
        } message: {
            Text(pendingDelete.map { "「\($0.title)」删除后不可恢复。" } ?? "")
        }
    }

    // MARK: - 日视图
    private var dayView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(dayGroups, id: \.title) { group in
                Text(group.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColorTheme.textSub)
                    .padding(.top, 12).padding(.bottom, 8).padding(.horizontal, 20)

                ForEach(group.items, id: \.id) { e in
                    scheduleRow(e)
                    Divider().foregroundStyle(AppColorTheme.border).padding(.leading, 78)
                }
            }
        }
    }

    private func scheduleRow(_ e: ScheduleEvent) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(
                get: { openSwipeId == e.id },
                set: { openSwipeId = $0 ? e.id : nil }
            ),
            onTap: { editingEvent = e },
            onDelete: { pendingDelete = e }
        ) {
            HStack(alignment: .top, spacing: 12) {
                Text(e.isAllDay ? "全天" : e.startDate.hourMinute)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
                    .frame(width: 46, alignment: .trailing)
                    .padding(.top, 3)
                Rectangle().fill(barColor(e.colorTag))
                    .frame(width: 3).cornerRadius(2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColorTheme.text)
                    if !e.remark.isEmpty {
                        Text(e.remark).font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12).padding(.horizontal, 20)
        }
    }

    private func barColor(_ tag: ScheduleColorTag) -> Color {
        switch tag {
        case .blue: return AppColorTheme.primary
        case .green: return AppColorTheme.success
        case .orange: return Color(hex: 0xF0A150)
        }
    }

    private var dayGroups: [(title: String, items: [ScheduleEvent])] {
        let cal = Calendar.current
        var buckets: [Date: [ScheduleEvent]] = [:]
        for e in events where !e.isCompleted {
            let d = cal.startOfDay(for: e.startDate)
            if d >= cal.startOfDay(for: Date()) {
                buckets[d, default: []].append(e)
            }
        }
        return buckets.keys.sorted().map { d in
            (title: dayTitle(d), items: buckets[d]!.sorted { $0.startDate < $1.startDate })
        }
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.startOfDay(for: Date()).daysBetween(cal.startOfDay(for: d))
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEEE"
        let base = f.string(from: d)
        switch days {
        case 0: return "今天 · \(base)"
        case 1: return "明天 · \(base)"
        default: return base
        }
    }

    // MARK: - 月视图
    private var monthView: some View {
        let cal = Calendar.current
        let today = Date()
        let comps = cal.dateComponents([.year, .month], from: today)
        let start = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: start)!
        let firstWeekday = cal.component(.weekday, from: start) // 1 = 周日
        let hasEvent: Set<Int> = Set(events.compactMap {
            let c = cal.dateComponents([.year, .month, .day], from: $0.startDate)
            return (c.year == comps.year && c.month == comps.month) ? c.day : nil
        })

        return VStack(spacing: 8) {
            let title: String = {
                let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy 年 M 月"
                return f.string(from: today)
            }()
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)

            HStack {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                    Text(w).font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)

            let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(0..<(firstWeekday - 1), id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(range, id: \.self) { day in
                    VStack(spacing: 3) {
                        Text("\(day)")
                            .font(.system(size: 14,
                                          weight: day == cal.component(.day, from: today) ? .bold : .regular))
                            .foregroundStyle(day == cal.component(.day, from: today)
                                             ? AppColorTheme.primary : AppColorTheme.text)
                        Circle().fill(hasEvent.contains(day) ? AppColorTheme.primary : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(height: 36)
                }
            }
            .padding(.horizontal, 20)

            monthList(year: comps.year!, month: comps.month!)
        }
    }

    // MARK: - 月视图：当月日程列表
    @ViewBuilder
    private func monthList(year: Int, month: Int) -> some View {
        let cal = Calendar.current
        let monthEvents: [ScheduleEvent] = events.filter {
            let c = cal.dateComponents([.year, .month], from: $0.startDate)
            return c.year == year && c.month == month
        }
        let groups: [(title: String, items: [ScheduleEvent])] = {
            var buckets: [Date: [ScheduleEvent]] = [:]
            for e in monthEvents {
                let d = cal.startOfDay(for: e.startDate)
                buckets[d, default: []].append(e)
            }
            return buckets.keys.sorted().map { d in
                (title: monthListDayTitle(d),
                 items: buckets[d]!.sorted { $0.startDate < $1.startDate })
            }
        }()

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("当月日程")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                Spacer()
                Text("共 \(monthEvents.count) 项")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)

            if monthEvents.isEmpty {
                Text("本月暂无日程")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColorTheme.textSub)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(groups, id: \.title) { group in
                    Text(group.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColorTheme.textSub)
                        .padding(.top, 12).padding(.bottom, 8).padding(.horizontal, 20)

                    ForEach(group.items, id: \.id) { e in
                        scheduleRow(e)
                        Divider().foregroundStyle(AppColorTheme.border).padding(.leading, 78)
                    }
                }
            }
        }
    }

    private func monthListDayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.startOfDay(for: Date()).daysBetween(cal.startOfDay(for: d))
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEEE"
        let base = f.string(from: d)
        switch days {
        case 0: return "今天 · \(base)"
        case 1: return "明天 · \(base)"
        case -1: return "昨天 · \(base)"
        default: return base
        }
    }
}

// MARK: - 左滑删除通用组件（ScrollView 场景下的手写实现，模拟系统 UITableView 交互）
private struct SwipeToDeleteRow<Content: View>: View {
    @Binding var isOpen: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    /// 删除按钮区域宽度（对齐系统通讯录约 74pt）
    private let actionWidth: CGFloat = 74

    /// 当前展示的水平位移（负值 = 向左露出按钮）。用 @State 而非 @GestureState，
    /// 让手势结束后的回弹和外部触发的收起共享一条动画曲线，避免快速滑多行时的跳变残影。
    @State private var offset: CGFloat = 0
    /// 是否已判定为横向手势（避免与 ScrollView 纵向滚动打架）
    @State private var isHorizontalDrag: Bool = false
    /// 记录手势起点时的静态位移，防止连续拖动累计误差
    @State private var dragStart: CGFloat = 0

    private var openOffset: CGFloat { -actionWidth }

    var body: some View {
        ZStack(alignment: .trailing) {
            // 后面的删除按钮：位移露出多少就跟着显示多少，前景文字随进度渐显
            Button {
                onDelete()
            } label: {
                Text("删除")
                    .font(.system(size: 17))       // 系统按钮字号
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(red: 1.0, green: 59/255, blue: 48/255))  // systemRed #FF3B30
                    .contentShape(Rectangle())
                    .opacity(min(1, abs(offset) / (actionWidth * 0.6)))
            }
            .buttonStyle(.plain)
            // 按钮宽度固定，通过位移把它从右边"推"出来
            .offset(x: max(0, actionWidth + offset))

            // 前面的内容行
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
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
                .gesture(
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

// MARK: - 新增 / 编辑日程弹窗
struct EditScheduleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传 nil 表示新增，传入实例表示编辑
    let event: ScheduleEvent?

    @State private var title: String
    @State private var remark: String
    @State private var startDate: Date
    @State private var isAllDay: Bool
    @State private var colorTag: ScheduleColorTag
    @State private var isCompleted: Bool

    init(event: ScheduleEvent?) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _remark = State(initialValue: event?.remark ?? "")
        _startDate = State(initialValue: event?.startDate ?? Date())
        _isAllDay = State(initialValue: event?.isAllDay ?? false)
        _colorTag = State(initialValue: event?.colorTag ?? .blue)
        _isCompleted = State(initialValue: event?.isCompleted ?? false)
    }

    private var isEditing: Bool { event != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title)
                    TextField("备注", text: $remark, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Toggle("全天", isOn: $isAllDay)
                    DatePicker("开始时间", selection: $startDate,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    Picker("颜色标签", selection: $colorTag) {
                        Text("蓝").tag(ScheduleColorTag.blue)
                        Text("绿").tag(ScheduleColorTag.green)
                        Text("橙").tag(ScheduleColorTag.orange)
                    }
                }
                if isEditing {
                    Section {
                        Toggle("已完成", isOn: $isCompleted)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑日程" : "新增日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        let finalTitle = title.isEmpty ? "无标题" : title
        if let e = event {
            e.title = finalTitle
            e.remark = remark
            e.startDate = startDate
            e.isAllDay = isAllDay
            e.colorTagRaw = colorTag.rawValue
            e.isCompleted = isCompleted
        } else {
            let e = ScheduleEvent(title: finalTitle,
                                  remark: remark, startDate: startDate,
                                  isAllDay: isAllDay, colorTag: colorTag)
            context.insert(e)
        }
        try? context.save()
    }
}
