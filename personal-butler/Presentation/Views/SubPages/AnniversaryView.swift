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
            ScrollView {
                VStack(spacing: 0) {
                    if let closest = closestYearly {
                        heroCard(closest)
                    }
                    SegmentedPill(items: [(AnniversaryType.yearly, "每年重复"),
                                          (AnniversaryType.cumulative, "累计天数")],
                                  selection: $mode)
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

                    ForEach(filtered, id: \.id) { a in
                        anniRow(a)
                        Divider().padding(.horizontal, 16)
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
                    TextField("名称（如 妈妈生日）", text: $name)
                }
                Section("图标") {
                    EmojiPickerRow(selection: $emoji)
                }
                Section {
                    Picker("类型", selection: $type) {
                        Text("每年重复").tag(AnniversaryType.yearly)
                        Text("累计天数").tag(AnniversaryType.cumulative)
                    }
                    DatePicker(type == .yearly ? "纪念日" : "起始日",
                               selection: $date, displayedComponents: [.date])
                    Toggle("按农历重复", isOn: $isLunar)
                }
            }
            .navigationTitle(isEditing ? "编辑纪念日" : "新增纪念日")
            .navigationBarTitleDisplayMode(.inline)
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
