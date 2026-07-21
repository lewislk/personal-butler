//
//  HomeView.swift
//  Tab1 · 主页：待办卡片 + 功能宫格
//

import SwiftUI
import SwiftData

enum HomeTodoTab: Hashable { case today, week }

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \ScheduleEvent.startDate) private var schedules: [ScheduleEvent]
    @Query(sort: \Anniversary.date) private var annis: [Anniversary]
    @Query(sort: \TodoItem.createdAt) private var manualTodos: [TodoItem]
    @Query(sort: \AppModule.order) private var modules: [AppModule]

    @State private var todoTab: HomeTodoTab = .today

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color.white)
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
                MiniSegmentedPill(items: [
                    (HomeTodoTab.today, "今日待办"),
                    (HomeTodoTab.week, "近期待办")
                ], selection: $todoTab)
                Spacer()
                Text("\(currentList.count) 项")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColorTheme.textSub)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(currentList.enumerated()), id: \.offset) { idx, todo in
                        TodoItemRow(name: todo.name, source: todo.sourceLabel,
                                    timeLabel: todo.timeLabel, urgent: todo.isUrgent,
                                    isDone: todo.isDone) {
                            toggle(todo)
                        }
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

    private struct TodoDisplay: Identifiable {
        let id: String
        let name: String
        let sourceLabel: String
        let timeLabel: String
        let isUrgent: Bool
        let isDone: Bool
        let refSchedule: ScheduleEvent?
        let refManual: TodoItem?
    }

    private var currentList: [TodoDisplay] {
        switch todoTab {
        case .today: return todayList
        case .week:  return weekList
        }
    }

    private var todayList: [TodoDisplay] {
        let today = Date().startOfDay
        let end = Date().endOfDay
        var items: [TodoDisplay] = []
        // 日程
        for s in schedules where s.startDate >= today && s.startDate <= end {
            let hm = s.isAllDay ? "全天" : s.startDate.hourMinute
            let urgent = !s.isCompleted && s.startDate.timeIntervalSinceNow < 3600 * 4 && s.startDate.timeIntervalSinceNow > 0
            items.append(.init(id: "sch-\(s.id)", name: s.title, sourceLabel: "日程",
                               timeLabel: s.isCompleted ? "已完成" : hm,
                               isUrgent: urgent, isDone: s.isCompleted,
                               refSchedule: s, refManual: nil))
        }
        // 手动/烹饪
        for t in manualTodos {
            if let d = t.dueDate, d >= today && d <= end {
                items.append(.init(id: "todo-\(t.id)", name: t.name,
                                   sourceLabel: t.source.label,
                                   timeLabel: t.isDone ? "已完成" : "今晚",
                                   isUrgent: false, isDone: t.isDone,
                                   refSchedule: nil, refManual: t))
            } else if t.dueDate == nil, !t.isDone {
                items.append(.init(id: "todo-\(t.id)", name: t.name,
                                   sourceLabel: t.source.label,
                                   timeLabel: "今日",
                                   isUrgent: false, isDone: false,
                                   refSchedule: nil, refManual: t))
            }
        }
        return items.sorted { !$0.isDone && $1.isDone }
    }

    private var weekList: [TodoDisplay] {
        let now = Date().startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        var items: [TodoDisplay] = []
        for s in schedules where s.startDate >= now && s.startDate <= end {
            let label = DateCalculator.relativeLabel(s.startDate)
            let urgent = s.startDate.timeIntervalSinceNow < 3600 * 6 && s.startDate.timeIntervalSinceNow > 0
            items.append(.init(id: "sch-\(s.id)", name: s.title, sourceLabel: "日程",
                               timeLabel: label, isUrgent: urgent, isDone: s.isCompleted,
                               refSchedule: s, refManual: nil))
        }
        for a in annis where a.type == .yearly {
            let days = DateCalculator.daysUntilNextYearly(from: a.date, isLunar: a.isLunar)
            if days <= 7 {
                let label = days == 0 ? "今天" : "\(days) 天后"
                items.append(.init(id: "anni-\(a.id)", name: a.name, sourceLabel: "纪念日",
                                   timeLabel: label, isUrgent: days <= 3, isDone: false,
                                   refSchedule: nil, refManual: nil))
            }
        }
        return items
    }

    private func toggle(_ todo: TodoDisplay) {
        if let s = todo.refSchedule {
            s.isCompleted.toggle()
            try? context.save()
        } else if let t = todo.refManual {
            t.isDone.toggle()
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
