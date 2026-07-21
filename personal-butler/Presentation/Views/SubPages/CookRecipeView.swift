//
//  CookRecipeView.swift
//  烹饪管理
//

import SwiftUI
import SwiftData

struct CookRecipeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CookRecipe.name) private var list: [CookRecipe]
    @State private var filterIndex: Int = 0
    @State private var showCreate = false

    private let categories: [(String, CookCategory)] = [
        ("全部菜谱", .all),
        ("家常菜", .home),
        ("面食", .noodle),
        ("汤羹", .soup),
        ("甜品", .dessert)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HorizontalTagBar(items: categories.map { $0.0 }, selectedIndex: $filterIndex)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(filtered, id: \.id) { r in
                            NavigationLink { RecipeDetailView(recipe: r) } label: {
                                cookCard(r)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    Spacer(minLength: 80)
                }
            }
            .background(Color.white)

            FABAddButton { showCreate = true }
        }
        .navigationTitle("烹饪管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) { CreateCookSheet() }
    }

    private var filtered: [CookRecipe] {
        let cat = categories[filterIndex].1
        return cat == .all ? list : list.filter { $0.category == cat }
    }

    private func cookCard(_ r: CookRecipe) -> some View {
        VStack(spacing: 0) {
            Text(r.emoji)
                .font(.system(size: 40))
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(
                    LinearGradient(colors: gradient(for: r.category),
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text(r.name).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                HStack(spacing: 6) {
                    Text(r.difficulty.label)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: 0xEEF3FD)))
                        .foregroundStyle(AppColorTheme.primary)
                    Text("\(r.minutes) 分钟")
                        .font(.system(size: 11))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(AppColorTheme.bg))
                        .foregroundStyle(AppColorTheme.textSub)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xF0F2F5), lineWidth: 1))
        .shadow(color: AppColorTheme.cardShadow, radius: 4, x: 0, y: 2)
    }

    private func gradient(for cat: CookCategory) -> [Color] {
        switch cat {
        case .home:    return [Color(hex: 0xC8E6C9), Color(hex: 0x81C784)]
        case .soup:    return [Color(hex: 0xC8E6C9), Color(hex: 0x81C784)]
        case .dessert: return [Color(hex: 0xE1BEE7), Color(hex: 0xBA8CCF)]
        case .noodle:  return [Color(hex: 0xFFE0B2), Color(hex: 0xFFAB6E)]
        case .all:     return [Color(hex: 0xFFE0B2), Color(hex: 0xFFAB6E)]
        }
    }
}

struct RecipeDetailView: View {
    let recipe: CookRecipe
    @Environment(\.modelContext) private var context
    @State private var toastVisible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(recipe.emoji).font(.system(size: 72))
                    .frame(maxWidth: .infinity).frame(height: 180)
                    .background(
                        LinearGradient(colors: [Color(hex: 0xFFE0B2), Color(hex: 0xFFAB6E)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 8) {
                    Text(recipe.difficulty.label)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: 0xEEF3FD)))
                        .foregroundStyle(AppColorTheme.primary)
                    Text("\(recipe.minutes) 分钟")
                        .font(.system(size: 12))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(AppColorTheme.bg))
                        .foregroundStyle(AppColorTheme.textSub)
                }

                if !recipe.ingredients.isEmpty {
                    section(title: "食材", content: recipe.ingredients)
                }
                if !recipe.steps.isEmpty {
                    section(title: "步骤", content: recipe.steps)
                }
                if !recipe.tips.isEmpty {
                    section(title: "小贴士", content: recipe.tips)
                }

                Button {
                    let todo = TodoItem(name: "尝试做\(recipe.name)", source: .cook, dueDate: Date())
                    context.insert(todo)
                    try? context.save()
                    withAnimation { toastVisible = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { toastVisible = false }
                    }
                } label: {
                    Text("加入今日烹饪计划")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppColorTheme.primary))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color.white)
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if toastVisible {
                Text("已加入今日待办")
                    .font(.system(size: 13))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.75)))
                    .foregroundStyle(.white)
                    .padding(.bottom, 32)
                    .transition(.opacity)
            }
        }
    }

    private func section(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(content).font(.system(size: 13))
                .foregroundStyle(AppColorTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
    }
}

struct CreateCookSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🍲"
    @State private var minutes = 30
    @State private var difficulty: CookDifficulty = .easy
    @State private var category: CookCategory = .home
    @State private var ingredients = ""
    @State private var steps = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("菜名", text: $name)
                    TextField("Emoji", text: $emoji)
                }
                Section {
                    Picker("难度", selection: $difficulty) {
                        ForEach(CookDifficulty.allCases, id: \.self) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    Stepper("时长：\(minutes) 分钟", value: $minutes, in: 5...240, step: 5)
                    Picker("分类", selection: $category) {
                        Text("家常菜").tag(CookCategory.home)
                        Text("面食").tag(CookCategory.noodle)
                        Text("汤羹").tag(CookCategory.soup)
                        Text("甜品").tag(CookCategory.dessert)
                    }
                }
                Section("食材") {
                    TextField("换行输入食材", text: $ingredients, axis: .vertical).lineLimit(3...8)
                }
                Section("步骤") {
                    TextField("按序号写", text: $steps, axis: .vertical).lineLimit(3...10)
                }
            }
            .navigationTitle("新增菜谱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let r = CookRecipe(name: name.isEmpty ? "未命名" : name,
                                           emoji: emoji, difficulty: difficulty,
                                           minutes: minutes, category: category,
                                           ingredients: ingredients, steps: steps)
                        context.insert(r)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
