//
//  CookRecipeView.swift
//  烹饪管理
//

import SwiftUI
import SwiftData
import UIKit

struct CookRecipeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CookRecipe.name) private var list: [CookRecipe]
    @Query(sort: \CookCart.addedAt) private var cartItems: [CookCart]
    @State private var filterIndex: Int = 0
    @State private var showCreate = false
    @State private var editingRecipe: CookRecipe?
    @State private var showCartSheet = false
    @State private var showSubmitConfirm = false
    @State private var toastVisible = false

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
                    Spacer(minLength: 120)
                }
            }
            .background(Color.white)

            // 烹饪车 bar
            if !cartItems.isEmpty {
                VStack {
                    Spacer()
                    cartBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 88)
                }
            }

            FABAddButton { showCreate = true }
        }
        .navigationTitle("烹饪管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) { CookRecipeEditSheet(recipe: nil) }
        .sheet(item: $editingRecipe) { r in
            CookRecipeEditSheet(recipe: r)
        }
        .sheet(isPresented: $showCartSheet) {
            CookCartSheet(showSubmitConfirm: $showSubmitConfirm)
        }
        .alert("提交烹饪任务", isPresented: $showSubmitConfirm) {
            Button("取消", role: .cancel) { }
            Button("提交") {
                try? SubmitCookTaskUseCase().execute(context: context)
                withAnimation { toastVisible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { toastVisible = false }
                }
            }
        } message: {
            if cartItems.count == 1 {
                Text("将生成 1 条准备食材任务 + 1 条烹饪任务，并清空烹饪车。")
            } else {
                Text("将生成 1 条准备食材任务 + \(cartItems.count) 条烹饪任务，并清空烹饪车。")
            }
        }
        .overlay(alignment: .bottom) {
            if toastVisible {
                Text("已生成 \(cartItems.count + 1) 条任务")
                    .font(.system(size: 13))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.75)))
                    .foregroundStyle(.white)
                    .padding(.bottom, 32)
                    .transition(.opacity)
            }
        }
    }

    private var cartBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "cart.fill")
                .foregroundStyle(AppColorTheme.primary)
            Text("烹饪车：\(cartItems.count) 道菜")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColorTheme.text)
            Spacer()
            Button("提交") {
                showSubmitConfirm = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Capsule().fill(.regularMaterial))
        .shadow(color: AppColorTheme.cardShadow, radius: 8, x: 0, y: 4)
        .onTapGesture {
            showCartSheet = true
        }
    }

    private var filtered: [CookRecipe] {
        let cat = categories[filterIndex].1
        return cat == .all ? list : list.filter { $0.category == cat }
    }

    private func cookCard(_ r: CookRecipe) -> some View {
        VStack(spacing: 0) {
            iconArea(r)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(AppColorTheme.primary.opacity(0.85)))
                        .padding(6)
                }
                .onTapGesture {
                    editingRecipe = r
                }
                .contentShape(Rectangle())
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

    @ViewBuilder
    private func iconArea(_ r: CookRecipe) -> some View {
        ZStack {
            LinearGradient(colors: gradient(for: r.category),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let data = r.iconImage, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .clipped()
            } else {
                Text(r.emoji)
                    .font(.system(size: 40))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
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
    @Environment(\.dismiss) private var dismiss
    @State private var toastVisible = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                iconArea
                    .onTapGesture { showEdit = true }
                    .contentShape(Rectangle())

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

                if !recipe.ingredients.isEmpty || !recipe.ingredientsLegacyRaw.isEmpty {
                    section(title: "食材", content: ingredientsText)
                }
                if !recipe.steps.isEmpty {
                    section(title: "步骤", content: recipe.steps)
                }
                if !recipe.tips.isEmpty {
                    section(title: "小贴士", content: recipe.tips)
                }

                Button {
                    let cart = CookCart(recipe: recipe, servings: 1)
                    context.insert(cart)
                    try? context.save()
                    withAnimation { toastVisible = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { toastVisible = false }
                    }
                } label: {
                    Label("加入烹饪车", systemImage: "cart.badge.plus")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            CookRecipeEditSheet(recipe: recipe)
        }
        .alert("删除菜谱", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                context.delete(recipe)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("将删除「\(recipe.name)」及其食材清单，无法撤销。")
        }
        .overlay(alignment: .bottom) {
            if toastVisible {
                Text("已加入烹饪车")
                    .font(.system(size: 13))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.75)))
                    .foregroundStyle(.white)
                    .padding(.bottom, 32)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var iconArea: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFFE0B2), Color(hex: 0xFFAB6E)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let data = recipe.iconImage, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
            } else {
                Text(recipe.emoji).font(.system(size: 72))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var ingredientsText: String {
        if recipe.ingredients.isEmpty {
            return recipe.ingredientsLegacyRaw
        }
        return recipe.ingredients.sorted { $0.order < $1.order }
            .map { ing in ing.amount.isEmpty ? ing.name : "\(ing.name)  \(ing.amount)" }
            .joined(separator: "\n")
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

struct CookRecipeEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let recipe: CookRecipe?

    // 表单状态
    @State private var name: String = ""
    @State private var emoji: String = "🍲"
    @State private var iconImage: Data? = nil
    @State private var minutes: Int = 30
    @State private var difficulty: CookDifficulty = .easy
    @State private var category: CookCategory = .home
    @State private var ingredients: [IngredientDraft] = [.init()]
    @State private var steps: String = ""
    @State private var tips: String = ""

    // UI 状态
    @FocusState private var focusedField: CookField?
    @State private var showIconPicker: Bool = false

    private enum CookField: Hashable {
        case name
        case ingredientName(UUID)
        case ingredientAmount(UUID)
        case steps
        case tips
    }

    private struct IngredientDraft: Identifiable {
        let id: UUID
        var name: String
        var amount: String
        init(id: UUID = UUID(), name: String = "", amount: String = "") {
            self.id = id; self.name = name; self.amount = amount
        }
    }

    init(recipe: CookRecipe?) {
        self.recipe = recipe
        if let r = recipe {
            _name = State(initialValue: r.name)
            _emoji = State(initialValue: r.emoji)
            _iconImage = State(initialValue: r.iconImage)
            _minutes = State(initialValue: r.minutes)
            _difficulty = State(initialValue: r.difficulty)
            _category = State(initialValue: r.category)
            _steps = State(initialValue: r.steps)
            _tips = State(initialValue: r.tips)
            _ingredients = State(initialValue: r.ingredients.isEmpty
                ? [IngredientDraft()]
                : r.ingredients.sorted { $0.order < $1.order }
                    .map { IngredientDraft(id: $0.id, name: $0.name, amount: $0.amount) })
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 1. 基础信息
                Section {
                    HStack {
                        TextField("菜名", text: $name)
                            .focused($focusedField, equals: .name)
                        if !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        focusedField = nil
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text("图标")
                            Spacer()
                            iconPreview
                                .frame(width: 36, height: 36)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // 2. 参数
                Section {
                    Picker("难度", selection: $difficulty) {
                        ForEach(CookDifficulty.allCases, id: \.self) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .onChange(of: difficulty) { _, _ in focusedField = nil }
                    Stepper("时长：\(minutes) 分钟", value: $minutes, in: 5...240, step: 5)
                        .onChange(of: minutes) { _, _ in focusedField = nil }
                    Picker("分类", selection: $category) {
                        Text("家常菜").tag(CookCategory.home)
                        Text("面食").tag(CookCategory.noodle)
                        Text("汤羹").tag(CookCategory.soup)
                        Text("甜品").tag(CookCategory.dessert)
                    }
                    .onChange(of: category) { _, _ in focusedField = nil }
                }

                // 3. 食材
                Section("食材") {
                    ForEach($ingredients) { $ing in
                        HStack {
                            TextField("名称", text: $ing.name)
                                .focused($focusedField, equals: .ingredientName(ing.id))
                                .frame(maxWidth: .infinity)
                            TextField("数量/单位", text: $ing.amount, prompt: Text("如 2 个"))
                                .focused($focusedField, equals: .ingredientAmount(ing.id))
                                .frame(width: 90)
                            Button {
                                focusedField = nil
                                deleteIngredient(ing.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        focusedField = nil
                        ingredients.append(IngredientDraft())
                    } label: {
                        Label("添加食材", systemImage: "plus.circle")
                    }
                }

                // 4. 步骤
                Section("步骤") {
                    TextField("按序号写", text: $steps, axis: .vertical)
                        .lineLimit(3...10)
                        .focused($focusedField, equals: .steps)
                }

                // 5. 小贴士
                Section("小贴士") {
                    TextField("如：盐少许、火候控制...", text: $tips, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focusedField, equals: .tips)
                }
            }
            .navigationTitle(recipe == nil ? "新增菜谱" : "编辑菜谱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        focusedField = nil
                        save()
                    }
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerSheet(initial: currentIcon,
                                onConfirm: { newIcon in
                    applyIcon(newIcon)
                }, emojiCandidates: IconPickerSheet.cookEmoji)
            }
        }
    }

    // MARK: - Icon

    private var currentIcon: FoodIcon {
        if let data = iconImage { return .image(data) }
        return .emoji(emoji)
    }

    private func applyIcon(_ icon: FoodIcon) {
        switch icon {
        case .emoji(let s):
            emoji = s
            iconImage = nil
        case .image(let d):
            iconImage = d
        }
    }

    @ViewBuilder
    private var iconPreview: some View {
        if let data = iconImage, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppColorTheme.bg))
        }
    }

    // MARK: - Ingredient

    private func deleteIngredient(_ id: UUID) {
        ingredients.removeAll { $0.id == id }
        if ingredients.isEmpty { ingredients.append(IngredientDraft()) }
    }

    // MARK: - Save

    private func save() {
        if let r = recipe {
            r.name = name.isEmpty ? "未命名" : name
            r.emoji = emoji
            r.iconImage = iconImage
            r.difficultyRaw = difficulty.rawValue
            r.minutes = minutes
            r.categoryRaw = category.rawValue
            r.steps = steps
            r.tips = tips
            for old in r.ingredients { context.delete(old) }
            for (i, draft) in ingredients.enumerated()
            where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                let ing = CookIngredient(name: draft.name, amount: draft.amount, order: i)
                ing.recipe = r
                context.insert(ing)
            }
        } else {
            let r = CookRecipe(name: name.isEmpty ? "未命名" : name,
                               emoji: emoji, difficulty: difficulty,
                               minutes: minutes, category: category,
                               steps: steps, tips: tips)
            r.iconImage = iconImage
            context.insert(r)
            for (i, draft) in ingredients.enumerated()
            where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                let ing = CookIngredient(name: draft.name, amount: draft.amount, order: i)
                ing.recipe = r
                context.insert(ing)
            }
        }
        try? context.save()
        dismiss()
    }
}

struct CookCartSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CookCart.addedAt) private var cartItems: [CookCart]
    @Binding var showSubmitConfirm: Bool

    var body: some View {
        NavigationStack {
            Group {
                if cartItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cart")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("烹饪车为空")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(cartItems) { item in
                            cartRow(item)
                        }
                    }
                }
            }
            .navigationTitle("烹饪车")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showSubmitConfirm = false }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("提交烹饪任务") {
                        showSubmitConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cartItems.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func cartRow(_ item: CookCart) -> some View {
        HStack(spacing: 12) {
            if let r = item.recipe {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xFFE0B2), Color(hex: 0xFFAB6E)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let data = r.iconImage, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        Text(r.emoji).font(.system(size: 22))
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.recipe?.name ?? "未知菜")
                    .font(.system(size: 14, weight: .semibold))
                Stepper("份数：\(item.servings)", value: Binding(
                    get: { item.servings },
                    set: { item.servings = $0; try? context.save() }
                ), in: 1...20)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }
}
