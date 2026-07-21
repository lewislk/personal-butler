# PersonalButler · 纪念日 · 模块级 SPEC

> 模块职责：管理两类"日期计数"事件：**每年重复**（`.yearly` 计算下次日期倒计时）与**累计天数**（`.cumulative` 从起始日算今天是第几天），支持公历 / 农历两种日历系统。

## 1. 范围与边界

本模块负责：

- 纪念日 CRUD（MVP 支持新增；编辑/删除留待后续）
- 顶部 Hero 卡片：展示"最近的一次每年重复纪念日"，大字倒计时
- 分段切换：每年重复 vs 累计天数
- 列表 badge：`.yearly` → "还有 N 天"（≤7 天橙色警戒）；`.cumulative` → "第 N 天" 蓝色
- 农历日期展示（`DateCalculator.lunarString`）
- 与主页近期待办的数据契约（`type == .yearly && 剩余天数 ≤ 7`）

不覆盖：

- 农历事件的**推送提醒注册**（当前 MVP 未接入 `NotificationManager`）
- 累计类的"周年提醒"（累计事件不进入主页 weekList）
- 编辑与删除 UI

## 2. 核心概念

### Anniversary

SwiftData `@Model`。核心字段：

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `name` | String | 纪念日名称 |
| `date` | Date | 每年类：原始年月日（取月/日作为周期基准）；累计类：起始日 |
| `isLunar` | Bool | 是否按农历循环（仅对 `.yearly` 有意义） |
| `type` | Enum(.yearly / .cumulative) | 类型 |
| `reminderDaysBefore` | Int? | 提前提醒天数（MVP 未接入通知） |
| `emoji` | String | 展示 emoji（🎂/💍/🌕…） |

### 类型的业务差异

| 类型 | 计算函数 | 展示逻辑 |
|------|---------|---------|
| `.yearly` | `DateCalculator.daysUntilNextYearly(from:isLunar:)` | 下一次发生距今 N 天；badge = "还有 N 天"；≤7 天橙色警戒 |
| `.cumulative` | `DateCalculator.cumulativeDays(from:)` | 从起始日算今天是第几天（含今天）；badge = "第 N 天" 蓝色 |

### Hero 卡片

在 `.yearly` 列表中挑距今**最近**的一项渲染。是本页视觉焦点。

- 大数字：距下次天数
- 副标题："今天" / "N 天后"
- 日期展示：农历 → `农历 · 冬月廿三` / 公历 → `公历 · 7月23日`

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 页面入口 | `Presentation/Views/SubPages/AnniversaryView.swift` · `AnniversaryView` | `AppRouter.open("anniversary")` 触发 |
| 数据订阅 | `@Query(sort: \Anniversary.date)` | 声明式 |
| 新增 | `AnniversaryView.swift` · `CreateAnniversarySheet` | FAB 触发 |
| 模型 | `Domain/Models/Anniversary.swift` | `@Model` + `AnniversaryType` |
| 日期计算 | `Core/Utils/DateCalculator.swift` | `daysUntilNextYearly` / `cumulativeDays` / `lunarString` / `gregorianDateLabel` |

## 4. 核心场景

### 每年重复倒计时

**代码入口：** `AnniversaryView.swift` · `filtered`（`mode == .yearly` 分支） + `DateCalculator.daysUntilNextYearly(from:isLunar:)`

**业务规则：**

- 从原始 `date` 中取"月/日"作为周期基准
- 农历：使用 `Calendar(identifier: .chinese)` 换算；公历：`.gregorian`
- 计算逻辑：以今年为基准构造下次发生日期；若已过则取明年
- 剩余天数 ≤ 7 视为"临近"（列表 badge 显示橙色 + `#FFF3E6` 背景）

**实现逻辑：**

1. `DateCalculator.daysUntilNextYearly`：
   - 目标日历 = 农历?`.chinese`:`.gregorian`
   - 提取原日期的 `month, day`
   - 拼装 `year = 今年 + month + day`；若得到日期 < `today.startOfDay` → `year += 1`
   - 返回 `today.daysBetween(next)`
2. 列表排序：`sorted { daysUntilNextYearly($0) < daysUntilNextYearly($1) }`
3. `closestYearly = list.filter(.yearly).min(by: 距今天数)` → 顶部 Hero 卡片
4. Hero 卡片：`Text("\(days)")` 大字 + 农历/公历标签（`labelForDate`）

### 累计天数

**代码入口：** `AnniversaryView.swift` · `filtered`（`mode == .cumulative`） + `DateCalculator.cumulativeDays(from:)`

**业务规则：**

- 用于"戒烟 / 在一起 / 入职纪念"等需要展示"已坚持第 N 天"
- 天数含今天（起始日为第 1 天）
- 显示为 "第 N 天" 蓝色 pill

**实现逻辑：**

1. `DateCalculator.cumulativeDays(from:)`：`dateComponents(.day, from: startOfDay(start), to: startOfDay(now)).day! + 1`
2. 列表按 `date` 升序（起始日越早越靠前）
3. badge：`Text("第 \(n) 天")` + `Color(hex: 0xEEF3FD)` 底

### 农历展示

**代码入口：** `DateCalculator.lunarString(from:)`

**业务规则：**

- 当 `isLunar == true` 时，列表副标题与 Hero 卡片副标题使用农历字串
- 格式：`农历 · 冬月廿三`（`Calendar(.chinese) + DateFormatter locale zh_CN + dateFormat "MMMMd日"`）

**实现逻辑：**

1. `DateFormatter.calendar = Calendar(identifier: .chinese)`
2. `dateFormat = "MMMMd日"`
3. 前缀 "农历 · "

### 新增纪念日

**代码入口：** `AnniversaryView.swift` · `CreateAnniversarySheet`

**业务规则：**

- 名称空时保存为"未命名"
- Emoji 默认 🎉
- 类型 Picker：每年重复 / 累计天数
- 农历开关（默认关）

**实现逻辑：**

1. FAB → `showCreate = true`
2. Form：name / emoji / type / date / isLunar
3. `Anniversary(name:..., date:..., isLunar:..., type:..., emoji:...)` → `context.insert` → `save`

### 主页近期待办联动

**代码入口：** `HomeView.swift` · `weekList`

**业务规则：**

- 仅 `type == .yearly` 且 `daysUntilNextYearly ≤ 7` 的项进入主页近期待办
- badge 显示"今天"或"N 天后"，≤ 3 天视为紧急（红色时间标签）

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/AnniversaryView.swift`
  - `personal-butler/Domain/Models/Anniversary.swift`
  - `personal-butler/Core/Utils/DateCalculator.swift`
- 文档：
  - `docs/PRD.md § 8 纪念日`
