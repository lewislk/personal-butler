# PersonalButler · 笔记 · 模块级 SPEC

> 模块职责：管理灵感 / 摘录 / 待整理三类文本笔记；支持关键字搜索与标签筛选。

## 1. 范围与边界

本模块负责：

- 笔记 CRUD（MVP：新增；编辑/删除留待后续）
- 顶部搜索框：按标题/内容模糊搜索
- 标签筛选：`全部 / 灵感 / 摘录 / 待整理`（`HorizontalTagBar`）
- 列表按 `updatedAt` 倒序排列

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
| 新增 | `NoteView.swift` · `CreateNoteSheet` | FAB 触发 sheet |
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

### 列表 Row

**代码入口：** `NoteView.swift` · `row(_:)`

**实现逻辑：**

1. 上部：`yyyy-MM-dd` 更新日期 + tag pill（蓝色 `#EEF3FD` 底）
2. 中部：非空 `title` 加粗 15pt
3. 下部：`content` 13pt，`lineLimit(3)`
4. 底部分隔线（缩进 16pt）

### 新增笔记

**代码入口：** `NoteView.swift` · `CreateNoteSheet`

**业务规则：**

- title 可选、tag 三选一、content 必填
- 保存后 `createdAt == updatedAt == 当前时间`

**实现逻辑：**

1. FAB → `.sheet(isPresented: $showCreate)`
2. Form: title / tag Picker / content（`.lineLimit(6...20)`）
3. `Note(title:content:tag:)` → `context.insert` → `save`

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/NoteView.swift`
  - `personal-butler/Domain/Models/Note.swift`
  - `personal-butler/Presentation/Components/HorizontalTagBar.swift`
- 文档：
  - `docs/PRD.md`（笔记章节）
