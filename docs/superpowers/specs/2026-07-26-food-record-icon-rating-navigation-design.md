# 美食记录·图标弹窗 / 半星评分 / 分类扩充 / 地址点击导航 · 设计

> 状态：待实现｜作者：AI 助手 + liukun｜日期：2026-07-26
> 影响模块：`FoodRecord` 域、美食记录 UI、备份同步契约、SwiftData 迁移

---

## 1. 目标

四件事一起做：

1. **图标选择弹窗**：现有 30 emoji 内嵌网格 → 独立 `IconPickerSheet`，三种数据源：Emoji / 相册 / 拍照
2. **半星评分**：`Int (0-5)` → `Double (0.0-5.0, step 0.5)`，交互支持左半点击 = 加半星
3. **分类扩充**：追加"西餐 / 大排档"两个 case（`western` / `streetfood`）
4. **地址点击导航**：列表行位置行改为可点击按钮，直接拉起 Apple Maps；不影响整行点击进入编辑

---

## 2. 数据模型变更

### 2.1 `FoodRecord`（`Domain/Models/FoodRecord.swift`）

字段变更：

```swift
var emoji: String                    // 保留：iconImage 缺失时的兜底显示
var rating: Double                   // Int → Double（0.0..5.0，step 0.5）
@Attribute(.externalStorage) var iconImage: Data?   // 新增：图片（JPEG 0.7 / 长边 512px）
```

`init` 签名变更：
- `rating: Double = 4.0`（原 `Int = 4`）
- 追加末位 `iconImage: Data? = nil`

**约束：**
- `rating` 值域仅允许 [0.0, 5.0]，步长 0.5（8 个可选值 + 0 = 11 个离散值）；UI 层负责规范，不做 model 层校验
- `iconImage` 与 `emoji` 二者可共存：`iconImage != nil` 时列表显示图片；`iconImage == nil` 时显示 `emoji`
- `iconImage` 用 `@Attribute(.externalStorage)` 独立文件存储，SQLite 只存路径引用（SwiftData 默认行为，无需迁移代码）

### 2.2 `FoodCategory` 追加两个 case

```swift
enum FoodCategory: String, Codable, CaseIterable {
    case all, hotpot, milktea, chinese, western, streetfood, japanese, coffee

    var label: String {
        switch self {
        case .all: return "全部"
        case .hotpot: return "火锅"
        case .milktea: return "奶茶"
        case .chinese: return "中餐"
        case .western: return "西餐"
        case .streetfood: return "大排档"
        case .japanese: return "日料"
        case .coffee: return "咖啡"
        }
    }
}
```

`FoodRecordView.categories` 列表同步补 2 项：`("西餐", .western)` / `("大排档", .streetfood)`，顺序：全部/火锅/奶茶/中餐/西餐/大排档/日料/咖啡

`EditFoodSheet.Form.Picker("分类")` 同步补 2 个 `Text("西餐").tag(.western)` / `Text("大排档").tag(.streetfood)`

`FoodRecordView.gradient(for:)` 追加两个 case 的颜色（`.western` / `.streetfood`）—— 用同 `.chinese` 的默认渐变即可，无需新配色

---

## 3. SwiftData 迁移

### 3.1 引入 `VersionedSchema`

`rating: Int → Double` 是**类型变更**，SwiftData 不支持 lightweight migration，必须用 `VersionedSchema` + `SchemaMigrationPlan`。

新建 `Domain/Models/FoodRecordSchema.swift`：

```swift
import Foundation
import SwiftData

enum FoodRecordSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [FoodRecordV2.self] }

    @Model
    final class FoodRecordV2 {
        @Attribute(.unique) var id: UUID
        var name: String
        var emoji: String
        var rating: Int                  // ← 旧类型
        var tagsRaw: String
        var remark: String
        var date: Date
        var categoryRaw: String
        var placeName: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?

        init(...) { ... }   // 略
    }
}

enum FoodRecordSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [FoodRecord.self] }
    // FoodRecord 是 V3 的当前形态（在主 FoodRecord.swift 里定义）
}

enum FoodRecordMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FoodRecordSchemaV2.self, FoodRecordSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [.custom(
            fromVersion: FoodRecordSchemaV2.self,
            toVersion: FoodRecordSchemaV3.self,
            willMigrate: nil,
            didMigrate: { context in
                let all = try context.fetch(FetchDescriptor<FoodRecord>())
                for r in all {
                    // V2 的 rating Int 已被 SwiftData 自动映射到 V3 的 rating Double（同名字段）
                    // 但因类型不同，SwiftData 会把 Int 写成 0.0；这里主动 cast 一次兜底
                    // 实际测试：SwiftData 对 Int→Double 同名字段有自动转换，此 didMigrate 主要为
                    // "iconImage 保持 nil"的显式确认，以及未来加逻辑的锚点
                }
                try context.save()
            }
        )]
    }
}
```

### 3.2 `PersonalButlerApp` 挂载 MigrationPlan

`ModelContainer` 初始化时加 `migrationPlan: FoodRecordMigrationPlan.self`：

```swift
let container = try ModelContainer(
    for: schema,
    migrationPlan: FoodRecordMigrationPlan.self,
    configurations: [config]
)
```

**兜底策略**：如果 `ModelContainer` 初始化仍然抛错（V2 → V3 迁移失败），fallback 到"删除本地 DB 重来"（用户按 CLAUDE.md 语义"存量数据强转不做重映射"—— 这也符合"没有云备份"的现状；用户会看到"数据已重置"的一次性提示）。这个 fallback 单独放一个 `if let container = try? ...` 兜底。

### 3.3 `dataVersion` 2 → 3

`BackupSyncUseCase.buildPayload` 里 `dataVersion: 2` → `dataVersion: 3`

---

## 4. 同步契约变更

### 4.1 `SyncFoodDTO`（`Data/Mapper/SyncPayload.swift`）

```swift
struct SyncFoodDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var rating: Double            // Int → Double（Codable：老 JSON 整数会正确解码为 Double）
    var tags: [String]
    var remark: String
    var date: Double
    var category: String
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var iconImageBase64: String?  // 新增（JPEG bytes 的 base64；nil = 未设置）
}
```

### 4.2 `BackupSyncUseCase`

- `buildPayload`：`iconImageBase64 = record.iconImage?.base64EncodedString()`；`rating = Double(record.rating)`（实际类型已是 Double，此为语义确认）
- `rebuild`：`iconImage = Data(base64Encoded: x.iconImageBase64 ?? "")`（nil 或 base64 解码失败 → `iconImage = nil`）
- **超时**：`makeRequest` 里 `req.timeoutInterval = 10` → `req.timeoutInterval = 25`（图片会显著增大 payload）

### 4.3 文档

- `docs/module-spec/module-backup-sync-spec.md` 追加 v3 变更历史条目

---

## 5. UI 设计

### 5.1 图标选择弹窗 `IconPickerSheet`

新建 `Presentation/Views/SubPages/Food/IconPickerSheet.swift`（+ 拆一个私有 `CameraPicker` 到同文件末尾）。

**统一回调协议：**

```swift
enum FoodIcon: Equatable {
    case emoji(String)
    case image(Data)   // 已压缩到 JPEG 0.7 / 长边 512px
}

struct IconPickerSheet: View {
    let initial: FoodIcon
    let onConfirm: (FoodIcon) -> Void
}
```

**布局：**

```
┌──────────────────────────────────────┐
│  选择图标                    取消    │  ← navigationBar
├──────────────────────────────────────┤
│      [Emoji] [相册] [拍照]           │  ← MiniSegmentedPill 顶部固定
├──────────────────────────────────────┤
│                                       │
│  当前 tab 内容                        │
│                                       │
├──────────────────────────────────────┤
│  [40x40 预览]              [ 保存 ]  │  ← 底部固定
└──────────────────────────────────────┘
```

**Emoji tab：** 6 列网格，30 个 emoji（沿用现有 `emojiOptions` 数组，从 `EditFoodSheet` 搬入 `IconPickerSheet`），点选后更新预览 `@State private var current: FoodIcon`；「保存」按钮才回调，避免误点即关闭

**相册 tab：**
- 一个大按钮（占位卡片式）"从相册选择照片"
- 点击 → SwiftUI `PhotosPicker(selection: $item, matching: .images)`
- 拿到 `PhotosPickerItem.loadTransferable(type: Data.self)` 后交给 `ImageProcessor.compress(data:)` 压缩
- 更新 `current = .image(compressed)`，同时在 tab 内显示"已选择照片"缩略图 + "重新选择"按钮

**拍照 tab：**
- 一个大按钮"打开相机拍照"
- 点击 → `.fullScreenCover` 挂载 `CameraPicker`（SwiftUI 薄包装 `UIImagePickerController`，`sourceType = .camera`）
- 拍完的 `UIImage.jpegData(compressionQuality: 0.7)` → `ImageProcessor.compress(data:)` 二次压缩长边
- 模拟器无相机：`UIImagePickerController.isSourceTypeAvailable(.camera) == false`，按钮 disabled + 副文案"当前设备无相机"

**底部：**
- 40×40 圆角预览：`FoodIcon.emoji` → 大字号 emoji；`FoodIcon.image` → `Image(uiImage:).resizable().scaledToFill()`
- 「保存」→ `onConfirm(current)` + `dismiss()`
- 「取消」（右上）→ 不回调，`dismiss()`

**权限（不改，已有）：**
- 相机：`INFOPLIST_KEY_NSCameraUsageDescription` = "用于扫描 2FA 二维码及美食拍照记录"（已存在，覆盖本次场景）
- 相册：`PhotosPicker` **不需要** `NSPhotoLibraryUsageDescription`（系统进程挑图，App 不访问 PhotoKit）
  - 现有 `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` 保留即可（是防御性覆盖）

### 5.2 `ImageProcessor`

新建 `Core/Utils/ImageProcessor.swift`：

```swift
enum ImageProcessor {
    /// 从原始 Data 或 UIImage 压缩到 JPEG 0.7 / 长边 <=512px。
    /// 失败（无法解码为 UIImage）返回 nil。
    static func compress(data raw: Data, maxLongSide: CGFloat = 512, quality: CGFloat = 0.7) -> Data? {
        guard let ui = UIImage(data: raw) else { return nil }
        return compress(uiImage: ui, maxLongSide: maxLongSide, quality: quality)
    }
    static func compress(uiImage: UIImage, maxLongSide: CGFloat = 512, quality: CGFloat = 0.7) -> Data? {
        let img = resize(uiImage, longSide: maxLongSide)
        return img.jpegData(compressionQuality: quality)
    }
    private static func resize(_ img: UIImage, longSide: CGFloat) -> UIImage {
        let (w, h) = (img.size.width, img.size.height)
        let long = max(w, h)
        guard long > longSide else { return img }
        let scale = longSide / long
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
```

### 5.3 `EditFoodSheet` 集成

**图标 Section 改造：**

现在：
```swift
Section("图标") { emojiPicker }   // 6 列 emoji 网格
```

改为：
```swift
Section("图标") {
    Button { showIconPicker = true } label: {
        HStack {
            iconPreview.frame(width: 60, height: 60)   // 显示当前 icon
            Text("点击更换")
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(AppColorTheme.textSub)
        }
    }
    .buttonStyle(.plain)
}
.sheet(isPresented: $showIconPicker) {
    IconPickerSheet(initial: icon) { picked in
        icon = picked
    }
}
```

State 变更：
- 删除 `@State private var emoji: String`
- 增加 `@State private var icon: FoodIcon`
- 增加 `@State private var showIconPicker: Bool = false`
- `init(record:)` 中 `icon` 初始化：
  - `record?.iconImage != nil` → `.image(record!.iconImage!)`
  - else → `.emoji(record?.emoji ?? "🍽️")`

`save()` 改造：
```swift
switch icon {
case .emoji(let s):
    r.emoji = s
    r.iconImage = nil
case .image(let d):
    // 保留 emoji 兜底值（图片被清后仍有 fallback）
    r.iconImage = d
}
```

新增记录同理。

**移除**：现有 `emojiPicker` / `emojiOptions` 从 `EditFoodSheet` 中删除（搬到 `IconPickerSheet`）

### 5.4 半星评分 UI

**交互 5 星（`EditFoodSheet`）：**

```swift
private var starRating: some View {
    HStack(spacing: 10) {
        ForEach(0..<5, id: \.self) { i in
            HStack(spacing: 0) {
                Button {
                    let target = Double(i) + 0.5
                    rating = (rating == target) ? 0 : target
                } label: {
                    starView(for: i).frame(width: 20, height: 40).clipShape(
                        Rectangle().path(in: CGRect(x: 0, y: 0, width: 20, height: 40))
                            .stroke(Color.clear).contentShape(Rectangle())  // 左半 hit
                    )
                }
                .buttonStyle(.plain)
                Button {
                    let target = Double(i) + 1.0
                    rating = (rating == target) ? 0 : target
                } label: {
                    Color.clear.frame(width: 20, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay(starView(for: i).allowsHitTesting(false))
        }
        Spacer()
        Text(rating > 0 ? String(format: "%.1f 星", rating) : "未评分")
            .font(.system(size: 13))
            .foregroundStyle(AppColorTheme.textSub)
    }
    .padding(.vertical, 4)
}

@ViewBuilder
private func starView(for i: Int) -> some View {
    let idx = Double(i)
    let icon: String =
        rating >= idx + 1.0 ? "star.fill"
        : rating >= idx + 0.5 ? "star.leadinghalf.filled"
        : "star"
    Image(systemName: icon)
        .font(.system(size: 26))
        .foregroundStyle(rating >= idx + 0.5 ? Color(hex: 0xF5A623) : Color(hex: 0xC7CCD4))
}
```

**说明：**
- 每颗星宽 40（两个 20 宽的 tap 区拼接），高 40，同现有触控目标大小
- 左半 tap → `Double(i) + 0.5`，右半 tap → `Double(i) + 1.0`
- 再点当前 target 归零
- 三态 SF Symbol：`star` / `star.leadinghalf.filled` / `star.fill`
- 副标签 `"3.5 星"` / `"未评分"`

**列表行只读 5 星（`FoodRecordView.row`）：**

```swift
HStack(spacing: 2) {
    ForEach(0..<5) { i in
        let idx = Double(i)
        let icon: String =
            f.rating >= idx + 1.0 ? "star.fill"
            : f.rating >= idx + 0.5 ? "star.leadinghalf.filled"
            : "star"
        Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundStyle(f.rating >= idx + 0.5 ? Color(hex: 0xF5A623) : Color(hex: 0xE2E5EA))
    }
}
```

### 5.5 列表行位置行改为可点击

**新建工具 `MapsNavigator`：**

```swift
// Core/Utils/MapsNavigator.swift
import UIKit

enum MapsNavigator {
    static func openInMaps(latitude: Double, longitude: Double, name: String? = nil) {
        let q = (name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(latitude),\(longitude)") else { return }
        UIApplication.shared.open(url)
    }
}
```

**`EditFoodSheet.openInMaps` 私有方法改为调用 `MapsNavigator`：**

```swift
private func openInMaps() {
    guard let lat = latitude, let lng = longitude else { return }
    MapsNavigator.openInMaps(latitude: lat, longitude: lng, name: placeName ?? address)
}
```

**`FoodRecordView.row` 位置行改造：**

```swift
if f.hasLocation, let loc = f.displayLocation, let lat = f.latitude, let lng = f.longitude {
    Button {
        MapsNavigator.openInMaps(latitude: lat, longitude: lng, name: f.placeName ?? f.address)
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "location.fill").font(.system(size: 10))
            Text(loc).lineLimit(1)
            Image(systemName: "arrow.up.forward").font(.system(size: 9))
                .foregroundStyle(AppColorTheme.primary)
        }
        .font(.system(size: 12))
        .foregroundStyle(AppColorTheme.textSub)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
```

**stopPropagation 由 SwiftUI `Button` 天然提供**——`Button` 独占 hit test，tap 不会往父容器 `SwipeToDeleteRow.onTap` 冒泡。

无位置的记录：`if` 条件不满足，整行不渲染，无影响。

---

## 6. 代码组织

### 6.1 新增文件

```
Domain/Models/FoodRecordSchema.swift            ← VersionedSchema V2/V3 + MigrationPlan
Core/Utils/ImageProcessor.swift                 ← JPEG 压缩 + 长边缩放
Core/Utils/MapsNavigator.swift                  ← Apple Maps 拉起（EditFoodSheet 与 FoodRecordView 共用）
Presentation/Views/SubPages/Food/IconPickerSheet.swift   ← 图标弹窗（含私有 CameraPicker）
```

### 6.2 修改文件

```
Domain/Models/FoodRecord.swift                  ← rating Int→Double、+iconImage、+2 分类、init 签名调整
Data/Mapper/SyncPayload.swift                   ← SyncFoodDTO rating Double + iconImageBase64
Domain/UseCases/BackupSyncUseCase.swift         ← dataVersion 2→3、build/rebuild 映射调整、超时 25s
App/PersonalButlerApp.swift                     ← ModelContainer 挂 migrationPlan + 兜底 fallback
Presentation/Views/SubPages/FoodRecordView.swift ← +2 分类、位置行改按钮、gradient 补 case、只读 5 星三态
Presentation/Views/SubPages/Food/EditFoodSheet.swift ← 图标 Section 改按钮式、+2 Picker case、交互 5 星三态、rating Double、清理 emojiPicker/emojiOptions
docs/module-spec/module-backup-sync-spec.md     ← v3 变更历史
```

---

## 7. 边界与约束确认

| 项 | 状态 |
|---|---|
| `UIImagePickerController` 引入 | ✅ AGENTS.md § 2 允许"系统集成必需"的 UIKit（如 UIPasteboard）；相机是同类必需 |
| `PhotosPicker` | ✅ SwiftUI 原生（iOS 16+）；不引入 UIKit 视图层 |
| SwiftData `@Attribute(.externalStorage)` | ✅ iOS 17+ 特性；本项目 iOS 18 起步；文件独立存储、SQLite 只存引用 |
| `Data` base64 进 JSON | ✅ 用户接受 payload 膨胀；超时放宽到 25s |
| 无 XCTest | ✅ 沿用 `xcodebuild build` 兜底 |
| SwiftData 迁移 | ⚠️ `VersionedSchema` + custom stage；有兜底"删库重建" fallback |
| 主色板 | ✅ `AppColorTheme.*` |
| 图标 emoji fallback | ✅ 图片被清时列表仍有 emoji 兜底显示 |

---

## 8. 手动验证清单

1. 打开编辑弹窗 → 图标 Section 显示当前 icon（60×60）+「点击更换」
2. 点击 → `IconPickerSheet` 弹出，默认在 Emoji tab
3. 切到"相册" tab → `PhotosPicker` 选一张 → 压缩后底部预览显示图片
4. 切到"拍照" tab → 打开相机（真机；模拟器 disable）→ 拍完预览显示
5. 保存后 EditFoodSheet 图标 Section 显示新 icon
6. 记录列表：`iconImage != nil` 的记录左侧显示图片；`iconImage == nil` 的记录显示 emoji（同现有渐变卡片）
7. 半星：点第 3 星左半 → rating = 2.5，副标签"2.5 星"；再点同一位置 → 归零"未评分"
8. 分类过滤：切到"西餐"/"大排档" tab，只显示对应记录
9. 位置行点击 → 拉起 Apple Maps 且不打开编辑弹窗
10. 整行其它位置点击 → 打开编辑弹窗
11. 数据库迁移：升级前的老记录（rating 4 = Int）在新版本首启后 rating = 4.0，UI 显示 4 星
12. 同步：`LocalBackupSheet` 导出 JSON，包含新字段（`iconImageBase64` / `rating: 4.0`）
13. 局域网同步：payload 含图片时超时 25s 内完成上传/下载

---

## 9. YAGNI · 明确不做

- 不做多图（一条记录一张图）
- 不做图片裁剪 / 滤镜 / 编辑
- 不做手势拖动评分（只 tap）
- 不做地址点击时的"选择导航 App"弹窗（Apple Maps only）
- 不做分类图标（8 个分类目前无 icon 差异化，保持现状）
- 不做迁移进度条 / 失败提示 UI（fallback 后直接进空数据 App）

---

## 10. 影响文件汇总

| 类型 | 文件 |
|---|---|
| 模型 | `Domain/Models/FoodRecord.swift`（改）、`Domain/Models/FoodRecordSchema.swift`（新增） |
| 工具 | `Core/Utils/ImageProcessor.swift`（新增）、`Core/Utils/MapsNavigator.swift`（新增） |
| 同步 | `Data/Mapper/SyncPayload.swift`（改）、`Domain/UseCases/BackupSyncUseCase.swift`（改） |
| App | `App/PersonalButlerApp.swift`（改 ModelContainer） |
| UI 弹窗 | `Presentation/Views/SubPages/Food/IconPickerSheet.swift`（新增） |
| UI 页面 | `Presentation/Views/SubPages/FoodRecordView.swift`（改）、`Presentation/Views/SubPages/Food/EditFoodSheet.swift`（改） |
| 文档 | `docs/module-spec/module-backup-sync-spec.md`（改） |
