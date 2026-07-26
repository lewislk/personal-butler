# 美食记录·位置录入 与 导航 · 设计

> 状态：待实现｜作者：AI 助手 + liukun｜日期：2026-07-26
> 影响模块：`FoodRecord` 域、美食记录 UI、备份同步契约、系统权限

---

## 1. 目标

在**新增 / 编辑美食记录**时支持录入位置（POI 搜索 + 地图选点两种方式），后续可从记录中一键**导航到该地点**（Apple Maps）。

覆盖两类真实场景：
1. **现场即时录入** —— 一键"使用当前位置"或 POI 搜索附近店铺
2. **事后补录** —— 通过 POI 名称搜索 或 地图上手动选点

---

## 2. 数据模型变更

### 2.1 `FoodRecord`（`Domain/Models/FoodRecord.swift`）

新增 4 个可选字段，向下兼容老数据：

```swift
var placeName: String?   // POI 名称（地图上的正式名称，与 name 语义分离：
                         //   name = 用户记的菜品/店铺记忆点
                         //   placeName = 地图上返回的正式店名）
var address: String?     // 结构化地址（示例："北京市朝阳区工体北路 4 号"）
var latitude: Double?    // WGS84 纬度
var longitude: Double?   // WGS84 经度
```

**约束：**
- 全部 Optional，无位置的老记录 / 用户不填时保持 `nil`
- `latitude` 与 `longitude` 视为整体：保存时校验"要么都有要么都无"，`address` / `placeName` 允许独立缺失
- 不引入嵌套 `struct Location` —— 与现有 `ScheduleEvent` / `Anniversary` 铺平字段风格一致，规避 SwiftData 对嵌套值类型的处理不稳定问题

**计算属性：**

```swift
extension FoodRecord {
    var hasLocation: Bool { latitude != nil && longitude != nil }
    var displayLocation: String? {
        address ?? placeName   // 列表行位置行显示优先级
    }
}
```

### 2.2 `init` 签名扩展

```swift
init(id: UUID = UUID(),
     name: String,
     emoji: String = "🍽️",
     rating: Int = 4,
     tags: [String] = [],
     remark: String = "",
     date: Date = .init(),
     category: FoodCategory = .chinese,
     placeName: String? = nil,
     address: String? = nil,
     latitude: Double? = nil,
     longitude: Double? = nil)
```

四个新参数放末位并给默认值 `nil`，不破坏现有调用点。

---

## 3. 同步契约变更

### 3.1 `SyncFoodDTO`（`Data/Mapper/SyncPayload.swift`）

追加 4 个可选字段：

```swift
struct SyncFoodDTO: Codable {
    // ... 已有字段
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
}
```

### 3.2 `SyncMeta.dataVersion`

- 当前值：`1`（见 `BackupSyncUseCase.buildPayload`）
- 变更后：`2`
- 递增位置：`BackupSyncUseCase.buildPayload` 中 `SyncMeta(dataVersion: 1)` → `SyncMeta(dataVersion: 2)`

### 3.3 `BackupSyncUseCase`

- `buildPayload` 中 `FoodRecord → SyncFoodDTO` 时映射 4 个新字段
- 下载 / 解析路径（`applyPayload` 或等价方法）反向映射，老备份缺字段则保持 `nil`

### 3.4 文档同步

- 更新 [`docs/module-spec/module-backup-sync-spec.md`](../../module-spec/module-backup-sync-spec.md)：在 `SyncFoodDTO` 段落列出 4 个新字段 + `dataVersion` 变更历史
- 服务端向下兼容：新客户端 → 旧服务端时字段透传（服务端仅存 JSON blob，不解析字段）；新客户端 → 旧备份时字段为 `nil`

---

## 4. UI 设计

### 4.1 编辑弹窗新增「位置」Section

位置：`EditFoodSheet` 内，位于「分类」Section 之后、「标签/备注」Section 之前。

**未录入状态：**

```
┌─ 位置 ────────────────────────────────┐
│  🔍 搜索附近地点        (输入框)         │
│  📍 使用当前位置                        │
│  🗺  地图选点                          │
└───────────────────────────────────────┘
```

**已录入状态：**

```
┌─ 位置 ────────────────────────────────┐
│  ┌─────────────────────────────┐      │
│  │ 📍 金鼎轩（工体店）           │      │
│  │    北京市朝阳区工体北路 4 号   │      │
│  │                    [修改][✕] │      │
│  └─────────────────────────────┘      │
│  ┌─────────────────────────────┐      │
│  │   🧭  导航到这里              │      │
│  └─────────────────────────────┘      │
└───────────────────────────────────────┘
```

### 4.2 方案 A · POI 搜索（同页展开）

- 输入框触发 `MKLocalSearch`，**防抖 300ms**
- `MKLocalSearch.Request`：`naturalLanguageQuery` = 输入文本，`region` 优先使用当前定位取的中心（无权限则用一个默认 `MKCoordinateRegion` 兜底，如国内某默认中心 + 大 span）
- 结果列表最多 8 条：每行显示 `MKMapItem.name` + `placemark` 拼装的地址
- 点选 → 填充 `placeName / address / latitude / longitude` 到 `@State`，收起搜索结果
- 输入框内容为空或用户点其他入口时也收起

### 4.3 方案 B · 地图选点（推 `.sheet` 全屏）

组件：`LocationPickerSheet`

```
┌─────────────────────────────────────┐
│  取消    地图选点            确定    │  ← 顶部工具栏
├─────────────────────────────────────┤
│  🔍 搜索地点               (输入框)  │  ← 复用 MKLocalSearch
├─────────────────────────────────────┤
│                                     │
│              ▼                      │  ← 屏幕正中央固定大头针
│           (地图)                     │
│                                     │
├─────────────────────────────────────┤
│  📍 金鼎轩（工体店）                  │  ← Sticky 底部卡片
│  北京市朝阳区工体北路 4 号             │     反解结果
└─────────────────────────────────────┘
```

- SwiftUI `Map` + `MapReader`；大头针以 overlay 形式贴屏幕中心，不随地图移动
- 用户拖地图 → 松手后 `CLGeocoder.reverseGeocodeLocation(centerCoordinate)`，防抖 500ms
- 顶部搜索：`MKLocalSearch` → 结果点击后 `setRegion` 平移到该点，用户可再微调
- 「确定」→ 通过 completion 回传 `(placeName?, address?, lat, lng)` 后 dismiss
- 「取消」→ 直接 dismiss，不修改父页面 `@State`

### 4.4 「📍 使用当前位置」

- 触发 `LocationService.requestOneShot()`
- 首次调用时系统弹权限对话框
- 成功：`CLGeocoder.reverseGeocodeLocation(coord)` 反解出地址 → 填充 4 个字段
- 失败（权限拒绝 / 定位超时）：Toast 或按钮下方红字提示，附「去设置」链接

### 4.5 「修改」/「✕」

**「修改」按钮：**
- 弹出 `confirmationDialog`（底部 action sheet）：
  - 「搜索地点」→ 展开搜索框（复用 4.2）
  - 「使用当前位置」→ 复用 4.4
  - 「地图选点」→ 打开 `LocationPickerSheet`
  - 「取消」

**「✕」按钮：**
- 直接置 4 个字段为 `nil`，回到未录入态

### 4.6 列表行位置显示（`FoodRecordView.row`）

在评分 / 标签 / 备注下方，条件渲染一行：

```swift
if let loc = f.displayLocation, f.hasLocation {
    HStack(spacing: 4) {
        Image(systemName: "location.fill")
        Text(loc).lineLimit(1)
    }
    .font(.system(size: 12))
    .foregroundStyle(AppColorTheme.textSub)
}
```

无位置的记录不渲染此行，不占空间。

### 4.7 「导航到这里」按钮

- 只在已录入位置（`hasLocation == true`）时显示
- 位置：编辑弹窗内位置卡片下方独立 Section
- 行为：

```swift
let lat = latitude!, lng = longitude!
let q = (placeName ?? address ?? "").addingPercentEncoding(...) ?? ""
let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(lat),\(lng)")!
UIApplication.shared.open(url)
```

- 用 `http://maps.apple.com/` 而非 `maps://`：系统自动路由到 Maps.app，且不装 Maps 时有 Web 兜底
- 不做多导航 App 选择器（YAGNI）

**新增记录未保存时可否导航？** 可以。按钮读的是 `@State` 里的 4 个字段，不依赖记录 insert，符合直觉。

---

## 5. 权限

### 5.1 Info.plist

追加：

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>美食记录需要在录入时读取当前位置，用于快速填充店铺地址。位置数据仅保存在本地。</string>
```

只申请 `WhenInUse`，不申请 `Always` / `AlwaysAndWhenInUse`。

### 5.2 降级策略

| 场景 | 表现 |
|------|------|
| 首次点「使用当前位置」/「地图选点」 | 触发系统权限弹窗 |
| 用户同意 | 正常获取定位 |
| 用户拒绝 | 「使用当前位置」按钮转灰，副文案"位置权限未开启，去设置"，点击跳 `UIApplication.openSettingsURLString` |
| 权限未开启时使用「POI 搜索」/「地图选点」 | 依然可用，但地图初始中心 / 搜索 region 使用兜底默认值 |

---

## 6. 代码组织

### 6.1 新增文件

```
Core/Utils/LocationService.swift              ← CLLocationManager 一次性定位封装
Presentation/Views/SubPages/Food/
  ├─ LocationPickerSheet.swift                ← 方案 B：地图选点 sheet
  └─ POISearchResults.swift                   ← 方案 A：搜索结果 List（供 EditFoodSheet 内联）
```

`LocationService` 只暴露一个 API：

```swift
enum LocationError: Error { case denied, unavailable, timeout }

final class LocationService: NSObject {
    static let shared = LocationService()
    func requestOneShot() async throws -> CLLocationCoordinate2D
}
```

内部管理 `CLLocationManager` + delegate；`requestOneShot` 是纯一次性抓取（不持续监听），完成后释放。首次调用时会自动申请权限。

### 6.2 顺手重构

`FoodRecordView.swift` 当前 293 行，承载列表 + 编辑弹窗两大块。本次叠加位置录入后会突破可维护阈值。

**同步做的搬家（不改 API、不改行为）：**

```
Presentation/Views/SubPages/
  ├─ FoodRecordView.swift        ← 只保留列表 + FABAddButton + Sheet 挂载
  └─ Food/
      ├─ EditFoodSheet.swift     ← 从 FoodRecordView.swift 搬出
      ├─ LocationPickerSheet.swift  (新增)
      └─ POISearchResults.swift     (新增)
```

不做与本次目标无关的重构。

---

## 7. 边界与约束确认

| 项 | 状态 |
|----|------|
| MapKit / CoreLocation 引入 | ✅ 苹果系统框架，AGENTS.md § 2 允许（"禁止 UIKit"红线针对第三方 UI 层，不含 MapKit） |
| 网络策略 | ✅ `MKLocalSearch` / `CLGeocoder` 是系统 → 苹果 MapKit 后端调用，与"禁止外网 / 埋点 SDK"红线的立法意图（不做用户行为分析、不做自定义外网 API）一致 |
| 权限范围 | ✅ 仅 `WhenInUse`，无后台定位 |
| SwiftData 存储 | ✅ 4 个字段全 Optional 基本类型，不使用嵌套自定义类型 |
| 敏感度 | 用户主动录入的餐厅位置，随 SwiftData 明文存储（与店名同级），随同步 JSON 传输（用户自建服务端） |

---

## 8. 手动验证清单

在原有验证清单基础上追加：

1. 编辑弹窗新增 3 个位置录入入口，未录入时均可见
2. 首次点「使用当前位置」触发系统权限弹窗；同意后 3s 内填充地址
3. 拒绝定位权限后按钮转灰，点击跳系统设置
4. 地图选点全屏 sheet：拖动地图 → 底部地址卡片跟随刷新
5. POI 搜索输入框：输入 2 字符以上出结果列表，点选后收起 + 填充
6. 已录入位置的记录：列表行显示 "📍 地址"；编辑弹窗内出现「导航到这里」按钮
7. 「导航到这里」→ 拉起 Apple Maps 且定位正确
8. 位置字段随 `LocalBackupSheet` 导出的 JSON 备份
9. 位置字段随 `LanSyncView` 上传 / 下载往返不丢失
10. 老数据（无位置字段）读取正常，字段呈 `nil`，UI 上不显示位置行

---

## 9. YAGNI · 明确不做

- 不做多导航 App 选择器（高德 / 百度 / Google Maps）
- 不做"最近使用过的地点"缓存
- 不做"距离我 / 附近"排序
- 不做地理围栏 / 到店自动提醒
- 不缓存反解结果（每次现场调 `CLGeocoder`）
- 不做位置模糊化 / 隐私脱敏（用户自定的餐厅，非高敏数据）

---

## 10. 影响文件清单

| 类型 | 文件 |
|------|------|
| 模型 | `Domain/Models/FoodRecord.swift` |
| 同步 DTO | `Data/Mapper/SyncPayload.swift` |
| 同步用例 | `Domain/UseCases/BackupSyncUseCase.swift` |
| 位置服务 | `Core/Utils/LocationService.swift` (新增) |
| 编辑弹窗 | `Presentation/Views/SubPages/Food/EditFoodSheet.swift` (从旧文件搬迁 + 扩展) |
| 地图选点 | `Presentation/Views/SubPages/Food/LocationPickerSheet.swift` (新增) |
| POI 搜索 | `Presentation/Views/SubPages/Food/POISearchResults.swift` (新增) |
| 列表页 | `Presentation/Views/SubPages/FoodRecordView.swift` (瘦身 + 列表行改动) |
| 配置 | `Info.plist`（或 Xcode Target 的 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`） |
| 文档 | `docs/module-spec/module-backup-sync-spec.md` |
