# 美食记录·图标弹窗 / 半星评分 / 分类扩充 / 地址点击导航 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 美食记录支持图标三选一（Emoji / 相册 / 拍照）、半星评分（Double 0..5 step 0.5）、新增"西餐 / 大排档"分类、列表位置行点击直接拉起 Apple Maps；同步契约 v2 → v3，SwiftData 走 VersionedSchema 迁移 + 兜底重建。

**Architecture:**
- 模型：`FoodRecord.rating: Int → Double`；追加 `@Attribute(.externalStorage) iconImage: Data?`；`FoodCategory` 追加 `western` / `streetfood`
- 迁移：`VersionedSchema` V2 → V3 + `SchemaMigrationPlan` custom stage；`ModelContainer` 初始化失败 fallback 到"清库重建"
- 同步：`SyncFoodDTO` rating Double + `iconImageBase64`；`SyncMeta.dataVersion` 2 → 3；`URLRequest.timeoutInterval` 10 → 25
- 工具：`ImageProcessor`（JPEG 0.7 长边 512）、`MapsNavigator`（Apple Maps URL 拉起）
- UI：`IconPickerSheet`（含私有 `CameraPicker`）；`EditFoodSheet` 图标 Section 改按钮 + 交互 5 星三态；`FoodRecordView` 列表分类补 2 项 + 位置行改 Button + 只读 5 星三态 + 图片/emoji 双源展示

**Tech Stack:** SwiftUI · SwiftData（`VersionedSchema` / `.externalStorage`）· PhotosUI（`PhotosPicker`）· UIKit（`UIImagePickerController` 相机 + `UIApplication.open`）· CoreImage / UIGraphicsImageRenderer

## Global Constraints

- iOS 18+；可用 iOS 18 新 API，不写 `if #available` 兜底
- 纯 SwiftUI 视图层；仅在**必要系统集成**处允许 UIKit：`UIImagePickerController`（相机）、`UIApplication.shared.open`（拉起 Maps）
- SwiftData 迁移策略：`VersionedSchema` V2 → V3 + custom stage；`ModelContainer(...)` 抛错时 fallback 清除本地 store 后重建（用户可接受，spec § 3.2 已确认）
- `SyncFoodDTO.rating: Double`（老 JSON 整数会正确解码为 Double；Codable 天然兼容）
- `iconImage` 走 `@Attribute(.externalStorage)`；同步 payload 用 base64 编码进 `iconImageBase64: String?`
- `URLRequest.timeoutInterval` 从 10 改为 25（图片显著增大 payload）
- 图片压缩规格：JPEG `compressionQuality: 0.7` + 长边 ≤ 512px
- 分类新增 rawValue：`western` / `streetfood`；顺序：全部 / 火锅 / 奶茶 / 中餐 / 西餐 / 大排档 / 日料 / 咖啡
- 半星评分：`Double` 0..5 step 0.5；三态 SF Symbol `star` / `star.leadinghalf.filled` / `star.fill`
- 位置行点击不冒泡到整行编辑（用 SwiftUI `Button` 天然 stopPropagation）
- 主色板走 `AppColorTheme.*`；中文注释、英文标识符；文件名 = 主类型名
- 相机权限用现有 `INFOPLIST_KEY_NSCameraUsageDescription`（不改）；`PhotosPicker` 无需 PhotoKit 权限
- 无 XCTest 基建；`xcodebuild build` 是唯一 CI；xcodebuild 前置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`

## File Structure

```
Domain/Models/FoodRecord.swift                    ← 修改：rating Double、+iconImage、+2 分类、init 签名扩展
Domain/Models/FoodRecordSchema.swift              ← 新建：VersionedSchema V2/V3 + MigrationPlan
Core/Utils/ImageProcessor.swift                   ← 新建：JPEG 压缩 + 长边缩放
Core/Utils/MapsNavigator.swift                    ← 新建：Apple Maps 拉起（EditFoodSheet 与 FoodRecordView 共用）
Data/Mapper/SyncPayload.swift                     ← 修改：SyncFoodDTO rating Double + iconImageBase64
Domain/UseCases/BackupSyncUseCase.swift           ← 修改：dataVersion 3、build/rebuild 映射调整、超时 25s
App/PersonalButlerApp.swift                       ← 修改：ModelContainer 挂 migrationPlan + fallback
Presentation/Views/SubPages/Food/IconPickerSheet.swift  ← 新建：图标弹窗（+ 私有 CameraPicker）
Presentation/Views/SubPages/Food/EditFoodSheet.swift    ← 修改：图标 Section 按钮化、+2 分类 Picker、交互 5 星三态、rating Double、清理 emojiPicker/emojiOptions
Presentation/Views/SubPages/FoodRecordView.swift  ← 修改：分类补 2 项、位置行改 Button、图片/emoji 双源展示、只读 5 星三态、gradient 补 case
docs/module-spec/module-backup-sync-spec.md       ← 修改：v3 变更历史
```

---

### Task 1: `FoodCategory` 追加 `western` / `streetfood` + Label

**Files:**
- Modify: `personal-butler/Domain/Models/FoodRecord.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `FoodCategory.western` / `FoodCategory.streetfood`
  - `label` 计算属性：`.western → "西餐"`, `.streetfood → "大排档"`

- [ ] **Step 1: 修改 FoodCategory 枚举**

打开 `personal-butler/Domain/Models/FoodRecord.swift`，把 `enum FoodCategory { ... }` 整段替换为：

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

- [ ] **Step 2: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED（下游 `FoodRecordView.gradient(for:)` 的 switch 是 `default` 兜底，不会因新增 case 报缺失；`EditFoodSheet` 的 Picker 显式列 case，本任务不动 Picker，编译不受影响）

- [ ] **Step 3: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Domain/Models/FoodRecord.swift && \
  git commit -m "feat(food): FoodCategory 追加 western / streetfood"
```

---

### Task 2: `FoodRecord` 字段升级（rating Double + iconImage）

**Files:**
- Modify: `personal-butler/Domain/Models/FoodRecord.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `FoodRecord.rating: Double`（原 `Int`）
  - `FoodRecord.iconImage: Data?`（新增，`@Attribute(.externalStorage)`）
  - `FoodRecord.init(...)` 签名：`rating: Double = 4.0`（原 `Int = 4`）；末位追加 `iconImage: Data? = nil`

- [ ] **Step 1: 修改 FoodRecord 模型**

在 `personal-butler/Domain/Models/FoodRecord.swift` 里，把 `@Model final class FoodRecord { ... }` 整段替换为：

```swift
@Model
final class FoodRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var rating: Double        // 半星支持：0.0..5.0，step 0.5；iconImage 缺失时 emoji 作为兜底
    var tagsRaw: String       // 逗号分隔
    var remark: String
    var date: Date
    var categoryRaw: String

    // 位置字段（全 Optional）
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?

    // 图片图标（可选）：走 external storage，SQLite 只存引用
    @Attribute(.externalStorage) var iconImage: Data?

    init(id: UUID = UUID(), name: String, emoji: String = "🍽️",
         rating: Double = 4.0, tags: [String] = [], remark: String = "",
         date: Date = .init(), category: FoodCategory = .chinese,
         placeName: String? = nil, address: String? = nil,
         latitude: Double? = nil, longitude: Double? = nil,
         iconImage: Data? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.rating = rating
        self.tagsRaw = tags.joined(separator: ",")
        self.remark = remark
        self.date = date
        self.categoryRaw = category.rawValue
        self.placeName = placeName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.iconImage = iconImage
    }

    var tags: [String] {
        tagsRaw.split(separator: ",").map { String($0) }
    }

    var category: FoodCategory { FoodCategory(rawValue: categoryRaw) ?? .chinese }

    /// 经纬度成对齐备才视为"有位置"
    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// 列表 / 卡片单行位置展示优先级：正式地址 → POI 名称
    var displayLocation: String? { address ?? placeName }
}
```

- [ ] **Step 2: 修复上下游编译错误（把 Int rating 相关消费点先临时改为 Double）**

编译此时会在 3 个地方报错（Int → Double 类型不匹配），先做**最小修复**让 build 通过；完整的半星 UI/构造逻辑放到后续 Task：

**修复 A**：`personal-butler/Domain/UseCases/BackupSyncUseCase.swift` 里 `SyncFoodDTO(...)` 传参 `rating: $0.rating`，改成 `rating: Double($0.rating)` **等等，$0.rating 现在已经是 Double**——不用改。检查一下 rebuild 里 `rating: x.rating` 传参：`FoodRecord.init(rating: ...)` 现在期待 `Double`，`SyncFoodDTO.rating` 目前还是 `Int`，会报错。在这个 Task 里**先本地转换**：`rating: Double(x.rating)`，Task 3 再把 DTO 改成 Double。

具体：把 `personal-butler/Domain/UseCases/BackupSyncUseCase.swift` 里 `rebuild` 中：

```swift
let m = FoodRecord(
    id: uuid, name: x.name, emoji: x.emoji,
    rating: x.rating, tags: x.tags, remark: x.remark,
    ...
)
```

改为：

```swift
let m = FoodRecord(
    id: uuid, name: x.name, emoji: x.emoji,
    rating: Double(x.rating), tags: x.tags, remark: x.remark,
    ...
)
```

**修复 B**：`personal-butler/Presentation/Views/SubPages/FoodRecordView.swift` 里列表行 `ForEach(0..<5) { i in Image(systemName: i < f.rating ? "star.fill" : "star") ... }` —— `i` 是 `Int`，`f.rating` 现在是 `Double`。改成：

```swift
ForEach(0..<5) { i in
    Image(systemName: Double(i) < f.rating ? "star.fill" : "star")
        .font(.system(size: 11))
        .foregroundStyle(Double(i) < f.rating ? Color(hex: 0xF5A623) : Color(hex: 0xE2E5EA))
}
```

（半星三态渲染放到 Task 9 完整替换。）

**修复 C**：`personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift` 里：
- `@State private var rating: Int` → `@State private var rating: Double`
- `_rating = State(initialValue: record?.rating ?? 4)` → `_rating = State(initialValue: record?.rating ?? 4.0)`
- `starRating` 里 `rating = (rating == i) ? 0 : i` —— `i` 是 `Int`，`rating` 现在是 `Double`。改成 `rating = (rating == Double(i)) ? 0 : Double(i)`，同时 `i <= rating` → `Double(i) <= rating`（这两处也是临时修复，Task 8 再完整替换成半星）
- `save()` 里 `r.rating = rating`（`FoodRecord.rating` 已是 Double，直接赋 OK）；新建分支 `FoodRecord(name:, emoji:, rating: rating, ...)`（同上）

- [ ] **Step 3: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Domain/Models/FoodRecord.swift \
          personal-butler/Domain/UseCases/BackupSyncUseCase.swift \
          personal-butler/Presentation/Views/SubPages/FoodRecordView.swift \
          personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift && \
  git commit -m "feat(food): FoodRecord rating Int→Double + iconImage 字段（含消费点临时兼容修复）"
```

---

### Task 3: 同步契约 · `SyncFoodDTO` rating Double + iconImageBase64 + dataVersion 3

**Files:**
- Modify: `personal-butler/Data/Mapper/SyncPayload.swift`
- Modify: `personal-butler/Domain/UseCases/BackupSyncUseCase.swift`

**Interfaces:**
- Consumes: `FoodRecord.rating: Double`（Task 2）、`FoodRecord.iconImage: Data?`（Task 2）
- Produces:
  - `SyncFoodDTO.rating: Double`
  - `SyncFoodDTO.iconImageBase64: String?`
  - `SyncMeta.dataVersion == 3`
  - `URLRequest.timeoutInterval == 25`

- [ ] **Step 1: 修改 SyncFoodDTO**

在 `personal-butler/Data/Mapper/SyncPayload.swift` 中把 `struct SyncFoodDTO: Codable { ... }` 整段替换为：

```swift
struct SyncFoodDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var rating: Double            // v3：Int→Double；Codable 天然兼容整数 JSON 解码为 Double
    var tags: [String]
    var remark: String
    var date: Double
    var category: String
    // v2 位置字段
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    // v3 图片图标（base64 编码的 JPEG bytes；nil = 未设置）
    var iconImageBase64: String?
}
```

- [ ] **Step 2: `buildPayload` 组装图片 base64 + 移除 Task 2 的 Double 强转**

在 `personal-butler/Domain/UseCases/BackupSyncUseCase.swift` 中把 `foodRecordList: foods.map { ... }` 整段替换为：

```swift
foodRecordList: foods.map {
    SyncFoodDTO(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                rating: $0.rating, tags: $0.tags, remark: $0.remark,
                date: $0.date.timeIntervalSince1970, category: $0.categoryRaw,
                placeName: $0.placeName, address: $0.address,
                latitude: $0.latitude, longitude: $0.longitude,
                iconImageBase64: $0.iconImage?.base64EncodedString())
},
```

- [ ] **Step 3: `rebuild` 反向解析 base64 + 移除 Task 2 的 Double 强转**

在 `personal-butler/Domain/UseCases/BackupSyncUseCase.swift` 中把 `for x in data.foodRecordList { ... }` 整段替换为：

```swift
for x in data.foodRecordList {
    guard let uuid = UUID(uuidString: x.id) else { continue }
    // 解 base64 → Data；解码失败视为无图片（保留 emoji 兜底显示）
    let iconData: Data? = {
        guard let b64 = x.iconImageBase64, !b64.isEmpty else { return nil }
        return Data(base64Encoded: b64)
    }()
    let m = FoodRecord(
        id: uuid, name: x.name, emoji: x.emoji,
        rating: x.rating, tags: x.tags, remark: x.remark,
        date: Date(timeIntervalSince1970: x.date),
        category: FoodCategory(rawValue: x.category) ?? .chinese,
        placeName: x.placeName, address: x.address,
        latitude: x.latitude, longitude: x.longitude,
        iconImage: iconData
    )
    context.insert(m)
}
```

- [ ] **Step 4: `dataVersion` 递增 + 超时放宽**

在 `personal-butler/Domain/UseCases/BackupSyncUseCase.swift` 中：

把
```swift
let meta = SyncMeta(deviceId: AppSyncConfig.deviceID,
                    syncTimestamp: Int64(Date().timeIntervalSince1970),
                    appVersion: "1.0.0",
                    dataVersion: 2)
```
改为
```swift
let meta = SyncMeta(deviceId: AppSyncConfig.deviceID,
                    syncTimestamp: Int64(Date().timeIntervalSince1970),
                    appVersion: "1.0.0",
                    dataVersion: 3)
```

把 `req.timeoutInterval = 10` 改为 `req.timeoutInterval = 25`。

- [ ] **Step 5: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Data/Mapper/SyncPayload.swift \
          personal-butler/Domain/UseCases/BackupSyncUseCase.swift && \
  git commit -m "feat(sync): SyncFoodDTO rating Double + iconImageBase64, dataVersion 2→3, timeout 10→25s"
```

---

### Task 4: SwiftData 迁移 · `VersionedSchema` V2→V3 + fallback

**Files:**
- Create: `personal-butler/Domain/Models/FoodRecordSchema.swift`
- Modify: `personal-butler/App/PersonalButlerApp.swift`

**Interfaces:**
- Consumes: 无（V3 复用主 `FoodRecord`）
- Produces:
  - `FoodRecordSchemaV2` / `FoodRecordSchemaV3`（`VersionedSchema`）
  - `FoodRecordMigrationPlan: SchemaMigrationPlan`

- [ ] **Step 1: 新建 FoodRecordSchema.swift**

创建 `personal-butler/Domain/Models/FoodRecordSchema.swift`：

```swift
//
//  FoodRecordSchema.swift
//  FoodRecord 版本化 Schema 与 V2→V3 迁移计划
//
//  V2：rating: Int，无 iconImage
//  V3：rating: Double，含 iconImage: Data?
//

import Foundation
import SwiftData

enum FoodRecordSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [FoodRecordV2.self] }

    @Model
    final class FoodRecordV2 {
        @Attribute(.unique) var id: UUID
        var name: String
        var emoji: String
        var rating: Int
        var tagsRaw: String
        var remark: String
        var date: Date
        var categoryRaw: String
        var placeName: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?

        init(id: UUID = UUID(), name: String, emoji: String = "🍽️",
             rating: Int = 4, tagsRaw: String = "", remark: String = "",
             date: Date = .init(), categoryRaw: String = "chinese",
             placeName: String? = nil, address: String? = nil,
             latitude: Double? = nil, longitude: Double? = nil) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.rating = rating
            self.tagsRaw = tagsRaw
            self.remark = remark
            self.date = date
            self.categoryRaw = categoryRaw
            self.placeName = placeName
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
        }
    }
}

enum FoodRecordSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    // V3 使用主 FoodRecord.swift 里的当前类型
    static var models: [any PersistentModel.Type] { [FoodRecord.self] }
}

/// V2→V3 迁移计划。
/// SwiftData 对 rating Int→Double（同名字段类型变更）在实测中行为不稳定：
/// 部分场景下 Int 数据被读作 0.0。因此不依赖自动映射，而是清库 fallback
/// 在 App/PersonalButlerApp.swift 的 bootstrap 里处理。这里保留
/// MigrationPlan 结构，为未来的字段追加（无类型变更）留一个可扩展点。
enum FoodRecordMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FoodRecordSchemaV2.self, FoodRecordSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        // custom stage 里我们目前不做重映射（spec 明确"存量数据强转，不做重映射"）
        // 若 SwiftData 引擎无法完成 Int→Double 类型变更，会在 ModelContainer 初始化时抛错，
        // 由 bootstrap 中的 fallback 路径处理。
        [.custom(
            fromVersion: FoodRecordSchemaV2.self,
            toVersion: FoodRecordSchemaV3.self,
            willMigrate: nil,
            didMigrate: { _ in
                // 无重映射；rating 类型变更依赖 SwiftData 自动处理，
                // iconImage 保持默认 nil
            }
        )]
    }
}
```

- [ ] **Step 2: `PersonalButlerApp.bootstrap` 挂 migrationPlan + fallback 清库重建**

在 `personal-butler/App/PersonalButlerApp.swift` 中把 `bootstrap()` 方法整段替换为：

```swift
    /// 冷启初始化：SwiftData 建库/迁移 + SeedData 首启灌数据。
    /// 全部走后台任务，SwiftUI 首帧可以立即渲染 LaunchView。
    /// 保底展示 0.5s，避免二次启动 bootstrap 秒完导致切换太生硬。
    ///
    /// **v2→v3 迁移策略**：
    /// - 挂载 `FoodRecordMigrationPlan` 尝试正常迁移
    /// - 失败（rating Int→Double 类型变更无法自动完成）时清库重建
    ///   （spec 明确"存量数据强转，不考虑迁移"）
    @MainActor
    private func bootstrap() async {
        let start = Date()

        let container: ModelContainer = await Task.detached(priority: .userInitiated) {
            let schema = Schema([
                TodoItem.self,
                ScheduleEvent.self,
                Anniversary.self,
                PasswordAccount.self,
                OTPAccount.self,
                FoodRecord.self,
                CookRecipe.self,
                Note.self,
                AppModule.self,
                AppSetting.self
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

            // 尝试正常迁移
            if let ok = try? ModelContainer(
                for: schema,
                migrationPlan: FoodRecordMigrationPlan.self,
                configurations: [config]
            ) {
                return ok
            }

            // Fallback：清除本地 store 后重建
            // 定位默认 SwiftData store 文件并删除；SwiftData 会在下一次
            // ModelContainer 初始化时新建空库
            let fm = FileManager.default
            if let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil, create: false) {
                // SwiftData 默认 store 文件名为 default.store（含 -shm / -wal 附属文件）
                for name in ["default.store", "default.store-shm", "default.store-wal"] {
                    let url = appSupport.appendingPathComponent(name)
                    try? fm.removeItem(at: url)
                }
            }

            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("SwiftData 初始化失败（清库后重建仍失败）: \(error)")
            }
        }.value

        SeedData.ensureSeeded(in: container.mainContext)

        let elapsed = Date().timeIntervalSince(start)
        let minShow: TimeInterval = 0.5
        if elapsed < minShow {
            try? await Task.sleep(nanoseconds: UInt64((minShow - elapsed) * 1_000_000_000))
        }

        modelContainer = container
    }
```

- [ ] **Step 3: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Domain/Models/FoodRecordSchema.swift \
          personal-butler/App/PersonalButlerApp.swift && \
  git commit -m "feat(food): 引入 FoodRecordSchema V2/V3 迁移 + bootstrap fallback 清库重建"
```

---

### Task 5: 新建 `ImageProcessor`

**Files:**
- Create: `personal-butler/Core/Utils/ImageProcessor.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `ImageProcessor.compress(data: Data, maxLongSide: CGFloat, quality: CGFloat) -> Data?`
  - `ImageProcessor.compress(uiImage: UIImage, maxLongSide: CGFloat, quality: CGFloat) -> Data?`
  - 默认参数：`maxLongSide = 512`, `quality = 0.7`

- [ ] **Step 1: 新建 ImageProcessor.swift**

创建 `personal-butler/Core/Utils/ImageProcessor.swift`：

```swift
//
//  ImageProcessor.swift
//  美食图标图片压缩：JPEG + 长边缩放
//

import UIKit

enum ImageProcessor {
    /// 从原始 Data 压缩：解码为 UIImage → 长边 <= maxLongSide → JPEG 编码。
    /// 无法解码返回 nil。
    static func compress(data raw: Data,
                         maxLongSide: CGFloat = 512,
                         quality: CGFloat = 0.7) -> Data? {
        guard let ui = UIImage(data: raw) else { return nil }
        return compress(uiImage: ui, maxLongSide: maxLongSide, quality: quality)
    }

    /// 从 UIImage 压缩：长边 <= maxLongSide → JPEG 编码。
    static func compress(uiImage: UIImage,
                         maxLongSide: CGFloat = 512,
                         quality: CGFloat = 0.7) -> Data? {
        let img = resize(uiImage, longSide: maxLongSide)
        return img.jpegData(compressionQuality: quality)
    }

    /// 按长边等比缩放；已在长边范围内则原样返回。
    private static func resize(_ img: UIImage, longSide: CGFloat) -> UIImage {
        let w = img.size.width
        let h = img.size.height
        let long = max(w, h)
        guard long > longSide else { return img }
        let scale = longSide / long
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

- [ ] **Step 2: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Core/Utils/ImageProcessor.swift && \
  git commit -m "feat(core): 新增 ImageProcessor（JPEG 0.7 + 长边 512 压缩）"
```

---

### Task 6: 新建 `MapsNavigator`

**Files:**
- Create: `personal-butler/Core/Utils/MapsNavigator.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `MapsNavigator.openInMaps(latitude: Double, longitude: Double, name: String?)`

- [ ] **Step 1: 新建 MapsNavigator.swift**

创建 `personal-butler/Core/Utils/MapsNavigator.swift`：

```swift
//
//  MapsNavigator.swift
//  Apple Maps 拉起（供 EditFoodSheet 与 FoodRecordView 位置行共用）
//

import UIKit

enum MapsNavigator {
    /// 用 http://maps.apple.com/ 拉起 Apple Maps；未装 Maps 时系统兜底走 Web。
    /// 相比 maps://，http:// 有更强的可用性保证。
    static func openInMaps(latitude: Double, longitude: Double, name: String? = nil) {
        let q = (name ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(latitude),\(longitude)") else {
            return
        }
        UIApplication.shared.open(url)
    }
}
```

- [ ] **Step 2: 修改 `EditFoodSheet.openInMaps` 私有方法改调 `MapsNavigator`**

在 `personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift` 中把 `openInMaps()` 私有方法整段替换为：

```swift
private func openInMaps() {
    guard let lat = latitude, let lng = longitude else { return }
    MapsNavigator.openInMaps(latitude: lat, longitude: lng, name: placeName ?? address)
}
```

- [ ] **Step 3: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Core/Utils/MapsNavigator.swift \
          personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift && \
  git commit -m "feat(core): 新增 MapsNavigator 工具 + EditFoodSheet 复用"
```

---

### Task 7: 新建 `IconPickerSheet`（Emoji / 相册 / 拍照）

**Files:**
- Create: `personal-butler/Presentation/Views/SubPages/Food/IconPickerSheet.swift`

**Interfaces:**
- Consumes: `ImageProcessor.compress(...)`（Task 5）
- Produces:
  - `enum FoodIcon: Equatable { case emoji(String); case image(Data) }`
  - `struct IconPickerSheet: View`
    - `init(initial: FoodIcon, onConfirm: @escaping (FoodIcon) -> Void)`
  - 内部：`enum IconTab { case emoji, album, camera }`
  - 私有 `struct CameraPicker: UIViewControllerRepresentable`

- [ ] **Step 1: 新建 IconPickerSheet.swift**

创建 `personal-butler/Presentation/Views/SubPages/Food/IconPickerSheet.swift`：

```swift
//
//  IconPickerSheet.swift
//  美食图标弹窗：Emoji / 相册 / 拍照 三选一
//

import SwiftUI
import PhotosUI
import UIKit

/// 统一的图标回传协议：emoji 字符 或 已压缩 JPEG 二进制。
enum FoodIcon: Equatable {
    case emoji(String)
    case image(Data)
}

private enum IconTab: Hashable { case emoji, album, camera }

struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: FoodIcon
    let onConfirm: (FoodIcon) -> Void

    @State private var current: FoodIcon
    @State private var tab: IconTab = .emoji

    // 相册
    @State private var pickedItem: PhotosPickerItem?
    @State private var albumBusy: Bool = false

    // 拍照
    @State private var showCamera: Bool = false

    /// 30 个候选 emoji（覆盖火锅/奶茶/中餐/西餐/日料/咖啡/大排档等主流场景）
    private static let emojiOptions: [String] = [
        "🍽️", "🍜", "🍚", "🍛", "🍲", "🍱",
        "🍣", "🍤", "🥟", "🍔", "🍕", "🌮",
        "🥗", "🍖", "🍗", "🥘", "🍢", "🍧",
        "🍰", "🧁", "🍩", "🍪", "🍦", "🍮",
        "☕️", "🍵", "🧋", "🥤", "🍺", "🍷"
    ]

    init(initial: FoodIcon, onConfirm: @escaping (FoodIcon) -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        _current = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部 tab
                MiniSegmentedPill(items: [
                    (IconTab.emoji, "Emoji"),
                    (IconTab.album, "相册"),
                    (IconTab.camera, "拍照")
                ], selection: $tab)
                .padding(.vertical, 12)

                // 中部内容
                Group {
                    switch tab {
                    case .emoji:  emojiGrid
                    case .album:  albumPane
                    case .camera: cameraPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)

                // 底部预览 + 保存
                Divider()
                HStack(spacing: 12) {
                    preview
                        .frame(width: 40, height: 40)
                    Spacer()
                    Button("保存") {
                        onConfirm(current)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
            }
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    if let compressed = data.flatMap({ ImageProcessor.compress(data: $0) }) {
                        current = .image(compressed)
                    }
                    showCamera = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private var preview: some View {
        switch current {
        case .emoji(let s):
            Text(s.isEmpty ? "🍽️" : s)
                .font(.system(size: 26))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppColorTheme.bg))
        case .image(let d):
            if let ui = UIImage(data: d) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColorTheme.bg)
                    .frame(width: 40, height: 40)
            }
        }
    }

    // MARK: - Emoji tab

    private var emojiGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Self.emojiOptions, id: \.self) { e in
                    Button {
                        current = .emoji(e)
                    } label: {
                        Text(e)
                            .font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isCurrentEmoji(e)
                                          ? AppColorTheme.primary.opacity(0.12)
                                          : AppColorTheme.bg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isCurrentEmoji(e) ? AppColorTheme.primary : .clear,
                                            lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func isCurrentEmoji(_ e: String) -> Bool {
        if case .emoji(let s) = current { return s == e }
        return false
    }

    // MARK: - 相册 tab

    private var albumPane: some View {
        VStack(spacing: 16) {
            if case .image(let d) = current, let ui = UIImage(data: d) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Text("重新选择")
                        .font(.system(size: 14, weight: .medium))
                }
            } else {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColorTheme.primary)
                        Text("从相册选择照片")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColorTheme.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
                }
            }
            if albumBusy {
                ProgressView()
            }
            Spacer()
        }
        .padding(.top, 8)
        .onChange(of: pickedItem) { _, newValue in
            guard let item = newValue else { return }
            albumBusy = true
            Task {
                let raw = try? await item.loadTransferable(type: Data.self)
                let compressed = raw.flatMap { ImageProcessor.compress(data: $0) }
                await MainActor.run {
                    if let c = compressed { current = .image(c) }
                    albumBusy = false
                }
            }
        }
    }

    // MARK: - 拍照 tab

    private var cameraPane: some View {
        VStack(spacing: 16) {
            if case .image(let d) = current, let ui = UIImage(data: d) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("重新拍照") { showCamera = true }
                    .font(.system(size: 14, weight: .medium))
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            } else {
                Button {
                    showCamera = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColorTheme.primary)
                        Text("打开相机拍照")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColorTheme.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
                }
                .buttonStyle(.plain)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Text("当前设备无相机")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColorTheme.textSub)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - 相机 UIImagePickerController 薄包装

private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void
        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            // 直接把 UIImage 交给 ImageProcessor 走 UIImage 分支（避免二次 Data→UIImage 转码）
            let data = image.flatMap { ImageProcessor.compress(uiImage: $0) }
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
```

**注意**：`CameraPicker.onCapture` 直接调 `ImageProcessor.compress(uiImage:)` 二次压缩，避免在 IconPickerSheet 内做重复的 `Data → UIImage → Data` 转码。上层 `.fullScreenCover` 里的回调 `if let compressed = data.flatMap({ ImageProcessor.compress(data: $0) })` 会被走成"已压缩数据再压缩一次"—— 修正为直接使用 `data`（`CameraPicker` 已经压好）。所以上层回调实际写：

```swift
CameraPicker { data in
    if let d = data { current = .image(d) }
    showCamera = false
}
```

**请以此为准**（替换掉本 Step Body 里 `.fullScreenCover` 那块的 `flatMap({ ImageProcessor.compress(data: $0) })` —— 之前那行是笔误）。

- [ ] **Step 2: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/Food/IconPickerSheet.swift && \
  git commit -m "feat(food): 新增 IconPickerSheet（Emoji/相册/拍照 三选一）"
```

---

### Task 8: `EditFoodSheet` 集成 IconPickerSheet + 半星评分 + 分类 Picker 补 2 项

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift`

**Interfaces:**
- Consumes: `IconPickerSheet` / `FoodIcon`（Task 7）；`FoodCategory.western/.streetfood`（Task 1）
- Produces: 无（内部改造）

- [ ] **Step 1: State 与 init 调整**

在 `personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift` 中：

删除 `@State private var emoji: String`；增加：
```swift
@State private var icon: FoodIcon
@State private var showIconPicker: Bool = false
```

`init(record:)` 里删除 `_emoji = State(initialValue: record?.emoji ?? "🍽️")`，改为：
```swift
if let data = record?.iconImage {
    _icon = State(initialValue: .image(data))
} else {
    _icon = State(initialValue: .emoji(record?.emoji ?? "🍽️"))
}
```

- [ ] **Step 2: 替换「图标」Section**

在 Form 中把 `Section("图标") { emojiPicker }` 整段替换为：

```swift
Section("图标") {
    Button {
        showIconPicker = true
    } label: {
        HStack(spacing: 12) {
            iconPreview
                .frame(width: 60, height: 60)
            Text("点击更换")
                .font(.system(size: 15))
                .foregroundStyle(AppColorTheme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(AppColorTheme.textSub)
        }
    }
    .buttonStyle(.plain)
}
```

在 `body` 的 `.toolbar { ... }` 后（若已存在其它 sheet 挂载点，紧随其后）追加：

```swift
.sheet(isPresented: $showIconPicker) {
    IconPickerSheet(initial: icon) { picked in
        icon = picked
    }
}
```

- [ ] **Step 3: 补 iconPreview view + 移除旧 emojiPicker / emojiOptions**

在 `EditFoodSheet` 内**移除** `private static let emojiOptions: [String] = [...]` 常量和 `private var emojiPicker: some View { ... }` 方法。

在原 emojiPicker 附近新增：

```swift
@ViewBuilder
private var iconPreview: some View {
    switch icon {
    case .emoji(let s):
        Text(s.isEmpty ? "🍽️" : s)
            .font(.system(size: 36))
            .frame(width: 60, height: 60)
            .background(RoundedRectangle(cornerRadius: 10).fill(AppColorTheme.bg))
    case .image(let d):
        if let ui = UIImage(data: d) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColorTheme.bg)
                .frame(width: 60, height: 60)
        }
    }
}
```

- [ ] **Step 4: 半星评分三态 UI**

在 `EditFoodSheet` 内把 `private var starRating: some View { ... }` 整段替换为：

```swift
private var starRating: some View {
    HStack(spacing: 10) {
        ForEach(0..<5, id: \.self) { i in
            starCell(index: i)
        }
        Spacer()
        Text(rating > 0 ? String(format: "%.1f 星", rating) : "未评分")
            .font(.system(size: 13))
            .foregroundStyle(AppColorTheme.textSub)
    }
    .padding(.vertical, 4)
}

/// 每颗星拆左右两半 tap 区：左半 = +0.5，右半 = +1.0；再点当前值归零
@ViewBuilder
private func starCell(index i: Int) -> some View {
    let idx = Double(i)
    let iconName: String =
        rating >= idx + 1.0 ? "star.fill"
        : rating >= idx + 0.5 ? "star.leadinghalf.filled"
        : "star"
    let filled = rating >= idx + 0.5

    ZStack {
        Image(systemName: iconName)
            .font(.system(size: 26))
            .foregroundStyle(filled ? Color(hex: 0xF5A623) : Color(hex: 0xC7CCD4))
            .allowsHitTesting(false)
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 20, height: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    let target = idx + 0.5
                    rating = (rating == target) ? 0 : target
                }
            Color.clear
                .frame(width: 20, height: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    let target = idx + 1.0
                    rating = (rating == target) ? 0 : target
                }
        }
    }
    .frame(width: 40, height: 40)
}
```

- [ ] **Step 5: 分类 Picker 补 2 项**

在 Form 中把 `Picker("分类", selection: $category) { ... }` 整段替换为：

```swift
Picker("分类", selection: $category) {
    Text("火锅").tag(FoodCategory.hotpot)
    Text("奶茶").tag(FoodCategory.milktea)
    Text("中餐").tag(FoodCategory.chinese)
    Text("西餐").tag(FoodCategory.western)
    Text("大排档").tag(FoodCategory.streetfood)
    Text("日料").tag(FoodCategory.japanese)
    Text("咖啡").tag(FoodCategory.coffee)
}
```

- [ ] **Step 6: `save()` 分支写入 icon**

在 `EditFoodSheet.save()` 中，把编辑分支和新建分支都调整为按 `icon` 落库。

编辑分支（`if let r = record`）里，删除 `r.emoji = emoji` 和之前 rating 相关（保留 `r.rating = rating`），改为：

```swift
r.name = finalName
r.rating = rating
r.tagsRaw = tagList.joined(separator: ",")
r.remark = remark
r.categoryRaw = category.rawValue
r.placeName = placeName
r.address = address
r.latitude = latitude
r.longitude = longitude
switch icon {
case .emoji(let s):
    r.emoji = s.isEmpty ? "🍽️" : s
    r.iconImage = nil
case .image(let d):
    // 保留原 emoji 作为兜底显示（图片被清后仍有 fallback）
    r.iconImage = d
}
```

新建分支（`else`）改为：

```swift
let effectiveEmoji: String
let effectiveImage: Data?
switch icon {
case .emoji(let s):
    effectiveEmoji = s.isEmpty ? "🍽️" : s
    effectiveImage = nil
case .image(let d):
    effectiveEmoji = "🍽️"     // 兜底 emoji
    effectiveImage = d
}
let f = FoodRecord(name: finalName,
                   emoji: effectiveEmoji, rating: rating,
                   tags: tagList,
                   remark: remark, category: category,
                   placeName: placeName, address: address,
                   latitude: latitude, longitude: longitude,
                   iconImage: effectiveImage)
context.insert(f)
```

- [ ] **Step 7: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

模拟器手测：
- 打开新增：图标 Section 显示 60×60 emoji + "点击更换"
- 点击 → IconPickerSheet；Emoji tab 网格 30 项能选中高亮；保存后回到 EditFoodSheet 图标展示更新
- 相册 tab（模拟器需给相册塞图）→ 选照片 → 图标区域变成图片；保存回 EditFoodSheet
- 拍照 tab → 模拟器 disabled + "当前设备无相机"
- 半星：点第 3 星左半 → rating=2.5，副标签 "2.5 星"；点第 3 星右半 → rating=3.0；再点右半 → 归零
- 分类 Picker 有 7 个选项（不含"全部"），含"西餐"/"大排档"

- [ ] **Step 8: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift && \
  git commit -m "feat(food): EditFoodSheet 集成 IconPickerSheet、半星评分、+2 分类"
```

---

### Task 9: `FoodRecordView` 分类补 2 项、位置行改 Button、图片双源、只读 5 星三态

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/FoodRecordView.swift`

**Interfaces:**
- Consumes: `FoodRecord.iconImage`（Task 2）、`FoodCategory.western/.streetfood`（Task 1）、`MapsNavigator`（Task 6）
- Produces: 无

- [ ] **Step 1: 分类列表补 2 项**

在 `FoodRecordView` 中把 `private let categories: [(String, FoodCategory)] = [...]` 整段替换为：

```swift
private let categories: [(String, FoodCategory)] = [
    ("全部", .all),
    ("火锅", .hotpot),
    ("奶茶", .milktea),
    ("中餐", .chinese),
    ("西餐", .western),
    ("大排档", .streetfood),
    ("日料", .japanese),
    ("咖啡", .coffee)
]
```

- [ ] **Step 2: 列表行 icon 展示 双源**

在 `FoodRecordView.row(_:)` 中，把左侧 `Text(f.emoji).font(.system(size: 32)).frame(width: 90, height: 90).background(...)` 整段替换为：

```swift
Group {
    if let data = f.iconImage, let ui = UIImage(data: data) {
        Image(uiImage: ui)
            .resizable()
            .scaledToFill()
            .frame(width: 90, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    } else {
        Text(f.emoji)
            .font(.system(size: 32))
            .frame(width: 90, height: 90)
            .background(RoundedRectangle(cornerRadius: 10).fill(
                LinearGradient(colors: gradient(for: f.category),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            ))
    }
}
```

- [ ] **Step 3: 只读 5 星三态渲染**

在 `row(_:)` 中把评分那段 `HStack(spacing: 2) { ForEach(0..<5) { i in ... } }` 整段替换为：

```swift
HStack(spacing: 2) {
    ForEach(0..<5, id: \.self) { i in
        let idx = Double(i)
        let iconName: String =
            f.rating >= idx + 1.0 ? "star.fill"
            : f.rating >= idx + 0.5 ? "star.leadinghalf.filled"
            : "star"
        Image(systemName: iconName)
            .font(.system(size: 11))
            .foregroundStyle(f.rating >= idx + 0.5 ? Color(hex: 0xF5A623) : Color(hex: 0xE2E5EA))
    }
}
```

- [ ] **Step 4: 位置行改可点击 Button**

在 `row(_:)` 中，把现有位置行整段：

```swift
if f.hasLocation, let loc = f.displayLocation {
    HStack(spacing: 4) {
        Image(systemName: "location.fill")
            .font(.system(size: 10))
        Text(loc)
            .lineLimit(1)
    }
    .font(.system(size: 12))
    .foregroundStyle(AppColorTheme.textSub)
}
```

替换为：

```swift
if f.hasLocation, let loc = f.displayLocation,
   let lat = f.latitude, let lng = f.longitude {
    Button {
        MapsNavigator.openInMaps(latitude: lat, longitude: lng,
                                 name: f.placeName ?? f.address)
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.system(size: 10))
            Text(loc)
                .lineLimit(1)
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 9))
                .foregroundStyle(AppColorTheme.primary)
        }
        .font(.system(size: 12))
        .foregroundStyle(AppColorTheme.textSub)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
```

（Button 独占 hit test，tap 不会冒泡到 `SwipeToDeleteRow.onTap`）

- [ ] **Step 5: `gradient(for:)` 补 2 个 case**

`gradient(for:)` 现有的 `default: return [...]` 会自动兜底 `.western` / `.streetfood`；无需修改，跳过。

- [ ] **Step 6: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED

模拟器手测：
- 顶部分类 tab 现在 8 项（含"西餐"/"大排档"）
- 有 iconImage 的记录：左侧 90×90 直接展示照片（无渐变背景）；无 iconImage 的记录：保持现有 emoji + 渐变
- 半星记录（rating=2.5）：显示 2 颗满星 + 1 颗半星 + 2 颗空星
- 有位置的记录：位置行右侧多一个 `↗` 箭头，点位置行直接拉起 Apple Maps；整行其它区域点击 → 打开编辑弹窗

- [ ] **Step 7: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/FoodRecordView.swift && \
  git commit -m "feat(food): 列表 +2 分类、图片/emoji 双源渲染、半星三态、位置行可点击导航"
```

---

### Task 10: 文档同步 · `module-backup-sync-spec.md` v3 变更历史

**Files:**
- Modify: `docs/module-spec/module-backup-sync-spec.md`

**Interfaces:**
- Consumes: 无
- Produces: 无

- [ ] **Step 1: 更新文档**

在 `docs/module-spec/module-backup-sync-spec.md` 里：

- 找 `dataVersion (=2)` 改为 `dataVersion (=3)`
- 找 `dataVersion = 2（硬编码）` 改为 `dataVersion = 3（硬编码）`
- 在「变更历史」节末尾追加：

```
- v3 (2026-07-26): SyncFoodDTO 追加变更
  - rating: Int → Double（半星评分，Codable 天然兼容老 JSON 整数）
  - iconImageBase64?: String（图片图标，base64 编码的 JPEG bytes）
  - URLRequest.timeoutInterval 由 10s 放宽为 25s（图片显著增大 payload）
```

- [ ] **Step 2: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add docs/module-spec/module-backup-sync-spec.md && \
  git commit -m "docs(sync): dataVersion v3 变更历史（rating Double + iconImageBase64 + timeout 25s）"
```

---

## Self-Review

**1. Spec 覆盖：**
- 数据模型（rating Double + iconImage + 分类）→ Task 1、2 ✅
- 同步契约（rating Double + iconImageBase64 + dataVersion 3 + 超时）→ Task 3 ✅
- SwiftData 迁移 + fallback → Task 4 ✅
- ImageProcessor 压缩 → Task 5 ✅
- MapsNavigator 抽公用 → Task 6 ✅
- IconPickerSheet（Emoji / 相册 / 拍照）→ Task 7 ✅
- EditFoodSheet 集成（图标弹窗 / 半星 UI / 分类 Picker / save）→ Task 8 ✅
- FoodRecordView（分类补 2 / 位置行 Button / 图片双源 / 只读 5 星三态）→ Task 9 ✅
- 文档 v3 → Task 10 ✅

**2. 类型一致性：**
- `FoodRecord.rating: Double`（Task 2）↔ `SyncFoodDTO.rating: Double`（Task 3）↔ `EditFoodSheet.rating: Double`（Task 2 Step 2 修复 C + Task 8 完整化）✅
- `FoodRecord.iconImage: Data?`（Task 2）↔ `SyncFoodDTO.iconImageBase64: String?`（Task 3）✅
- `FoodIcon` 枚举（Task 7）↔ `EditFoodSheet.icon: FoodIcon`（Task 8）↔ `IconPickerSheet(initial:onConfirm:)`（Task 7）✅
- `FoodCategory.western / .streetfood`（Task 1）↔ `FoodRecordView.categories`（Task 9）↔ `EditFoodSheet.Picker`（Task 8 Step 5）✅
- `MapsNavigator.openInMaps(latitude:longitude:name:)`（Task 6）↔ `EditFoodSheet.openInMaps`（Task 6 Step 2）↔ `FoodRecordView.row` 位置行（Task 9 Step 4）✅
- `ImageProcessor.compress(data:)` / `.compress(uiImage:)`（Task 5）↔ `IconPickerSheet.albumPane` / `CameraPicker.onCapture`（Task 7）✅

**3. Placeholder 扫描：** 无 TBD / TODO；每个代码步骤都给出完整可粘贴代码。Task 7 Step 1 结尾有一处对 `.fullScreenCover` 里回调写法的显式勘误说明（避免 CameraPicker 内已压缩的数据被再次压缩），要求以修正版为准。

**4. 修复依赖顺序：**
- Task 2 里 `SyncFoodDTO.rating` 还是 `Int`，故 `rebuild` 里用 `Double(x.rating)` 兜底
- Task 3 里把 `SyncFoodDTO.rating` 改为 `Double`，同时移除兜底转换
- Task 6 抽 `MapsNavigator` 前 Task 2 里 `EditFoodSheet.openInMaps` 仍用旧代码；Task 6 Step 2 才切换到 `MapsNavigator`

**5. 破坏性变更检查：**
- `dataVersion` 2→3（Task 3）→ 老服务端解析新 payload 忽略新字段 OK；新客户端读老 payload 缺 `iconImageBase64`（Optional）→ nil OK；缺 `rating` 不会发生（老 payload 有 rating Int，Codable 兼容 Double 解码）
- SwiftData 迁移 fallback 会清空**整个** SwiftData store（含 Note / Todo / Password 等），仅在 `ModelContainer(...)` 抛错时触发；spec 已确认用户接受

---

## 备注

- Task 4 的 `default.store` 名称是 SwiftData 默认约定；若项目未来指定过 `ModelConfiguration(url:)` 则需要在 fallback 里同步修改删除路径。当前 `ModelConfiguration(schema:, isStoredInMemoryOnly: false)` 走默认路径，`default.store` 正确
- 相册 tab 用 `PhotosPicker` 不申请任何权限；相机 tab 走 `UIImagePickerController.sourceType = .camera`，权限用现有 `NSCameraUsageDescription`
- 半星交互算法：ZStack 里 Image 底层显示 + HStack 顶层两个 Color.clear tap 区，Image 加 `allowsHitTesting(false)` 让 tap 只走 HStack 层——避免 Image 抢事件
- `LocationPickerSheet` 与 `IconPickerSheet` 都放在 `Presentation/Views/SubPages/Food/` 下，模块归拢
