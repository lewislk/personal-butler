# PersonalButler · Main Tab · 模块级 SPEC

> 模块职责：底部三 Tab 主界面 ── 主页（待办聚合 + 功能宫格）、全部应用（拖拽排序）、我的（隐私 / 备份 / 同步入口）。它是所有业务子页面的**唯一入口**，也是「跨模块聚合」的关键页面。

## 1. 范围与边界

本模块负责：

- 自定义底部 tab bar（HStack，非系统 `TabView`）
- 主页 `HomeView`：**今日 / 近期待办聚合**、功能宫格 Top 6、勾选完成
- 全部应用 `AllAppView`：模块拖拽排序、Top6 分割线提示、跳转子页面
- 我的 `MineView`：应用锁 / 数据备份 / 数据恢复 / 局域网同步 / 清除缓存 / 版本信息 入口
- 每 Tab 首次进入时保证种子数据已注入（通过 `MainTabView.task`）

不覆盖：

- 各子页面（见 [module-schedule-spec.md](./module-schedule-spec.md)、[module-anniversary-spec.md](./module-anniversary-spec.md)、[module-password-otp-spec.md](./module-password-otp-spec.md) 等）
- 备份 / 局域网同步的具体逻辑（见 [module-backup-sync-spec.md](./module-backup-sync-spec.md)）
- ModelContainer / 根 NavigationStack 初始化（见 [module-app-shell-spec.md](./module-app-shell-spec.md)）

## 2. 核心概念

### 待办聚合（HomeTodoTab）

首页顶部卡片有两种视角：`today` / `week`。它们不是「查一张 Todo 表」而是把多来源的事件按业务规则**动态合成**成一个统一列表：

| 来源 | 今日视角 | 近期视角 |
|------|---------|---------|
| `ScheduleEvent` | 开始时间落在今天 0-24 点 | 开始时间落在未来 7 天 |
| `TodoItem` | `dueDate` 在今天 或 `dueDate == nil && !isDone` | — |
| `Anniversary(type = .yearly)` | — | 距下次发生 ≤ 7 天 |

紧急态判定：日程距离现在 < 4h（今日）/ < 6h（近期），或纪念日 ≤ 3 天。

### AppModule 与 Top6

`AppModule.order` 决定在「全部应用」中的排列位置，同时首页宫格只截取前 6 项（`modules.prefix(6)`）。用户在 AllAppView 拖拽即更新 `order` 字段。

### 排序编辑模式

`AllAppView.editing: Bool` 只用于切换右上角按钮文案 / 颜色（排序 ↔ 完成）；**实际拖拽随时可用**，不因 `editing` 是否为 true 而受限。

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 主 Tab 容器 | `Presentation/Views/MainTab/MainTabView.swift` | 自定义 HStack tab bar；`.task` 触发 SeedData |
| 主页 | `Presentation/Views/MainTab/HomeView.swift` | 待办卡片 + 功能宫格（Top6）；勾选 toggle |
| 全部应用 | `Presentation/Views/MainTab/AllAppView.swift` | 拖拽排序（`.onDrag` + `AppDropDelegate`）；点击跳转 |
| 我的 | `Presentation/Views/MainTab/MineView.swift` | 隐私安全设置卡片 + 关于卡片 + 弹窗触发 |
| 复用 UI | `Presentation/Components/TodoItemRow.swift` / `SegmentedPill.swift` / `HorizontalTagBar.swift` | 见 [module-infra-spec.md](./module-infra-spec.md) |

## 4. 核心场景

### 主页 · 今日待办聚合

**代码入口：** `HomeView.swift` · `todayList: [TodoDisplay]`

**业务规则：**

- 展示"今天 0-24 点"的所有待办事项，来源合并：日程 + 手动/烹饪 Todo
- 已完成条目排在未完成之后
- 时间标签：日程显示 `HH:mm` 或 "全天"；已完成显示 "已完成"；手动 Todo 无日期时显示 "今日"
- 紧急态：日程距现在 < 4h → 红色时间标签

**实现逻辑：**

1. 通过 `@Query(sort: \ScheduleEvent.startDate)`、`@Query(sort: \Anniversary.date)`、`@Query(sort: \TodoItem.createdAt)` 声明式订阅数据
2. `todayList`:
   - 遍历 `schedules`：`s.startDate >= today && s.startDate <= endOfToday` → 拼装 `TodoDisplay(sourceLabel: "日程", timeLabel: hm)`
   - 遍历 `manualTodos`：有 `dueDate` 且落在今日 / 或 `dueDate == nil && !isDone` → 拼装 `TodoDisplay(sourceLabel: t.source.label, timeLabel: "今晚" / "今日")`
3. 稳定排序：`sorted { !$0.isDone && $1.isDone }`（未完成在前）
4. 渲染 `TodoItemRow`，每项 `onToggle` 回调触发 `toggle(_ todo:)`
5. `toggle(_:)`：分支处理 `refSchedule?.isCompleted.toggle()` 或 `refManual?.isDone.toggle()`，随后 `context.save()`；SwiftData `@Query` 自动感知刷新

### 主页 · 近期待办聚合

**代码入口：** `HomeView.swift` · `weekList: [TodoDisplay]`

**业务规则：**

- 展示未来 7 天（含今日）的日程 + 每年重复类纪念日（累计类不参与）
- 时间标签使用 `DateCalculator.relativeLabel(_:)`：今天 / 明天 / EEEE / N 天后
- 纪念日 ≤ 3 天为紧急

**实现逻辑：**

1. 计算 `now = startOfDay`，`end = now + 7 天`
2. 收集 `schedules where startDate ∈ [now, end]`
3. 收集 `annis where type == .yearly && daysUntilNextYearly ≤ 7`
4. 每项组装 `TodoDisplay(timeLabel: DateCalculator.relativeLabel(...))`
5. 顺序不额外排序（`@Query` 已按时间/日期排序）

### 主页 · 功能宫格

**代码入口：** `HomeView.swift` · `appsGrid`

**业务规则：**

- 3 列 LazyVGrid，只显示 `AppModule.order` 前 6 项
- 点击进入对应子页面；`comingSoon == true` 禁用点击

**实现逻辑：**

1. `@Query(sort: \AppModule.order) var modules`
2. `modules.prefix(6)`
3. `FeatureCard(module:)` 展示 SF Symbol + name + tag
4. Button `router.open(m.id)` → 由 App 骨架 `AppModuleRouter` 分发到具体子页面

### 全部应用 · 拖拽排序

**代码入口：** `AllAppView.swift` · `appList` + `AppDropDelegate.performDrop`

**业务规则：**

- 长按任意 row 拖拽即可移动位置；不需先切换到编辑模式
- 前 6 项与后续项之间视觉上有 "— 首页折叠 —" 分割线，用户能直观理解「拖到前 6 项就会上首页」
- 拖拽结束按新顺序重排全部 `AppModule.order`，`context.save()` 落库
- 首页 `@Query(sort: \AppModule.order)` 自动感知并刷新宫格

**实现逻辑：**

1. `ForEach(Array(modules.enumerated()), id: \.element.id) { idx, m in }`
2. `idx == 6` 时插入分割行（视觉标记 "首页折叠"）
3. 每 row：`.onDrag { NSItemProvider(object: m.id as NSString) }`
4. `.onDrop(of: [.text], delegate: AppDropDelegate(target: m, list: modules, context: context))`
5. `AppDropDelegate.performDrop`：
   - 从 `NSItemProvider` 取 dragged id
   - 定位 fromIdx / toIdx
   - 数组 `remove(at: fromIdx)` + `insert(at: toIdx)`
   - 遍历重写每项 `order = i`
   - `context.save()`

### 全部应用 · 跳转子页面

**代码入口：** `AllAppView.swift` · `AppRow` Button

**业务规则：**

- 点击任何一行（包括 `comingSoon: true` 的项）都 `router.open(module.id)`
- 未注册子页面的模块 id 由 `AppModuleRouter` 兜底展示 `ComingSoonView`（"敬请期待"）

### 我的 · 各入口

**代码入口：** `MineView.swift` · `privacyCard` / `aboutCard`

**业务规则：**

- **应用锁**：只读展示 `setting?.appLockMethod == "faceID"` → "面容ID"；MVP 不提供切换逻辑
- **数据备份 / 数据恢复**：均触发 `showBackupSheet = true`，弹出 `LocalBackupSheet`（当前 MVP 只有"导出"能力，"恢复"入口点击行为同样是打开该弹窗）
- **局域网同步**：触发 `showSyncSheet = true`，弹出 `LanSyncView`
- **清除缓存**：直接把 `cacheSize` 置 "0 KB" 并 toast「已清除」；未真正扫描/删除文件（MVP）
- **版本信息**：硬编码 `"v1.0.0"`

**实现逻辑：**

1. `@Query var settings: [AppSetting]` → `settings.first`（业务上永远只有 1 条）
2. `env.lastSyncTime` 用于渲染同步入口的副标题
3. 各 row 通过 `row(icon:label:value:action:)` 生成，统一样式
4. Toast 使用 `withAnimation` + `DispatchQueue.main.asyncAfter(1.5)` 自动隐藏

### 首启种子数据触发

**代码入口：** `MainTabView.swift` · `.task { SeedData.ensureSeeded(in: context) }`

**业务规则：**

- 每次 `MainTabView` 出现都调用；`SeedData` 内部通过「AppModule 是否为空」保证幂等
- 目的：确保用户第一次打开就有可视化数据；不影响后续正常使用

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/MainTab/MainTabView.swift`
  - `personal-butler/Presentation/Views/MainTab/HomeView.swift`
  - `personal-butler/Presentation/Views/MainTab/AllAppView.swift`
  - `personal-butler/Presentation/Views/MainTab/MineView.swift`
  - `personal-butler/Data/LocalDataSource/SeedData.swift`
  - `personal-butler/Presentation/Components/TodoItemRow.swift`
- 文档：
  - `docs/PRD.md § 4 主页 / § 5 全部应用 / § 6 我的`
  - `docs/UI_DEMO.md`
