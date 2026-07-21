# 日程管理：编辑 / 删除 / 月视图列表

日期：2026-07-21
涉及文件：
- `personal-butler/Presentation/Views/SubPages/ScheduleView.swift`
- `docs/module-spec/module-schedule-spec.md`

## 背景

用户反馈两个问题：
1. 月视图只有日历网格没有列表，无法看到当月全部日程
2. 日程行无法编辑/删除

## 决策

### 编辑：合并 `CreateScheduleSheet` → `EditScheduleSheet(event: ScheduleEvent?)`

- `event == nil` 复用新增流程，`event != nil` 走编辑流程
- `init` 把 model 字段拷贝到 `@State`，避免 SwiftData 属性直接绑到 `@State` 引发的写时机不明确问题
- 保存时判断 `event` 是否为空：新增 `context.insert`，编辑逐字段回写
- 编辑模式额外显示"已完成"开关

### 删除：向左滑 → 红色"删除"按钮 → `.alert` 二次确认

- **为什么不用 `.swipeActions`**：`.swipeActions` 只在 `List` 里有效；本页是 `ScrollView + VStack`（要和日历网格共存，整体转 `List` 会打乱布局与分组头样式）
- **为什么不用 `.contextMenu`**：产品要求"苹果原生经典交互 = 左滑露删除"，与 iOS 通讯录/邮件/备忘录一致
- **手写实现 `SwipeToDeleteRow`（本文件私有组件）**：
  - `ZStack(alignment: .trailing)`：底层红色按钮，上层内容行 + `.offset`
  - `@GestureState` 跟踪实时位移，结束自动归零
  - **关键：判定手势方向** `|Δx| > |Δy|` 才认作左滑，否则让 `ScrollView` 处理垂直滚动
  - `.spring(response: 0.28, dampingFraction: 0.85)` 接近系统曲线
  - 展开态提升到父视图 `openSwipeId: UUID?`，通过 `Binding` 注入 → 新展开一行自动关闭旧行
  - `ScrollView.simultaneousGesture(TapGesture)` → 点空白收回；切视图 `onChange(of: mode)` 也收回
  - 已展开时点击行本身 → 先收回，不触发编辑（贴合系统行为）

### 月视图列表：网格下方 `monthList(year:month:)`

- 复用 `scheduleRow`（点击编辑 + 长按删除）
- 数据源与网格独立：网格只取 day，列表按天分桶后按 `startDate` 排序
- 桶标题加入"昨天"前缀（网格不需要，因为不区分过去 / 未来；列表混合展示需要区分）

## 踩坑

- SwiftUI `.alert(isPresented:)` 需要 `Binding<Bool>`，把 `pendingDelete: ScheduleEvent?` 派生：`Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })`
- `.sheet(item:)` 要求 item 是 `Identifiable`。`ScheduleEvent` 已是 `@Model` 且有 `id: UUID`，SwiftData 的 `@Model` 会自动符合 `Identifiable`，可以直接用
- **手写左滑最容易踩的坑**：不判定 `|Δx| > |Δy|` 就会让内容行"吃掉"纵向手势，页面滚不动。修法是同时 `@GestureState` 一个 `isHorizontalDrag`，在 `.onEnded` 里也再校验一次
- `@GestureState` 手势结束自动归零，比 `@State` 更安全，避免状态残留导致的抖动

## 引用

- 项目规范：[[AGENTS]] § 6 编码约定 · SwiftData `@Model`
- 相关模块：`AnniversaryView` / `NoteView` 后续如果也补编辑删除，可以参照这个 sheet 抽象方式
