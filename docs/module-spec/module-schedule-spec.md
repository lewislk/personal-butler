# PersonalButler · 日程管理 · 模块级 SPEC

> 模块职责：管理用户的日程事件（`ScheduleEvent`），提供「日视图（按天分组）」与「月视图（当月日历）」两种展示，同时把符合条件的日程回流到主页待办聚合。

## 1. 范围与边界

本模块负责：

- 日程 CRUD（当前 MVP 支持新增，编辑/删除留待后续版本）
- 日视图：按天分组展示未来日程（`今天 / 明天 / M月d日 EEEE`）
- 月视图：当月日历网格，仅在当月有事件的日期下方显示蓝点
- 颜色标签（`blue / green / orange`）驱动左侧竖条颜色
- 全天 vs 指定时刻两种事件形态
- 与主页待办聚合的数据契约（提供 `startDate / isCompleted / isAllDay`）

不覆盖：

- 编辑/删除 UI（暂无）
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

当前只渲染 **今天所在的月份**，无左右翻月能力（MVP）。

- 头部：`yyyy 年 M 月`
- 星期表头：`日/一/二/三/四/五/六`（周日起）
- 网格：`Calendar.range(of: .day, in: .month, ...)`；起始占位数 = `firstWeekday - 1`
- 事件标记：`hasEvent: Set<Int>` = 本月内 startDate 命中的日；命中的日期下方渲染 4pt 蓝点

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 页面入口 | `Presentation/Views/SubPages/ScheduleView.swift` · `ScheduleView` | 通过 `AppRouter.open("schedule")` 触发导航 push |
| 数据订阅 | `ScheduleView` 内 `@Query(sort: \ScheduleEvent.startDate)` | 声明式绑定，无需手动 fetch |
| 新增日程 | `ScheduleView.swift` · `CreateScheduleSheet` | 由 FAB 触发 `.sheet` |
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

**代码入口：** `ScheduleView.swift` · `monthView`

**业务规则：**

- 仅显示当月，标注当月内有日程的日期
- 当日高亮：数字加粗 + 主色
- 事件小点直径 4pt

**实现逻辑：**

1. `cal.dateComponents([.year, .month], from: today)` 定位当月起点
2. `range = cal.range(of: .day, in: .month, for: start)` 得到 `1...31` 类似区间
3. `firstWeekday = cal.component(.weekday, from: start)` 决定顶部空白格数
4. 遍历 events：若 `dateComponents.year == 当年 && .month == 当月` → 记录 `.day` 进 `hasEvent: Set<Int>`
5. LazyVGrid 渲染每个 day：数字 + 圆点（`hasEvent.contains(day)` 时着色）

### 新增日程

**代码入口：** `ScheduleView.swift` · `CreateScheduleSheet`

**业务规则：**

- 标题为空默认 "无标题"
- 全天开关切换 `DatePicker` 的可选组件（date-only 或 date + hourAndMinute）
- 颜色标签三选一（`.blue/.green/.orange`）

**实现逻辑：**

1. FAB 点击 → `showCreate = true` → sheet 弹出 `CreateScheduleSheet`
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
