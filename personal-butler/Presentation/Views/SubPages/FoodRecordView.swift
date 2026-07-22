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

// MARK: - 新增 / 编辑美食记录弹窗
struct EditFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传 nil 表示新增，传入实例表示编辑
    let record: FoodRecord?

    @State private var name: String
    @State private var emoji: String
    @State private var rating: Int
    @State private var category: FoodCategory
    @State private var tags: String
    @State private var remark: String

    init(record: FoodRecord?) {
        self.record = record
        _name = State(initialValue: record?.name ?? "")
        _emoji = State(initialValue: record?.emoji ?? "🍽️")
        _rating = State(initialValue: record?.rating ?? 4)
        _category = State(initialValue: record?.category ?? .chinese)
        _tags = State(initialValue: record?.tagsRaw ?? "")
        _remark = State(initialValue: record?.remark ?? "")
    }

    private var isEditing: Bool { record != nil }

    /// 可选 Emoji 面板：覆盖火锅/奶茶/中餐/日料/咖啡等常见品类，末位保留一个通用兜底
    private static let emojiOptions: [String] = [
        "🍽️", "🍜", "🍚", "🍛", "🍲", "🍱",
        "🍣", "🍤", "🥟", "🍔", "🍕", "🌮",
        "🥗", "🍖", "🍗", "🥘", "🍢", "🍧",
        "🍰", "🧁", "🍩", "🍪", "🍦", "🍮",
        "☕️", "🍵", "🧋", "🥤", "🍺", "🍷"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("店名 / 菜品", text: $name)
                }
                Section("图标") {
                    emojiPicker
                }
                Section("评分") {
                    starRating
                }
                Section {
                    Picker("分类", selection: $category) {
                        Text("火锅").tag(FoodCategory.hotpot)
                        Text("奶茶").tag(FoodCategory.milktea)
                        Text("中餐").tag(FoodCategory.chinese)
                        Text("日料").tag(FoodCategory.japanese)
                        Text("咖啡").tag(FoodCategory.coffee)
                    }
                }
                Section {
                    TextField("标签（逗号分隔）", text: $tags)
                    TextField("备注", text: $remark, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "编辑美食" : "新增美食")
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
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let r = record {
            r.name = finalName
            r.emoji = emoji
            r.rating = rating
            r.tagsRaw = tagList.joined(separator: ",")
            r.remark = remark
            r.categoryRaw = category.rawValue
        } else {
            let f = FoodRecord(name: finalName,
                               emoji: emoji, rating: rating,
                               tags: tagList,
                               remark: remark, category: category)
            context.insert(f)
        }
        try? context.save()
    }

    // MARK: - Emoji 网格选择
    private var emojiPicker: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Self.emojiOptions, id: \.self) { e in
                Button {
                    emoji = e
                } label: {
                    Text(e)
                        .font(.system(size: 22))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(emoji == e
                                      ? AppColorTheme.primary.opacity(0.12)
                                      : AppColorTheme.bg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(emoji == e ? AppColorTheme.primary : .clear,
                                        lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 5 星评分（点第 N 颗 = N 星；再点当前分值可清 0）
    private var starRating: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = (rating == i) ? 0 : i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 26))
                        .foregroundStyle(i <= rating
                                         ? Color(hex: 0xF5A623)
                                         : Color(hex: 0xC7CCD4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(rating > 0 ? "\(rating) 星" : "未评分")
                .font(.system(size: 13))
                .foregroundStyle(AppColorTheme.textSub)
        }
        .padding(.vertical, 4)
    }
}
