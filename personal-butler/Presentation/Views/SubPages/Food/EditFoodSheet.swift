//
//  EditFoodSheet.swift
//  美食记录 · 新增 / 编辑弹窗
//

import SwiftUI
import SwiftData

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
