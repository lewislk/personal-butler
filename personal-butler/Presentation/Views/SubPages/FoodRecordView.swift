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
                    .padding(.horizontal, 16)
                }
            }
            .background(Color.white)

            FABAddButton { showCreate = true }
        }
        .navigationTitle("美食记录")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) { CreateFoodSheet() }
    }

    private var filtered: [FoodRecord] {
        let cat = categories[filterIndex].1
        return cat == .all ? list : list.filter { $0.category == cat }
    }

    private func row(_ f: FoodRecord) -> some View {
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
    }

    private func gradient(for cat: FoodCategory) -> [Color] {
        switch cat {
        case .japanese: return [Color(hex: 0xBEE1FF), Color(hex: 0x6AA9E9)]
        case .milktea:  return [Color(hex: 0xFFE29A), Color(hex: 0xF0B650)]
        default:        return [Color(hex: 0xFFD7B5), Color(hex: 0xFF8A65)]
        }
    }
}

struct CreateFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🍽️"
    @State private var rating = 4
    @State private var category: FoodCategory = .chinese
    @State private var tags = ""
    @State private var remark = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("店名 / 菜品", text: $name)
                    TextField("Emoji", text: $emoji)
                    Stepper("评分：\(rating) 星", value: $rating, in: 1...5)
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
            .navigationTitle("新增美食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let f = FoodRecord(name: name.isEmpty ? "未命名" : name,
                                           emoji: emoji, rating: rating,
                                           tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                           remark: remark, category: category)
                        context.insert(f)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
