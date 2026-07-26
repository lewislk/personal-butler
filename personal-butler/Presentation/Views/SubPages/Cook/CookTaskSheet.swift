//
//  CookTaskSheet.swift
//  烹饪任务详情：展示菜谱食材/步骤/小贴士 + 完成按钮
//

import SwiftUI
import SwiftData

struct CookTaskSheet: View {
    let todo: TodoItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allRecipes: [CookRecipe]

    private var recipe: CookRecipe? {
        guard let rid = todo.recipeId else { return nil }
        return allRecipes.first { $0.id == rid }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let r = recipe {
                    VStack(spacing: 16) {
                        iconArea(r)
                        VStack(spacing: 4) {
                            Text(r.name).font(.system(size: 18, weight: .semibold))
                            HStack(spacing: 12) {
                                Label(r.difficulty.label, systemImage: "gauge.medium")
                                Label("\(r.minutes) 分钟", systemImage: "clock")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if !r.ingredients.isEmpty {
                            section(title: "食材") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(r.ingredients.sorted { $0.order < $1.order }) { ing in
                                        HStack {
                                            Text(ing.name)
                                                .font(.system(size: 14))
                                            Spacer()
                                            Text(ing.amount)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        if !r.steps.isEmpty {
                            section(title: "步骤") {
                                Text(r.steps)
                                    .font(.system(size: 14))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !r.tips.isEmpty {
                            section(title: "小贴士") {
                                Text(r.tips)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("菜谱已删除")
                            .foregroundStyle(.secondary)
                        Text("任务仍可标记完成")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 80)
                }
            }
            .navigationTitle("烹饪任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("完成烹饪") {
                        todo.isDone = true
                        try? context.save()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func iconArea(_ r: CookRecipe) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFFE0B2), Color(hex: 0xFFAB6E)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let data = r.iconImage, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(r.emoji).font(.system(size: 64))
            }
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func section<Content: View>(title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
    }
}
