//
//  HomeView.swift
//  Tab1 · 主页：待办卡片 + 功能宫格
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \ScheduleEvent.startDate) private var schedules: [ScheduleEvent]
    @Query(sort: \Anniversary.date) private var annis: [Anniversary]
    @Query(sort: \TodoItem.createdAt) private var manualTodos: [TodoItem]
    @Query(sort: \AppModule.order) private var modules: [AppModule]

    @State private var prepSheetItem: TodoItem?
    @State private var cookSheetItem: TodoItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color.white)
        .sheet(item: $prepSheetItem) { todo in
            PrepTaskSheet(todo: todo)
        }
        .sheet(item: $cookSheetItem) { todo in
            CookTaskSheet(todo: todo)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("私人管家")
                .font(.system(size: 20, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColorTheme.border).frame(height: 0.5)
        }
    }

    // MARK: - Content
    private var content: some View {
        GeometryReader { geo in
            let available = max(0, geo.size.height - 32)  // 减去外层 vertical padding
            VStack(spacing: 16) {
                todoCard
                    .frame(height: max(120, available * 3 / 5))
                appsGrid
                    .frame(height: max(120, available * 2 / 5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Todo Card
    private var todoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待办")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                Spacer()
                Text("\(currentList.count) 项")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColorTheme.textSub)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(currentList.enumerated()), id: \.offset) { idx, todo in
                        row(for: todo)
                        if idx < currentList.count - 1 {
                            Divider().foregroundStyle(Color.black.opacity(0.04))
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(colors: [.black, .black, .black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
    }

    // MARK: - Apps Grid
    private var appsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)]
        let top6 = modules.prefix(6)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(top6), id: \.id) { m in
                Button {
                    router.open(m.id)
                } label: {
                    FeatureCard(module: m)
                }
                .buttonStyle(.plain)
                .disabled(m.comingSoon)
            }
        }
    }

    // MARK: - 数据组合

    @ViewBuilder
    private func row(for todo: TodoDisplay) -> some View {
        switch todo.taskType {
        case .prep:
            PrepTodoRow(name: todo.name,
                        timeLabel: todo.timeLabel,
                        isDone: todo.isDone,
                        checkedCount: todo.checkedIngredients.count,
                        expectedCount: todo.expectedIngredients.count,
                        onToggle: { toggle(todo) },
                        onTap: { prepSheetItem = todo.refManual })
        case .cook:
            CookTodoRow(name: todo.name,
                        timeLabel: todo.timeLabel,
                        isDone: todo.isDone,
                        onToggle: { toggle(todo) },
                        onTap: { cookSheetItem = todo.refManual })
        case .none:
            TodoItemRow(name: todo.name, source: todo.sourceLabel,
                        timeLabel: todo.timeLabel, urgent: todo.isUrgent,
                        isDone: todo.isDone) {
                toggle(todo)
            }
        }
    }

    private struct TodoDisplay: Identifiable {
        let id: String
        let name: String
        let sourceLabel: String
        let timeLabel: String
        let isUrgent: Bool
        let isDone: Bool
        let sortDate: Date          // 用于时间排序，纪念日/无期限手动待办用推导时间
        let refSchedule: ScheduleEvent?
        let refManual: TodoItem?
        let taskType: TodoTaskType
        let recipeId: UUID?
        let expectedIngredients: [String]
        let checkedIngredients: [String]
    }

    /// 近期待办：合并今天起未来 7 天窗口内的日程、纪念日、手动/烹饪待办
    private var currentList: [TodoDisplay] {
        let now = Date().startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let todayEnd = Date().endOfDay
        var items: [TodoDisplay] = []

        // 日程：7 天窗口内
        for s in schedules where s.startDate >= now && s.startDate <= end {
            let isToday = s.startDate <= todayEnd
            let hm = s.isAllDay ? "全天" : s.startDate.hourMinute
            let label: String
            if s.isCompleted {
                label = "已完成"
            } else if isToday {
                label = hm
            } else {
                label = DateCalculator.relativeLabel(s.startDate)
            }
            let urgent = !s.isCompleted && s.startDate.timeIntervalSinceNow < 3600 * 6 && s.startDate.timeIntervalSinceNow > 0
            items.append(.init(id: "sch-\(s.id)", name: s.title, sourceLabel: "日程",
                               timeLabel: label, isUrgent: urgent, isDone: s.isCompleted,
                               sortDate: s.startDate,
                               refSchedule: s, refManual: nil,
                               taskType: .none, recipeId: nil,
                               expectedIngredients: [], checkedIngredients: []))
        }

        // 纪念日：未来 7 天内到期
        for a in annis where a.type == .yearly {
            let days = DateCalculator.daysUntilNextYearly(from: a.date, isLunar: a.isLunar)
            if days <= 7 {
                let label = days == 0 ? "今天" : "\(days) 天后"
                let sort = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
                items.append(.init(id: "anni-\(a.id)", name: a.name, sourceLabel: "纪念日",
                                   timeLabel: label, isUrgent: days <= 3, isDone: false,
                                   sortDate: sort,
                                   refSchedule: nil, refManual: nil,
                                   taskType: .none, recipeId: nil,
                                   expectedIngredients: [], checkedIngredients: []))
            }
        }

        // 手动 / 烹饪待办
        for t in manualTodos {
            let taskType = t.taskType
            let recipeId = t.recipeId
            let expected = t.expectedIngredients
            let checked = t.checkedIngredients

            if let d = t.dueDate {
                guard d >= now && d <= end else { continue }
                let label: String
                if t.isDone {
                    label = "已完成"
                } else if d <= todayEnd {
                    label = "今日"
                } else {
                    label = DateCalculator.relativeLabel(d)
                }
                items.append(.init(id: "todo-\(t.id)", name: t.name,
                                   sourceLabel: t.source.label,
                                   timeLabel: label,
                                   isUrgent: false, isDone: t.isDone,
                                   sortDate: d,
                                   refSchedule: nil, refManual: t,
                                   taskType: taskType, recipeId: recipeId,
                                   expectedIngredients: expected,
                                   checkedIngredients: checked))
            } else if !t.isDone {
                // 未设截止的手动待办，视作近期，排在今天
                items.append(.init(id: "todo-\(t.id)", name: t.name,
                                   sourceLabel: t.source.label,
                                   timeLabel: "近期",
                                   isUrgent: false, isDone: false,
                                   sortDate: now,
                                   refSchedule: nil, refManual: t,
                                   taskType: taskType, recipeId: recipeId,
                                   expectedIngredients: expected,
                                   checkedIngredients: checked))
            }
        }

        // 未完成优先 → prep > cook > none → 时间升序
        return items.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone && b.isDone }
            if a.taskType != b.taskType {
                let order: [TodoTaskType: Int] = [.prep: 0, .cook: 1, .none: 2]
                return order[a.taskType]! < order[b.taskType]!
            }
            return a.sortDate < b.sortDate
        }
    }

    private func toggle(_ todo: TodoDisplay) {
        if let s = todo.refSchedule {
            s.isCompleted.toggle()
            try? context.save()
        } else if let t = todo.refManual {
            if todo.taskType == .prep {
                // prep 圆圈点击 = 全部已买 / 取消全买
                if t.isDone {
                    t.checkedIngredientsRaw = ""
                    t.isDone = false
                } else {
                    t.checkedIngredientsRaw = todo.expectedIngredients.joined(separator: ",")
                    t.isDone = true
                }
            } else {
                t.isDone.toggle()
            }
            try? context.save()
        }
    }
}

// MARK: - 宫格卡片

private struct FeatureCard: View {
    let module: AppModule
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: module.iconSystemName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AppColorTheme.primary)
                .frame(height: 32)
            Text(module.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColorTheme.text)
            Text(module.tag)
                .font(.system(size: 11))
                .foregroundStyle(AppColorTheme.textSub)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: AppColorTheme.cardShadow, radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: 0xF0F2F5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Prep / Cook 任务行

private struct PrepTodoRow: View {
    let name: String
    let timeLabel: String
    let isDone: Bool
    let checkedCount: Int
    let expectedCount: Int
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isDone ? AppColorTheme.primary : .secondary)
            }
            .buttonStyle(.plain)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isDone ? .secondary : AppColorTheme.text)
                        .strikethrough(isDone, color: .secondary)
                    if expectedCount > 0 {
                        Text("\(checkedCount)/\(expectedCount) 已买")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(timeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct CookTodoRow: View {
    let name: String
    let timeLabel: String
    let isDone: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isDone ? AppColorTheme.primary : .secondary)
            }
            .buttonStyle(.plain)
            Button(action: onTap) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDone ? .secondary : AppColorTheme.text)
                    .strikethrough(isDone, color: .secondary)
                Spacer()
                Label("查看步骤", systemImage: "book")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(timeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
