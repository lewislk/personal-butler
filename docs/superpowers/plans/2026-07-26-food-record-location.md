# 美食记录·位置录入 与 导航 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让美食记录在新增/编辑时支持 POI 搜索 + 地图选点两种方式录入位置，并支持从记录一键导航到该地点（Apple Maps）。

**Architecture:** `FoodRecord` 模型增加 4 个可选定位字段（`placeName / address / latitude / longitude`）；引入 `Core/Utils/LocationService.swift` 一次性抓取当前位置；`EditFoodSheet` 内新增「位置」Section 承载三个入口（搜索、当前位置、地图选点），全屏 `LocationPickerSheet` 承载地图选点；列表行 & 编辑弹窗联动导航按钮拉起 Apple Maps。同步契约 `SyncFoodDTO` 追加同 4 字段，`SyncMeta.dataVersion` 由 1 递增为 2。

**Tech Stack:** SwiftUI · SwiftData · MapKit（`Map` / `MKLocalSearch`）· CoreLocation（`CLLocationManager` / `CLGeocoder`）· UIKit（仅 `UIApplication.shared.open` 拉起 Maps 与跳系统设置）。

## Global Constraints

- iOS 最低版本 18；可用 iOS 18 新 API，不写 `if #available` 兜底
- 纯 SwiftUI；禁止引入 UIKit 视图层（仅允许 `UIApplication.shared.open` / `UIPasteboard` 这类系统集成 API）
- 存储：非敏感走 SwiftData；本次不新增 Keychain 项
- 网络：本次不涉及外网；`MKLocalSearch` / `CLGeocoder` 属苹果系统框架，视同系统 Maps 行为
- 权限申请文案统一简体中文；只申请 `WhenInUse`，不申请 `Always`
- SwiftData 字段：新增字段必须带默认值 / Optional，兼容旧数据；枚举/坐标铺平存储，不引入嵌套 struct
- 命名：文件名 = 主类型名；枚举 raw 值小写英文；View 内私有类型用 `private struct`
- 同步契约变更：只增不删、不改语义；变更 `SyncData` 任一 DTO 必须递增 `SyncMeta.dataVersion`
- Info.plist 通过 Xcode Target 的 `INFOPLIST_KEY_*` 配置（`project.pbxproj` 里已有 `INFOPLIST_KEY_NSCameraUsageDescription` 等参考），不新建 Info.plist 文件

## File Structure

```
Domain/Models/FoodRecord.swift                        ← 修改：+4 字段 + hasLocation/displayLocation
Data/Mapper/SyncPayload.swift                         ← 修改：SyncFoodDTO +4 字段
Domain/UseCases/BackupSyncUseCase.swift               ← 修改：dataVersion 1→2；buildPayload/rebuild 增字段
Core/Utils/LocationService.swift                      ← 新建：一次性抓取当前坐标
Presentation/Views/SubPages/FoodRecordView.swift      ← 修改：列表行位置行；把 EditFoodSheet 搬出
Presentation/Views/SubPages/Food/EditFoodSheet.swift  ← 新建（含从旧文件搬迁 + 位置 Section）
Presentation/Views/SubPages/Food/POISearchResults.swift ← 新建：MKLocalSearch 结果列表组件
Presentation/Views/SubPages/Food/LocationPickerSheet.swift ← 新建：全屏地图选点
docs/module-spec/module-backup-sync-spec.md           ← 修改：字段清单 + dataVersion 变更历史
personal-butler.xcodeproj/project.pbxproj             ← 修改：追加 INFOPLIST_KEY_NSLocationWhenInUseUsageDescription
```

---

### Task 1: 扩展 `FoodRecord` 模型（+4 字段 & 计算属性）

**Files:**
- Modify: `personal-butler/Domain/Models/FoodRecord.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `FoodRecord.placeName: String?`
  - `FoodRecord.address: String?`
  - `FoodRecord.latitude: Double?`
  - `FoodRecord.longitude: Double?`
  - `FoodRecord.hasLocation: Bool`（计算属性）
  - `FoodRecord.displayLocation: String?`（计算属性；优先返回 `address`，兜底 `placeName`）
  - `FoodRecord.init(...)` 签名末位追加：`placeName: String? = nil, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil`

- [ ] **Step 1: 修改 `FoodRecord.swift`，加字段 + 扩展 init**

打开 `personal-butler/Domain/Models/FoodRecord.swift`，把 `@Model final class FoodRecord { ... }` 整段替换为：

```swift
@Model
final class FoodRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var rating: Int
    var tagsRaw: String       // 逗号分隔
    var remark: String
    var date: Date
    var categoryRaw: String

    // 位置字段（全 Optional，兼容老数据；latitude / longitude 视为整体）
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?

    init(id: UUID = UUID(), name: String, emoji: String = "🍽️",
         rating: Int = 4, tags: [String] = [], remark: String = "",
         date: Date = .init(), category: FoodCategory = .chinese,
         placeName: String? = nil, address: String? = nil,
         latitude: Double? = nil, longitude: Double? = nil) {
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

- [ ] **Step 2: 验证编译（构建 App target）**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。（旧的 `FoodRecord(name:emoji:rating:tags:remark:category:)` 调用点因新参数全带默认值不会被破坏。）

- [ ] **Step 3: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Domain/Models/FoodRecord.swift && \
  git commit -m "feat(food): FoodRecord 新增 placeName/address/latitude/longitude 字段"
```

---

### Task 2: 同步契约 · `SyncFoodDTO` 增 4 字段 & `dataVersion` 1→2

**Files:**
- Modify: `personal-butler/Data/Mapper/SyncPayload.swift`
- Modify: `personal-butler/Domain/UseCases/BackupSyncUseCase.swift`

**Interfaces:**
- Consumes: Task 1 的 4 个字段
- Produces:
  - `SyncFoodDTO.placeName: String?`
  - `SyncFoodDTO.address: String?`
  - `SyncFoodDTO.latitude: Double?`
  - `SyncFoodDTO.longitude: Double?`
  - `SyncMeta.dataVersion == 2`

- [ ] **Step 1: 扩展 `SyncFoodDTO`**

打开 `personal-butler/Data/Mapper/SyncPayload.swift`，把 `struct SyncFoodDTO: Codable { ... }` 整段替换为：

```swift
struct SyncFoodDTO: Codable {
    var id: String
    var name: String
    var emoji: String
    var rating: Int
    var tags: [String]
    var remark: String
    var date: Double
    var category: String
    // 位置字段（Optional，向下兼容：老服务端/老备份缺字段解析为 nil）
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
}
```

- [ ] **Step 2: `BackupSyncUseCase.buildPayload` 组装映射带上 4 字段**

在 `personal-butler/Domain/UseCases/BackupSyncUseCase.swift`，把 `foodRecordList: foods.map { ... }` 那一小段替换为：

```swift
foodRecordList: foods.map {
    SyncFoodDTO(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                rating: $0.rating, tags: $0.tags, remark: $0.remark,
                date: $0.date.timeIntervalSince1970, category: $0.categoryRaw,
                placeName: $0.placeName, address: $0.address,
                latitude: $0.latitude, longitude: $0.longitude)
},
```

- [ ] **Step 3: `BackupSyncUseCase.rebuild` 反向映射带上 4 字段**

在 `personal-butler/Domain/UseCases/BackupSyncUseCase.swift`，把 `for x in data.foodRecordList { ... }` 那一小段替换为：

```swift
for x in data.foodRecordList {
    guard let uuid = UUID(uuidString: x.id) else { continue }
    let m = FoodRecord(
        id: uuid, name: x.name, emoji: x.emoji,
        rating: x.rating, tags: x.tags, remark: x.remark,
        date: Date(timeIntervalSince1970: x.date),
        category: FoodCategory(rawValue: x.category) ?? .chinese,
        placeName: x.placeName, address: x.address,
        latitude: x.latitude, longitude: x.longitude
    )
    context.insert(m)
}
```

- [ ] **Step 4: `SyncMeta.dataVersion` 递增**

在同一个文件，把：

```swift
let meta = SyncMeta(deviceId: AppSyncConfig.deviceID,
                    syncTimestamp: Int64(Date().timeIntervalSince1970),
                    appVersion: "1.0.0",
                    dataVersion: 1)
```

改成：

```swift
let meta = SyncMeta(deviceId: AppSyncConfig.deviceID,
                    syncTimestamp: Int64(Date().timeIntervalSince1970),
                    appVersion: "1.0.0",
                    dataVersion: 2)
```

- [ ] **Step 5: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 6: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Data/Mapper/SyncPayload.swift \
          personal-butler/Domain/UseCases/BackupSyncUseCase.swift && \
  git commit -m "feat(sync): SyncFoodDTO 增加位置字段，dataVersion 1→2"
```

---

### Task 3: 新建 `LocationService` · 一次性抓取当前坐标

**Files:**
- Create: `personal-butler/Core/Utils/LocationService.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum LocationError: Error { case denied, unavailable, timeout }`
  - `final class LocationService: NSObject`
  - `static let LocationService.shared: LocationService`
  - `func LocationService.requestOneShot() async throws -> CLLocationCoordinate2D`（成功返回坐标；权限拒绝 → `.denied`；系统关服务 → `.unavailable`；15s 未返回 → `.timeout`）

- [ ] **Step 1: 新建 `LocationService.swift`**

创建 `personal-butler/Core/Utils/LocationService.swift`，内容：

```swift
//
//  LocationService.swift
//  一次性抓取当前坐标（Foreground WhenInUse），供美食记录位置录入使用。
//

import Foundation
import CoreLocation

enum LocationError: Error, LocalizedError {
    case denied         // 用户拒绝 / 家长控制限制
    case unavailable    // 系统定位服务关闭 / 无法定位
    case timeout        // 15s 未返回

    var errorDescription: String? {
        switch self {
        case .denied:      return "位置权限未开启"
        case .unavailable: return "无法获取当前位置"
        case .timeout:     return "定位超时，请重试"
        }
    }
}

/// 一次性定位服务：调用 `requestOneShot()` 返回一次坐标后自动 `stopUpdatingLocation`。
/// 不做持续监听，不订阅方向 / 大范围变化，不申请 `Always` 权限。
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // 餐厅粒度足够
    }

    func requestOneShot() async throws -> CLLocationCoordinate2D {
        // 已在跑一次抓取：拒绝并发调用
        if continuation != nil {
            throw LocationError.unavailable
        }

        // 权限检查 / 申请
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // 等待用户回应；didChangeAuthorization 会驱动后续
        case .denied, .restricted:
            throw LocationError.denied
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            throw LocationError.unavailable
        }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            // 只有已授权时才立即请求；未定则等 didChangeAuthorization 回调再请求
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }

            // 15s 超时兜底
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                await MainActor.run {
                    self?.finish(with: .failure(LocationError.timeout))
                }
            }
        }
    }

    private func finish(with result: Result<CLLocationCoordinate2D, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let cont = continuation else { return }
        continuation = nil
        switch result {
        case .success(let c): cont.resume(returning: c)
        case .failure(let e): cont.resume(throwing: e)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                // 用户刚同意：真正发起请求
                if self.continuation != nil { self.manager.requestLocation() }
            case .denied, .restricted:
                self.finish(with: .failure(LocationError.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor [weak self] in
            self?.finish(with: .success(coord))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: .failure(LocationError.unavailable))
        }
    }
}
```

- [ ] **Step 2: 追加 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` 到两个 target configuration**

打开 `personal-butler.xcodeproj/project.pbxproj`，找到两处（Debug / Release 各一）已存在的：

```
INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "用于选择美食记录配图";
```

在**每一处**紧随其后（同缩进）加一行：

```
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "美食记录需要在录入时读取当前位置，用于快速填充店铺地址。位置数据仅保存在本地。";
```

（`project.pbxproj` 里有两段 `XCBuildConfiguration`，都要加。用 grep 定位两处 `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` 即可。）

- [ ] **Step 3: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Core/Utils/LocationService.swift \
          personal-butler.xcodeproj/project.pbxproj && \
  git commit -m "feat(core): 新增 LocationService 一次性抓取当前坐标 + 前台定位权限文案"
```

---

### Task 4: 从 `FoodRecordView.swift` 搬出 `EditFoodSheet.swift`（不改行为）

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/FoodRecordView.swift`
- Create: `personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift`

**Interfaces:**
- Consumes: 无（纯搬家）
- Produces: `struct EditFoodSheet: View`（签名同今日：`init(record: FoodRecord?)`），行为不变

- [ ] **Step 1: 新建 `Food/EditFoodSheet.swift`（把旧文件里 EditFoodSheet 段落逐字搬入）**

创建 `personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift`，内容为 `FoodRecordView.swift` 中从 `// MARK: - 新增 / 编辑美食记录弹窗` 开始到文件末尾的 `struct EditFoodSheet` 整段（含 `emojiPicker` / `starRating`），并在顶部加：

```swift
//
//  EditFoodSheet.swift
//  美食记录 · 新增 / 编辑弹窗
//

import SwiftUI
import SwiftData
```

（此步骤 100% 逐字搬迁，不做任何行为改动；位置 Section 在 Task 5 才加。）

- [ ] **Step 2: 从 `FoodRecordView.swift` 删除 `EditFoodSheet` 段**

编辑 `personal-butler/Presentation/Views/SubPages/FoodRecordView.swift`，删除从 `// MARK: - 新增 / 编辑美食记录弹窗` 开始到文件末尾（含 `struct EditFoodSheet`）的整段。保留文件顶部 `import` 和 `struct FoodRecordView` 部分。

- [ ] **Step 3: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。（`FoodRecordView` 里的 `EditFoodSheet(record: nil)` / `EditFoodSheet(record: r)` 现在跨文件访问同 target 里的 `struct EditFoodSheet`，Swift 会解析成功。）

- [ ] **Step 4: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/FoodRecordView.swift \
          personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift && \
  git commit -m "refactor(food): 把 EditFoodSheet 搬出到独立文件"
```

---

### Task 5: POI 搜索结果组件 `POISearchResults`

**Files:**
- Create: `personal-butler/Presentation/Views/SubPages/Food/POISearchResults.swift`

**Interfaces:**
- Consumes: 无
- Produces: `struct POISearchResults: View`
  - `init(query: String, region: MKCoordinateRegion?, onPick: @escaping (SelectedLocation) -> Void)`
  - 内部私有类型 `SelectedLocation` 是模块级 struct（本任务在同文件内定义并对外暴露）：
    - `struct SelectedLocation { let placeName: String?; let address: String?; let latitude: Double; let longitude: Double }`
    - 该 struct 后续被 Task 6/7 消费；因此在本文件顶部声明为**非私有**

- [ ] **Step 1: 新建 `POISearchResults.swift`**

创建 `personal-butler/Presentation/Views/SubPages/Food/POISearchResults.swift`，内容：

```swift
//
//  POISearchResults.swift
//  POI 搜索结果列表（MKLocalSearch），供 EditFoodSheet 内联使用。
//

import SwiftUI
import MapKit

/// 位置选择结果：跨组件传递（POISearchResults / LocationPickerSheet → EditFoodSheet）
struct SelectedLocation: Equatable {
    let placeName: String?
    let address: String?
    let latitude: Double
    let longitude: Double
}

struct POISearchResults: View {
    /// 当前搜索关键字（外部驱动，本组件不管输入框）
    let query: String
    /// 搜索的 region（当前定位附近 / 兜底默认区域）
    let region: MKCoordinateRegion?
    /// 用户点选后回调，父视图负责收起搜索
    let onPick: (SelectedLocation) -> Void

    @State private var items: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSearching {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("搜索中…")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColorTheme.textSub)
                }
                .padding(.vertical, 8)
            } else if items.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("未找到匹配地点")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                    Button {
                        onPick(Self.mapItemToLocation(item))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "未命名地点")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColorTheme.text)
                                .lineLimit(1)
                            Text(Self.formatAddress(item.placemark))
                                .font(.system(size: 12))
                                .foregroundStyle(AppColorTheme.textSub)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().foregroundStyle(Color.black.opacity(0.04))
                }
            }
        }
        .onChange(of: query) { _, newValue in
            triggerSearch(newValue)
        }
        .onAppear { triggerSearch(query) }
        .onDisappear { searchTask?.cancel() }
    }

    // 防抖 300ms 触发搜索
    private func triggerSearch(_ raw: String) {
        searchTask?.cancel()
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            items = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = text
            if let region {
                req.region = region
            }
            do {
                let resp = try await MKLocalSearch(request: req).start()
                if Task.isCancelled { return }
                await MainActor.run {
                    self.items = resp.mapItems
                    self.isSearching = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.items = []
                    self.isSearching = false
                }
            }
        }
    }

    static func mapItemToLocation(_ item: MKMapItem) -> SelectedLocation {
        let coord = item.placemark.coordinate
        return SelectedLocation(
            placeName: item.name,
            address: formatAddress(item.placemark),
            latitude: coord.latitude,
            longitude: coord.longitude
        )
    }

    /// 从 CLPlacemark 拼出中文可读地址：administrativeArea + locality + subLocality + thoroughfare + subThoroughfare
    static func formatAddress(_ p: CLPlacemark) -> String {
        [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare]
            .compactMap { $0 }
            .joined()
    }
}
```

- [ ] **Step 2: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/Food/POISearchResults.swift && \
  git commit -m "feat(food): 新增 POISearchResults 组件（MKLocalSearch 结果列表）"
```

---

### Task 6: 地图选点全屏 sheet `LocationPickerSheet`

**Files:**
- Create: `personal-butler/Presentation/Views/SubPages/Food/LocationPickerSheet.swift`

**Interfaces:**
- Consumes: `SelectedLocation`（Task 5）
- Produces: `struct LocationPickerSheet: View`
  - `init(initial: SelectedLocation?, onConfirm: @escaping (SelectedLocation) -> Void)`
  - 内部行为：全屏地图 + 中心大头针 + 顶部搜索栏 + 底部反解地址卡片 + 顶部工具栏「取消 / 确定」

- [ ] **Step 1: 新建 `LocationPickerSheet.swift`**

创建 `personal-butler/Presentation/Views/SubPages/Food/LocationPickerSheet.swift`，内容：

```swift
//
//  LocationPickerSheet.swift
//  美食记录 · 地图选点（方案 B）
//
//  中心大头针固定屏幕正中；拖地图 → 松手后反解地址；顶部搜索可快速跳转区域。
//

import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: SelectedLocation?
    let onConfirm: (SelectedLocation) -> Void

    // 地图相机（用 position + region 双读；region 用于 MKLocalSearch，coord 用于反解）
    @State private var camera: MapCameraPosition
    @State private var centerCoord: CLLocationCoordinate2D
    @State private var currentRegion: MKCoordinateRegion?

    // 搜索
    @State private var query: String = ""
    @State private var showResults: Bool = false

    // 反解
    @State private var revLabel: String = "拖动地图选择位置"
    @State private var revSubLabel: String = ""
    @State private var revTask: Task<Void, Never>?
    @State private var lastRevCoord: CLLocationCoordinate2D?

    init(initial: SelectedLocation?,
         onConfirm: @escaping (SelectedLocation) -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        // 有传入位置就用它；否则用一个默认区域（北京市中心，跨度 10km）
        let coord = initial.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        _centerCoord = State(initialValue: coord)
        _camera = State(initialValue: .region(
            MKCoordinateRegion(center: coord,
                               span: MKCoordinateSpan(latitudeDelta: 0.05,
                                                     longitudeDelta: 0.05))
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $camera)
                    .mapControls { MapCompass() }
                    .onMapCameraChange { ctx in
                        centerCoord = ctx.camera.centerCoordinate
                        currentRegion = ctx.region
                        scheduleReverseGeocode(ctx.camera.centerCoordinate)
                    }
                    .ignoresSafeArea(edges: .bottom)

                // 屏幕中心固定大头针（不随地图移动）
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColorTheme.primary)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    searchBar
                    if showResults {
                        POISearchResults(query: query, region: currentRegion) { picked in
                            applyPicked(picked)
                            showResults = false
                            query = ""
                        }
                        .padding(.horizontal, 12)
                        .background(Color.white)
                    }
                    Spacer()
                    bottomCard
                }
            }
            .navigationTitle("地图选点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onConfirm(SelectedLocation(
                            placeName: initial?.placeName,     // 拖点没有 POI 名，保留原始名（若从已选处进入）
                            address: revLabel == "拖动地图选择位置" ? nil : revLabel,
                            latitude: centerCoord.latitude,
                            longitude: centerCoord.longitude
                        ))
                        dismiss()
                    }
                }
            }
            .onAppear {
                scheduleReverseGeocode(centerCoord)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColorTheme.textSub)
            TextField("搜索地点", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onChange(of: query) { _, v in
                    showResults = !v.trimmingCharacters(in: .whitespaces).isEmpty
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    showResults = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColorTheme.textSub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(AppColorTheme.primary)
                Text(revLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                    .lineLimit(1)
            }
            if !revSubLabel.isEmpty {
                Text(revSubLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColorTheme.border).frame(height: 0.5)
        }
    }

    private func applyPicked(_ picked: SelectedLocation) {
        centerCoord = CLLocationCoordinate2D(latitude: picked.latitude,
                                             longitude: picked.longitude)
        camera = .region(MKCoordinateRegion(
            center: centerCoord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        revLabel = picked.placeName ?? picked.address ?? "已选择位置"
        revSubLabel = picked.address ?? ""
    }

    private func scheduleReverseGeocode(_ coord: CLLocationCoordinate2D) {
        // 距上次反解 <20m 时不重复请求，节省 CLGeocoder 配额
        if let last = lastRevCoord {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if a.distance(from: b) < 20 { return }
        }
        lastRevCoord = coord
        revTask?.cancel()
        revTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)   // 防抖 500ms
            if Task.isCancelled { return }
            let geo = CLGeocoder()
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let placemarks = try? await geo.reverseGeocodeLocation(loc)
            guard let p = placemarks?.first else { return }
            let addr = POISearchResults.formatAddress(p)
            let name = p.name ?? addr
            await MainActor.run {
                self.revLabel = name.isEmpty ? "已选择位置" : name
                self.revSubLabel = addr == name ? "" : addr
            }
        }
    }
}
```

- [ ] **Step 2: 构建验证**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/Food/LocationPickerSheet.swift && \
  git commit -m "feat(food): 新增 LocationPickerSheet 地图选点全屏 sheet"
```

---

### Task 7: `EditFoodSheet` 集成「位置」Section + 「导航到这里」按钮

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift`

**Interfaces:**
- Consumes: `LocationService.shared.requestOneShot()`（Task 3）；`POISearchResults`（Task 5）；`SelectedLocation`（Task 5）；`LocationPickerSheet`（Task 6）
- Produces: 无（内部改造）

- [ ] **Step 1: 在 `EditFoodSheet` 顶部加 import**

在 `personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift` 顶部现有 `import SwiftUI` / `import SwiftData` 后追加：

```swift
import MapKit
import CoreLocation
```

- [ ] **Step 2: `EditFoodSheet` 内新增 4 个位置字段 State + UI 交互 State**

把现有 State 段（`@State private var name: String` … `@State private var remark: String`）之后追加：

```swift
@State private var placeName: String?
@State private var address: String?
@State private var latitude: Double?
@State private var longitude: Double?

// 位置 UI 交互
@State private var poiQuery: String = ""
@State private var showPOIResults: Bool = false
@State private var showMapPicker: Bool = false
@State private var showChangeActions: Bool = false
@State private var locationErrorText: String?
@State private var isFetchingCurrent: Bool = false
```

并在 `init(record:)` 里追加初始化：

```swift
_placeName = State(initialValue: record?.placeName)
_address = State(initialValue: record?.address)
_latitude = State(initialValue: record?.latitude)
_longitude = State(initialValue: record?.longitude)
```

- [ ] **Step 3: 在 Form 中插入「位置」Section**

在 Form 里 `Section { Picker("分类", selection: $category) { ... } }` 与 `Section { TextField("标签...") ...}` 之间插入新 Section：

```swift
Section("位置") {
    if hasLocation {
        // 已录入卡片 + 修改/清除
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundStyle(AppColorTheme.primary)
                Text(placeName ?? address ?? "已选择位置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                Spacer()
                Button("修改") { showChangeActions = true }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))
                Button {
                    clearLocation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColorTheme.textSub)
                }
                .buttonStyle(.borderless)
            }
            if let a = address, a != placeName {
                Text(a).font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
            }
        }

        Button {
            openInMaps()
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                Text("导航到这里")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(AppColorTheme.primary)
        }
    } else {
        // 未录入：三入口
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColorTheme.textSub)
            TextField("搜索附近地点", text: $poiQuery)
                .onChange(of: poiQuery) { _, v in
                    showPOIResults = !v.trimmingCharacters(in: .whitespaces).isEmpty
                }
        }
        if showPOIResults {
            POISearchResults(query: poiQuery, region: nil) { picked in
                apply(picked)
                showPOIResults = false
                poiQuery = ""
            }
        }
        Button {
            useCurrentLocation()
        } label: {
            HStack {
                if isFetchingCurrent {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "location.fill")
                }
                Text(isFetchingCurrent ? "获取中…" : "使用当前位置")
            }
        }
        Button {
            showMapPicker = true
        } label: {
            HStack {
                Image(systemName: "map.fill")
                Text("地图选点")
            }
        }
        if let err = locationErrorText {
            HStack {
                Text(err).font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xD9534F))
                Spacer()
                if err.contains("权限") {
                    Button("去设置") { openSystemSettings() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                }
            }
        }
    }
}
```

- [ ] **Step 4: 在 `body` 的 `NavigationStack { Form { ... } .toolbar ... }` 末端挂载 sheet / confirmationDialog**

在 `.toolbar { ... }` 之后加：

```swift
.sheet(isPresented: $showMapPicker) {
    LocationPickerSheet(initial: currentSelected) { picked in
        apply(picked)
    }
}
.confirmationDialog("修改位置", isPresented: $showChangeActions, titleVisibility: .visible) {
    Button("搜索地点") {
        clearLocation()
        showPOIResults = false     // 用户再手动展开
    }
    Button("使用当前位置") {
        useCurrentLocation()
    }
    Button("地图选点") {
        showMapPicker = true
    }
    Button("取消", role: .cancel) {}
}
```

- [ ] **Step 5: 补齐辅助计算属性 + 私有方法**

在 `EditFoodSheet` 的 `save()` 之前，追加：

```swift
private var hasLocation: Bool { latitude != nil && longitude != nil }

private var currentSelected: SelectedLocation? {
    guard let lat = latitude, let lng = longitude else { return nil }
    return SelectedLocation(placeName: placeName, address: address,
                            latitude: lat, longitude: lng)
}

private func apply(_ picked: SelectedLocation) {
    placeName = picked.placeName
    address = picked.address
    latitude = picked.latitude
    longitude = picked.longitude
    locationErrorText = nil
}

private func clearLocation() {
    placeName = nil; address = nil
    latitude = nil; longitude = nil
    locationErrorText = nil
}

private func useCurrentLocation() {
    guard !isFetchingCurrent else { return }
    isFetchingCurrent = true
    locationErrorText = nil
    Task {
        do {
            let coord = try await LocationService.shared.requestOneShot()
            let geo = CLGeocoder()
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let placemarks = try? await geo.reverseGeocodeLocation(loc)
            let p = placemarks?.first
            let picked = SelectedLocation(
                placeName: p?.name,
                address: p.map { POISearchResults.formatAddress($0) },
                latitude: coord.latitude,
                longitude: coord.longitude
            )
            await MainActor.run {
                apply(picked)
                isFetchingCurrent = false
            }
        } catch let err as LocationError {
            await MainActor.run {
                isFetchingCurrent = false
                switch err {
                case .denied:      locationErrorText = "位置权限未开启"
                case .unavailable: locationErrorText = "无法获取当前位置"
                case .timeout:     locationErrorText = "定位超时，请重试"
                }
            }
        } catch {
            await MainActor.run {
                isFetchingCurrent = false
                locationErrorText = "无法获取当前位置"
            }
        }
    }
}

private func openSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}

private func openInMaps() {
    guard let lat = latitude, let lng = longitude else { return }
    let q = (placeName ?? address ?? "")
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    guard let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(lat),\(lng)") else { return }
    UIApplication.shared.open(url)
}
```

- [ ] **Step 6: `save()` 也写入 4 个位置字段**

把 `EditFoodSheet.save()` 整段替换为：

```swift
private func save() {
    let finalName = name.isEmpty ? "未命名" : name
    let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    if let r = record {
        r.name = finalName
        r.emoji = emoji
        r.rating = rating
        r.tagsRaw = tagList.joined(separator: ",")
        r.remark = remark
        r.categoryRaw = category.rawValue
        r.placeName = placeName
        r.address = address
        r.latitude = latitude
        r.longitude = longitude
    } else {
        let f = FoodRecord(name: finalName,
                           emoji: emoji, rating: rating,
                           tags: tagList,
                           remark: remark, category: category,
                           placeName: placeName, address: address,
                           latitude: latitude, longitude: longitude)
        context.insert(f)
    }
    try? context.save()
}
```

- [ ] **Step 7: 构建 & 手测**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。

模拟器手测：
- 新增美食：位置 Section 展示 3 个入口
- 点「使用当前位置」→ 首次触发权限弹窗（模拟器需 Features → Location → Custom Location 设一个坐标）→ 完成后卡片显示地址 + 「导航到这里」
- 点「地图选点」→ 全屏 sheet 出现；拖地图，底部地址跟随刷新
- 点顶部搜索栏输入"星巴克" → 结果出来 → 点一条，地图跳到该点
- 「导航到这里」→ 拉起 Apple Maps

- [ ] **Step 8: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/Food/EditFoodSheet.swift && \
  git commit -m "feat(food): EditFoodSheet 新增位置录入 Section 与导航按钮"
```

---

### Task 8: 列表行显示位置

**Files:**
- Modify: `personal-butler/Presentation/Views/SubPages/FoodRecordView.swift`

**Interfaces:**
- Consumes: `FoodRecord.hasLocation` / `FoodRecord.displayLocation`（Task 1）
- Produces: 无

- [ ] **Step 1: 在 `FoodRecordView.row(_:)` 中追加位置行**

在 `personal-butler/Presentation/Views/SubPages/FoodRecordView.swift` 的 `row(_ f: FoodRecord)` 里，把 `VStack(alignment: .leading, spacing: 6) { ... }` 内 `if !f.remark.isEmpty { ... }` 之后追加一段：

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

- [ ] **Step 2: 构建 & 手测**

Run:

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  xcodebuild -project personal-butler.xcodeproj -scheme personal-butler \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: BUILD SUCCEEDED。

模拟器手测：
- 已录入位置的记录，列表行底部出现「📍 地址」一行；未录入的记录不显示。

- [ ] **Step 3: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add personal-butler/Presentation/Views/SubPages/FoodRecordView.swift && \
  git commit -m "feat(food): 列表行显示位置行（有位置时）"
```

---

### Task 9: 文档同步 · `module-backup-sync-spec.md` 更新字段与版本历史

**Files:**
- Modify: `docs/module-spec/module-backup-sync-spec.md`

**Interfaces:**
- Consumes: 无
- Produces: 无

- [ ] **Step 1: 打开 `docs/module-spec/module-backup-sync-spec.md`，找到描述 `SyncFoodDTO` 字段的段落**

如果文档里明确列出了 `SyncFoodDTO` 的字段清单，把该清单末尾追加：

```
- placeName?: String   POI 名称，dataVersion ≥ 2 起
- address?: String     结构化地址，dataVersion ≥ 2 起
- latitude?: Double    WGS84 纬度，dataVersion ≥ 2 起
- longitude?: Double   WGS84 经度，dataVersion ≥ 2 起
```

在描述 `SyncMeta.dataVersion` 或"变更历史"的段落追加一行：

```
- v2 (2026-07-26): SyncFoodDTO 增加 placeName / address / latitude / longitude 四个可选字段（美食记录位置录入）
```

（若文档中没有对应段落，则在文档末尾新增一节「变更历史」并写入上述条目。）

- [ ] **Step 2: 提交**

```bash
cd /Users/lewis/XCodeProjects/personal-butler && \
  git add docs/module-spec/module-backup-sync-spec.md && \
  git commit -m "docs(sync): SyncFoodDTO 新增位置字段 + dataVersion 变更历史"
```

---

### Task 10: 更新 `AGENTS.md` § 7 已知 MVP 状态表（本次消耗一项占位）

**Files:**
- Modify: `AGENTS.md`（可选。若不涉及则跳过，本任务标可选。）

**Interfaces:**
- Consumes: 无
- Produces: 无

*说明：AGENTS.md § 7 目前没有列到"美食记录无位置字段"，本次也没消掉表中任一现存条目；此任务仅在验证时若发现相关矛盾条目再执行。默认跳过。*

- [ ] **Step 1: 查看 `AGENTS.md` § 7 是否有相关条目需调整**

Run:

```bash
grep -n "美食\|FoodRecord" /Users/lewis/XCodeProjects/personal-butler/AGENTS.md
```

Expected: 若无相关条目，跳过 Step 2 & Step 3；若有，按当前实现校正。

- [ ] **Step 2: （条件性）修改 `AGENTS.md`**

（跳过或按需修改）

- [ ] **Step 3: （条件性）提交**

（跳过或按需提交）

---

## Self-Review

- **Spec 覆盖：**
  - 数据模型变更 → Task 1 ✅
  - 同步契约变更（DTO + dataVersion + build/rebuild）→ Task 2 ✅
  - 权限（Info.plist）→ Task 3 Step 2 ✅
  - `LocationService` 一次性抓取 → Task 3 ✅
  - `POISearchResults` 方案 A → Task 5 ✅
  - `LocationPickerSheet` 方案 B → Task 6 ✅
  - 编辑弹窗位置 Section + 三入口 + 修改/清除/导航 → Task 7 ✅
  - 列表行位置显示 → Task 8 ✅
  - 顺手重构 `EditFoodSheet` 搬家 → Task 4 ✅
  - 同步契约文档更新 → Task 9 ✅
  - "导航到这里" 用 `http://maps.apple.com/?q=...&ll=...` → Task 7 Step 5 ✅
  - 权限降级"去设置" → Task 7 Step 5 `openSystemSettings()` ✅
  - 手动验证清单 → 各 Task Step 分散手测 ✅
  - YAGNI 项（不做多导航 App / 缓存 / 距离排序等） → 未新增，符合 ✅

- **类型一致性：**
  - `SelectedLocation` 从 Task 5 定义，Task 6/7 消费，字段与名称一致 ✅
  - `LocationError` 从 Task 3 定义（`.denied / .unavailable / .timeout`），Task 7 完整分支消费 ✅
  - `FoodRecord.hasLocation` / `displayLocation` 名称在 Task 1 定义、Task 8 消费一致 ✅
  - `LocationService.shared.requestOneShot()` 签名 Task 3 定义、Task 7 消费一致 ✅
  - `POISearchResults.formatAddress` 静态方法在 Task 5 定义、Task 6/7 消费 ✅

- **placeholder 扫描：** 无 TBD / TODO；每个代码步骤都给了完整可粘贴的代码 ✅

- **文件路径：** 所有路径为项目实际路径（`personal-butler/...` 下）✅

---

## 备注：非 XCTest 项目的验证

本项目当前未搭建 XCTest 基建（AGENTS.md §10），故本 plan 每个 Task 用 `xcodebuild ... build` 验证编译通过，功能层面靠模拟器手测 checklist 兜底，与项目现状一致。
