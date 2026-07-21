# PersonalButler · 美食记录 · 模块级 SPEC

> 模块职责：记录探店 / 打卡的美食，包含店名、emoji、评分（1-5 星）、分类（火锅/奶茶/中餐/日料/咖啡）、标签与备注。

## 1. 范围与边界

本模块负责：

- 美食 CRUD（MVP：新增；编辑/删除后续）
- 顶部横向筛选标签栏（全部 + 5 个分类）
- 列表按 `date` 倒序
- 分类差异化的封面渐变色（日料蓝 / 奶茶黄 / 其他橙）

不覆盖：

- 实际拍照 / 相册配图（当前 UI 仅展示 emoji，PRD 里的相册能力属 P1）
- 地点 / 地图 / 定位
- 主页待办联动（美食不参与）

## 2. 核心概念

### FoodRecord

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `name` | String | 店名 / 菜品 |
| `emoji` | String | 展示 emoji |
| `rating` | Int (1-5) | 星级 |
| `tags` | [String]（内部 `tagsRaw: String` 逗号分隔存储） | 展示 pill |
| `remark` | String | 备注 |
| `date` | Date | 记录时间 |
| `category` | Enum(.all/.hotpot/.milktea/.chinese/.japanese/.coffee) | 分类 |

`.all` 只作为筛选枚举使用，不作为 seed 数据分类。

### 分类筛选

`categories = [全部, 火锅, 奶茶, 中餐, 日料, 咖啡]`；`filterIndex == 0` (`.all`) 不过滤。

### 封面渐变色

| 分类 | 渐变 |
|------|------|
| `.japanese` | 蓝：`#BEE1FF → #6AA9E9` |
| `.milktea` | 黄：`#FFE29A → #F0B650` |
| 其他 | 橙：`#FFD7B5 → #FF8A65` |

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 页面入口 | `Presentation/Views/SubPages/FoodRecordView.swift` · `FoodRecordView` | `AppRouter.open("food")` 触发 |
| 数据订阅 | `@Query(sort: \FoodRecord.date, order: .reverse)` | 倒序 |
| 新增 | `FoodRecordView.swift` · `CreateFoodSheet` | FAB 触发 |
| 模型 | `Domain/Models/FoodRecord.swift` | `@Model` + `FoodCategory` |
| 筛选栏 | `Components/HorizontalTagBar.swift` | 复用 |

## 4. 核心场景

### 列表 + 分类筛选

**代码入口：** `FoodRecordView.swift` · `filtered`

**业务规则：**

- `.all` 分类跳过过滤，展示全部
- 其他按 `record.category == cat` 过滤

**实现逻辑：**

1. `HorizontalTagBar` 绑定 `$filterIndex`
2. `filtered = cat == .all ? list : list.filter { $0.category == cat }`

### 单条 Row 布局

**代码入口：** `FoodRecordView.swift` · `row(_:)`

**布局：**

1. 左侧 90×90 圆角封面：`Text(emoji).font(32)` + `LinearGradient(colors: gradient(for: category))`
2. 中间：
   - 店名 15pt semibold
   - 5 颗星（`star.fill` / `star`，`< rating` 亮）
   - tags pill（若不为空）
   - 备注 12pt，`lineLimit(2)`
3. Divider 分隔

### 新增美食

**代码入口：** `FoodRecordView.swift` · `CreateFoodSheet`

**业务规则：**

- name 空 → "未命名"
- Stepper 控制评分（1-5）
- tags 输入以逗号分隔字符串，保存时 `split(",") + trim`
- 保存时 `date = 当前`

**实现逻辑：**

1. Form：name / emoji / rating(Stepper 1-5) / category(Picker) / tags / remark
2. 保存：
   ```swift
   let f = FoodRecord(name: ..., emoji: ..., rating: ...,
                      tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                      remark: ..., category: ...)
   context.insert(f); try? context.save(); dismiss()
   ```

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/FoodRecordView.swift`
  - `personal-butler/Domain/Models/FoodRecord.swift`
  - `personal-butler/Presentation/Components/HorizontalTagBar.swift`
- 文档：
  - `docs/PRD.md § 10 美食记录`
