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

            FABAddButton { showCreate = true }
        }
        .navigationTitle("纪念日")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) {
            CreateAnniversarySheet()
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

struct CreateAnniversarySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var type: AnniversaryType = .yearly
    @State private var isLunar = false
    @State private var emoji = "🎉"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（如 妈妈生日）", text: $name)
                    TextField("Emoji", text: $emoji)
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
            .navigationTitle("新增纪念日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let a = Anniversary(name: name.isEmpty ? "未命名" : name,
                                            date: date, isLunar: isLunar,
                                            type: type, emoji: emoji)
                        context.insert(a)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
