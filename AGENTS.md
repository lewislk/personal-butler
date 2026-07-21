# AGENTS.md — PersonalButler

面向 AI 编码助手的仓库入口。目标：**在最短篇幅内让 AI 判断"改哪里 / 别碰哪里 / 怎么改不违约"**。

面向人类读者的介绍见 [README.md](./README.md)。详细文档见 [docs/module-spec/](./docs/module-spec/index.md)。

---

## 1. 项目一句话

iOS 18+ SwiftUI 单端 App，纯本地（SwiftData + Keychain）个人生活管家；聚合待办 / 日程 / 纪念日 / 笔记 / 密码 + 2FA / 美食 / 菜谱；对外仅一条通道 —— 用户手动触发的**局域网 HTTP 全量同步**。无账号、无云、无广告。

---

## 2. 技术边界（别改错方向）

| 项 | 状态 |
|----|------|
| iOS 最低版本 | 18（可用 iOS 18 新 API，不必写 `if #available` 兜底） |
| UI 框架 | 纯 SwiftUI；**禁止**引入 UIKit（除系统集成必需，如 `UIPasteboard`） |
| 架构 | Clean Architecture 名义上分层，实际 MVP 阶段简单页面直连 `ModelContext`；只有跨模块聚合的备份同步被抽为 UseCase |
| 依赖 | **零第三方包**（无 SPM / Cocoapods），全部走系统原生 API |
| 存储 | 非敏感 → SwiftData（`@Model`，底层 SQLite）；敏感（密码明文 / 2FA 密钥）→ Keychain；轻配置 → UserDefaults |
| 网络 | 只允许 `URLSession` 访问局域网 `http://<host>:8090/sync/*`；**禁止**任何外网请求 / 埋点 / 分析 SDK |
| 加密 | CryptoKit（HMAC-SHA1 for TOTP）；不引入自签 HTTPS / AES 需求（PRD 二期） |
| 生物识别 | `LocalAuthentication` (`.deviceOwnerAuthentication`)，模拟器兜底放行 |
| 语言 & 语系 | 简体中文 UI（`locale: zh-Hans`）；代码注释可中文；标识符英文 |

---

## 3. 目录导航（速查）

```
personal-butler/
├── App/                          ← App 入口 / 全局环境 / 根路由 / 主题
│   ├── PersonalButlerApp.swift   ← @main；SwiftData ModelContainer 一次性注册全部 @Model
│   ├── AppEnvironment.swift      ← 全局状态：dataChanged / isUnlocked / lastSyncTime
│   ├── AppRouter.swift           ← NavigationStack.path 承载子页面 id
│   ├── AppTab.swift              ← 底部 Tab 枚举
│   ├── AppSyncConfig.swift       ← 同步配置 UserDefaults 读写 + 稳定 deviceID
│   └── AppColorTheme.swift       ← 全局主色板；改主题只碰这里
├── Core/                         ← 无业务耦合的通用底座
│   ├── Auth/LocalAuthService.swift
│   ├── Utils/{Keychain,OTPGenerator,DateCalculator,NotificationManager}.swift
│   ├── Extensions/{Date,Color,View}+Ext.swift
│   └── Constants/UIConstant.swift
├── Domain/
│   ├── Models/*.swift            ← 10 个 SwiftData @Model（Todo/Schedule/Anniversary/Password/OTP/Food/CookRecipe/Note/AppModule/AppSetting）
│   └── UseCases/BackupSyncUseCase.swift  ← 目前唯一 UseCase
├── Data/
│   ├── Mapper/SyncPayload.swift  ← 同步 JSON DTO
│   └── LocalDataSource/SeedData.swift  ← 首启种子（幂等：AppModule 空才写）
├── Presentation/
│   ├── Views/RootView.swift            ← 常驻 NavigationStack(path: $router.path)
│   ├── Views/AppModuleRouter.swift     ← 模块 id → 子页面工厂（switch）
│   ├── Views/MainTab/{MainTab,Home,AllApp,Mine}View.swift
│   ├── Views/SubPages/*.swift          ← 各业务子页面
│   ├── Components/*.swift              ← 通用 UI 组件
│   └── Sheets/LocalBackupSheet.swift
└── Assets.xcassets/
```

**找什么去哪里：**

| 想做的事 | 起点文件 |
|---------|---------|
| 新增一个业务模块 | 见 [§9 新增模块 checklist](#9-新增模块-checklist) |
| 修改主色 / 尺寸 | `App/AppColorTheme.swift` / `Core/Constants/UIConstant.swift` |
| 修改同步接口 / JSON 结构 | `Data/Mapper/SyncPayload.swift` + `Domain/UseCases/BackupSyncUseCase.swift`；**必须同时递增 `SyncMeta.dataVersion`** |
| 主页待办为什么会/不会显示某条 | `Presentation/Views/MainTab/HomeView.swift` · `todayList` / `weekList` |
| 密码 / 2FA 相关一切 | `Presentation/Views/SubPages/PasswordView.swift` + `Core/Utils/{KeychainManager,OTPGenerator}.swift` |
| 日期 / 农历 / 倒计时 | `Core/Utils/DateCalculator.swift`（勿在业务代码里手写日历算法） |
| 生物识别时机 | `Core/Auth/LocalAuthService.swift` 是唯一封装；调用点见 [§5 敏感操作红线](#5-敏感操作红线) |

---

## 4. 数据流心智模型

```
用户操作 (View)
    │
    │  日常 CRUD：直接用 @Environment(\.modelContext) + @Query
    │  跨模块聚合（备份同步）：走 BackupSyncUseCase
    ▼
SwiftData (SQLite)  ←──────── @Query 自动订阅 / ModelContext 手动 insert-save
    │
    │  敏感字段（密码明文 / TOTP 密钥）绝不落这里
    ▼
Keychain (Security)  ←──────── 通过 @Model 里的 xxxKeychainKey 关联
    │
    ▼
LAN HTTP (仅用户手动触发)  ←── BackupSyncUseCase.upload / download
```

**跨页面路由**：`AppRouter.path: [String]` → `NavigationStack.navigationDestination(for: String.self)` → `AppModuleRouter.destination(for: id)`；path 元素就是 `AppModule.id`（如 `"schedule"`）。

**跨页面广播**：`AppEnvironment.dataChanged: PassthroughSubject<Void, Never>`（当前无发送方，仅占位，属预留能力）。

---

## 5. 敏感操作红线

**以下操作前必须调 `await LocalAuthService.authenticate(reason:)`**：

1. 进入 `PasswordView`（`.task` 里）
2. 查看/复制密码明文（如果你把 `reveal` 门禁改成延迟到点击时，也要过一次生物识别）
3. `LocalBackupSheet.doExport()` 导出 JSON 文件
4. `LanSyncView.doUpload()` / `doDownload()` 上传下载

**Keychain 用法**：

- Key 规范：`pwd.<uuid>` / `otp.<uuid>`
- 写：先 `SecItemDelete` 再 `SecItemAdd`（`KeychainManager.save` 已封装）
- accessibility：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（不改）
- **禁止**把明文写进 `@Model` 属性 / 打日志 / 塞进 UserDefaults

**同步 JSON 明文字段**：`SyncPasswordDTO.passwordPlain` / `SyncOTPDTO.secretPlain` 只允许在内存组装 → 局域网传输的路径上出现；落磁盘只发生在**用户主动导出的 JSON 备份文件**中（且该文件本身没有加密，属已知取舍）。

---

## 6. 编码约定（写代码前扫一眼）

### SwiftData `@Model`

- 枚举字段一律用 `xxxRaw: String` 落库 + 计算属性读回类型；见 `TodoItem.source` / `ScheduleEvent.colorTag` 等
- `@Attribute(.unique) var id: UUID`（AppModule 例外，`id: String` 稳定标识）
- Date 用 `Date` 类型；同步 DTO 里再转 `timeIntervalSince1970: Double`
- 新增字段必须带默认值 / Optional，兼容旧数据

### 视图层

- 主色板走 `AppColorTheme.*`；圆角走 12 / 8 / 6；间距 4/8/16/24；字号 20/16/14/12
- 复用组件：`SegmentedPill` / `MiniSegmentedPill` / `HorizontalTagBar` / `FABAddButton` / `TodoItemRow`
- 图标一律 SF Symbols
- 子页面顶部标题栏走 `.navigationTitle(...)` + `.navigationBarTitleDisplayMode(.inline)`
- 悬浮 + 按钮统一 `FABAddButton { }`，放在 `ZStack(alignment: .bottomTrailing)` 底层

### 命名

- 文件名 = 主类型名（`PasswordView.swift` / `BackupSyncUseCase.swift`）
- 枚举 raw 值小写英文；`label: String` 计算属性放中文展示
- View 内部私有类型 / 组件用 `private struct`，避免污染模块作用域

### 异步

- `LocalAuthService.authenticate` 是 `async`，调用点用 `.task { ... }` 或 `Task { ... }`
- `BackupSyncUseCase` 标 `@MainActor`；网络操作 `async throws`

---

## 7. 已知 MVP 状态（不要当 bug 修）

| 现象 | 状态 | 何处 |
|------|------|------|
| `BackupSyncUseCase.restore(_:)` 拿到 payload 后不实际覆盖本地数据，只 `context.save()` | **故意占位**，避免开发期误删 | `Domain/UseCases/BackupSyncUseCase.swift` |
| `/sync/info` / `/sync/clear` 客户端未实现 | MVP 未做 | 同上 |
| 日程 / 纪念日的推送提醒未注册（`NotificationManager` 能力就绪） | MVP 未接入 | `SubPages/ScheduleView.swift` / `AnniversaryView.swift` |
| MineView "清除缓存" 只把 `cacheSize` 置 0，不真删文件 | MVP 占位 | `MainTab/MineView.swift` |
| `LocalAuthService` 模拟器直接返回 true | **开发兜底**，勿改 | `Core/Auth/LocalAuthService.swift` |
| Home / All 页面头部标题栏是自制的（不用 `.navigationTitle`），子页面用系统 nav bar | 有意为之，避免 Tab 页多一层 nav 高度 | `MainTab/*View.swift` |
| `AppEnvironment.dataChanged` 无发送方 | 预留能力 | `App/AppEnvironment.swift` |
| `AppSetting` 未纳入 `SyncPayload.setting` | 占位空 map | `Domain/UseCases/BackupSyncUseCase.swift` · `buildPayload` |
| `AppModule` 中 `comingSoon: true` 的 4 项（记账/健康/旅行/观影）点击进入统一走 `ComingSoonView` | PRD 二期功能 | `Presentation/Views/AppModuleRouter.swift` |

修 bug 之前先对照本表确认不是"故意的 MVP 简化"。

---

## 8. 同步契约（改前必读）

服务端由用户自建。客户端与服务端遵守以下契约：

- 地址：`http://<host>:8090`
- 头：`Content-Type: application/json` / `X-Device-ID` / `X-Sync-Token`
- 顶层 JSON：`{ syncMeta: {...}, data: {...} }`；见 `Data/Mapper/SyncPayload.swift`
- 4 个端点：`POST /sync/upload` / `GET /sync/download` / `GET /sync/info` / `DELETE /sync/clear`
- 统一返回结构：`{ code: Int, msg: String, data: T? }`
- 错误码：0 成功 / 1001 头缺失 / 1002 密钥错 / 1003 JSON 解析失败 / 2001 存储失败 / 2002 无备份 / 5000 内部异常

**破坏性变更规则**：

- 只增字段、不删字段、不改字段语义
- 变更 `SyncData` 任一 DTO 必须递增 `SyncMeta.dataVersion`
- 同步更新 [`docs/module-spec/module-backup-sync-spec.md`](./docs/module-spec/module-backup-sync-spec.md)

---

## 9. 新增模块 checklist

想加一个全新的功能模块（例：记账本）？按序：

1. **模型**：`Domain/Models/Ledger.swift` — `@Model final class Ledger { ... }`
2. **注册容器**：`App/PersonalButlerApp.swift` · `Schema([...])` 追加 `Ledger.self`
3. **子页面**：`Presentation/Views/SubPages/LedgerView.swift`
4. **路由分发**：`Presentation/Views/AppModuleRouter.swift` · `switch` 加 `case "ledger": LedgerView()`
5. **模块入口卡片**：`Data/LocalDataSource/SeedData.swift` · `seedAppModules` 把 `.init(id: "ledger", ..., comingSoon: false)` 更新
6. **同步 DTO**（如需支持备份/同步）：
   - `Data/Mapper/SyncPayload.swift`：新增 `SyncLedgerDTO` + `SyncData.ledgerList`
   - `BackupSyncUseCase.buildPayload`：fetch + map 拼装
   - `SyncMeta.dataVersion += 1`
7. **SPEC**：
   - 新建 `docs/module-spec/module-ledger-spec.md`（复用同目录任一 module-*-spec.md 结构）
   - 更新 `docs/module-spec/project-spec.md` § 4 模块导航表
   - 更新 `docs/module-spec/index.md`
   - 更新 `README.md` § 9 模块导航
8. **主页联动**（可选）：若想让 Ledger 项进主页待办卡片，去 `MainTab/HomeView.swift` · `todayList` / `weekList` 添加合并逻辑

**唯一路由 id**：一旦选定就是"永久稳定标识"，同时被 `AppRouter.path` 元素、`AppModuleRouter switch key`、`AppModule.id`（`@Attribute(.unique)`）共同使用；改名 = 破坏旧用户 SwiftData 数据。

---

## 10. 提交与验证

- **格式化**：Xcode 保存自动缩进即可，无 linter
- **测试**：目前无 XCTest；如新增 UseCase 逻辑（非 UI），推荐补 `Tests/`
- **构建/运行**：Xcode Cmd+R，Simulator 或真机
- **手动验证清单**（改动后建议自测）：
  - App 冷启后主页 6 个宫格 + 待办卡片能正常出现（`SeedData` 未损坏）
  - 密码页首次进入触发面容识别，通过后能显隐密码明文
  - 2FA cell 每秒刷新，30s 归零
  - LanSyncView 未配置 host 时"上传/下载"按钮 disabled；配置后不真的连服务端也不能崩
  - MineView "数据备份" 弹窗能生成 JSON 文件并出现 ShareLink

---

## 11. 参考文档

- SPEC 目录索引：[docs/module-spec/index.md](./docs/module-spec/index.md)
- 服务级 SPEC：[docs/module-spec/project-spec.md](./docs/module-spec/project-spec.md)
- 产品需求：[docs/PRD.md](./docs/PRD.md)
- UI 视觉规范：[docs/UI_DEMO.md](./docs/UI_DEMO.md)
- 原始技术栈设计（历史存档，与代码略有出入以代码为准）：[TDD.md](./docs/TDD.md)
