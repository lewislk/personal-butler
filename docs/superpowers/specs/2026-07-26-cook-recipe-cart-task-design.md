# 烹饪管理 · 点菜 / 烹饪车 / 烹饪任务 设计文档

- 日期：2026-07-26
- 范围：`CookRecipe` 模块（录入、列表、详情）+ `TodoItem` 扩展（任务类型 / 菜谱回链）+ `HomeView` 任务层联动
- 关联模块：`CookRecipe` / `TodoItem` / `HomeView` / `BackupSync`
- 同步版本：`SyncMeta.dataVersion` 3 → 4

---

## 1. 目标

在现有烹饪菜谱模块基础上补齐「点菜 → 提交烹饪任务 → 主页追踪」的端到端流程：

1. **录入层**：食材标准化（结构化子模型）；菜名一键清除；图标选择复用 `IconPickerSheet`（注入菜肴专用 emoji）；录入下一项时键盘自动收起；补齐 `tips` 字段表单；列表/详情图标可点进入编辑。
2. **烹饪车**：菜谱可加入烹饪车（落库）；底部 bar 显示车项数 + 提交按钮；提交时生成「1 条准备食材任务 + N 条烹饪任务」并清空车。
3. **任务层**：主页 7 天窗口内区分 prep / cook 两类任务；点击 prep 弹食材清单（可逐项勾选，全选后自动完成）；点击 cook 弹步骤 + tips（只读，一键完成）。

---

## 2. 数据模型

### 2.1 新增 `CookIngredient` @Model

文件：`Domain/Models/CookIngredient.swift`

```swift
@Model
final class CookIngredient {
    @Attribute(.unique) var id: UUID
    var recipe: CookRecipe?           // 多对一反向关系
    var name: String                  // "番茄"
    var amount: String                // "2 个" — 数量与单位合并（用户输入）
    var order: Int                    // 录入顺序，列表稳定排序
    var createdAt: Date

    init(name: String, amount: String = "", order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.order = order
        self.createdAt = Date()
    }
}
```

**字段说明**：

- `amount` 兼容 "2 个" / "少许" / "200g" 等自由格式（数量与单位不拆分，窄屏友好）。
- `order` 用于列表渲染稳定排序，新增行追加最大 order+1。

### 2.2 新增 `CookCart` @Model

文件：`Domain/Models/CookCart.swift`

```swift
@Model
final class CookCart {
    @Attribute(.unique) var id: UUID
    var recipe: CookRecipe?           // 多对一
    var servings: Int                 // 份数，默认 1
    var addedAt: Date

    init(recipe: CookRecipe?, servings: Int = 1) {
        self.id = UUID()
        self.recipe = recipe
        self.servings = servings
        self.addedAt = Date()
    }
}
```

- 删除菜谱时 cart 项 cascade 删除（`CookRecipe` 持有 `@Relationship(deleteRule: .cascade) var cartItems: [CookCart]`，反向不需查询）。

### 2.3 扩展 `CookRecipe` @Model

文件：`Domain/Models/CookRecipe.swift`

**变更**：

| 操作 | 字段 | 类型 | 说明 |
|---|---|---|---|
| 重命名 | `ingredients: String` → `ingredientsLegacyRaw: String` | `String` | 旧多行文本，迁移用，不删 |
| 新增 | `ingredients: [CookIngredient]` | `@Relationship(deleteRule: .cascade)` | 结构化食材 |
| 新增 | `iconImage: Data?` | `@Attribute(.externalStorage)` | 图片图标，与 `FoodRecord` 一致 |

**默认值兼容**：

- `ingredientsLegacyRaw: String = ""`（迁移后保留旧文本）。
- `ingredients: [CookIngredient] = []`（关系默认空）。
- `iconImage: Data? = nil`。

### 2.4 扩展 `TodoItem` @Model

文件：`Domain/Models/TodoItem.swift`

**新增字段**（都带默认值 / Optional，兼容旧数据）：

```swift
var taskTypeRaw: String = TodoTaskType.none.rawValue   // "none" / "prep" / "cook"
var recipeId: UUID? = nil                              // 回链 CookRecipe.id（仅 cook 任务有值）
var expectedIngredientsRaw: String = ""                // prep 任务应有食材名称列表，逗号分隔，提交时冻结
var checkedIngredientsRaw: String = ""                 // prep 任务已勾选食材名称列表，逗号分隔
```

**字段语义**：

- `expectedIngredientsRaw` / `checkedIngredientsRaw` 仅 prep 任务使用，存食材**名称**（不是 UUID，因为 prep 任务是多菜合并，没有单一 recipe 反查路径）。
- prep 任务清单只存 name，不存 amount（用户在 prep sheet 里看到的是「番茄」「鸡蛋」等名称；要看 amount 去 cook 任务的 sheet 实时从 recipe 读）。

**新增枚举**：

```swift
enum TodoTaskType: String, Codable, CaseIterable {
    case none   // 普通待办（含日程/纪念日/手动/旧 cook 待办）
    case prep   // 准备食材
    case cook   // 烹饪
    var label: String {
        switch self {
        case .none: return ""
        case .prep: return "准备"
        case .cook: return "烹饪"
        }
    }
}
```

**计算属性**：`var taskType: TodoTaskType { .init(rawValue: taskTypeRaw) ?? .none }`

### 2.5 兼容旧数据

- 旧 `TodoItem`（包括旧 `.cook` 来源的「尝试做 X」待办）：`taskTypeRaw = "none"`（默认）、`recipeId = nil`、`checkedIngredientsRaw = ""`。
- HomeView 按普通待办渲染，行为不变。
- 旧的 `RecipeDetailView` "加入今日烹饪计划" 按钮**移除**，替换为"加入烹饪车"。

---

## 3. 录入层

### 3.1 `CreateCookSheet` → `CookRecipeEditSheet`

文件：`Presentation/Views/SubPages/CookRecipeView.swift`（同文件内重命名）

**复用新增/编辑**：参考 `EditFoodSheet` 模式，`init(recipe: CookRecipe?)` 区分模式。

### 3.2 表单结构（按需求逐项落实）

#### ① 菜名一键清除

```swift
Section("基础信息") {
    HStack {
        TextField("菜名", text: $name)
            .focused($focusedField, equals: .name)
        if !name.isEmpty {
            Button { name = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    // 图标 row（见 ③）
}
```

#### ② 食材标准化录入（2 列动态行）

```swift
Section("食材") {
    ForEach($ingredients) { $ing in
        HStack {
            TextField("名称", text: $ing.name)
                .focused($focusedField, equals: .ingredientName(ing.id))
                .frame(maxWidth: .infinity)
            TextField("数量/单位", text: $ing.amount, prompt: Text("如 2 个"))
                .focused($focusedField, equals: .ingredientAmount(ing.id))
                .frame(width: 90)
            Button { deleteIngredient(ing.id) } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
    Button {
        appendIngredient()   // 内部 focusedField = nil 收键盘后 append
    } label: {
        Label("添加食材", systemImage: "plus.circle")
    }
}
```

**初始**：`@State private var ingredients: [IngredientDraft] = [.init()]`（默认 1 个空行）。

**IngredientDraft**（私有 `@State` 草稿，不直接绑 `@Model`）：

```swift
private struct IngredientDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var amount: String = ""
}
```

#### ③ 图标选择复用 `IconPickerSheet`

`IconPickerSheet` 修改为支持注入 emoji 列表：

```swift
struct IconPickerSheet: View {
    var emojiCandidates: [String] = IconPickerSheet.defaultFoodEmoji   // 新增默认参数
    // ...
    static let defaultFoodEmoji = [/* 现有 30 个 emoji，Food 调用方不传 = 行为不变 */]
    static let cookEmoji = [
        "🍳", "🥘", "🥗", "🍲", "🍜", "🍚", "🍛", "🍢",
        "🍣", "🍤", "🥟", "🍝", "🍞", "🥖", "🧀", "🍗",
        "🍖", "🥩", "🍔", "🍟", "🍕", "🌭", "🌮", "🌯",
        "🥙", "🥚", "🥞", "🧇", "🥓", "🥪"
    ]
}
```

- `CookRecipe` 调用：`IconPickerSheet(current: icon, emojiCandidates: .cook)`
- `FoodRecord` 调用：不传 `emojiCandidates`（保持现有行为）。
- `CookRecipe` 新增 `iconImage: Data?`，预览优先 `iconImage` 否则 emoji（与 `FoodRecord` 一致）。

#### ④ 录入下一项时键盘收起

```swift
@FocusState private var focusedField: CookField?

enum CookField: Hashable {
    case name
    case ingredientName(UUID)
    case ingredientAmount(UUID)
    case steps
    case tips
}
```

**触发收键盘的场景**：

- 切换 `Picker`（难度/分类）→ `focusedField = nil`
- 切换 `Stepper`（时长）→ `focusedField = nil`
- 点击"添加食材"按钮 → `focusedField = nil` + append 新行
- 点击"删除食材"按钮 → `focusedField = nil` + delete
- 点击图标 row 弹 `IconPickerSheet` → `focusedField = nil`
- toolbar「完成」按钮 → `focusedField = nil` + save

#### ⑤ `tips` 字段补齐

```swift
Section("小贴士") {
    TextField("如：盐少许、火候控制...", text: $tips, axis: .vertical)
        .lineLimit(2...6)
        .focused($focusedField, equals: .tips)
}
```

### 3.3 表单 Section 顺序

1. 基础信息：菜名（一键清除）+ 图标（整行点击弹 picker）
2. 参数：难度 Picker / 时长 Stepper / 分类 Picker
3. 食材：动态行列表 + "添加食材"按钮
4. 步骤：多行 TextField（`lineLimit(3...10)`）
5. 小贴士：多行 TextField（`lineLimit(2...6)`）
6. toolbar：取消（leading） / 完成（trailing）

### 3.4 编辑模式数据回填

```swift
init(recipe: CookRecipe?) {
    self.recipe = recipe
    if let r = recipe {
        _name = State(initialValue: r.name)
        _emoji = State(initialValue: r.emoji)
        _iconImage = State(initialValue: r.iconImage)
        _difficulty = State(initialValue: r.difficulty)
        _minutes = State(initialValue: r.minutes)
        _category = State(initialValue: r.category)
        _steps = State(initialValue: r.steps)
        _tips = State(initialValue: r.tips)
        _ingredients = State(initialValue: r.ingredients
            .sorted { $0.order < $1.order }
            .map { IngredientDraft(id: $0.id, name: $0.name, amount: $0.amount) })
    } else {
        _ingredients = State(initialValue: [IngredientDraft()])
    }
}
```

**注意**：`IngredientDraft.id` 用 `CookIngredient.id`（编辑模式下保留原 id，保存时按 id 匹配更新；新增模式下 `IngredientDraft.id = UUID()` 由保存逻辑生成新 `CookIngredient`）。

### 3.5 保存逻辑

```swift
private func save() {
    let context = modelContext
    if let r = recipe {
        // 编辑：更新 recipe 字段
        r.name = name.isEmpty ? "未命名" : name
        r.emoji = emoji
        r.iconImage = iconImage
        r.difficulty = difficulty
        r.minutes = minutes
        r.category = category
        r.steps = steps
        r.tips = tips
        // 删除旧 ingredients
        for old in r.ingredients { context.delete(old) }
        // 插入新 ingredients
        for (i, draft) in ingredients.enumerated() where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let ing = CookIngredient(name: draft.name, amount: draft.amount, order: i)
            ing.recipe = r
            context.insert(ing)
        }
    } else {
        // 新增
        let r = CookRecipe(name: name.isEmpty ? "未命名" : name,
                           emoji: emoji, difficulty: difficulty,
                           minutes: minutes, category: category,
                           steps: steps, tips: tips)
        r.iconImage = iconImage
        context.insert(r)
        for (i, draft) in ingredients.enumerated() where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let ing = CookIngredient(name: draft.name, amount: draft.amount, order: i)
            ing.recipe = r
            context.insert(ing)
        }
    }
    try? context.save()
    dismiss()
}
```

---

## 4. 列表层

### 4.1 `CookRecipeView` 列表卡片改造

**⑥ 图标点击进入编辑**

```swift
private func cookCard(_ recipe: CookRecipe) -> some View {
    NavigationLink {
        RecipeDetailView(recipe: recipe)
    } label: {
        VStack(spacing: 0) {
            iconArea(recipe)            // 顶部图标区
                .onTapGesture {
                    editingRecipe = recipe   // 触发 CookRecipeEditSheet(recipe:)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            // 底部菜名 + 标签
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name).font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    CapsuleLabel(recipe.difficulty.label)
                    CapsuleLabel("\(recipe.minutes) 分钟")
                }
            }
            .padding(8)
        }
    }
    .buttonStyle(.plain)
}
```

**图标渲染优先级**：

```swift
@ViewBuilder
private func iconArea(_ recipe: CookRecipe) -> some View {
    ZStack {
        LinearGradient(...).clipShape(RoundedRectangle(cornerRadius: 12))
        if let data = recipe.iconImage, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(height: 100).clipped()
        } else {
            Text(recipe.emoji).font(.system(size: 40))
        }
    }
    .frame(height: 100)
}
```

**状态**：

```swift
@State private var editingRecipe: CookRecipe?
// .sheet(item: $editingRecipe) { CookRecipeEditSheet(recipe: $0) }
```

### 4.2 `RecipeDetailView` 改造

- 顶部图标区也可点 → `editingRecipe = recipe`。
- toolbar：
  - trailing：`EditButton`（pencil）→ `editingRecipe = recipe`
  - trailing：`DeleteButton`（trash）→ 二次确认 alert → `context.delete(recipe)` + dismiss
- 底部按钮：**"加入烹饪车"**（替换原"加入今日烹饪计划"）

```swift
Button {
    let cart = CookCart(recipe: recipe, servings: 1)
    modelContext.insert(cart)
    try? modelContext.save()
    showToast = true
} label: {
    Label("加入烹饪车", systemImage: "cart.badge.plus")
        .frame(maxWidth: .infinity)
}
.buttonStyle(.borderedProminent)
```

### 4.3 烹饪车 bar

**列表页底部浮动 bar**：

```swift
ZStack(alignment: .bottomTrailing) {
    ScrollView { /* 列表内容 */ }
    if !cartItems.isEmpty {
        VStack {
            Spacer()
            cartBar
                .padding(.horizontal, 16)
                .padding(.bottom, 80)   // 避开 FAB
        }
    }
    FABAddButton { showCreate = true }
}
```

**cartBar 实现**：

```swift
private var cartBar: some View {
    HStack(spacing: 12) {
        Image(systemName: "cart.fill")
        Text("烹饪车：\(cartItems.count) 道菜")
            .font(.system(size: 14, weight: .medium))
        Spacer()
        Button("提交烹饪任务") {
            showSubmitConfirm = true
        }
        .buttonStyle(.borderedProminent)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .background(.regularMaterial, in: Capsule())
    .onTapGesture { showCartSheet = true }   // 点 bar 中央打开详情 sheet
}
```

### 4.4 `CookCartSheet`（车详情）

```swift
struct CookCartSheet: View {
    @Query(sort: \CookCart.addedAt) var cartItems: [CookCart]
    @Environment(\.modelContext) var context
    @Binding var showSubmitConfirm: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(cartItems) { item in
                    HStack {
                        emojiBlock(item.recipe)
                        VStack(alignment: .leading) {
                            Text(item.recipe?.name ?? "未知菜").font(.weight(.semibold))
                            Stepper("份数：\(item.servings)", value: Binding(
                                get: { item.servings },
                                set: { item.servings = $0; try? context.save() }
                            ), in: 1...20)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            context.delete(item); try? context.save()
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
            .navigationTitle("烹饪车")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("提交烹饪任务") { showSubmitConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(cartItems.isEmpty)
                }
            }
        }
    }
}
```

---

## 5. 提交烹饪任务

### 5.1 `SubmitCookTaskUseCase`

文件：`Domain/UseCases/SubmitCookTaskUseCase.swift`

```swift
@MainActor
struct SubmitCookTaskUseCase {
    func execute(context: ModelContext) throws {
        let carts = (try? context.fetch(FetchDescriptor<CookCart>())) ?? []
        guard !carts.isEmpty else { return }

        // 1. 聚合食材：按 name 完全相等去重（不合并 amount，不单位换算）
        //    prep 任务清单只存 name，不存 amount（详见 §2.4 字段语义）
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
        let prepTodo = TodoItem(name: "准备食材（\(carts.count) 道菜）",
                                source: .cook,
                                taskType: .prep,
                                dueDate: Date(),
                                recipeId: nil,
                                expectedIngredients: expectedIngredients,
                                checkedIngredients: [])
        context.insert(prepTodo)

        // 3. 每道菜生成 1 条 cook 任务
        for cart in carts {
            guard let recipe = cart.recipe else { continue }
            let cookTodo = TodoItem(name: "烹饪：\(recipe.name)",
                                    source: .cook,
                                    taskType: .cook,
                                    recipeId: recipe.id,
                                    dueDate: Date())
            context.insert(cookTodo)
        }

        // 4. 清空购物车
        for cart in carts { context.delete(cart) }
        try context.save()
    }
}
```

**`TodoItem` 新增便利初始化**（保留旧 init 兼容）：

```swift
convenience init(name: String,
                 source: TodoSource,
                 taskType: TodoTaskType = .none,
                 dueDate: Date? = nil,
                 recipeId: UUID? = nil,
                 expectedIngredients: [String] = [],
                 checkedIngredients: [String] = []) {
    self.init(name: name, source: source, dueDate: dueDate)
    self.taskTypeRaw = taskType.rawValue
    self.recipeId = recipeId
    self.expectedIngredientsRaw = expectedIngredients.joined(separator: ",")
    self.checkedIngredientsRaw = checkedIngredients.joined(separator: ",")
}
```

**食材快照决策**：

- cook 任务**不快照**步骤/tips（第 6 问已确认），sheet 实时从 recipe 读。
- prep 任务**冻结应有食材名称列表**到 `expectedIngredientsRaw`（提交时刻），防止用户后续修改菜谱后旧 prep 任务清单跟着变。
- prep 任务**不存 amount**（用户在 prep sheet 看到的是食材名称清单，要看 amount 去 cook 任务 sheet）。

### 5.2 二次确认

`CookRecipeView` 提交按钮：

```swift
.alert("提交烹饪任务", isPresented: $showSubmitConfirm) {
    Button("取消", role: .cancel) { }
    Button("提交") {
        try? SubmitCookTaskUseCase().execute(context: modelContext)
        showToast = true
    }
} message: {
    if let cart = cartItems.first, cartItems.count == 1 {
        Text("将生成 1 条准备食材任务 + 1 条烹饪任务，并清空烹饪车。")
    } else {
        Text("将生成 1 条准备食材任务 + \(cartItems.count) 条烹饪任务，并清空烹饪车。")
    }
}
```

---

## 6. 任务层与主页联动

### 6.1 `HomeView` 改造

#### 排序调整

```swift
items.sorted { a, b in
    if a.isDone != b.isDone { return !a.isDone && b.isDone }
    if a.taskType != b.taskType {
        let order: [TodoTaskType: Int] = [.prep: 0, .cook: 1, .none: 2]
        return order[a.taskType]! < order[b.taskType]!
    }
    return a.sortDate < b.sortDate
}
```

#### TodoDisplay 扩展

```swift
private struct TodoDisplay: Identifiable {
    let id: String
    let name: String
    let sourceLabel: String
    let timeLabel: String
    let isUrgent: Bool
    let isDone: Bool
    let sortDate: Date
    let refSchedule: ScheduleEvent?
    let refManual: TodoItem?
    let taskType: TodoTaskType       // 新增
    let recipeId: UUID?              // 新增（仅 cook）
    let expectedIngredients: [String] // 新增（仅 prep，从 expectedIngredientsRaw split）
    let checkedIngredients: [String]  // 新增（仅 prep，从 checkedIngredientsRaw split）
}
```

#### 渲染分发

```swift
@ViewBuilder
private func row(for item: TodoDisplay) -> some View {
    switch item.taskType {
    case .prep:
        PrepTodoRow(item: item,
                    onToggle: { toggle(item) },
                    onTap: { prepSheetItem = item })
    case .cook:
        CookTodoRow(item: item,
                    onToggle: { toggle(item) },
                    onTap: { cookSheetItem = item })
    case .none:
        TodoItemRow(name: item.name, source: item.sourceLabel,
                    timeLabel: item.timeLabel, urgent: item.isUrgent,
                    isDone: item.isDone, onToggle: { toggle(item) })
    }
}
```

### 6.2 `PrepTodoRow`（私有组件，HomeView 同文件）

```swift
private struct PrepTodoRow: View {
    let item: TodoDisplay
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) { /* 圆形勾选 */ }
                .buttonStyle(.plain)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 14, weight: .medium))
                    Text("\(item.checkedIngredients.count)/\(item.expectedIngredients.count) 已买")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.timeLabel).font(.caption2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
```

### 6.3 `CookTodoRow`（私有组件）

```swift
private struct CookTodoRow: View {
    let item: TodoDisplay
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) { /* 圆形勾选 */ }
                .buttonStyle(.plain)
            Button(action: onTap) {
                Text(item.name).font(.system(size: 14, weight: .medium))
                Spacer()
                Text("查看步骤").font(.caption2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
```

### 6.4 `PrepTaskSheet`

文件：`Presentation/Views/SubPages/Cook/PrepTaskSheet.swift`

```swift
struct PrepTaskSheet: View {
    let todo: TodoItem
    @Environment(\.modelContext) var context

    private var expected: [String] {
        todo.expectedIngredientsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    private var checked: Set<String> {
        Set(todo.checkedIngredientsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("食材清单") {
                    ForEach(expected, id: \.self) { name in
                        Button {
                            toggle(name)
                        } label: {
                            HStack {
                                Image(systemName: checked.contains(name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(name) ? AppColorTheme.primary : .secondary)
                                Text(name)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    Button("全部已购买") {
                        todo.checkedIngredientsRaw = expected.joined(separator: ",")
                        todo.isDone = true
                        try? context.save()
                    }
                }
            }
            .navigationTitle(todo.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func toggle(_ name: String) {
        var set = checked
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
        todo.checkedIngredientsRaw = set.sorted().joined(separator: ",")
        todo.isDone = set.count == expected.count && !expected.isEmpty
        try? context.save()
    }
}
```

### 6.5 `CookTaskSheet`

文件：`Presentation/Views/SubPages/Cook/CookTaskSheet.swift`

```swift
struct CookTaskSheet: View {
    let todo: TodoItem
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss

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
                            Text(r.name).font(.headline)
                            HStack {
                                Label(r.difficulty.label, systemImage: "gauge.medium")
                                Label("\(r.minutes) 分钟", systemImage: "clock")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        if !r.ingredients.isEmpty {
                            section("食材") {
                                ForEach(r.ingredients.sorted { $0.order < $1.order }) { ing in
                                    HStack {
                                        Text(ing.name)
                                        Spacer()
                                        Text(ing.amount).foregroundStyle(.secondary).font(.caption)
                                    }
                                }
                            }
                        }
                        if !r.steps.isEmpty {
                            section("步骤") { Text(r.steps).font(.system(size: 14)) }
                        }
                        if !r.tips.isEmpty {
                            section("小贴士") { Text(r.tips).font(.system(size: 14)).foregroundStyle(.secondary) }
                        }
                    }
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                        Text("菜谱已删除").foregroundStyle(.secondary)
                    }.padding(.top, 80)
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
}
```

### 6.6 toggle 行为

`HomeView.toggle(item:)` 扩展：

```swift
private func toggle(_ item: TodoDisplay) {
    if let todo = item.refManual {
        if item.taskType == .prep {
            // prep 圆圈点击 = 全部已买
            if todo.isDone {
                todo.checkedIngredientsRaw = ""
                todo.isDone = false
            } else {
                todo.checkedIngredientsRaw = item.expectedIngredients.joined(separator: ",")
                todo.isDone = true
            }
        } else {
            // cook / none：直接 toggle
            todo.isDone.toggle()
        }
        try? modelContext.save()
    } else if let sch = item.refSchedule {
        sch.isCompleted.toggle()
        try? modelContext.save()
    }
}
```

---

## 7. 迁移与同步

### 7.1 SwiftData 轻量级迁移

**容器注册**（`PersonalButlerApp.swift`）：

```swift
Schema([
    TodoItem.self, ScheduleEvent.self, Anniversary.self,
    FoodRecord.self,
    CookRecipe.self, CookIngredient.self, CookCart.self,   // CookIngredient / CookCart 新增
    Note.self, Password.self, OTP.self,
    AppModule.self, AppSetting.self
])
```

**首启迁移**（在 `bootstrap()` 里 `SeedData.ensureSeeded` 之后追加）：

```swift
func migrateCookIngredients(context: ModelContext) {
    let recipes = (try? context.fetch(FetchDescriptor<CookRecipe>())) ?? []
    for r in recipes {
        guard r.ingredients.isEmpty, !r.ingredientsLegacyRaw.isEmpty else { continue }
        let lines = r.ingredientsLegacyRaw.split(separator: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let ing = CookIngredient(name: trimmed, order: i)
            ing.recipe = r
            context.insert(ing)
        }
    }
    try? context.save()
}
```

- 旧多行文本按行拆，每行整体作为 `name`（不强行解析数量/单位，格式不统一）。
- `ingredientsLegacyRaw` 保留不删（迁移失败可回滚）。
- 幂等：`r.ingredients.isEmpty` 判断。

### 7.2 同步契约变更

按 AGENTS.md §8 要求：

1. `SyncRecipeDTO` 新增 `ingredients: [SyncIngredientDTO]`（id/name/amount/unit/order）。
2. 新增 `SyncCartDTO`（id/recipeId/servings/addedAt） + `SyncData.cartList`。
3. `SyncTodoDTO` 新增 `taskType` / `recipeId` / `expectedIngredients` / `checkedIngredients` 字段。
4. **`SyncMeta.dataVersion`: 3 → 4**。
5. `BackupSyncUseCase.buildPayload`：fetch `CookIngredient` / `CookCart`，组装到 payload。
6. `BackupSyncUseCase.applyPayload`：反向写入。
7. `ingredientsLegacyRaw` **不纳入同步**（本地遗留字段，新设备从 sync 拿到的就是结构化 ingredients）。

### 7.3 `SeedData` 调整

`seedRecipes` 补充结构化 `ingredients`（不再用 `ingredientsLegacyRaw`）+ 补充 `tips` 示例：

```swift
let r1 = CookRecipe(name: "番茄鸡蛋面", emoji: "🍅", difficulty: .easy,
                    minutes: 20, category: .noodle,
                    steps: "...", tips: "鸡蛋炒时加少许料酒去腥")
context.insert(r1)
["面条 200g", "番茄 2 个", "鸡蛋 2 枚"].enumerated().forEach { (i, name) in
    let ing = CookIngredient(name: name, amount: "", order: i)
    ing.recipe = r1
    context.insert(ing)
}
```

---

## 8. 风险与取舍

| 风险 | 影响 | 缓解 |
|---|---|---|
| `CookRecipe.ingredients` 字段重命名（String → [CookIngredient]）+ 旧字段保留为 `ingredientsLegacyRaw` | SwiftData 轻量迁移可能失败 | 字段重命名实际是「旧字段保留+新增关系」，无字段删除；与 `FoodRecord` V2→V3 一致。失败时迁移逻辑幂等，重试即可。 |
| `IconPickerSheet` 改为支持注入 emoji 列表可能影响 `EditFoodSheet` | Food 模块回归 | 新增 `emojiCandidates` 默认参数 = `defaultFoodEmoji`，Food 不传 = 行为不变。 |
| 食材合并仅按 name 完全相等 | "番茄" / "西红柿" 不合并 | 文档明确：用户需自行统一命名。后续可加"食材别名表"（YAGNI）。 |
| cook 任务不快照步骤，菜谱被改后任务 sheet 显示新内容 | 用户体验轻微割裂 | 第 6 问已确认接受。 |
| 烹饪车跨设备同步可能重复提交 | 多设备同时操作时任务重复 | 同步本身是手动触发，低频；接受。 |
| `SubmitCookTaskUseCase` 误提交 | 用户误点 | alert 二次确认。 |

---

## 9. 测试策略

按 AGENTS.md §10，项目当前无 XCTest，本次不补自动化测试（用户决策）。改为手动验证清单：

### 录入层

- [ ] 列表卡片图标点击 → 进入编辑 sheet（不跳详情）
- [ ] 详情页图标点击 / toolbar 编辑按钮 → 进入编辑 sheet
- [ ] 详情页 toolbar 删除按钮 → 二次确认 → 删除后返回列表
- [ ] 表单 5 个 Section 完整填写 + 保存
- [ ] 菜名输入后右侧出现 ✕，点击清除
- [ ] 食材动态加 / 删行
- [ ] 切换 Picker / Stepper / 点击图标 row → 键盘自动收起
- [ ] 图标点击弹 `IconPickerSheet`，菜肴专用 emoji 候选可见
- [ ] 相册选图 / 拍照选图 → 列表卡片显示图片图标
- [ ] tips 字段输入并保存

### 列表层 / 烹饪车

- [ ] 列表卡片图标显示图片优先（无图片显示 emoji）
- [ ] 详情页"加入烹饪车"按钮 → toast + 底部 cartBar 出现
- [ ] cartBar 显示车项数
- [ ] 点击 cartBar → `CookCartSheet` 列出菜品 + 份数 stepper + 删除按钮
- [ ] 调整份数 / 移除菜品后 cartBar 数量同步

### 提交任务

- [ ] 提交按钮 → 二次确认 alert → 提交后 cartBar 消失
- [ ] 主页今日待办区出现 1 条 prep + N 条 cook 任务
- [ ] prep 任务名 "准备食材（N 道菜）"
- [ ] cook 任务名 "烹饪：菜名"
- [ ] 同名食材在 prep 任务清单中合并显示

### 任务层

- [ ] prep 任务点击 row → 弹 `PrepTaskSheet`，显示食材清单
- [ ] 逐项勾选食材 → "X/N 已买" 实时更新
- [ ] 全部勾选 → prep 任务自动 isDone=true
- [ ] prep 任务点击圆形勾选 → 直接全选 + isDone=true
- [ ] 已完成 prep 任务点击圆形勾选 → 取消全选 + isDone=false
- [ ] cook 任务点击 row → 弹 `CookTaskSheet`，显示食材/步骤/tips
- [ ] cook 任务 `recipeId` 对应菜谱已删 → sheet 显示"菜谱已删除"
- [ ] cook 任务点击"完成烹饪" → isDone=true
- [ ] HomeView 排序：prep → cook → none，未完成优先

### 同步

- [ ] `SyncMeta.dataVersion == 4`
- [ ] 上传备份包含结构化 ingredients + cartList + 扩展字段
- [ ] 下载恢复后数据一致

---

## 10. 实现范围

### 新增文件（5）

- `Domain/Models/CookIngredient.swift`
- `Domain/Models/CookCart.swift`
- `Domain/UseCases/SubmitCookTaskUseCase.swift`
- `Presentation/Views/SubPages/Cook/PrepTaskSheet.swift`
- `Presentation/Views/SubPages/Cook/CookTaskSheet.swift`

### 修改文件

- `Domain/Models/CookRecipe.swift` — 重命名 `ingredients → ingredientsLegacyRaw`，新增 `ingredients: [CookIngredient]` 关系 + `iconImage: Data?`
- `Domain/Models/TodoItem.swift` — 新增 `taskTypeRaw` / `recipeId` / `checkedIngredientsRaw` / `expectedIngredientsRaw` + `TodoTaskType` 枚举
- `Presentation/Views/SubPages/CookRecipeView.swift` — 重命名 `CreateCookSheet → CookRecipeEditSheet` + 完整表单 + 列表图标可点编辑 + 烹饪车 bar
- `Presentation/Views/SubPages/Food/IconPickerSheet.swift` — 新增 `emojiCandidates` 参数 + `cookEmoji` 静态列表
- `Presentation/Views/MainTab/HomeView.swift` — `PrepTodoRow` / `CookTodoRow` + 排序 + sheet 弹出 + toggle 扩展
- `App/PersonalButlerApp.swift` — Schema 注册 `CookIngredient.self` / `CookCart.self` + 迁移调用
- `Data/LocalDataSource/SeedData.swift` — `seedRecipes` 改用结构化 ingredients + 补 tips 示例
- `Data/Mapper/SyncPayload.swift` — `SyncRecipeDTO.ingredients` / `SyncCartDTO` / `SyncTodoDTO` 扩展字段
- `Domain/UseCases/BackupSyncUseCase.swift` — `buildPayload` / `applyPayload` 扩展 + `dataVersion: 4`
- `docs/module-spec/module-cook-spec.md` — 更新模块 spec
- `docs/module-spec/module-backup-sync-spec.md` — 同步契约更新

---

## 11. 不做的事（YAGNI）

- 食材预设库 / 别名表（"番茄" ↔ "西红柿"）。
- 食材单位换算（"200g + 100g = 300g"）。
- prep / cook 任务支持未来日期（首版固定 `dueDate = Date()`）。
- cook 任务步骤快照。
- cook 任务步骤可勾选进度。
- 跨设备烹饪车并发提交去重。
- 自动化测试（用户决策）。
