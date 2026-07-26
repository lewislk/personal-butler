# 烹饪管理点菜 / 烹饪车 / 烹饪任务 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 CookRecipe 模块上补齐「点菜 → 提交烹饪任务 → 主页追踪 prep/cook 任务」端到端流程，覆盖食材标准化录入、菜名一键清除、图标选择复用 IconPickerSheet、键盘自动收起、列表/详情图标可点编辑、烹饪车、提交任务、主页任务层联动。

**Architecture:** 新增 `CookIngredient` / `CookCart` 两个 SwiftData @Model；扩展 `CookRecipe`（关系 + iconImage）和 `TodoItem`（taskType / recipeId / expected/checkedIngredients）；新增 `SubmitCookTaskUseCase`、`PrepTaskSheet`、`CookTaskSheet`；改造 `CookRecipeView`（重命名 CreateCookSheet → CookRecipeEditSheet，列表图标可点编辑，烹饪车 bar）；改造 `HomeView`（PrepTodoRow / CookTodoRow + 排序 + sheet 弹出）；扩展同步 DTO 与 `dataVersion` 3→4。

**Tech Stack:** iOS 18+ SwiftUI / SwiftData / PhotosUI / CryptoKit（无新增依赖）

## Global Constraints

- iOS 18 最低版本（可用 iOS 18 新 API，无需 `if #available` 兜底）
- 纯 SwiftUI，禁止引入 UIKit（除 `UIImagePickerController` 系统集成必需）
- 简体中文 UI（locale: zh-Hans）；代码注释可中文；标识符英文
- SwiftData `@Model` 枚举字段用 `xxxRaw: String` 落库 + 计算属性读回类型
- `@Attribute(.unique) var id: UUID`（AppModule 例外 `id: String`）
- 新增字段必须带默认值 / Optional，兼容旧数据
- 同步 DTO 只增字段、不删字段、不改字段语义；变更必须递增 `SyncMeta.dataVersion`
- 路由 id `"cook"` / `TodoSource.cook` rawValue / `CookCategory` `CookDifficulty` rawValue 不可改名（永久稳定标识）
- Keychain 仅用于密码 / 2FA 密钥，禁止把明文写进 `@Model` 属性
- 项目当前无 XCTest；不补自动化测试（用户决策）
- 主色板走 `AppColorTheme.*`；圆角 12 / 8 / 6；间距 4/8/16/24；字号 20/16/14/12
- 图标一律 SF Symbols
- 复用组件：`SegmentedPill` / `MiniSegmentedPill` / `HorizontalTagBar` / `FABAddButton` / `TodoItemRow`
- 子页面顶部标题栏走 `.navigationTitle(...)` + `.navigationBarTitleDisplayMode(.inline)`

---

## 文件结构

### 新增文件（5）

| 文件 | 责任 |
|---|---|
| `personal-butler/Domain/Models/CookIngredient.swift` | 食材子模型，多对一关联 CookRecipe |
| `personal-butler/Domain/Models/CookCart.swift` | 烹饪车项，多对一关联 CookRecipe |
| `personal-butler/Domain/UseCases/SubmitCookTaskUseCase.swift` | 提交烹饪任务：聚合食材 + 生成 N+1 条 TodoItem + 清空车 |
| `personal-butler/Presentation/Views/SubPages/Cook/PrepTaskSheet.swift` | 准备食材任务详情 sheet（食材清单 + 逐项勾选） |
| `personal-butler/Presentation/Views/SubPages/Cook/CookTaskSheet.swift` | 烹饪任务详情 sheet（步骤 + tips + 完成按钮） |

### 修改文件（9）

| 文件 | 改动 |
|---|---|
| `personal-butler/Domain/Models/CookRecipe.swift` | 重命名 `ingredients: String` → `ingredientsLegacyRaw: String`；新增 `ingredients: [CookIngredient]` 关系 + `cartItems: [CookCart]` 关系 + `iconImage: Data?` |
| `personal-butler/Domain/Models/TodoItem.swift` | 新增 4 字段（taskTypeRaw / recipeId / expectedIngredientsRaw / checkedIngredientsRaw）+ `TodoTaskType` 枚举 + 便利 init |
| `personal-butler/Presentation/Views/SubPages/CookRecipeView.swift` | 重命名 `CreateCookSheet` → `CookRecipeEditSheet`（复用新增/编辑）+ 完整表单（食材动态行 / 一键清除 / IconPickerSheet / 键盘收起 / tips）+ 列表卡片图标可点编辑 + 详情页编辑/删除 + 烹饪车 bar + CookCartSheet + 提交二次确认 |
| `personal-butler/Presentation/Views/SubPages/Food/IconPickerSheet.swift` | 新增 `emojiCandidates` 参数（默认 `defaultFoodEmoji`）+ `cookEmoji` 静态列表 |
| `personal-butler/Presentation/Views/MainTab/HomeView.swift` | TodoDisplay 扩展 4 字段 + PrepTodoRow / CookTodoRow 私有组件 + 排序调整（prep→cook→none）+ sheet 弹出 + toggle 扩展 |
| `personal-butler/App/PersonalButlerApp.swift` | Schema 注册 `CookIngredient.self` / `CookCart.self` + 迁移调用 |
| `personal-butler/Data/LocalDataSource/SeedData.swift` | seedRecipes 改用结构化 ingredients + 补 tips 示例 |
| `personal-butler/Data/Mapper/SyncPayload.swift` | `SyncRecipeDTO.ingredients` 改为 `[SyncIngredientDTO]` + `ingredientsLegacyRaw` 字段 + 新增 `SyncIngredientDTO` / `SyncCartDTO` + `SyncData.cartList` + `SyncTodoDTO` 4 字段 |
| `personal-butler/Domain/UseCases/BackupSyncUseCase.swift` | buildPayload / restore 扩展 CookIngredient / CookCart + TodoItem 新字段 + `dataVersion: 4` |

---

## Task 1: 新增 `CookIngredient` @Model

**Files:**
- Create: `personal-butler/Domain/Models/CookIngredient.swift`

**Interfaces:**
- Produces: `CookIngredient` 类型，字段 `id: UUID` / `recipe: CookRecipe?` / `name: String` / `amount: String` / `order: Int` / `createdAt: Date`；init `(name: String, amount: String = "", order: Int = 0)`

- [ ] **Step 1: 创建 CookIngredient.swift**

```swift
//
//  CookIngredient.swift
//  菜谱食材子模型（标准化录入）
//

import Foundation
import SwiftData

@Model
final class CookIngredient {
    @Attribute(.unique) var id: UUID
    var recipe: CookRecipe?           // 多对一反向关系
    var name: String                  // "番茄"
    var amount: String                // "2 个" — 数量与单位合并
    var order: Int                    // 录入顺序，列表稳定排序
    var createdAt: Date

    init(id: UUID = UUID(), name: String, amount: String = "", order: Int = 0,
         createdAt: Date = .init()) {
        self.id = id
        self.name = name
        self.amount = amount
        self.order = order
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED（CookIngredient 已注册到 Schema 在 Task 6 完成；此处仅类型编译通过即可）

> 注：此时 CookIngredient 还未注册到 ModelContainer Schema，运行时会报错，但类型本身能编译。Task 6 会注册它。

- [ ] **Step 3: Commit**

```bash
git add personal-butler/Domain/Models/CookIngredient.swift
git commit -m "feat(cook): 新增 CookIngredient 食材子模型"
```

---

## Task 2: 新增 `CookCart` @Model

**Files:**
- Create: `personal-butler/Domain/Models/CookCart.swift`

**Interfaces:**
- Produces: `CookCart` 类型，字段 `id: UUID` / `recipe: CookRecipe?` / `servings: Int` / `addedAt: Date`；init `(recipe: CookRecipe?, servings: Int = 1)`

- [ ] **Step 1: 创建 CookCart.swift**

```swift
//
//  CookCart.swift
//  烹饪车项（用户加车未提交）
//

import Foundation
import SwiftData

@Model
final class CookCart {
    @Attribute(.unique) var id: UUID
    var recipe: CookRecipe?           // 多对一
    var servings: Int                 // 份数，默认 1
    var addedAt: Date

    init(id: UUID = UUID(), recipe: CookRecipe?, servings: Int = 1,
         addedAt: Date = .init()) {
        self.id = id
        self.recipe = recipe
        self.servings = servings
        self.addedAt = addedAt
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add personal-butler/Domain/Models/CookCart.swift
git commit -m "feat(cook): 新增 CookCart 烹饪车模型"
```

---

## Task 3: 扩展 `CookRecipe` @Model

**Files:**
- Modify: `personal-butler/Domain/Models/CookRecipe.swift`

**Interfaces:**
- Consumes: `CookIngredient`（Task 1）/ `CookCart`（Task 2）
- Produces: `CookRecipe.ingredients: [CookIngredient]` 关系（cascade delete）；`CookRecipe.cartItems: [CookCart]` 关系（cascade delete）；`CookRecipe.iconImage: Data?`；`CookRecipe.ingredientsLegacyRaw: String`（重命名自 `ingredients`）

- [ ] **Step 1: 修改 CookRecipe.swift**

完整替换文件内容：

```swift
//
//  CookRecipe.swift
//

import Foundation
import SwiftData

enum CookCategory: String, Codable, CaseIterable {
    case all, home, noodle, soup, dessert

    var label: String {
        switch self {
        case .all: return "全部菜谱"
        case .home: return "家常菜"
        case .noodle: return "面食"
        case .soup: return "汤羹"
        case .dessert: return "甜品"
        }
    }
}

enum CookDifficulty: String, Codable, CaseIterable {
    case easy, medium, hard
    var label: String {
        switch self {
        case .easy: return "简单"
        case .medium: return "中等"
        case .hard: return "进阶"
        }
    }
}

@Model
final class CookRecipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var difficultyRaw: String
    var minutes: Int
    var categoryRaw: String

    /// 旧版多行文本食材字段（迁移用，不删；新代码请用 `ingredients: [CookIngredient]`）
    var ingredientsLegacyRaw: String
    /// 结构化食材（与 CookIngredient 一对多）
    @Relationship(deleteRule: .cascade) var ingredients: [CookIngredient]
    /// 烹饪车项（与 CookCart 一对多；删除菜谱时 cascade 删除车项）
    @Relationship(deleteRule: .cascade) var cartItems: [CookCart]

    var steps: String         // 多行
    var tips: String

    /// 图片图标（JPEG 二进制，与 FoodRecord 一致）
    @Attribute(.externalStorage) var iconImage: Data?

    init(id: UUID = UUID(), name: String, emoji: String = "🍲",
         difficulty: CookDifficulty = .easy, minutes: Int = 30,
         category: CookCategory = .home,
         ingredientsLegacyRaw: String = "",
         ingredients: [CookIngredient] = [],
         cartItems: [CookCart] = [],
         steps: String = "", tips: String = "",
         iconImage: Data? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.difficultyRaw = difficulty.rawValue
        self.minutes = minutes
        self.categoryRaw = category.rawValue
        self.ingredientsLegacyRaw = ingredientsLegacyRaw
        self.ingredients = ingredients
        self.cartItems = cartItems
        self.steps = steps
        self.tips = tips
        self.iconImage = iconImage
    }

    var difficulty: CookDifficulty { CookDifficulty(rawValue: difficultyRaw) ?? .easy }
    var category: CookCategory { CookCategory(rawValue: categoryRaw) ?? .home }
}
```

**关键变更说明**：

- 旧 `var ingredients: String` → 重命名为 `var ingredientsLegacyRaw: String`（保留默认空串，兼容旧 SwiftData 数据）
- 新 `var ingredients: [CookIngredient]` 是 `@Relationship`（SwiftData 见到 `[CookIngredient]` 自动建反向关系 `CookIngredient.recipe`）
- 新 `var cartItems: [CookCart]` 同上
- 新 `var iconImage: Data?` 用 `@Attribute(.externalStorage)` 与 `FoodRecord` 一致
- 旧 init 签名 `ingredients: String` 改为 `ingredientsLegacyRaw: String` + 新增 `ingredients` / `cartItems` / `iconImage` 参数（都有默认值）

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -30`
Expected: 多处编译错误（调用方还在用旧 `ingredients: String` 参数），下一步会修复

- [ ] **Step 3: 修复 SeedData.swift 调用方**

文件：`personal-butler/Data/LocalDataSource/SeedData.swift`

替换 `seedRecipes(_ ctx: ModelContext)` 整个方法（当前第 113-125 行）：

```swift
private static func seedRecipes(_ ctx: ModelContext) {
    struct R {
        let name: String; let emoji: String; let difficulty: CookDifficulty
        let minutes: Int; let category: CookCategory
        let ingredients: [(name: String, amount: String)]
        let steps: String; let tips: String
    }
    let list: [R] = [
        .init(name: "番茄鸡蛋面", emoji: "🍅", difficulty: .easy, minutes: 20, category: .noodle,
              ingredients: [("面条", "200g"), ("番茄", "2 个"), ("鸡蛋", "2 枚")],
              steps: "1. 番茄去皮切块\n2. 鸡蛋炒散\n3. 加水煮面 10 分钟",
              tips: "鸡蛋炒时加少许料酒去腥"),
        .init(name: "蒜蓉炒时蔬", emoji: "🥬", difficulty: .easy, minutes: 10, category: .home,
              ingredients: [("时蔬", "1 把"), ("蒜蓉", "适量")],
              steps: "1. 蒜蓉爆香\n2. 大火快炒 2 分钟",
              tips: ""),
        .init(name: "红烧肉", emoji: "🍖", difficulty: .medium, minutes: 90, category: .home,
              ingredients: [("五花肉", "500g"), ("冰糖", "30g"), ("生抽", "2 勺")],
              steps: "1. 五花肉焯水\n2. 冰糖炒糖色\n3. 加生抽炖 60 分钟",
              tips: "糖色炒至琥珀色即可，过头发苦"),
        .init(name: "舒芙蕾松饼", emoji: "🍰", difficulty: .hard, minutes: 40, category: .dessert,
              ingredients: [("鸡蛋", "2 枚"), ("低筋面粉", "60g"), ("牛奶", "100ml")],
              steps: "1. 蛋黄 + 面粉 + 牛奶拌匀\n2. 蛋白打发\n3. 小火煎 8 分钟",
              tips: "蛋白打发到硬性发泡"),
        .init(name: "日式豚骨拉面", emoji: "🍜", difficulty: .hard, minutes: 120, category: .noodle,
              ingredients: [("拉面", "2 人份"), ("叉烧", "4 片"), ("溏心蛋", "2 枚")],
              steps: "1. 豚骨汤熬 90 分钟\n2. 煮面 3 分钟\n3. 摆盘",
              tips: ""),
        .init(name: "冬瓜排骨汤", emoji: "🍲", difficulty: .easy, minutes: 60, category: .soup,
              ingredients: [("排骨", "300g"), ("冬瓜", "200g")],
              steps: "1. 排骨焯水\n2. 加冬瓜炖 40 分钟",
              tips: "冬瓜后放避免煮烂"),
    ]
    for r in list {
        let recipe = CookRecipe(name: r.name, emoji: r.emoji,
                                difficulty: r.difficulty, minutes: r.minutes,
                                category: r.category,
                                steps: r.steps, tips: r.tips)
        ctx.insert(recipe)
        for (i, ing) in r.ingredients.enumerated() {
            let m = CookIngredient(name: ing.name, amount: ing.amount, order: i)
            m.recipe = recipe
            ctx.insert(m)
        }
    }
}
```

- [ ] **Step 4: 修复 CookRecipeView.swift 中 CreateCookSheet 调用方**

文件：`personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

第 235-238 行（CreateCookSheet 保存逻辑里的 `CookRecipe(name:emoji:difficulty:minutes:category:ingredients:steps:)`）改为：

```swift
let r = CookRecipe(name: name.isEmpty ? "未命名" : name,
                   emoji: emoji, difficulty: difficulty,
                   minutes: minutes, category: category,
                   steps: steps)
context.insert(r)
try? context.save()
dismiss()
```

> 注：Task 8 会完整重写 CookRecipeEditSheet，此处仅是临时修复让编译通过。

- [ ] **Step 5: 修复 RecipeDetailView.swift 中 `recipe.ingredients` 调用**

文件：`personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

第 131-133 行：

```swift
if !recipe.ingredients.isEmpty {
    section(title: "食材", content: recipe.ingredients)
}
```

改为：

```swift
if !recipe.ingredientsLegacyRaw.isEmpty || !recipe.ingredients.isEmpty {
    let content = recipe.ingredients.isEmpty
        ? recipe.ingredientsLegacyRaw
        : recipe.ingredients.sorted { $0.order < $1.order }
            .map { ing in ing.amount.isEmpty ? ing.name : "\(ing.name)  \(ing.amount)" }
            .joined(separator: "\n")
    section(title: "食材", content: content)
}
```

> 注：兼容旧 legacy 字段（迁移前的数据）和新结构化字段（迁移后）。Task 9 会完整重写 RecipeDetailView。

- [ ] **Step 6: 修复 BackupSyncUseCase.swift 调用方**

文件：`personal-butler/Domain/UseCases/BackupSyncUseCase.swift`

第 77-82 行（cookRecipeList map）改为：

```swift
cookRecipeList: recipes.map {
    SyncRecipeDTO(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                  difficulty: $0.difficultyRaw, minutes: $0.minutes,
                  category: $0.categoryRaw,
                  ingredientsLegacyRaw: $0.ingredientsLegacyRaw,
                  ingredients: $0.ingredients.sorted { $0.order < $1.order }
                      .map { SyncIngredientDTO(id: $0.id.uuidString,
                                                name: $0.name, amount: $0.amount,
                                                order: $0.order) },
                  steps: $0.steps, tips: $0.tips,
                  iconImageBase64: $0.iconImage?.base64EncodedString())
},
```

第 359-369 行（rebuild cookRecipeList）改为：

```swift
for x in data.cookRecipeList {
    guard let uuid = UUID(uuidString: x.id) else { continue }
    let iconData: Data? = {
        guard let b64 = x.iconImageBase64, !b64.isEmpty else { return nil }
        return Data(base64Encoded: b64)
    }()
    let m = CookRecipe(
        id: uuid, name: x.name, emoji: x.emoji,
        difficulty: CookDifficulty(rawValue: x.difficulty) ?? .easy,
        minutes: x.minutes,
        category: CookCategory(rawValue: x.category) ?? .home,
        ingredientsLegacyRaw: x.ingredientsLegacyRaw,
        steps: x.steps, tips: x.tips,
        iconImage: iconData
    )
    context.insert(m)
    // 重建食材子项
    for ing in x.ingredients {
        guard let ingUUID = UUID(uuidString: ing.id) else { continue }
        let im = CookIngredient(id: ingUUID, name: ing.name,
                                amount: ing.amount, order: ing.order)
        im.recipe = m
        context.insert(im)
    }
    // 重建烹饪车项
    if let carts = data.cartList {
        for c in carts where c.recipeId == x.id {
            guard let cUUID = UUID(uuidString: c.id) else { continue }
            let cm = CookCart(id: cUUID, recipe: m,
                              servings: c.servings,
                              addedAt: Date(timeIntervalSince1970: c.addedAt))
            context.insert(cm)
        }
    }
}
```

> 注：此处 `data.cartList` 是 Optional，Task 7 会让 `SyncData.cartList` 非空。这里先按 Optional 处理避免编译错误。

- [ ] **Step 7: 修复 SyncPayload.swift**

文件：`personal-butler/Data/Mapper/SyncPayload.swift`

第 84-94 行（`SyncRecipeDTO`）替换为：

```swift
struct SyncIngredientDTO: Codable {
    var id: String
    var name: String
    var amount: String
    var order: Int
}

struct SyncCartDTO: Codable {
    var id: String
    var recipeId: String
    var servings: Int
    var addedAt: Double
}

struct SyncRecipeDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var difficulty: String
    var minutes: Int
    var category: String
    var ingredientsLegacyRaw: String
    var ingredients: [SyncIngredientDTO]
    var steps: String
    var tips: String
    var iconImageBase64: String?
}
```

第 114-125 行（`SyncData`）替换为：

```swift
struct SyncData: Codable {
    var todoList: [SyncTodoDTO]
    var scheduleList: [SyncScheduleDTO]
    var anniversaryList: [SyncAnniDTO]
    var passwordList: [SyncPasswordDTO]
    var otpList: [SyncOTPDTO]
    var foodRecordList: [SyncFoodDTO]
    var cookRecipeList: [SyncRecipeDTO]
    var cartList: [SyncCartDTO]?
    var noteList: [SyncNoteDTO]
    var appModuleList: [SyncModuleDTO]
    var setting: [String: String]
}
```

第 15-22 行（`SyncTodoDTO`）替换为：

```swift
struct SyncTodoDTO: Codable {
    var id: String
    var name: String
    var source: String
    var dueDate: Double?
    var isDone: Bool
    var createdAt: Double
    // v4 新增字段
    var taskType: String?
    var recipeId: String?
    var expectedIngredients: [String]?
    var checkedIngredients: [String]?
}
```

> 这些 v4 字段都设为 Optional，旧服务端返回不带这些字段时解码为 nil。

- [ ] **Step 8: 修复 BackupSyncUseCase.swift buildPayload 的 todoList**

文件：`personal-butler/Domain/UseCases/BackupSyncUseCase.swift`

第 32-38 行（todoList map）替换为：

```swift
todoList: todos.map {
    SyncTodoDTO(id: $0.id.uuidString, name: $0.name,
                source: $0.sourceRaw,
                dueDate: $0.dueDate?.timeIntervalSince1970,
                isDone: $0.isDone,
                createdAt: $0.createdAt.timeIntervalSince1970,
                taskType: $0.taskTypeRaw,
                recipeId: $0.recipeId?.uuidString,
                expectedIngredients: $0.expectedIngredientsRaw
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .isEmpty
                    ? nil
                    : $0.expectedIngredientsRaw
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty },
                checkedIngredients: $0.checkedIngredientsRaw
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .isEmpty
                    ? nil
                    : $0.checkedIngredientsRaw
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty })
},
```

第 31 行 `data = SyncData(...)` 调用末尾的 `setting: [:]` 之前补 `cartList: carts,`：

```swift
let carts = (try? context.fetch(FetchDescriptor<CookCart>())) ?? []
```

加入 carts fetch（在 recipes fetch 后追加一行）。

并补全 `SyncData(...)` 的 `cartList: carts.map { SyncCartDTO(id: $0.id.uuidString, recipeId: $0.recipe?.id.uuidString ?? "", servings: $0.servings, addedAt: $0.addedAt.timeIntervalSince1970) },`

> 注：这一步先满足编译；Task 7 会重新整理 buildPayload 完整逻辑。

- [ ] **Step 9: 修复 BackupSyncUseCase.swift rebuild 的 todoList**

文件：`personal-butler/Domain/UseCases/BackupSyncUseCase.swift`

第 272-282 行（todoList rebuild）替换为：

```swift
for x in data.todoList {
    guard let uuid = UUID(uuidString: x.id) else { continue }
    let m = TodoItem(
        id: uuid, name: x.name,
        source: TodoSource(rawValue: x.source) ?? .manual,
        dueDate: x.dueDate.map { Date(timeIntervalSince1970: $0) },
        isDone: x.isDone,
        createdAt: Date(timeIntervalSince1970: x.createdAt)
    )
    // v4 新字段（Optional，旧服务端可能不带）
    if let tt = x.taskType, let type = TodoTaskType(rawValue: tt) {
        m.taskTypeRaw = type.rawValue
    }
    if let rid = x.recipeId, let rUUID = UUID(uuidString: rid) {
        m.recipeId = rUUID
    }
    if let exp = x.expectedIngredients {
        m.expectedIngredientsRaw = exp.joined(separator: ",")
    }
    if let chk = x.checkedIngredients {
        m.checkedIngredientsRaw = chk.joined(separator: ",")
    }
    context.insert(m)
}
```

> 注：此时 TodoItem 还没有 taskTypeRaw 等字段（Task 4 才加），所以这一步会编译失败。下一步会修复。

- [ ] **Step 10: 暂时跳过编译验证（依赖 Task 4 TodoItem 扩展）**

此时 CookRecipe 字段已重命名，但 TodoItem 还没扩展（依赖未就绪），跳过 build；Task 4 完成后统一验证。

- [ ] **Step 11: Commit**

```bash
git add personal-butler/Domain/Models/CookRecipe.swift \
        personal-butler/Data/LocalDataSource/SeedData.swift \
        personal-butler/Presentation/Views/SubPages/CookRecipeView.swift \
        personal-butler/Data/Mapper/SyncPayload.swift \
        personal-butler/Domain/UseCases/BackupSyncUseCase.swift
git commit -m "feat(cook): 扩展 CookRecipe 字段（ingredients 关系 / cartItems / iconImage / legacyRaw）"
```

> 注：此 commit 后 build 暂时未通过，因为 TodoItem 还未扩展。Task 4 完成后统一编译验证。

---

## Task 4: 扩展 `TodoItem` @Model + `TodoTaskType` 枚举

**Files:**
- Modify: `personal-butler/Domain/Models/TodoItem.swift`

**Interfaces:**
- Produces: `TodoTaskType` 枚举（none/prep/cook，rawValue 落库）；`TodoItem.taskType` 计算属性；4 个新字段 `taskTypeRaw` / `recipeId` / `expectedIngredientsRaw` / `checkedIngredientsRaw`；便利 init `(name:source:taskType:dueDate:recipeId:expectedIngredients:checkedIngredients:)`

- [ ] **Step 1: 修改 TodoItem.swift**

完整替换文件内容：

```swift
//
//  TodoItem.swift
//

import Foundation
import SwiftData

/// 待办来源：日程 / 纪念日 / 烹饪
enum TodoSource: String, Codable, CaseIterable {
    case schedule
    case anniversary
    case cook
    case manual
    var label: String {
        switch self {
        case .schedule: return "日程"
        case .anniversary: return "纪念日"
        case .cook: return "烹饪"
        case .manual: return "手动"
        }
    }
}

/// 任务类型：普通 / 准备食材 / 烹饪
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

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var sourceRaw: String
    var dueDate: Date?
    var isDone: Bool
    var createdAt: Date

    // v4 新增字段（都带默认值/Optional，兼容旧数据）
    var taskTypeRaw: String = TodoTaskType.none.rawValue
    var recipeId: UUID? = nil
    /// prep 任务应有食材名称列表，逗号分隔，提交时冻结
    var expectedIngredientsRaw: String = ""
    /// prep 任务已勾选食材名称列表，逗号分隔
    var checkedIngredientsRaw: String = ""

    init(id: UUID = UUID(), name: String, source: TodoSource = .manual,
         dueDate: Date? = nil, isDone: Bool = false, createdAt: Date = .init(),
         taskType: TodoTaskType = .none,
         recipeId: UUID? = nil,
         expectedIngredients: [String] = [],
         checkedIngredients: [String] = []) {
        self.id = id
        self.name = name
        self.sourceRaw = source.rawValue
        self.dueDate = dueDate
        self.isDone = isDone
        self.createdAt = createdAt
        self.taskTypeRaw = taskType.rawValue
        self.recipeId = recipeId
        self.expectedIngredientsRaw = expectedIngredients.joined(separator: ",")
        self.checkedIngredientsRaw = checkedIngredients.joined(separator: ",")
    }

    var source: TodoSource { TodoSource(rawValue: sourceRaw) ?? .manual }
    var taskType: TodoTaskType { TodoTaskType(rawValue: taskTypeRaw) ?? .none }

    /// 应有食材名称列表（按 expectedIngredientsRaw split 得到）
    var expectedIngredients: [String] {
        expectedIngredientsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 已勾选食材名称列表
    var checkedIngredients: [String] {
        checkedIngredientsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 2: 编译验证（全量）**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

> 此时 Task 3 末尾的 BackupSyncUseCase 编译错误应该已经解决（TodoItem 已扩展）。

- [ ] **Step 3: Commit**

```bash
git add personal-butler/Domain/Models/TodoItem.swift
git commit -m "feat(todo): 扩展 TodoItem 任务类型字段（taskType/recipeId/expected/checked）"
```

---

## Task 5: App Schema 注册 + 迁移逻辑

**Files:**
- Modify: `personal-butler/App/PersonalButlerApp.swift`

**Interfaces:**
- Consumes: `CookIngredient`（Task 1）/ `CookCart`（Task 2）
- Produces: `PersonalButlerApp.bootstrap()` 在 `SeedData.ensureSeeded` 之后调用 `migrateCookIngredients(context:)`，迁移旧 `ingredientsLegacyRaw` 多行文本到结构化 `CookIngredient`

- [ ] **Step 1: 修改 PersonalButlerApp.swift**

第 53-65 行（Schema 构造）替换为：

```swift
let schema = Schema([
    TodoItem.self,
    ScheduleEvent.self,
    Anniversary.self,
    PasswordAccount.self,
    OTPAccount.self,
    FoodRecord.self,
    CookRecipe.self,
    CookIngredient.self,
    CookCart.self,
    Note.self,
    AppModule.self,
    AppSetting.self
])
```

第 98 行（`SeedData.ensureSeeded(in: container.mainContext)` 之后）追加迁移调用：

```swift
SeedData.ensureSeeded(in: container.mainContext)
migrateCookIngredients(context: container.mainContext)
```

在 `PersonalButlerApp` 结构体末尾（`bootstrap()` 方法之后，闭合大括号 `}` 之前）追加迁移函数：

```swift
/// 旧版 CookRecipe.ingredients 是多行文本 String。
/// v4 起改为结构化 [CookIngredient] 关系，旧字段保留为 ingredientsLegacyRaw。
/// 此函数把旧多行文本按行解析为 CookIngredient（整行作为 name，不强行解析数量/单位）。
/// 幂等：仅对 ingredients 关系为空且 ingredientsLegacyRaw 非空的 recipe 执行。
@MainActor
private func migrateCookIngredients(context: ModelContext) {
    let recipes = (try? context.fetch(FetchDescriptor<CookRecipe>())) ?? []
    var changed = false
    for r in recipes {
        guard r.ingredients.isEmpty, !r.ingredientsLegacyRaw.isEmpty else { continue }
        let lines = r.ingredientsLegacyRaw.split(separator: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let ing = CookIngredient(name: trimmed, order: i)
            ing.recipe = r
            context.insert(ing)
            changed = true
        }
    }
    if changed { try? context.save() }
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 运行验证（手动）**

Run: Xcode Cmd+R 启动模拟器

预期：
- App 冷启正常（无崩溃）
- 主页 6 个宫格 + 待办卡片正常显示
- 进入"烹饪管理"，6 条种子菜谱可见
- 进入任一菜谱详情，食材 section 显示（迁移后的结构化数据，按行渲染）

- [ ] **Step 4: Commit**

```bash
git add personal-butler/App/PersonalButlerApp.swift
git commit -m "feat(app): 注册 CookIngredient/CookCart 到 Schema + 旧 ingredients 迁移逻辑"
```

---

## Task 6: 扩展 IconPickerSheet 支持注入 emoji 列表

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/Food/IconPickerSheet.swift`

**Interfaces:**
- Produces: `IconPickerSheet.init(initial:onConfirm:emojiCandidates:)` 新参数（默认 `IconPickerSheet.defaultFoodEmoji`）；静态常量 `IconPickerSheet.defaultFoodEmoji` / `IconPickerSheet.cookEmoji`

- [ ] **Step 1: 修改 IconPickerSheet.swift**

第 18-47 行（struct IconPickerSheet + emojiOptions + init）替换为：

```swift
struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: FoodIcon
    let onConfirm: (FoodIcon) -> Void
    let emojiCandidates: [String]

    @State private var current: FoodIcon
    @State private var tab: IconTab = .emoji

    // 相册
    @State private var pickedItem: PhotosPickerItem?
    @State private var albumBusy: Bool = false

    // 拍照
    @State private var showCamera: Bool = false

    /// FoodRecord 等模块的默认 emoji 候选（30 个，覆盖火锅/奶茶/中餐/西餐/日料/咖啡/大排档等）
    static let defaultFoodEmoji: [String] = [
        "🍽️", "🍜", "🍚", "🍛", "🍲", "🍱",
        "🍣", "🍤", "🥟", "🍔", "🍕", "🌮",
        "🥗", "🍖", "🍗", "🥘", "🍢", "🍧",
        "🍰", "🧁", "🍩", "🍪", "🍦", "🍮",
        "☕️", "🍵", "🧋", "🥤", "🍺", "🍷"
    ]

    /// CookRecipe 模块的菜肴专用 emoji 候选（30 个，偏烹饪场景）
    static let cookEmoji: [String] = [
        "🍳", "🥘", "🥗", "🍲", "🍜", "🍚",
        "🍛", "🍢", "🍣", "🍤", "🥟", "🍝",
        "🍞", "🥖", "🧀", "🍗", "🍖", "🥩",
        "🍔", "🍟", "🍕", "🌭", "🌮", "🌯",
        "🥙", "🥚", "🥞", "🧇", "🥓", "🥪"
    ]

    init(initial: FoodIcon,
         onConfirm: @escaping (FoodIcon) -> Void,
         emojiCandidates: [String] = IconPickerSheet.defaultFoodEmoji) {
        self.initial = initial
        self.onConfirm = onConfirm
        self.emojiCandidates = emojiCandidates
        _current = State(initialValue: initial)
    }
```

第 133 行（`ForEach(Self.emojiOptions, id: \.self) { e in`）改为：

```swift
ForEach(emojiCandidates, id: \.self) { e in
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

> FoodRecord 调用方 `EditFoodSheet` 不传 emojiCandidates 参数，使用默认值，行为不变。

- [ ] **Step 3: 运行验证（手动）**

Run: Xcode Cmd+R 启动模拟器

预期：
- 进入"美食记录"，点击 + 新增，点击图标 row → IconPickerSheet 弹出，Emoji tab 显示 30 个美食 emoji（与改动前一致）

- [ ] **Step 4: Commit**

```bash
git add personal-butler/Presentation/Views/SubPages/Food/IconPickerSheet.swift
git commit -m "feat(food): IconPickerSheet 支持注入 emoji 列表 + cookEmoji 静态常量"
```

---

## Task 7: 完整重写 `CookRecipeEditSheet`（替换 CreateCookSheet）

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`（重命名 `CreateCookSheet` → `CookRecipeEditSheet`，完整重写）

**Interfaces:**
- Consumes: `CookRecipe.ingredients` / `CookIngredient`（Task 1/3）/ `IconPickerSheet` 改造版（Task 6）
- Produces: `CookRecipeEditSheet(recipe: CookRecipe?)` 初始化器（nil = 新增，非 nil = 编辑）

- [ ] **Step 1: 重写 CookRecipeView.swift 的 CreateCookSheet → CookRecipeEditSheet**

文件：`personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

把第 190-247 行（整个 `struct CreateCookSheet`）替换为：

```swift
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
            r.difficulty = difficulty
            r.minutes = minutes
            r.category = category
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
```

- [ ] **Step 2: 修复 CookRecipeView 中 CreateCookSheet → CookRecipeEditSheet 调用**

文件：`personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

第 13 行附近 `@State private var showCreate = false` 保持不变；第 48 行：

```swift
.sheet(isPresented: $showCreate) { CreateCookSheet() }
```

改为：

```swift
.sheet(isPresented: $showCreate) { CookRecipeEditSheet(recipe: nil) }
```

- [ ] **Step 3: 在 CookRecipeView 顶部新增 editingRecipe 状态**

第 9-13 行（CookRecipeView struct 头部）替换为：

```swift
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
```

- [ ] **Step 4: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 运行验证（手动）**

Run: Xcode Cmd+R

预期：
- 进入"烹饪管理"，点 + → "新增菜谱" sheet
- 5 个 Section 完整可见：基础信息 / 参数 / 食材 / 步骤 / 小贴士
- 菜名输入后右侧出现 ✕，点击清除
- 食材动态加减行
- 切换 Picker / Stepper → 键盘自动收起
- 点击"添加食材"按钮 → 键盘收起 + 新行 append
- 点击图标 row → IconPickerSheet 弹出，菜肴专用 emoji 候选可见（🍳🥘🍲 等）
- 选 emoji 或相册图片 → 预览更新
- 保存后列表出现新菜谱

- [ ] **Step 6: Commit**

```bash
git add personal-butler/Presentation/Views/SubPages/CookRecipeView.swift
git commit -m "feat(cook): 完整重写 CookRecipeEditSheet（食材标准化 / 一键清除 / 图标 picker / 键盘收起 / tips）"
```

---

## Task 8: 列表卡片图标可点进入编辑 + 详情页改造

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

**Interfaces:**
- Consumes: `CookRecipeEditSheet`（Task 7）/ `CookRecipe.iconImage`（Task 3）
- Produces: `CookRecipeView.cookCard` 卡片图标区点击触发 `editingRecipe`；`RecipeDetailView` toolbar 编辑/删除按钮 + 图标区可点编辑 + 底部"加入烹饪车"按钮

- [ ] **Step 1: 修改 CookRecipeView.swift 的 cookCard 方法**

文件：`personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

把第 56-89 行（`private func cookCard(_ r: CookRecipe) -> some View`）替换为：

```swift
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
```

- [ ] **Step 2: CookRecipeView body 添加 editingRecipe sheet**

在 `.sheet(isPresented: $showCreate) { CookRecipeEditSheet(recipe: nil) }` 之后追加：

```swift
.sheet(item: $editingRecipe) { r in
    CookRecipeEditSheet(recipe: r)
}
```

> `CookRecipe` 是 `PersistentModel`，自动 conforms to `Identifiable`（通过 `id` UUID）。

- [ ] **Step 3: 修改 RecipeDetailView（详情页）**

文件：`personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

把第 102-188 行（整个 `struct RecipeDetailView`）替换为：

```swift
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
```

- [ ] **Step 4: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 运行验证（手动）**

Run: Xcode Cmd+R

预期：
- 列表卡片图标区点击 → 弹编辑 sheet（不跳详情）
- 列表卡片其它区域点击 → 跳详情
- 详情页顶部图标区点击 → 弹编辑 sheet
- 详情页 toolbar 有编辑（pencil）/ 删除（trash）按钮
- 点删除 → 二次确认 alert → 确认后返回列表
- 详情页底部按钮文案为"加入烹饪车"，点击后 toast "已加入烹饪车"
- 列表卡片图标显示图片优先（无图片显示 emoji）

- [ ] **Step 6: Commit**

```bash
git add personal-butler/Presentation/Views/SubPages/CookRecipeView.swift
git commit -m "feat(cook): 列表卡片图标可点编辑 + 详情页编辑/删除/加入烹饪车"
```

---

## Task 9: 烹饪车 bar + CookCartSheet

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

**Interfaces:**
- Consumes: `CookCart`（Task 2）/ `cartItems` @Query（Task 7 已添加）
- Produces: `CookRecipeView` 底部 cartBar（车项数 + 提交按钮）+ CookCartSheet（车详情 sheet）

- [ ] **Step 1: 修改 CookRecipeView body 增加 cartBar**

文件：`personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`

第 23-49 行（`var body`）替换为：

```swift
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
```

- [ ] **Step 2: 在 CookRecipeView.swift 文件末尾追加 CookCartSheet**

```swift
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
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: 多个错误：`SubmitCookTaskUseCase` 未定义（Task 10 创建），跳过 build 等到 Task 10 完成后验证

- [ ] **Step 4: Commit（暂不验证 build）**

```bash
git add personal-butler/Presentation/Views/SubPages/CookRecipeView.swift
git commit -m "feat(cook): 烹饪车 bar + CookCartSheet（份数 stepper + 删除 + 提交确认）"
```

---

## Task 10: 新增 `SubmitCookTaskUseCase`

**Files:**
- Create: `personal-butler/Domain/UseCases/SubmitCookTaskUseCase.swift`

**Interfaces:**
- Consumes: `CookCart` / `CookRecipe.ingredients` / `CookIngredient` / `TodoItem` 便利 init（Task 4）
- Produces: `SubmitCookTaskUseCase.execute(context:)` 方法；副作用：插入 1 条 prep + N 条 cook TodoItem，删除所有 CookCart，save

- [ ] **Step 1: 创建 SubmitCookTaskUseCase.swift**

```swift
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
            taskType: .prep,
            dueDate: Date(),
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
                taskType: .cook,
                dueDate: Date(),
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
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 运行验证（手动）**

Run: Xcode Cmd+R

预期：
- 进入烹饪管理，进入菜谱详情，点"加入烹饪车" → toast
- 列表底部出现 cartBar（"烹饪车：1 道菜"）
- 点 cartBar → CookCartSheet 弹出，列出菜品 + 份数 stepper + 删除按钮
- 关闭 sheet，再点"提交"按钮 → 二次确认 alert
- 点"提交" → toast "已生成 2 条任务"
- cartBar 消失
- 进入主页，今日待办区出现 1 条"准备食材（1 道菜）"+ 1 条"烹饪：菜名"
- 多加几道菜再提交，验证 prep 任务里食材清单合并（同名食材只显示一次）

- [ ] **Step 4: Commit**

```bash
git add personal-butler/Domain/UseCases/SubmitCookTaskUseCase.swift
git commit -m "feat(cook): 新增 SubmitCookTaskUseCase（聚合食材 + 生成 prep/cook 任务）"
```

---

## Task 11: 新增 `PrepTaskSheet`

**Files:**
- Create: `personal-butler/Presentation/Views/SubPages/Cook/PrepTaskSheet.swift`

**Interfaces:**
- Consumes: `TodoItem.expectedIngredients` / `TodoItem.checkedIngredients`（Task 4 计算属性）
- Produces: `PrepTaskSheet(todo: TodoItem)` 视图；副作用：toggle 食材勾选 → 写 `checkedIngredientsRaw`，全选时 `isDone = true`

- [ ] **Step 1: 创建目录与文件**

Run: `mkdir -p personal-butler/Presentation/Views/SubPages/Cook`

- [ ] **Step 2: 创建 PrepTaskSheet.swift**

```swift
//
//  PrepTaskSheet.swift
//  准备食材任务详情：逐项勾选食材购买进度
//

import SwiftUI
import SwiftData

struct PrepTaskSheet: View {
    let todo: TodoItem
    @Environment(\.modelContext) private var context

    private var expected: [String] { todo.expectedIngredients }
    private var checked: Set<String> { Set(todo.checkedIngredients) }

    var body: some View {
        NavigationStack {
            List {
                Section("食材清单") {
                    if expected.isEmpty {
                        Text("暂无食材").foregroundStyle(.secondary)
                    } else {
                        ForEach(expected, id: \.self) { name in
                            Button {
                                toggle(name)
                            } label: {
                                HStack {
                                    Image(systemName: checked.contains(name) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(checked.contains(name) ? AppColorTheme.primary : .secondary)
                                    Text(name)
                                        .foregroundStyle(checked.contains(name) ? .secondary : AppColorTheme.text)
                                        .strikethrough(checked.contains(name), color: .secondary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Button("全部已购买") {
                        todo.checkedIngredientsRaw = expected.joined(separator: ",")
                        todo.isDone = true
                        try? context.save()
                    }
                    .disabled(expected.isEmpty)
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

- [ ] **Step 3: 把 PrepTaskSheet.swift 加入 Xcode project**

Run: 通过 Xcode 的 File → Add Files to "personal-butler"... 把 `personal-butler/Presentation/Views/SubPages/Cook/PrepTaskSheet.swift` 加入到 project 的 group `Presentation/Views/SubPages/`（如果 Xcode project 是文件夹同步型，文件已经会被识别；如果是 .pbxproj 显式管理，需手动 add）。

检查方式：编译看是否报 "Cannot find 'PrepTaskSheet' in scope"。

- [ ] **Step 4: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add personal-butler/Presentation/Views/SubPages/Cook/PrepTaskSheet.swift
git commit -m "feat(cook): 新增 PrepTaskSheet（食材清单 + 逐项勾选）"
```

---

## Task 12: 新增 `CookTaskSheet`

**Files:**
- Create: `personal-butler/Presentation/Views/SubPages/Cook/CookTaskSheet.swift`

**Interfaces:**
- Consumes: `TodoItem.recipeId`（Task 4）/ `CookRecipe.ingredients` / `CookRecipe.steps` / `CookRecipe.tips`
- Produces: `CookTaskSheet(todo: TodoItem)` 视图；副作用：点击"完成烹饪" → `isDone = true`

- [ ] **Step 1: 创建 CookTaskSheet.swift**

```swift
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
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add personal-butler/Presentation/Views/SubPages/Cook/CookTaskSheet.swift
git commit -m "feat(cook): 新增 CookTaskSheet（步骤 + tips + 完成按钮）"
```

---

## Task 13: HomeView 主页改造（PrepTodoRow + CookTodoRow + 排序 + sheet）

**Files:**
- Modify: `personal-butler/Presentation/Views/MainTab/HomeView.swift`

**Interfaces:**
- Consumes: `TodoItem.taskType` / `recipeId` / `expectedIngredients` / `checkedIngredients`（Task 4）/ `PrepTaskSheet`（Task 11）/ `CookTaskSheet`（Task 12）
- Produces: HomeView 任务列表按 taskType 分发到 `PrepTodoRow` / `CookTodoRow` / `TodoItemRow`；排序 prep→cook→none；toggle 扩展

- [ ] **Step 1: 修改 HomeView TodoDisplay 结构**

文件：`personal-butler/Presentation/Views/MainTab/HomeView.swift`

第 113-123 行（`private struct TodoDisplay`）替换为：

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
    let taskType: TodoTaskType
    let recipeId: UUID?
    let expectedIngredients: [String]
    let checkedIngredients: [String]
}
```

- [ ] **Step 2: 修改 HomeView currentList 中日程/纪念日初始化**

第 145-148 行（日程的 `.init(...)`）添加 taskType 等字段：

```swift
items.append(.init(id: "sch-\(s.id)", name: s.title, sourceLabel: "日程",
                   timeLabel: label, isUrgent: urgent, isDone: s.isCompleted,
                   sortDate: s.startDate,
                   refSchedule: s, refManual: nil,
                   taskType: .none, recipeId: nil,
                   expectedIngredients: [], checkedIngredients: []))
```

第 157-160 行（纪念日的 `.init(...)`）添加 taskType 等字段：

```swift
items.append(.init(id: "anni-\(a.id)", name: a.name, sourceLabel: "纪念日",
                   timeLabel: label, isUrgent: days <= 3, isDone: false,
                   sortDate: sort,
                   refSchedule: nil, refManual: nil,
                   taskType: .none, recipeId: nil,
                   expectedIngredients: [], checkedIngredients: []))
```

- [ ] **Step 3: 修改 HomeView currentList 中手动/烹饪待办初始化**

第 165-191 行（手动/烹饪待办循环）替换为：

```swift
for t in manualTodos {
    let taskType = t.taskType
    let recipeId = t.recipeId
    let expected = t.expectedIngredients
    let checked = t.checkedIngredients

    if let d = t.dueDate {
        guard d >= now && d <= end else { continue }
        let label: String
        if t.isDone {
            label = "已完成"
        } else if d <= todayEnd {
            label = "今日"
        } else {
            label = DateCalculator.relativeLabel(d)
        }
        items.append(.init(id: "todo-\(t.id)", name: t.name,
                           sourceLabel: t.source.label,
                           timeLabel: label,
                           isUrgent: false, isDone: t.isDone,
                           sortDate: d,
                           refSchedule: nil, refManual: t,
                           taskType: taskType, recipeId: recipeId,
                           expectedIngredients: expected,
                           checkedIngredients: checked))
    } else if !t.isDone {
        items.append(.init(id: "todo-\(t.id)", name: t.name,
                           sourceLabel: t.source.label,
                           timeLabel: "近期",
                           isUrgent: false, isDone: false,
                           sortDate: now,
                           refSchedule: nil, refManual: t,
                           taskType: taskType, recipeId: recipeId,
                           expectedIngredients: expected,
                           checkedIngredients: checked))
    }
}
```

- [ ] **Step 4: 修改排序逻辑**

第 194-197 行（排序）替换为：

```swift
return items.sorted { a, b in
    if a.isDone != b.isDone { return !a.isDone && b.isDone }
    if a.taskType != b.taskType {
        let order: [TodoTaskType: Int] = [.prep: 0, .cook: 1, .none: 2]
        return order[a.taskType]! < order[b.taskType]!
    }
    return a.sortDate < b.sortDate
}
```

- [ ] **Step 5: 修改 todoCard 的 LazyVStack 渲染分发**

第 67-79 行（LazyVStack 内的 ForEach）替换为：

```swift
ScrollView {
    LazyVStack(spacing: 0) {
        ForEach(Array(currentList.enumerated()), id: \.offset) { idx, todo in
            row(for: todo)
            if idx < currentList.count - 1 {
                Divider().foregroundStyle(Color.black.opacity(0.04))
            }
        }
    }
}
```

并在 `HomeView` 内新增 `row(for:)` 方法（放在 `currentList` 之上）：

```swift
@ViewBuilder
private func row(for todo: TodoDisplay) -> some View {
    switch todo.taskType {
    case .prep:
        PrepTodoRow(name: todo.name,
                    timeLabel: todo.timeLabel,
                    isDone: todo.isDone,
                    checkedCount: todo.checkedIngredients.count,
                    expectedCount: todo.expectedIngredients.count,
                    onToggle: { toggle(todo) },
                    onTap: { prepSheetItem = todo.refManual })
    case .cook:
        CookTodoRow(name: todo.name,
                    timeLabel: todo.timeLabel,
                    isDone: todo.isDone,
                    onToggle: { toggle(todo) },
                    onTap: { cookSheetItem = todo.refManual })
    case .none:
        TodoItemRow(name: todo.name, source: todo.sourceLabel,
                    timeLabel: todo.timeLabel, urgent: todo.isUrgent,
                    isDone: todo.isDone) {
            toggle(todo)
        }
    }
}
```

- [ ] **Step 6: 修改 toggle 方法**

第 200-208 行（`toggle` 方法）替换为：

```swift
private func toggle(_ todo: TodoDisplay) {
    if let s = todo.refSchedule {
        s.isCompleted.toggle()
        try? context.save()
    } else if let t = todo.refManual {
        if todo.taskType == .prep {
            // prep 圆圈点击 = 全部已买 / 取消全买
            if t.isDone {
                t.checkedIngredientsRaw = ""
                t.isDone = false
            } else {
                t.checkedIngredientsRaw = todo.expectedIngredients.joined(separator: ",")
                t.isDone = true
            }
        } else {
            t.isDone.toggle()
        }
        try? context.save()
    }
}
```

- [ ] **Step 7: 新增 prepSheetItem / cookSheetItem 状态 + sheet 弹出**

在 HomeView struct 第 14 行（`@Query(sort: \AppModule.order) private var modules: [AppModule]` 之后）追加：

```swift
@State private var prepSheetItem: TodoItem?
@State private var cookSheetItem: TodoItem?
```

在 `body` 的 `VStack` 末尾追加 sheet（紧跟 `appsGrid` 之后，闭合 VStack 之前不需要；应在 `content` 之后或 `body` 末尾）。

修改 `body`：

```swift
var body: some View {
    VStack(spacing: 0) {
        header
        content
    }
    .background(Color.white)
    .sheet(item: $prepSheetItem) { todo in
        PrepTaskSheet(todo: todo)
    }
    .sheet(item: $cookSheetItem) { todo in
        CookTaskSheet(todo: todo)
    }
}
```

- [ ] **Step 8: 在 HomeView.swift 文件末尾追加 PrepTodoRow / CookTodoRow 私有组件**

```swift
// MARK: - Prep / Cook 任务行

private struct PrepTodoRow: View {
    let name: String
    let timeLabel: String
    let isDone: Bool
    let checkedCount: Int
    let expectedCount: Int
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isDone ? AppColorTheme.primary : .secondary)
            }
            .buttonStyle(.plain)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isDone ? .secondary : AppColorTheme.text)
                        .strikethrough(isDone, color: .secondary)
                    if expectedCount > 0 {
                        Text("\(checkedCount)/\(expectedCount) 已买")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(timeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct CookTodoRow: View {
    let name: String
    let timeLabel: String
    let isDone: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isDone ? AppColorTheme.primary : .secondary)
            }
            .buttonStyle(.plain)
            Button(action: onTap) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDone ? .secondary : AppColorTheme.text)
                    .strikethrough(isDone, color: .secondary)
                Spacer()
                Label("查看步骤", systemImage: "book")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(timeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 9: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: 运行验证（手动）**

Run: Xcode Cmd+R

预期：
- 提交一份烹饪车任务后，主页今日待办区出现 1 条 prep + N 条 cook
- prep 任务显示名称 + "0/N 已买" 副标题
- cook 任务显示名称 + "查看步骤" + 时间
- 排序：prep 在 cook 之前，cook 在普通待办之前
- 点击 prep row（非圆圈）→ PrepTaskSheet 弹出
- 逐项勾选食材 → "X/N 已买" 实时更新
- 全部勾选 → prep 任务自动 isDone=true
- 点击 prep 圆圈 → 直接全选 + isDone=true
- 已完成 prep 点击圆圈 → 取消全选 + isDone=false
- 点击 cook row（非圆圈）→ CookTaskSheet 弹出，显示食材/步骤/tips
- cook 任务 recipe 已删 → sheet 显示"菜谱已删除"
- 点击"完成烹饪" → isDone=true + sheet 关闭

- [ ] **Step 11: Commit**

```bash
git add personal-butler/Presentation/Views/MainTab/HomeView.swift
git commit -m "feat(home): 主页区分 prep/cook 任务 + 弹窗 + 排序"
```

---

## Task 14: 整理 BackupSyncUseCase 同步逻辑

**Files:**
- Modify: `personal-butler/Domain/UseCases/BackupSyncUseCase.swift`

**Interfaces:**
- Consumes: `CookIngredient` / `CookCart` / TodoItem 新字段（Task 4）
- Produces: `buildPayload` 完整包含 CookIngredient / CookCart / TodoItem 新字段；`restore` 完整重建；`dataVersion: 4`

- [ ] **Step 1: 修改 buildPayload 的 dataVersion**

第 19 行：`dataVersion: 3` → `dataVersion: 4`

- [ ] **Step 2: 修改 buildPayload cartList（确保非空）**

在 buildPayload 内 `let recipes = ...` 之后追加：

```swift
let carts = (try? context.fetch(FetchDescriptor<CookCart>())) ?? []
```

确保 `SyncData(...)` 调用里有：

```swift
cartList: carts.map {
    SyncCartDTO(id: $0.id.uuidString,
                recipeId: $0.recipe?.id.uuidString ?? "",
                servings: $0.servings,
                addedAt: $0.addedAt.timeIntervalSince1970)
},
```

- [ ] **Step 3: 修改 restore 中 cartList 重建**

确认 `rebuild(from:newKeychainKeys:)` 里 cookRecipeList 重建后追加 CookCart 重建（Task 3 Step 6 已写，但 cartList 是 Optional，这里要确保完整）。

替换 cookRecipeList rebuild 整段：

```swift
// 先建 recipe → ingredients，再单独建 cart（避免 cart 引用未建好的 recipe）
var recipeMap: [String: CookRecipe] = [:]
for x in data.cookRecipeList {
    guard let uuid = UUID(uuidString: x.id) else { continue }
    let iconData: Data? = {
        guard let b64 = x.iconImageBase64, !b64.isEmpty else { return nil }
        return Data(base64Encoded: b64)
    }()
    let m = CookRecipe(
        id: uuid, name: x.name, emoji: x.emoji,
        difficulty: CookDifficulty(rawValue: x.difficulty) ?? .easy,
        minutes: x.minutes,
        category: CookCategory(rawValue: x.category) ?? .home,
        ingredientsLegacyRaw: x.ingredientsLegacyRaw,
        steps: x.steps, tips: x.tips,
        iconImage: iconData
    )
    context.insert(m)
    recipeMap[x.id] = m
    for ing in x.ingredients {
        guard let ingUUID = UUID(uuidString: ing.id) else { continue }
        let im = CookIngredient(id: ingUUID, name: ing.name,
                                amount: ing.amount, order: ing.order)
        im.recipe = m
        context.insert(im)
    }
}

// 重建 CookCart（依赖 recipeMap）
if let carts = data.cartList {
    for c in carts {
        guard let cUUID = UUID(uuidString: c.id) else { continue }
        let recipe = recipeMap[c.recipeId]
        let cm = CookCart(id: cUUID, recipe: recipe,
                          servings: c.servings,
                          addedAt: Date(timeIntervalSince1970: c.addedAt))
        context.insert(cm)
    }
}
```

- [ ] **Step 4: clearAllSyncedEntities 新增 CookIngredient / CookCart**

第 252-262 行追加：

```swift
try deleteAll(FetchDescriptor<CookIngredient>())
try deleteAll(FetchDescriptor<CookCart>())
```

> 注：因为 CookRecipe cascade delete，CookIngredient / CookCart 实际会被 delete CookRecipe 时级联删除。但显式 delete 更安全。

- [ ] **Step 5: 编译验证**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: 运行验证（手动）**

Run: Xcode Cmd+R

预期：
- 进入 MineView → 数据备份 → 弹 LocalBackupSheet
- 选择导出 → 生成 JSON 文件
- 文件内容含 `syncMeta.dataVersion: 4` + `cookRecipeList[].ingredients: [...]` + `cartList: []` + `todoList[].taskType / recipeId / expectedIngredients / checkedIngredients`
- 选择恢复（如有备份服务器配置）→ 不崩溃，数据一致

- [ ] **Step 7: Commit**

```bash
git add personal-butler/Domain/UseCases/BackupSyncUseCase.swift
git commit -m "feat(sync): dataVersion 4 + CookIngredient/CookCart 同步 + TodoItem 新字段"
```

---

## Task 15: 整体验证 + 提交

**Files:** 无新改动

- [ ] **Step 1: 全量编译**

Run: `xcodebuild -scheme personal-butler -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: 完整功能手动验证清单**

按 spec §9 测试策略逐项验证：

**录入层**：
- [ ] 列表卡片图标点击 → 进入编辑 sheet（不跳详情）
- [ ] 详情页图标点击 / toolbar 编辑按钮 → 进入编辑 sheet
- [ ] 详情页 toolbar 删除按钮 → 二次确认 → 删除后返回列表
- [ ] 表单 5 个 Section 完整填写 + 保存
- [ ] 菜名输入后右侧出现 ✕，点击清除
- [ ] 食材动态加 / 删行
- [ ] 切换 Picker / Stepper / 点击图标 row → 键盘自动收起
- [ ] 图标点击弹 IconPickerSheet，菜肴专用 emoji 候选可见
- [ ] 相册选图 / 拍照选图 → 列表卡片显示图片图标
- [ ] tips 字段输入并保存

**列表层 / 烹饪车**：
- [ ] 列表卡片图标显示图片优先（无图片显示 emoji）
- [ ] 详情页"加入烹饪车"按钮 → toast + 底部 cartBar 出现
- [ ] cartBar 显示车项数
- [ ] 点击 cartBar → CookCartSheet 列出菜品 + 份数 stepper + 删除按钮
- [ ] 调整份数 / 移除菜品后 cartBar 数量同步

**提交任务**：
- [ ] 提交按钮 → 二次确认 alert → 提交后 cartBar 消失
- [ ] 主页今日待办区出现 1 条 prep + N 条 cook 任务
- [ ] prep 任务名 "准备食材（N 道菜）"
- [ ] cook 任务名 "烹饪：菜名"
- [ ] 同名食材在 prep 任务清单中合并显示（只显示一次）

**任务层**：
- [ ] prep 任务点击 row → 弹 PrepTaskSheet，显示食材清单
- [ ] 逐项勾选食材 → "X/N 已买" 实时更新
- [ ] 全部勾选 → prep 任务自动 isDone=true
- [ ] prep 任务点击圆形勾选 → 直接全选 + isDone=true
- [ ] 已完成 prep 任务点击圆形勾选 → 取消全选 + isDone=false
- [ ] cook 任务点击 row → 弹 CookTaskSheet，显示食材/步骤/tips
- [ ] cook 任务 recipeId 对应菜谱已删 → sheet 显示"菜谱已删除"
- [ ] cook 任务点击"完成烹饪" → isDone=true
- [ ] HomeView 排序：prep → cook → none，未完成优先

**同步**：
- [ ] SyncMeta.dataVersion == 4
- [ ] 上传备份包含结构化 ingredients + cartList + 扩展字段
- [ ] 下载恢复后数据一致

- [ ] **Step 3: 最终 commit**

如果上述验证全部通过且无遗留改动，无需新 commit。如果有修复，commit 一次：

```bash
git add -A
git commit -m "chore(cook): 整体验证修复"
```

---

## 自检

### 1. Spec 覆盖

| Spec 条目 | 实现 Task |
|---|---|
| §2.1 CookIngredient | Task 1 |
| §2.2 CookCart | Task 2 |
| §2.3 CookRecipe 扩展 | Task 3 |
| §2.4 TodoItem 扩展 | Task 4 |
| §3 录入层（菜名清除 / 食材标准化 / 图标 / 键盘收起 / tips） | Task 6 (IconPicker) + Task 7 (CookRecipeEditSheet) |
| §4.1 列表卡片图标点击编辑 | Task 8 |
| §4.2 详情页改造（编辑/删除/加入烹饪车） | Task 8 |
| §4.3 烹饪车 bar | Task 9 |
| §4.4 CookCartSheet | Task 9 |
| §5.1 SubmitCookTaskUseCase | Task 10 |
| §5.2 提交二次确认 | Task 9 |
| §6.1 HomeView 排序 + TodoDisplay 扩展 | Task 13 |
| §6.2 PrepTodoRow | Task 13 |
| §6.3 CookTodoRow | Task 13 |
| §6.4 PrepTaskSheet | Task 11 |
| §6.5 CookTaskSheet | Task 12 |
| §6.6 toggle 扩展 | Task 13 |
| §7.1 迁移逻辑 | Task 5 |
| §7.2 同步契约 | Task 3 (DTO) + Task 14 (UseCase) |
| §7.3 SeedData | Task 3 |

无遗漏。

### 2. 占位符扫描

- 无 TBD / TODO / "implement later"。
- 所有 step 都有具体代码。
- 验证步骤有具体命令和预期输出。

### 3. 类型一致性

- `CookIngredient` 字段：id / recipe / name / amount / order / createdAt — Task 1 定义，Task 3/5/7/10/14 使用一致。
- `CookCart` 字段：id / recipe / servings / addedAt — Task 2 定义，Task 3/9/10/14 使用一致。
- `CookRecipe` 新字段：ingredientsLegacyRaw / ingredients / cartItems / iconImage — Task 3 定义，Task 7/8/9/10/12/14 使用一致。
- `TodoItem` 新字段：taskTypeRaw / recipeId / expectedIngredientsRaw / checkedIngredientsRaw — Task 4 定义，Task 10/11/12/13/14 使用一致。
- `TodoTaskType` 枚举：none / prep / cook — Task 4 定义，Task 10/11/12/13 使用一致。
- `IconPickerSheet` 新参数：emojiCandidates / cookEmoji — Task 6 定义，Task 7 使用一致。
- `SubmitCookTaskUseCase.execute(context:)` — Task 10 定义，Task 9 使用一致。
- `PrepTaskSheet(todo:)` / `CookTaskSheet(todo:)` — Task 11/12 定义，Task 13 使用一致。

类型与签名一致，无歧义。

---

## 执行选择

Plan complete and saved to `docs/superpowers/plans/2026-07-26-cook-recipe-cart-task.md`. Two execution options:

1. **Subagent-Driven (recommended)** - 每个 Task 派发独立 subagent，task 间 review，迭代快
2. **Inline Execution** - 在当前会话内顺序执行，带 checkpoint review

哪种方式？
