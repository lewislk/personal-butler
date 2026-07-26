//
//  FoodRecordView.swift
//  美食记录
//

import SwiftUI
import SwiftData

struct FoodRecordView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodRecord.date, order: .reverse) private var list: [FoodRecord]
    @State private var filterIndex: Int = 0
    @State private var showCreate = false
    @State private var editingRecord: FoodRecord?
    @State private var pendingDelete: FoodRecord?
    /// 当前处于展开态（已左滑露出删除按钮）的记录 id；同一时刻最多一个
    @State private var openSwipeId: UUID?

    private let categories: [(String, FoodCategory)] = [
        ("全部", .all),
        ("火锅", .hotpot),
        ("奶茶", .milktea),
        ("中餐", .chinese),
        ("日料", .japanese),
        ("咖啡", .coffee)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HorizontalTagBar(items: categories.map { $0.0 }, selectedIndex: $filterIndex)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { f in
                            row(f)
                            Divider()
                        }
                        Spacer(minLength: 80)
                    }
                }
                // 点击空白处收起已展开的滑动行
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if openSwipeId != nil {
                            openSwipeId = nil
                        }
                    }
                )
                // 切换分类时也顺手收起
                .onChange(of: filterIndex) { _, _ in openSwipeId = nil }
            }
            .background(Color.white)

            FABAddButton { showCreate = true }
        }
        .navigationTitle("美食记录")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) {
            EditFoodSheet(record: nil)
        }
        .sheet(item: $editingRecord) { r in
            EditFoodSheet(record: r)
        }
        .alert("删除该记录？",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let f = pendingDelete {
                    context.delete(f)
                    try? context.save()
                }
                pendingDelete = nil
                openSwipeId = nil
            }
        } message: {
            Text(pendingDelete.map { "「\($0.name)」删除后不可恢复。" } ?? "")
        }
    }

    private var filtered: [FoodRecord] {
        let cat = categories[filterIndex].1
        return cat == .all ? list : list.filter { $0.category == cat }
    }

    private func row(_ f: FoodRecord) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(
                get: { openSwipeId == f.id },
                set: { openSwipeId = $0 ? f.id : nil }
            ),
            onTap: { editingRecord = f },
            onDelete: { pendingDelete = f }
        ) {
            HStack(alignment: .top, spacing: 12) {
                Text(f.emoji)
                    .font(.system(size: 32))
                    .frame(width: 90, height: 90)
                    .background(RoundedRectangle(cornerRadius: 10).fill(
                        LinearGradient(colors: gradient(for: f.category),
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    ))
                VStack(alignment: .leading, spacing: 6) {
                    Text(f.name).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColorTheme.text)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < f.rating ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundStyle(i < f.rating ? Color(hex: 0xF5A623) : Color(hex: 0xE2E5EA))
                        }
                    }
                    if !f.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(f.tags, id: \.self) { t in
                                Text(t).font(.system(size: 11))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Capsule().fill(AppColorTheme.bg))
                                    .foregroundStyle(AppColorTheme.textSub)
                            }
                        }
                    }
                    if !f.remark.isEmpty {
                        Text(f.remark).font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                            .lineLimit(2)
                    }
                    if f.hasLocation, let loc = f.displayLocation {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                            Text(loc)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(AppColorTheme.textSub)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
    }

    private func gradient(for cat: FoodCategory) -> [Color] {
        switch cat {
        case .japanese: return [Color(hex: 0xBEE1FF), Color(hex: 0x6AA9E9)]
        case .milktea:  return [Color(hex: 0xFFE29A), Color(hex: 0xF0B650)]
        default:        return [Color(hex: 0xFFD7B5), Color(hex: 0xFF8A65)]
        }
    }
}
