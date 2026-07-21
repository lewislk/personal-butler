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
