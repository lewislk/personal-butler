# PersonalButler · 笔记 · 模块级 SPEC

> 模块职责：管理灵感 / 摘录 / 待整理三类文本笔记；支持关键字搜索、标签筛选、左滑删除、点击编辑。

## 1. 范围与边界

本模块负责：

- 笔记 CRUD（新增 / 编辑 / 删除，均已上线）
- 顶部搜索框：按标题/内容模糊搜索；支持整块可点击聚焦、清空按钮、点空白/滚动收键盘
- 标签筛选：`全部 / 灵感 / 摘录 / 待整理`（`HorizontalTagBar`）
- 列表按 `updatedAt` 倒序排列
- 左滑露红色删除按钮 + `.alert` 二次确认

不覆盖：

- 富文本 / Markdown 编辑（当前为纯 String）
- 与其他业务模块交互（笔记不参与主页待办聚合）
- 图片附件

## 2. 核心概念

### Note

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `title` | String | 可选标题；空时列表不展示标题行 |
| `content` | String | 正文（多行） |
| `tag` | String | 标签，MVP 固定枚举字符串："灵感 / 摘录 / 待整理" |
| `createdAt` | Date | 创建时间 |
| `updatedAt` | Date | 更新时间（列表排序依据） |

### 标签筛选

`tags = ["全部", "灵感", "摘录", "待整理"]`；`filterIndex == 0` 表示"全部"；其他按 `note.tag == tags[filterIndex]` 精确匹配。

### 搜索

`localizedStandardContains` 大小写/语言不敏感匹配，作用于 `title` 与 `content` 任意命中即入选。

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 页面入口 | `Presentation/Views/SubPages/NoteView.swift` · `NoteView` | `AppRouter.open("note")` 触发 |
| 数据订阅 | `@Query(sort: \Note.updatedAt, order: .reverse)` | 倒序展示 |
| 新增 / 编辑 | `NoteView.swift` · `EditNoteSheet(note: Note?)` | FAB / 点击行触发 |
| 删除 | `NoteView.swift` · `.alert("删除该笔记？")` | 左滑红按钮触发 |
| 左滑组件 | `Presentation/Components/SwipeToDeleteRow.swift` | 与 Schedule / Anniversary / Password 共用 |
| 模型 | `Domain/Models/Note.swift` | `@Model` |
| 筛选栏 | `Components/HorizontalTagBar.swift` | 复用组件 |

## 4. 核心场景

### 列表 + 筛选 + 搜索

**代码入口：** `NoteView.swift` · `filtered`

**业务规则：**

- 无搜索关键字、`filterIndex == 0` → 展示全部
- 有关键字 → 应用 `localizedStandardContains`
- 有 tag 筛选 → 按 tag 精确匹配
- 搜索与筛选可同时叠加

**实现逻辑：**

1. `var arr = list`
2. 若 `filterIndex > 0` → `arr.filter { $0.tag == tags[filterIndex] }`
3. 若 `!search.isEmpty` → `arr.filter { $0.content.localizedStandardContains(search) || $0.title.localizedStandardContains(search) }`
4. 返回 `arr`

### 顶部搜索胶囊

**代码入口：** `NoteView.swift` · `body` 顶部 `HStack`

**业务规则：**

- 整块可点击（放大镜图标、TextField、右侧留白）都能聚焦 TextField
- 有内容时右侧显示 `xmark.circle.fill` 清空按钮，点击清空并保持焦点
- 键盘弹起时胶囊高度固定（不随内容/键盘避让抖动）
- 列表滚动 / 点空白列表 → 自动收键盘

**实现逻辑：**

1. `HStack(spacing: 8)` 内置放大镜图标 + `TextField(...).focused($isSearchFocused)` + 条件清空按钮
2. `.frame(height: 36)` + `.fixedSize(horizontal: false, vertical: true)` 锁死高度
3. `.contentShape(RoundedRectangle(cornerRadius: 8))` + `.onTapGesture { isSearchFocused = true }` 扩大点击命中区
4. `ScrollView.scrollDismissesKeyboard(.immediately)` 承担"滚动收键盘"
5. `ScrollView.simultaneousGesture(TapGesture)` 承担"点空白收键盘 + 收滑动行"
6. LazyVStack 尾部 `Color.clear.frame(minHeight: 200).contentShape(Rectangle())` 兜底空态可点区域

### 列表 Row

**代码入口：** `NoteView.swift` · `row(_:)`

**实现逻辑：**

1. 外层包 `SwipeToDeleteRow(isOpen:onTap:onDelete:)`：点行 → 编辑；左滑 → 删除
2. 上部：`yyyy-MM-dd` 更新日期（`NoteView.dateLabel(_:)` 静态方法，`DateFormatter` 静态实例复用避免每帧新建）+ tag pill（蓝色 `#EEF3FD` 底）
3. 中部：非空 `title` 加粗 15pt
4. 下部：`content` 13pt，`lineLimit(3)`
5. 底部分隔线（缩进 16pt）

### 新增 / 编辑笔记

**代码入口：** `NoteView.swift` · `EditNoteSheet`

**业务规则：**

- `note == nil` 新增；非空编辑
- title 可选、tag 三选一、content 必填
- 新增：`createdAt == updatedAt == 当前时间`
- 编辑：仅刷新 `updatedAt`，`createdAt` 保持不变；被编辑的条目自动上浮到列表最上（列表按 `updatedAt` 倒序）

**实现逻辑：**

1. FAB → `.sheet(isPresented: $showCreate) { EditNoteSheet(note: nil) }`
2. 行点击 → `.sheet(item: $editingNote) { EditNoteSheet(note: $0) }`
3. Form: title / tag Picker / content（`.lineLimit(6...20)`）
4. 保存：编辑逐字段回写 + `updatedAt = Date()`；新增 `context.insert(Note(...))`
5. `try? context.save()`

### 删除笔记

**代码入口：** `NoteView.swift` · `.alert("删除该笔记？", ...)`

**业务规则：**

- 左滑行 → 露出红色 `trash.fill` 按钮 → 点击 → `.alert` 二次确认
- 同一时刻仅一行处于展开态（`openSwipeId: UUID?`）
- 切换筛选 / 修改搜索词 / 点空白 → 自动收起展开的滑动行

**实现逻辑：**

1. `SwipeToDeleteRow.onDelete` → `pendingDelete = n`
2. `.alert` 派生 `Binding<Bool>` 于 `pendingDelete != nil`
3. 确认删除：`context.delete(n)` → `try? context.save()` → `pendingDelete = nil; openSwipeId = nil`
4. 删除文案：`title` 非空取 title，否则截 `content.prefix(12)`

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/NoteView.swift`
  - `personal-butler/Domain/Models/Note.swift`
  - `personal-butler/Presentation/Components/HorizontalTagBar.swift`
  - `personal-butler/Presentation/Components/SwipeToDeleteRow.swift`
- 文档：
  - `docs/PRD.md`（笔记章节）
  - `knowledge/2026-07-21-schedule-edit-delete.md`（左滑删除模式起源）
  - `knowledge/2026-07-22-note-search-swipe.md`（本次搜索栏 UX + 笔记编辑/删除迭代）
