# 笔记：搜索栏 UX 修复 + 编辑/删除交互

日期：2026-07-22
类型：feature + bugfix（UX 问题一揽子修复）
涉及文件：
- `personal-butler/Presentation/Views/SubPages/NoteView.swift`
- `docs/module-spec/module-note-spec.md`

## 背景

用户在笔记页反馈 5 个 UX 问题，本次一次性收敛：

1. 搜索栏点放大镜图标 / 胶囊边缘不聚焦
2. 搜索栏聚焦时随键盘弹起被"挤压"（高度抖动）
3. 点列表空白处不会收键盘
4. 列表不支持编辑
5. 列表不支持删除

编辑/删除交互要求"参考日程管理子页面"（即 `ScheduleView` 已上线的 `SwipeToDeleteRow` 模式）。

## 决策

### 1. 搜索胶囊：整块可点击 + 固定高度 + 清空按钮

- **整块可点击**：`HStack` 加 `.contentShape(RoundedRectangle(cornerRadius: 8))` + `.onTapGesture { isSearchFocused = true }`，把 `TextField` 的命中区扩到整个胶囊
- **固定高度防挤压**：改用 `.frame(height: 36)` + `.fixedSize(horizontal: false, vertical: true)`，不再靠 `padding(.vertical, 8)` 弹性撑起；键盘弹起触发 SwiftUI 键盘避让时，胶囊不会被上下压缩
- **`.textFieldStyle(.plain)` + `.submitLabel(.search)`**：屏蔽默认样式的隐性内边距，回车键显示"搜索"
- **清空按钮**：`if !search.isEmpty { Button { search=""; isSearchFocused = true } }`；`xmark.circle.fill` 灰色图标，`.transition(.opacity)` + `.animation(.easeInOut(0.15), value: search.isEmpty)` 淡入淡出；清空后保持焦点方便继续输入

### 2. 点空白收键盘

- `ScrollView.scrollDismissesKeyboard(.immediately)`：一滚就收（iOS 16+ 系统能力）
- `ScrollView.simultaneousGesture(TapGesture)`：点空白同时收滑动行 + `isSearchFocused = false`
- `LazyVStack` 末尾追加一块 `Color.clear.frame(minHeight: 200).contentShape(Rectangle())` 占位：笔记条目少时下方也有可点区域

### 3. 编辑 / 删除：全套复用 `SwipeToDeleteRow`（对齐 ScheduleView）

- **合并 sheet**：`CreateNoteSheet` → `EditNoteSheet(note: Note?)`，`note == nil` 新增、非空编辑
- **保存策略**：编辑分支逐字段回写并**刷新 `updatedAt = Date()`**（保持列表按 `updatedAt` 倒序时被改动的条目上浮）
- **左滑露删除**：`SwipeToDeleteRow` 直接复用，`openSwipeId: UUID?` 保证同一时刻仅一行展开
- **二次确认**：`.alert("删除该笔记？")`，删除消息优先取 `title`，为空时取 `content.prefix(12)`（灵感类笔记很多不填标题）
- **自动收起滑动行**：`onChange(of: filterIndex)` / `onChange(of: search)` / 点空白 都会把 `openSwipeId` 置 nil

## 踩坑

- **SwiftUI TextField 聚焦时"挤压"感的真实原因**：`TextField` 聚焦会渲染 caret + 清除按钮，容器若是弹性高度（`padding(.vertical, N)`），加上键盘避让触发的 layout pass，视觉上就是抖一下。**修法**必须锁死容器高度：`.frame(height: N) + .fixedSize(vertical: true)`，双管齐下，缺一个都可能因为 fittingSize 不稳定复发
- **`SwipeToDeleteRow` 的 `content` 闭包是 `@ViewBuilder`**：内部用 `let` 声明 `DateFormatter` 再 `return VStack` 会让 result builder 推断失败（这次一开始踩了，改成 `private static let rowDateFormatter` + `NoteView.dateLabel(_:)` 静态方法绕开）
- **`.scrollDismissesKeyboard` 只作用于 `ScrollView`**：如果搜索栏在 `ScrollView` **外部**（本文件的布局就是如此，搜索栏在 `VStack` 顶部、列表在 `ScrollView` 里），键盘由 `TextField` 的聚焦驱动而不是被列表滚动带出，因此这个 modifier 只能覆盖"滚列表收键盘"这半段；点空白收键盘必须靠 `simultaneousGesture(TapGesture)` 补齐
- **清空按钮的焦点保持**：如果 `Button` 里只写 `search = ""`，SwiftUI 会因为按钮点击途中把焦点转出去，键盘瞬间收起、又因 `TextField` 无焦点重新弹回，视觉抖动。显式 `isSearchFocused = true` 兜住焦点是必要的
- **动画作用域**：`.animation(_:value:)` 挂在 `HStack` 上，只对内部子元素（清空按钮的 transition）生效；不能挂在最外层胶囊上，否则整个胶囊都会跟着淡入淡出

## 关联

- `SwipeToDeleteRow` 模式复用来源：`knowledge/2026-07-21-schedule-edit-delete.md`
- 组件本体：`personal-butler/Presentation/Components/SwipeToDeleteRow.swift`
- 同类模式已复用页面：ScheduleView / AnniversaryView / PasswordView

## 后续 TODO

- 目前搜索框的清空按钮/固定高度/整块可点击/点空白收键盘属于"搜索胶囊"的通用能力，其它子页面（`AnniversaryView` 顶部 / `PasswordView` 顶部）若也有同款交互需求，可抽 `SearchPill` 通用组件放到 `Presentation/Components/`
- 长文本笔记编辑时如需承载 Markdown / 富文本，`EditNoteSheet` 现在的 `TextField(axis: .vertical)` 需要替换成 `TextEditor` 或第三方富文本方案（PRD 二期）
