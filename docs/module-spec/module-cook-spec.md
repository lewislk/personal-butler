# PersonalButler · 烹饪 / 菜谱 · 模块级 SPEC

> 模块职责：管理自建菜谱库；提供分类筛选、菜谱详情查看、以及"加入今日烹饪计划"能力（自动写一条 Todo，回流到主页）。

## 1. 范围与边界

本模块负责：

- 菜谱 CRUD（MVP：新增；编辑/删除后续）
- 分类筛选（全部菜谱 / 家常菜 / 面食 / 汤羹 / 甜品）
- 双列 LazyVGrid 卡片列表；每卡显示 emoji + 难度 + 时长
- 菜谱详情：食材 / 步骤 / 小贴士 分段展示
- 「加入今日烹饪计划」：向 `TodoItem` 表插入一条 `source == .cook`、`dueDate = 当前` 的待办
- 与主页今日待办的联动（新增的烹饪 Todo 会立即出现在主页）

不覆盖：

- 菜谱步骤计时器 / 引导烹饪
- 菜谱图片（当前仅 emoji + 渐变色块）
- 菜谱分享 / 导出

## 2. 核心概念

### CookRecipe

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `name` | String | 菜名 |
| `emoji` | String | 封面 emoji |
| `difficulty` | Enum(.easy/.medium/.hard) | 难度 pill（蓝底） |
| `minutes` | Int | 预计耗时（分钟） |
| `category` | Enum(.all/.home/.noodle/.soup/.dessert) | 分类 |
| `ingredients` | String（多行） | 食材，每行一条 |
| `steps` | String（多行） | 步骤，每行一条 |
| `tips` | String | 小贴士 |

### 分类差异化渐变

| 分类 | 渐变 |
|------|------|
| `.home` / `.soup` | 绿：`#C8E6C9 → #81C784` |
| `.dessert` | 紫：`#E1BEE7 → #BA8CCF` |
| `.noodle` / `.all`（回退） | 橙：`#FFE0B2 → #FFAB6E` |

### 烹饪计划 = Todo

「加入今日烹饪计划」不是新表，而是往 `TodoItem` 写一条：

```swift
TodoItem(name: "尝试做\(recipe.name)", source: .cook, dueDate: Date())
```

主页 `HomeView.todayList` 会通过 `t.dueDate` 命中今日 → 自动出现在"今日待办"卡片，标注 `source.label == "烹饪"`。

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 页面入口 | `Presentation/Views/SubPages/CookRecipeView.swift` · `CookRecipeView` | `AppRouter.open("cook")` 触发 |
| 详情 | `CookRecipeView.swift` · `RecipeDetailView` | 通过 SwiftUI `NavigationLink` 打开（在子页面栈中再 push） |
| 新增 | `CookRecipeView.swift` · `CreateCookSheet` | FAB 触发 |
| 模型 | `Domain/Models/CookRecipe.swift` | `@Model` + `CookDifficulty` + `CookCategory` |
| 联动 | `TodoItem.source == .cook` | 写入 Todo，主页自动展示 |

## 4. 核心场景

### 双列网格列表

**代码入口：** `CookRecipeView.swift` · `body` · `LazyVGrid`

**业务规则：**

- 两列，`spacing: 12`
- 每卡上方 100pt 高的渐变色块 + emoji
- 下方名称 + 难度 pill（蓝底）+ 时长 pill（灰底）
- 分类筛选走 `HorizontalTagBar`

**实现逻辑：**

1. `@Query(sort: \CookRecipe.name) var list`
2. `filtered = cat == .all ? list : list.filter { $0.category == cat }`
3. `LazyVGrid(columns: [GridItem, GridItem], spacing: 12) { ForEach(filtered) { NavigationLink { RecipeDetailView(recipe:) } label: { cookCard(r) } } }`
4. `.buttonStyle(.plain)` 关闭默认高亮

### 菜谱详情

**代码入口：** `CookRecipeView.swift` · `RecipeDetailView`

**业务规则：**

- 顶部 180pt Hero（emoji 72pt + 橙色渐变）
- 三个 section：食材 / 步骤 / 小贴士（内容非空才渲染）
- 底部主色大按钮："加入今日烹饪计划"

**实现逻辑：**

1. `ScrollView { VStack { Hero + pills + section*3 + 大按钮 } }`
2. `section(title:content:)` 复用组件：14pt semibold 标题 + 13pt 正文；卡片背景 `AppColorTheme.bg`
3. 大按钮点击 → 写入 Todo（下节）+ Toast

### 加入今日烹饪计划

**代码入口：** `RecipeDetailView` · 底部大按钮 action

**业务规则：**

- 每次点击都插入一条新 Todo（不去重）
- Todo 名称："尝试做{菜名}"；`source = .cook`；`dueDate = Date()`
- 保存后 1.2s 显示 Toast "已加入今日待办" 后自动淡出

**实现逻辑：**

```swift
let todo = TodoItem(name: "尝试做\(recipe.name)", source: .cook, dueDate: Date())
context.insert(todo)
try? context.save()
withAnimation { toastVisible = true }
DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
    withAnimation { toastVisible = false }
}
```

- Toast 使用 `.overlay(alignment: .bottom)` + `RoundedRectangle(20)` 黑底
- SwiftData `@Query` 自动感知，主页 HomeView 下次进入即可看到

### 新增菜谱

**代码入口：** `CookRecipeView.swift` · `CreateCookSheet`

**业务规则：**

- name 空 → "未命名"
- 时长 Stepper 5-240 分钟，步长 5
- 分类 Picker 4 选（家常菜 / 面食 / 汤羹 / 甜品；不含 `.all`）
- 食材 / 步骤 都是多行 TextField（`.lineLimit(3...8)` / `3...10`）

**实现逻辑：**

1. FAB → sheet
2. Form 收集全部字段 → `CookRecipe(...)` → `context.insert` → save

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/CookRecipeView.swift`
  - `personal-butler/Domain/Models/CookRecipe.swift`
  - `personal-butler/Domain/Models/TodoItem.swift`
- 文档：
  - `docs/PRD.md § 11 烹饪 / 菜谱`
