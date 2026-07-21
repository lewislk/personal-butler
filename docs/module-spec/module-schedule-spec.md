# PersonalButler · 日程管理 · 模块级 SPEC

> 模块职责：管理用户的日程事件（`ScheduleEvent`），提供「日视图（按天分组）」与「月视图（当月日历）」两种展示，同时把符合条件的日程回流到主页待办聚合。

## 1. 范围与边界

本模块负责：

- 日程 CRUD（新增 / 编辑 / 删除；删除需二次确认）
- 日视图：按天分组展示未来日程（`今天 / 明天 / M月d日 EEEE`）
- 月视图：当月日历网格 + **当月全部日程列表**（含过去日期，按天分组）
- 颜色标签（`blue / green / orange`）驱动左侧竖条颜色
- 全天 vs 指定时刻两种事件形态
- 与主页待办聚合的数据契约（提供 `startDate / isCompleted / isAllDay`）

不覆盖：

- 与系统 Calendar 双向同步（不做）
- 定时推送注册（`NotificationManager` 已提供能力但本模块 MVP 未接入）
- 待办勾选逻辑（在 [module-main-tab-spec.md](./module-main-tab-spec.md) 主页卡片内完成）

## 2. 核心概念

### ScheduleEvent

SwiftData `@Model`，一次日程一行。关键字段：

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `title` | String | 标题 |
| `remark` | String | 备注 |
| `startDate` | Date | 开始时间；日/月视图排序主键 |
| `endDate` | Date? | 结束时间（当前 UI 未使用） |
| `isAllDay` | Bool | 是否全天，全天则显示 "全天" |
| `reminderMinutesBefore` | Int? | 提前提醒分钟数（MVP 未注册通知） |
| `colorTag` | Enum(.blue/.green/.orange) | 决定日视图左侧竖条颜色 |
| `isCompleted` | Bool | 已完成（主页勾选切换） |

### 日视图分组

按 `Calendar.startOfDay(for: startDate)` 分桶；未完成且 `startDate >= 今天 0 点` 的事件才纳入；每桶内按 `startDate` 升序。

标题格式：

- 今天 → `"今天 · M月d日 EEEE"`
- 明天 → `"明天 · M月d日 EEEE"`
- 之后 → `"M月d日 EEEE"`

### 月视图数据

月视图分为两部分：**日历网格** 与 **当月日程列表**。

**日历网格（仅当月，MVP 无左右翻月）：**

- 头部：`yyyy 年 M 月`
- 星期表头：`日/一/二/三/四/五/六`（周日起）
- 网格：`Calendar.range(of: .day, in: .month, ...)`；起始占位数 = `firstWeekday - 1`
- 事件标记：`hasEvent: Set<Int>` = 本月内 startDate 命中的日；命中的日期下方渲染 4pt 蓝点

**当月日程列表（网格下方）：**

- 数据源：`events` 中 `startDate` 落在当月的全部事件（含已完成、含今日之前）
- 分组：按 `Calendar.startOfDay(for: startDate)` 分桶，桶内按 `startDate` 升序
- 桶标题：`今天 · … / 明天 · … / 昨天 · … / M月d日 EEEE`
- 空态：`本月暂无日程`
- 复用日视图的 `scheduleRow`：点击进入编辑，长按弹出「编辑 / 删除」上下文菜单

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 页面入口 | `Presentation/Views/SubPages/ScheduleView.swift` · `ScheduleView` | 通过 `AppRouter.open("schedule")` 触发导航 push |
| 数据订阅 | `ScheduleView` 内 `@Query(sort: \ScheduleEvent.startDate)` | 声明式绑定，无需手动 fetch |
| 新增 / 编辑 | `ScheduleView.swift` · `EditScheduleSheet(event:)` | `event == nil` 表示新增；否则复用同一 Form 编辑现有实例 |
| 删除入口 | `ScheduleView.swift` · `scheduleRow` 使用 `SwipeToDeleteRow` 包裹，向左滑露出红色"删除"按钮 → 点击后 `pendingDelete` 触发 `.alert` 二次确认 | `SwipeToDeleteRow` 为本文件私有组件，手写 `DragGesture`，仅在横向位移大于纵向时生效，避免与 `ScrollView` 垂直滚动冲突；同一时刻只允许一行处于展开态 |
| 模型 | `Domain/Models/ScheduleEvent.swift` | `@Model` + `ScheduleColorTag` 枚举 |
| 视图切换 | `ScheduleView.mode: Int (0/1)` + `SegmentedPill` | 0 = 日视图，1 = 月视图 |

## 4. 核心场景

### 日视图渲染

**代码入口：** `ScheduleView.swift` · `dayView` + `dayGroups`

**业务规则：**

- 只显示未完成 (`!isCompleted`) 且 `startDate >= today.startOfDay` 的日程
- 按天分桶，桶标题带"今天/明天"前缀
- 每行左侧根据 `colorTag` 显示 3pt 竖条（蓝/绿/橙）

**实现逻辑：**

1. `dayGroups` 计算：
   - `buckets: [Date: [ScheduleEvent]] = [:]`
   - 遍历 `events where !e.isCompleted`
   - `d = cal.startOfDay(for: e.startDate)`；若 `d >= 今天` 则 `buckets[d].append(e)`
   - 按 `d` 升序输出 tuple `(title, items)`
2. 每桶渲染 `Text(group.title)` + 内部逐个 `scheduleRow(e)`
3. `scheduleRow`：时间列（`e.isAllDay ? "全天" : e.startDate.hourMinute`）+ 颜色竖条 + 标题 + 备注
4. `barColor(ScheduleColorTag)`：blue → `primary`；green → `success`；orange → `#F0A150`

### 月视图渲染

**代码入口：** `ScheduleView.swift` · `monthView` + `monthList(year:month:)`

**业务规则：**

- 日历网格仅显示当月，标注当月内有日程的日期
- 当日高亮：数字加粗 + 主色
- 事件小点直径 4pt
- 网格下方额外渲染 **当月日程列表**：把当月全部事件（含过去、含已完成）按天分组列出

**实现逻辑：**

1. `cal.dateComponents([.year, .month], from: today)` 定位当月起点
2. `range = cal.range(of: .day, in: .month, for: start)` 得到 `1...31` 类似区间
3. `firstWeekday = cal.component(.weekday, from: start)` 决定顶部空白格数
4. 遍历 events：若 `dateComponents.year == 当年 && .month == 当月` → 记录 `.day` 进 `hasEvent: Set<Int>`
5. LazyVGrid 渲染每个 day：数字 + 圆点（`hasEvent.contains(day)` 时着色）
6. `monthList(year:month:)`：过滤当月事件 → 按 `startOfDay` 分桶 → 输出 `(monthListDayTitle, items)`；空态显示"本月暂无日程"；行复用 `scheduleRow`（点击编辑，长按删除）

### 编辑日程

**代码入口：** `ScheduleView.swift` · `scheduleRow` 点击 → `editingEvent = e` → `.sheet(item:)` 打开 `EditScheduleSheet(event: e)`

**实现逻辑：**

1. `EditScheduleSheet.init(event:)` 把 `event` 字段拷贝进 `@State`，避免 SwiftData 属性在 `@State` 生命周期里直接被写
2. 保存时 `event != nil` 分支：把 `@State` 值回写到原实例字段 → `context.save()`；SwiftData `@Query` 自动感知

### 删除日程（左滑 + 二次确认）

**代码入口：** `ScheduleView.swift` · `scheduleRow` 被 `SwipeToDeleteRow` 包裹 → 用户向左拖 → 露出红色"删除"按钮 → 点击 → `pendingDelete = e` → `.alert` 二次确认

**业务规则：**

- 交互与系统 `UITableView` 一致：向左滑超过按钮宽度一半锁定展开；已展开时向右滑超过一半（或点击行本身）收起；只允许一行同时展开
- 判定手势方向：**只有**当 `|Δx| > |Δy|` 才认作左滑，避免与 `ScrollView` 纵向滚动冲突
- 二次确认使用系统 `.alert`，标题 "删除该日程？"，消息带日程标题
- 取消 → 关闭弹窗，展开态保留（用户可再次选择）
- 确认 → `context.delete(e)` + `context.save()`，同时清空展开态；`@Query` 立即刷新，两种视图同步移除

**实现逻辑（`SwipeToDeleteRow`）：**

1. `ZStack(alignment: .trailing)`：底层放红色"删除"按钮，上层放内容行
2. `@GestureState` 跟踪 `dragTranslation` 与 `isHorizontalDrag`（手势结束自动归零，避免状态残留）
3. 内容行 `.offset(x: liveOffset)`；`liveOffset` 由 `baseOffset` (由父视图传入的 `isOpen` 派生) + 拖动位移得来，并 clamp 在 `[-1.2 * actionWidth, 0]`
4. `DragGesture.onEnded` 依据阈值切换 `isOpen`，用 `.spring(response: 0.28, dampingFraction: 0.85)` 动画
5. 展开态由父视图统一持有 (`openSwipeId: UUID?`) 且用 `Binding` 注入，因此新滑开一行时旧行会自动收回；点击 `ScrollView` 空白区通过 `.simultaneousGesture(TapGesture)` 也会收回

### 新增日程

**代码入口：** `ScheduleView.swift` · `EditScheduleSheet(event: nil)`

**业务规则：**

- 标题为空默认 "无标题"
- 全天开关切换 `DatePicker` 的可选组件（date-only 或 date + hourAndMinute）
- 颜色标签三选一（`.blue/.green/.orange`）
- 新增模式不显示"已完成"开关（该字段仅编辑模式可见）

**实现逻辑：**

1. FAB 点击 → `showCreate = true` → sheet 弹出 `EditScheduleSheet(event: nil)`
2. Form 收集 title / remark / startDate / isAllDay / colorTag
3. 保存：`ScheduleEvent(...)` → `context.insert(e)` → `context.save()` → `dismiss()`
4. SwiftData `@Query` 自动感知，日/月视图立即刷新

### 事件回流到主页

**代码入口：** `HomeView.swift` · `todayList` / `weekList`（见 [module-main-tab-spec.md](./module-main-tab-spec.md)）

**业务规则：**

- 主页读 `ScheduleEvent`，业务规则同 main-tab；本模块只需保证字段稳定：
  - `title` / `startDate` / `isAllDay` / `isCompleted` / `colorTag`
- 主页勾选时会写回 `isCompleted`；本模块日视图会自动过滤掉这些已完成项

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/ScheduleView.swift`
  - `personal-butler/Domain/Models/ScheduleEvent.swift`
  - `personal-butler/Core/Extensions/Date+Ext.swift`（`startOfDay / hourMinute / daysBetween`）
- 文档：
  - `docs/PRD.md § 7 日程管理`
  - `docs/UI_DEMO.md`
