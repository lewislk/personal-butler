//
//  AnniversaryView.swift
//  纪念日
//

import SwiftUI
import SwiftData

struct AnniversaryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Anniversary.date) private var list: [Anniversary]
    @State private var mode: AnniversaryType = .yearly
    @State private var showCreate = false
    @State private var editingAnni: Anniversary?
    @State private var pendingDelete: Anniversary?
    /// 当前处于展开态（已左滑露出删除按钮）的纪念日 id；同一时刻最多一个
    @State private var openSwipeId: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 顶部 hero + 分段 pill 固定不滚，只有下方数据行本身可上下滑动
            VStack(spacing: 0) {
                if let closest = closestYearly {
                    heroCard(closest)
                }
                SegmentedPill(items: [(AnniversaryType.yearly, "每年重复"),
                                      (AnniversaryType.cumulative, "累计天数")],
                              selection: $mode)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { a in
                            anniRow(a)
                            Divider().padding(.horizontal, 16)
                        }
                        // FAB = 52pt 高 + 24pt 底部 padding = 76pt，再留 ~44pt 净空避免遮挡末行
                        Spacer(minLength: 120)
                    }
                }
                // 显式声明填充剩余空间：VStack 顶部有 hero + SegmentedPill 时，
                // 确保 ScrollView 拿到导航栏以下的所有剩余高度，否则可能因布局歧义拿到 0 高度
                .frame(maxHeight: .infinity)
                // 点击列表空白区收起已展开的滑动行
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if openSwipeId != nil {
                            openSwipeId = nil
                        }
                    }
                )
            }
            .background(Color.white)
            // 切类型时也顺手收起
            .onChange(of: mode) { _, _ in openSwipeId = nil }

            FABAddButton { showCreate = true }
        }
        .navigationTitle("纪念日")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) {
            EditAnniversarySheet(anniversary: nil)
        }
        .sheet(item: $editingAnni) { a in
            EditAnniversarySheet(anniversary: a)
        }
        .alert("删除该纪念日？",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let a = pendingDelete {
                    context.delete(a)
                    try? context.save()
                }
                pendingDelete = nil
                openSwipeId = nil
            }
        } message: {
            Text(pendingDelete.map { "「\($0.name)」删除后不可恢复。" } ?? "")
        }
    }

    private var filtered: [Anniversary] {
        list.filter { $0.type == mode }
            .sorted {
                switch mode {
                case .yearly:
                    return DateCalculator.daysUntilNextYearly(from: $0.date, isLunar: $0.isLunar)
                        < DateCalculator.daysUntilNextYearly(from: $1.date, isLunar: $1.isLunar)
                case .cumulative:
                    return $0.date < $1.date
                }
            }
    }

    private var closestYearly: Anniversary? {
        list.filter { $0.type == .yearly }
            .min { DateCalculator.daysUntilNextYearly(from: $0.date, isLunar: $0.isLunar)
                <  DateCalculator.daysUntilNextYearly(from: $1.date, isLunar: $1.isLunar) }
    }

    private func heroCard(_ a: Anniversary) -> some View {
        let days = DateCalculator.daysUntilNextYearly(from: a.date, isLunar: a.isLunar)
        return VStack(alignment: .leading, spacing: 6) {
            Text("最近的纪念日").font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
            Text("\(a.name) \(a.emoji)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColorTheme.text)
                .padding(.top, 2)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(days)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColorTheme.success)
                Text(days == 0 ? "今天" : "天后")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColorTheme.success)
            }
            .padding(.top, 4)
            Text(labelForDate(a))
                .font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0xF0FBF5), Color(hex: 0xE7F6EE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD6EEDF)))
        .padding(.horizontal, 16).padding(.top, 16)
    }

    private func labelForDate(_ a: Anniversary) -> String {
        if a.isLunar {
            return DateCalculator.lunarString(from: a.date)
        }
        return DateCalculator.gregorianDateLabel(a.date)
    }

    private func anniRow(_ a: Anniversary) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(
                get: { openSwipeId == a.id },
                set: { openSwipeId = $0 ? a.id : nil }
            ),
            onTap: { editingAnni = a },
            onDelete: { pendingDelete = a }
        ) {
            HStack {
                Circle()
                    .fill(a.type == .yearly ? AppColorTheme.success : AppColorTheme.primary)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.name).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColorTheme.text)
                    Text(labelForDate(a)).font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                }
                Spacer()
                badge(a)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    private func badge(_ a: Anniversary) -> some View {
        switch a.type {
        case .yearly:
            let days = DateCalculator.daysUntilNextYearly(from: a.date, isLunar: a.isLunar)
            let warn = days <= 7
            return AnyView(
                Text("还有 \(days) 天")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(warn ? AppColorTheme.warn : AppColorTheme.success)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(warn ? Color(hex: 0xFFF3E6) : Color(hex: 0xE7F6EE)))
            )
        case .cumulative:
            let n = DateCalculator.cumulativeDays(from: a.date)
            return AnyView(
                Text("第 \(n) 天")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColorTheme.primary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0xEEF3FD)))
            )
        }
    }
}

// MARK: - 新增 / 编辑纪念日弹窗
struct EditAnniversarySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传 nil 表示新增，传入实例表示编辑
    let anniversary: Anniversary?

    @State private var name: String
    @State private var date: Date
    @State private var type: AnniversaryType
    @State private var isLunar: Bool
    @State private var emoji: String
    @FocusState private var isNameFocused: Bool
    /// 日期行是否展开内嵌日历（用来替换默认 compact 的悬浮日历——它选完不会自动收起）
    @State private var isDatePickerExpanded = false
    /// 悬浮日历打开时的基准日期：用来区分"用户切换年/月（不关闭）"和"用户点选具体某一天（关闭）"
    @State private var pickerAnchor: Date = Date()

    init(anniversary: Anniversary?) {
        self.anniversary = anniversary
        _name = State(initialValue: anniversary?.name ?? "")
        _date = State(initialValue: anniversary?.date ?? Date())
        _type = State(initialValue: anniversary?.type ?? .yearly)
        _isLunar = State(initialValue: anniversary?.isLunar ?? false)
        _emoji = State(initialValue: anniversary?.emoji ?? "🎉")
    }

    private var isEditing: Bool { anniversary != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField("名称（如 妈妈生日）", text: $name)
                            .focused($isNameFocused)
                        // 快速清除：仅有内容时出现；清空后保持聚焦便于继续输入
                        if !name.isEmpty {
                            Button {
                                name = ""
                                isNameFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppColorTheme.textSub)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: name.isEmpty)
                }
                Section("图标") {
                    EmojiPickerRow(selection: $emoji)
                        // 用户开始挑图标 = 输入名称告一段落，主动收键盘
                        .onChange(of: emoji) { _, _ in isNameFocused = false }
                }
                Section {
                    Picker("类型", selection: $type) {
                        Text("每年重复").tag(AnniversaryType.yearly)
                        Text("累计天数").tag(AnniversaryType.cumulative)
                    }
                    // 系统 .compact DatePicker 选完不会自动关闭悬浮气泡；
                    // 这里改成点行 → 弹出半屏悬浮日历 → 选到日期立即关闭。
                    Button {
                        isNameFocused = false
                        isDatePickerExpanded = true
                    } label: {
                        HStack {
                            Text(type == .yearly ? "纪念日" : "起始日")
                                .foregroundStyle(AppColorTheme.text)
                            Spacer()
                            Text(DateCalculator.gregorianDateLabel(date))
                                .font(.system(size: 15))
                                .foregroundStyle(isDatePickerExpanded ? AppColorTheme.primary : AppColorTheme.text)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Toggle("按农历重复", isOn: $isLunar)
                    HStack {
                        Text("对应农历")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColorTheme.textSub)
                        Spacer()
                        Text(DateCalculator.lunarString(from: date))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColorTheme.text)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑纪念日" : "新增纪念日")
            .navigationBarTitleDisplayMode(.inline)
            // 兜底：滚动 Form 即收键盘（挑 Emoji / 展开日历时下拉都能触发）
            .scrollDismissesKeyboard(.immediately)
            .sheet(isPresented: $isDatePickerExpanded) {
                NavigationStack {
                    Group {
                        if isLunar {
                            // 农历：三滚轮（年 / 月 / 日），月份用"一月/二月..."中文
                            LunarWheelPicker(date: $date)
                        } else {
                            // 阳历：保留系统 graphical 日历
                            ScrollView {
                                DatePicker("", selection: $date, displayedComponents: [.date])
                                    .datePickerStyle(.graphical)
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                    .labelsHidden()
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .navigationTitle("选择日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { isDatePickerExpanded = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                // 阳历：打开时记住基准年月，只有在"年月未变、日发生变化"时才判定为点选了具体日期。
                // 农历模式下走滚轮 + "完成"按钮关闭，onChange 逻辑对农历无影响（只会不断刷新 anchor）。
                .onAppear { pickerAnchor = date }
                .onChange(of: date) { _, new in
                    guard !isLunar else { pickerAnchor = new; return }
                    let cal = Calendar.current
                    let anchor = cal.dateComponents([.year, .month, .day], from: pickerAnchor)
                    let now = cal.dateComponents([.year, .month, .day], from: new)
                    if anchor.year == now.year, anchor.month == now.month, anchor.day != now.day {
                        isDatePickerExpanded = false
                    } else {
                        // 年 / 月被切换：更新基准，等待用户点具体的日
                        pickerAnchor = new
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
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
        let finalName = name.isEmpty ? "未命名" : name
        let finalEmoji = emoji.isEmpty ? "🎉" : emoji
        if let a = anniversary {
            a.name = finalName
            a.date = date
            a.isLunar = isLunar
            a.typeRaw = type.rawValue
            a.emoji = finalEmoji
        } else {
            let a = Anniversary(name: finalName,
                                date: date, isLunar: isLunar,
                                type: type, emoji: finalEmoji)
            context.insert(a)
        }
        try? context.save()
    }
}

// MARK: - 常用 Emoji 选择器
/// 纪念日场景常用 Emoji 选择器：预置常用图标网格 + 支持自定义输入。
/// 不引入系统键盘 Emoji 面板的原因：用户对"改成常用 Emoji 的选择器"的诉求就是
/// 一次点击直达，不要在 TextField 里切键盘 → 找 Emoji 分类 → 挑选。
private struct EmojiPickerRow: View {
    @Binding var selection: String
    @State private var showCustom = false
    @State private var customText: String = ""

    /// 纪念日场景高频 Emoji（生日 / 婚庆 / 家庭 / 成就 / 节日 / 旅行 …）
    private static let presets: [String] = [
        "🎉", "🎂", "🎁", "❤️", "💍", "💐",
        "👶", "🎓", "🏠", "✈️", "🌸", "🌟",
        "🎊", "🕯️", "🎈", "🍰", "💑", "👨‍👩‍👧",
        "🐾", "📅", "🥂", "🌈", "🙏", "✨"
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(selection.isEmpty ? "🎉" : selection)
                    .font(.system(size: 30))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xF4F6F8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前图标").font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                    Text("点选下方常用 Emoji，或自定义").font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                }
                Spacer()
                Button {
                    customText = selection
                    showCustom = true
                } label: {
                    Text("自定义")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColorTheme.primary)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.presets, id: \.self) { e in
                    Button {
                        selection = e
                    } label: {
                        Text(e)
                            .font(.system(size: 22))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection == e ? Color(hex: 0xEEF3FD) : Color(hex: 0xF4F6F8))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selection == e ? AppColorTheme.primary : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("自定义 Emoji", isPresented: $showCustom) {
            TextField("输入一个 Emoji", text: $customText)
            Button("取消", role: .cancel) { }
            Button("使用") {
                let picked = firstEmoji(in: customText)
                if !picked.isEmpty { selection = picked }
            }
        } message: {
            Text("只取输入的第一个 Emoji 字符。")
        }
    }

    /// 从字符串里挑出第一个可视 Emoji 字符（cluster）；若无，返回空串。
    private func firstEmoji(in s: String) -> String {
        for ch in s where ch.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji }) {
            return String(ch)
        }
        // 兜底：非 Emoji 也允许（例如 "生"），保留旧行为
        return s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).description
    }
}

// MARK: - 农历三滚轮选择器（年 数字 / 月 中文 / 日 数字）
/// 阳历分支复用系统 `.graphical DatePicker`；农历分支单独走这里，
/// 因为系统日历不提供中式农历月/日的可视选择。
///
/// 内部把 (公历年，农历月，农历日) 三元组通过 `Calendar(.chinese)` 反算成 Date：
/// 用当年 6 月 1 日探针取到对应的 chinese era/year，再拼上用户选的月、日。
/// 由于纪念日按农历重复只关心月+日（见 `DateCalculator.daysUntilNextYearly`），
/// 年份取哪一个 chinese 年只影响初始化和显示，不影响业务语义。
/// 简化：忽略闰月（业务侧当前也未区分闰月）。
private struct LunarWheelPicker: View {
    @Binding var date: Date

    private let chineseCal: Calendar = {
        var c = Calendar(identifier: .chinese)
        c.locale = Locale(identifier: "zh_CN")
        return c
    }()
    private let gregCal = Calendar(identifier: .gregorian)

    /// 公历年做展示（用户熟悉的年份数字），实际写回 Date 时再换算到 chinese 年
    @State private var year: Int = 2026
    /// 农历月 1...12（不支持闰月）
    @State private var monthIdx: Int = 1
    /// 农历日 1...(29 或 30)
    @State private var day: Int = 1

    private static let monthNames = [
        "一月","二月","三月","四月","五月","六月",
        "七月","八月","九月","十月","十一月","十二月"
    ]
    private var years: [Int] { Array(1950...2100) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text("\(String(y)) 年").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("", selection: $monthIdx) {
                    ForEach(1...12, id: \.self) { m in
                        Text(Self.monthNames[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("", selection: $day) {
                    ForEach(1...daysInSelectedLunarMonth, id: \.self) { d in
                        Text("\(d) 日").tag(d)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // 底部实时回显农历字符串，让用户明确当前选项对应哪一天
            Text(DateCalculator.lunarString(from: date))
                .font(.system(size: 13))
                .foregroundStyle(AppColorTheme.textSub)
                .padding(.top, 8)

            Spacer()
        }
        .onAppear {
            year = gregCal.component(.year, from: date)
            monthIdx = clampedMonth(chineseCal.component(.month, from: date))
            day = clampedDay(chineseCal.component(.day, from: date))
        }
        .onChange(of: year) { _, _ in syncDate() }
        .onChange(of: monthIdx) { _, _ in
            day = min(day, daysInSelectedLunarMonth)
            syncDate()
        }
        .onChange(of: day) { _, _ in syncDate() }
    }

    /// 依据当前 year + monthIdx 选择，返回该农历月的总天数（29 或 30；越界给 30 兜底）
    private var daysInSelectedLunarMonth: Int {
        var comps = DateComponents()
        if let era = currentChineseEraYear() {
            comps.era = era.era
            comps.year = era.year
        }
        comps.month = monthIdx
        comps.day = 1
        if let d = chineseCal.date(from: comps),
           let range = chineseCal.range(of: .day, in: .month, for: d) {
            return range.count
        }
        return 30
    }

    /// 通过当年 6 月 1 日的公历日期，反查到对应的 chinese era + year
    private func currentChineseEraYear() -> (era: Int, year: Int)? {
        var probe = DateComponents()
        probe.year = year; probe.month = 6; probe.day = 1
        guard let g = gregCal.date(from: probe) else { return nil }
        let c = chineseCal.dateComponents([.era, .year], from: g)
        guard let e = c.era, let y = c.year else { return nil }
        return (e, y)
    }

    private func syncDate() {
        guard let ey = currentChineseEraYear() else { return }
        var comps = DateComponents()
        comps.era = ey.era
        comps.year = ey.year
        comps.month = monthIdx
        comps.day = min(day, daysInSelectedLunarMonth)
        if let d = chineseCal.date(from: comps) {
            // 保留原 Date 的时分秒，避免 lunarString 之外的时间字段错乱
            var hms = gregCal.dateComponents([.hour, .minute, .second], from: date)
            hms.year = gregCal.component(.year, from: d)
            hms.month = gregCal.component(.month, from: d)
            hms.day = gregCal.component(.day, from: d)
            if let merged = gregCal.date(from: hms) {
                date = merged
            } else {
                date = d
            }
        }
    }

    private func clampedMonth(_ m: Int) -> Int { min(12, max(1, m)) }
    private func clampedDay(_ d: Int) -> Int { min(30, max(1, d)) }
}
