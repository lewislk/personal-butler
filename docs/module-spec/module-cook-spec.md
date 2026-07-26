# PersonalButler · 烹饪 / 菜谱 / 烹饪车 / 烹饪任务 · 模块级 SPEC

> 模块职责：管理自建菜谱库（食材标准化录入 / 图标 / 步骤 / 小贴士）；提供分类筛选、列表卡片图标可点编辑、详情页改造；支持"加入烹饪车 → 提交烹饪任务"流程，自动在主页生成 1 条 prep（准备食材）任务 + N 条 cook（烹饪）任务。

## 1. 范围与边界

本模块负责：

- 菜谱 CRUD（新增 / 编辑 / 删除，统一走 `CookRecipeEditSheet`）
- 食材标准化录入：动态行 + 名称/数量分列 + 删除/添加 + 键盘自动收起
- 图标录入：复用 `IconPickerSheet`，注入菜肴专用 `cookEmoji` 候选列表 + 相册/拍照图片
- 菜名一键清除（输入框右侧 ✕）
- 列表卡片图标区可点进入编辑（不跳详情）；其它区域点跳详情
- 详情页：编辑/删除 toolbar + 图标区可点编辑 + 底部"加入烹饪车"按钮
- 烹饪车 bar：底部胶囊条，显示车项数 + 提交按钮
- `CookCartSheet`：车详情 sheet（份数 Stepper / 删除 / 关闭 / 提交二次确认）
- `SubmitCookTaskUseCase`：聚合食材 + 生成 N+1 条 `TodoItem` + 清空车
- 主页任务层联动：`PrepTodoRow` / `CookTodoRow` + 排序 prep→cook→none + sheet 弹出
- `PrepTaskSheet`：准备食材任务详情，逐项勾选食材购买进度
- `CookTaskSheet`：烹饪任务详情，展示食材/步骤/小贴士 + 完成按钮

不覆盖：

- 菜谱步骤计时器 / 引导烹饪
- 菜谱分享 / 导出
- 食材单位换算 / 数量合并（聚合时按 name 完全相等去重，不合并 amount）

## 2. 核心概念

### CookRecipe

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `id` | UUID | `@Attribute(.unique)` |
| `name` | String | 菜名 |
| `emoji` | String | 封面 emoji（默认 "🍲"） |
| `difficultyRaw` | String | 难度枚举落库（easy/medium/hard） |
| `difficulty` | CookDifficulty | 计算属性读回 |
| `minutes` | Int | 预计耗时（分钟） |
| `categoryRaw` | String | 分类枚举落库（all/home/noodle/soup/dessert） |
| `category` | CookCategory | 计算属性读回 |
| `ingredientsLegacyRaw` | String | 旧版多行文本食材字段（v4 迁移用，迁移成功后清空） |
| `ingredients` | `[CookIngredient]` | 结构化食材列表（`@Relationship(.cascade)`） |
| `cartItems` | `[CookCart]` | 烹饪车项（`@Relationship(.cascade)`） |
| `steps` | String（多行） | 步骤，每行一条 |
| `tips` | String | 小贴士 |
| `iconImage` | Data? | 图片图标 JPEG 二进制（`@Attribute(.externalStorage)`，与 `FoodRecord` 一致） |

### CookIngredient

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `id` | UUID | `@Attribute(.unique)` |
| `recipe` | CookRecipe? | 多对一反向关系（SwiftData 自动建立） |
| `name` | String | 食材名称（"番茄"） |
| `amount` | String | 数量与单位合并（"2 个"） |
| `order` | Int | 录入顺序，列表稳定排序 |
| `createdAt` | Date | 创建时间 |

### CookCart

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `id` | UUID | `@Attribute(.unique)` |
| `recipe` | CookRecipe? | 多对一，删除菜谱时 cascade 删除车项 |
| `servings` | Int | 份数，默认 1 |
| `addedAt` | Date | 加入时间，用于排序 |

### TodoItem 扩展字段（v4）

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `taskTypeRaw` | String | 任务类型枚举落库（none/prep/cook），默认 `none` |
| `taskType` | TodoTaskType | 计算属性读回 |
| `recipeId` | UUID? | cook 任务关联的菜谱 ID |
| `expectedIngredientsRaw` | String | prep 任务应有食材名称列表，逗号分隔 |
| `expectedIngredients` | [String] | 计算属性：split + trim + filter |
| `checkedIngredientsRaw` | String | prep 任务已勾选食材名称列表，逗号分隔 |
| `checkedIngredients` | [String] | 计算属性：split + trim + filter |

### TodoTaskType 枚举

| case | label | 用途 |
|------|-------|------|
| `.none` | "" | 普通待办（含日程/纪念日/手动/旧 cook 待办） |
| `.prep` | "准备" | 准备食材任务（聚合所有菜的食材清单） |
| `.cook` | "烹饪" | 烹饪任务（每道菜一条） |

### 分类差异化渐变

| 分类 | 渐变 |
|------|------|
| `.home` / `.soup` | 绿：`#C8E6C9 → #81C784` |
| `.dessert` | 紫：`#E1BEE7 → #BA8CCF` |
| `.noodle` / `.all`（回退） | 橙：`#FFE0B2 → #FFAB6E` |

### 烹饪任务 = TodoItem（taskType 区分）

「提交烹饪任务」不是新表，而是往 `TodoItem` 写 N+1 条：

- 1 条 prep：`name = "准备食材（N 道菜）"`，`source = .cook`，`taskType = .prep`，`expectedIngredients = 聚合去重的食材名称列表`
- N 条 cook：`name = "烹饪：{菜名}"`，`source = .cook`，`taskType = .cook`，`recipeId = recipe.id`

主页 `HomeView.currentList` 通过 `taskType` 分发到不同行组件，排序 prep→cook→none。

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 列表页 | `Presentation/Views/SubPages/CookRecipeView.swift` · `CookRecipeView` | `AppRouter.open("cook")` 触发 |
| 详情页 | `CookRecipeView.swift` · `RecipeDetailView` | `NavigationLink` push |
| 新增/编辑 | `CookRecipeView.swift` · `CookRecipeEditSheet(recipe: CookRecipe?)` | nil = 新增；非 nil = 编辑 |
| 烹饪车 sheet | `CookRecipeView.swift` · `CookCartSheet` | cartBar 点击触发 |
| 提交用例 | `Domain/UseCases/SubmitCookTaskUseCase.swift` | `@MainActor struct`，`execute(context:)` |
| prep 任务 sheet | `Presentation/Views/SubPages/Cook/PrepTaskSheet.swift` | 主页 prep row 点击触发 |
| cook 任务 sheet | `Presentation/Views/SubPages/Cook/CookTaskSheet.swift` | 主页 cook row 点击触发 |
| 图标选择 | `Presentation/Views/SubPages/Food/IconPickerSheet.swift` | 复用美食记录组件，注入 `cookEmoji` |
| 模型 | `Domain/Models/CookRecipe.swift` / `CookIngredient.swift` / `CookCart.swift` | 3 个 `@Model` |
| Todo 扩展 | `Domain/Models/TodoItem.swift` | `TodoTaskType` 枚举 + 4 个新字段 |
| 主页联动 | `Presentation/Views/MainTab/HomeView.swift` | `PrepTodoRow` / `CookTodoRow` + 排序 |
| 旧数据迁移 | `App/PersonalButlerApp.swift` · `migrateCookIngredients` | `bootstrap()` 内调用，幂等 |

## 4. 核心场景

### 双列网格列表

**代码入口：** `CookRecipeView.swift` · `body` · `LazyVGrid`

**业务规则：**

- 两列，`spacing: 12`
- 每卡上方 100pt 高的渐变色块 + emoji（有图片显示图片）
- 图标区右下角 pencil overlay，点击进入编辑 sheet（不跳详情）
- 卡片其它区域点击跳详情
- 下方名称 + 难度 pill（蓝底）+ 时长 pill（灰底）
- 分类筛选走 `HorizontalTagBar`

### 菜谱详情

**代码入口：** `CookRecipeView.swift` · `RecipeDetailView`

**业务规则：**

- 顶部 180pt Hero（emoji 72pt 或图片 + 渐变），点击进入编辑
- toolbar：pencil（编辑）+ trash（删除，二次确认 alert）
- 三个 section：食材 / 步骤 / 小贴士（内容非空才渲染）
- 食材 section 兼容旧 `ingredientsLegacyRaw`（迁移前数据）和新 `ingredients`（结构化）
- 底部主色大按钮："加入烹饪车"，点击后插入 `CookCart` + Toast "已加入烹饪车"

### 新增 / 编辑菜谱

**代码入口：** `CookRecipeView.swift` · `CookRecipeEditSheet(recipe: CookRecipe?)`

**业务规则：**

- 5 个 Section：基础信息 / 参数 / 食材 / 步骤 / 小贴士
- 菜名输入框右侧 ✕ 一键清除（仅 name 非空时显示）
- 图标 row 点击 → `IconPickerSheet`（注入 `cookEmoji` 候选）→ 收键盘
- 食材动态行：名称 TextField + 数量 TextField + 删除按钮；"添加食材"按钮 append 新行
- 切换 Picker / Stepper / 点击图标 row / 点击删除/添加食材按钮 → `focusedField = nil` 收键盘
- 时长 Stepper 5-240 分钟，步长 5
- 分类 Picker 4 选（家常菜 / 面食 / 汤羹 / 甜品；不含 `.all`）
- 步骤 / 小贴士 多行 TextField
- 保存：编辑时先 `context.delete(old ingredients)` 再插入新食材；新增时直接 insert
- 保存后 dismiss

### 烹饪车 bar + CookCartSheet

**代码入口：** `CookRecipeView.swift` · `cartBar` + `CookCartSheet`

**业务规则：**

- cartBar 在 `!cartItems.isEmpty` 时显示，胶囊条 + 阴影，显示"烹饪车：N 道菜" + 提交按钮
- 点击 cartBar → CookCartSheet 弹出
- CookCartSheet：列表展示车项（图标 + 名称 + 份数 Stepper + 删除按钮），空态显示"烹饪车为空"
- 份数 Stepper 1-20，每次变化 `context.save()`
- 关闭按钮调用 `dismiss()`
- 底部"提交烹饪任务"按钮 → 触发 `showSubmitConfirm = true`（绑定到父 view 的 alert）

### 提交烹饪任务

**代码入口：** `CookRecipeView.swift` · alert "提交" action + `SubmitCookTaskUseCase.execute(context:)`

**业务规则：**

- alert 文案：`将生成 1 条准备食材任务 + N 条烹饪任务，并清空烹饪车。`
- 点击"提交"：
  1. `lastSubmittedCount = cartItems.count`（在 execute 前捕获，避免 @Query 清空后 toast 计数错误）
  2. `SubmitCookTaskUseCase().execute(context: context)`
  3. `showCartSheet = false`（关闭 CookCartSheet）
  4. Toast "已生成 \(lastSubmittedCount + 1) 条任务" 显示 1.2s 后淡出

**SubmitCookTaskUseCase 逻辑：**

1. `fetch` 所有 `CookCart`，空则 return
2. 聚合食材：遍历每个 cart.recipe.ingredients，按 name 完全相等去重（不合并 amount），`sorted()` 稳定排序
3. 生成 1 条 prep `TodoItem`：`name = "准备食材（N 道菜）"`，`taskType = .prep`，`expectedIngredients = 聚合清单`
4. 每道菜生成 1 条 cook `TodoItem`：`name = "烹饪：{菜名}"`，`taskType = .cook`，`recipeId = recipe.id`
5. `context.delete(cart)` 清空购物车
6. `context.save()`

### 主页 prep / cook 任务展示

**代码入口：** `HomeView.swift` · `currentList` + `row(for:)` + `toggle(_:)`

**业务规则：**

- `TodoDisplay` 扩展字段：`taskType / recipeId / expectedIngredients / checkedIngredients`
- 排序：未完成优先 → `prep(0) → cook(1) → none(2)` → 时间升序
- `row(for:)` switch 分发：
  - `.prep` → `PrepTodoRow`（圆圈 + 名称 + "X/N 已买" 副标题 + 时间）→ 点击 row 弹 `PrepTaskSheet`
  - `.cook` → `CookTodoRow`（圆圈 + 名称 + "查看步骤" Label + 时间）→ 点击 row 弹 `CookTaskSheet`
  - `.none` → `TodoItemRow`（原有组件）
- toggle 行为：
  - prep 圆圈点击 = 全选/全清（写 `expectedIngredientsRaw` 到 `checkedIngredientsRaw`，联动 `isDone`）
  - cook 圆圈点击 = `isDone.toggle()`
  - 普通待办 = 原 toggle 逻辑

### PrepTaskSheet

**代码入口：** `PrepTaskSheet.swift`

**业务规则：**

- List 展示 `todo.expectedIngredients`，每项一个圆圈 + 名称
- 点击行 → toggle 该食材（写 `checkedIngredientsRaw`）
- 全部勾选 → `isDone = true`；取消勾选 → `isDone = false`
- Section 末尾"全部已购买"按钮 = 一键全选 + `isDone = true`

### CookTaskSheet

**代码入口：** `CookTaskSheet.swift`

**业务规则：**

- 通过 `todo.recipeId` + `@Query` 查 `CookRecipe`
- recipe 存在：展示图标 Hero + 难度/时长 + 食材 section + 步骤 section + 小贴士 section
- recipe 已删：展示"菜谱已删除"占位 + "任务仍可标记完成"提示
- 底部"完成烹饪"按钮 → `isDone = true` + dismiss

### 旧数据迁移

**代码入口：** `PersonalButlerApp.swift` · `migrateCookIngredients(context:)`

**业务规则：**

- 在 `bootstrap()` 内 `SeedData.ensureSeeded` 之后调用
- 幂等：仅对 `ingredients.isEmpty && !ingredientsLegacyRaw.isEmpty` 的 recipe 执行
- 按行解析 `ingredientsLegacyRaw`，整行作为 name（不解析数量/单位），插入 `CookIngredient`
- **迁移成功后清空 `ingredientsLegacyRaw = ""`**，避免下次冷启时把用户已删除的食材"复活"
- `context.save()` 是原子的，迁移条目和清空 legacyRaw 要么一起落盘要么一起回滚

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`
  - `personal-butler/Presentation/Views/SubPages/Cook/PrepTaskSheet.swift`
  - `personal-butler/Presentation/Views/SubPages/Cook/CookTaskSheet.swift`
  - `personal-butler/Domain/Models/CookRecipe.swift`
  - `personal-butler/Domain/Models/CookIngredient.swift`
  - `personal-butler/Domain/Models/CookCart.swift`
  - `personal-butler/Domain/Models/TodoItem.swift`
  - `personal-butler/Domain/UseCases/SubmitCookTaskUseCase.swift`
  - `personal-butler/Presentation/Views/MainTab/HomeView.swift`
  - `personal-butler/App/PersonalButlerApp.swift`
- 文档：
  - `docs/PRD.md § 11 烹饪 / 菜谱`
  - `docs/module-spec/module-backup-sync-spec.md`（同步契约 v4）
  - `docs/module-spec/module-main-tab-spec.md`（主页任务层联动）

## 6. 变更历史

- v2 (2026-07-26): 烹饪管理点菜 / 烹饪车 / 烹饪任务改造
  - 新增 `CookIngredient` / `CookCart` 两个 `@Model`
  - `CookRecipe.ingredients` 类型 `String` → `[CookIngredient]` 关系（旧字段保留为 `ingredientsLegacyRaw`）
  - `CookRecipe` 新增 `cartItems` 关系 + `iconImage` 字段
  - `TodoItem` 新增 `taskTypeRaw` / `recipeId` / `expectedIngredientsRaw` / `checkedIngredientsRaw` 4 字段 + `TodoTaskType` 枚举
  - `CreateCookSheet` 重命名为 `CookRecipeEditSheet`，支持新增/编辑复用
  - 新增"加入烹饪车 → 提交烹饪任务"流程（`SubmitCookTaskUseCase`）
  - 新增 `PrepTaskSheet` / `CookTaskSheet` 任务详情页
  - 主页 `HomeView` 区分 prep/cook 任务展示与交互
  - 同步契约 `dataVersion` 3 → 4（详见 `module-backup-sync-spec.md`）
