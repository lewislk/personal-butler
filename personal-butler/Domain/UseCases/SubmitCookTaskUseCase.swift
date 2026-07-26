//
//  SubmitCookTaskUseCase.swift
//  提交烹饪任务：聚合食材 → 生成 1 条 prep + N 条 cook TodoItem → 清空烹饪车
//

import Foundation
import SwiftData

@MainActor
struct SubmitCookTaskUseCase {
    func execute(context: ModelContext) throws {
        let carts = (try? context.fetch(FetchDescriptor<CookCart>())) ?? []
        guard !carts.isEmpty else { return }

        // 1. 聚合食材：按 name 完全相等去重（不合并 amount，不单位换算）
        //    prep 任务清单只存 name（详见 spec §2.4 字段语义）
        var names: Set<String> = []
        for cart in carts {
            guard let recipe = cart.recipe else { continue }
            for ing in recipe.ingredients {
                let key = ing.name.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }
                names.insert(key)
            }
        }
        let expectedIngredients = names.sorted()   // 稳定排序

        // 2. 生成 1 条 prep 任务（合并所有食材）
        let prepTodo = TodoItem(
            name: "准备食材（\(carts.count) 道菜）",
            source: .cook,
            dueDate: Date(),
            taskType: .prep,
            recipeId: nil,
            expectedIngredients: expectedIngredients,
            checkedIngredients: []
        )
        context.insert(prepTodo)

        // 3. 每道菜生成 1 条 cook 任务
        for cart in carts {
            guard let recipe = cart.recipe else { continue }
            let cookTodo = TodoItem(
                name: "烹饪：\(recipe.name)",
                source: .cook,
                dueDate: Date(),
                taskType: .cook,
                recipeId: recipe.id,
                expectedIngredients: [],
                checkedIngredients: []
            )
            context.insert(cookTodo)
        }

        // 4. 清空购物车
        for cart in carts { context.delete(cart) }
        try context.save()
    }
}
