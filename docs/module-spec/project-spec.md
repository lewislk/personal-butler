# PersonalButler · 服务级 SPEC

> 服务定位：iOS 端极简、私密、纯本地的个人生活管家 App。聚合待办 / 日程 / 纪念日 / 笔记 / 密码 + 2FA / 美食 / 菜谱等日常事务，所有数据默认存本地 SwiftData（SQLite）+ Keychain，仅支持用户手动触发的局域网 HTTP 全量同步与本地 JSON 备份。

## 1. 服务边界

本服务负责：

- 日常事务的**本地增删改查**（Todo / Schedule / Anniversary / Note / Password / OTP / Food / CookRecipe / AppModule / AppSetting）
- 首页 **待办聚合**（把「日程 / 纪念日 / 烹饪计划 / 手动 Todo」统一收敛到一张待办卡片）
- 首页功能宫格与「全部应用」的**排序管理**（拖拽调整 `AppModule.order`）
- **密码库 + 内置 2FA**：明文/密钥仅存 Keychain；TOTP 由 `OTPGenerator` 本地生成
- **本地 JSON 备份**：`buildPayload → JSON 文件 → ShareLink 分享`
- **局域网 HTTP 全量同步**：POST/GET/DELETE `/sync/*`，用户手动触发
- **生物识别门禁**：查看密码 / 使用 2FA / 备份导出 / 同步操作前的 `LocalAuthService`

本服务不负责：

- 账号体系 / 云端多端同步 / 分享给他人（仅设备维度局域网同步）
- 广告 / 推荐 / 社区 / 埋点上报
- 与外部日历（iCloud Calendar / Google Calendar）双向同步
- 服务端实现（局域网 HTTP 服务端由用户自建）
- OCR / AI 内容识别（`otpauth` 二维码扫描已落地，见 password-otp 模块；其它识别场景不在范围内）

易混边界：

- **本地推送提醒**：由 `Core/Utils/NotificationManager` 提供能力，但当前业务模块（Schedule/Anniversary）暂未强制接入定时注册，属于 P1 待完善项
- **AppModule.comingSoon = true 的模块**（记账本 / 健康记录 / 旅行清单 / 观影记录）：仅在「全部应用」列表展示，点击进入统一走 `ComingSoonView` 占位

## 2. 业务域调用关系

本 App 为纯本地单端应用，无「上游服务」概念。仅存在设备 ↔ 局域网 HTTP 服务端 的手动同步：

**下游服务（可选）**

| 下游 | 调用目的 |
|------|---------|
| 局域网自建 HTTP 服务（`http://<host>:8090`） | 用户手动触发时上传/下载全量数据、查询/清空设备备份 |

**系统能力依赖**

| 能力 | 目的 |
|------|------|
| SwiftData / SQLite | 本地持久化所有非敏感字段 |
| Keychain (Security) | 存储密码明文 / 2FA Base32 密钥 |
| LocalAuthentication | 面容 / 密码解锁敏感操作 |
| CryptoKit（HMAC-SHA1） | 本地生成 TOTP |
| UserNotifications | 本地日历触发式推送 |
| UIPasteboard | 密码 / 2FA 复制到剪贴板 |
| ShareLink | 导出 JSON 备份文件 |

## 3. 目录结构

代码根 `personal-butler/`：

| 目录 | 主要功能 |
|------|---------|
| `App/` | App 入口、SwiftData 容器初始化、根路由 `AppRouter`、`AppEnvironment`、`AppSyncConfig`、`AppColorTheme` |
| `Core/Auth/` | `LocalAuthService`：面容/密码校验 |
| `Core/Utils/` | `KeychainManager` / `OTPGenerator` / `DateCalculator` / `NotificationManager` |
| `Core/Constants/` | `UIConstant`（尺寸/圆角/间距） |
| `Core/Extensions/` | `Color+Ext`（HEX 便捷）、`Date+Ext`（`startOfDay/hourMinute/daysBetween`）、`View+Ext` |
| `Domain/Models/` | 10 个 SwiftData `@Model`：Todo / Schedule / Anniversary / Password / OTP / Food / Cook / Note / AppModule / AppSetting |
| `Domain/UseCases/` | `BackupSyncUseCase`（组装 SyncPayload / HTTP 同步） |
| `Data/Mapper/` | `SyncPayload`（同步 JSON DTO 定义） |
| `Data/LocalDataSource/` | `SeedData`（首启种子数据） |
| `Presentation/Views/` | 根视图 / 路由工厂 / MainTab / SubPages |
| `Presentation/Components/` | 复用 UI 组件（FAB / SegmentedPill / TodoItemRow / HorizontalTagBar） |
| `Presentation/Sheets/` | `LocalBackupSheet`（本地备份弹窗） |

## 4. 模块导航

| 模块 | 职责 | 主要入口 | 上游 | 下游 | SPEC |
|------|------|---------|------|------|------|
| App 骨架 | ModelContainer、根路由、主题、Tab 枚举、同步配置 | `App/PersonalButlerApp.swift` · `App/RootView`（`Presentation/Views/RootView.swift`） | — | Main Tab | [module-app-shell-spec.md](./module-app-shell-spec.md) |
| Main Tab | 主页待办聚合、全部应用排序、我的入口 | `MainTabView.swift` / `HomeView.swift` / `AllAppView.swift` / `MineView.swift` | App 骨架 | 各业务子页面 / 备份同步 | [module-main-tab-spec.md](./module-main-tab-spec.md) |
| 日程管理 | 日/月视图；新增日程 | `ScheduleView.swift` | Main Tab | SwiftData / 首页聚合 / Notification | [module-schedule-spec.md](./module-schedule-spec.md) |
| 纪念日 | 每年重复 vs 累计天数；农历倒计时 | `AnniversaryView.swift` | Main Tab | SwiftData / `DateCalculator` | [module-anniversary-spec.md](./module-anniversary-spec.md) |
| 笔记 | 标签筛选 + 关键字搜索 | `NoteView.swift` | Main Tab | SwiftData | [module-note-spec.md](./module-note-spec.md) |
| 密码 & 2FA | 密码库 + TOTP 验证器；生物识别门禁 | `PasswordView.swift` | Main Tab | SwiftData / Keychain / `OTPGenerator` / `LocalAuthService` | [module-password-otp-spec.md](./module-password-otp-spec.md) |
| 美食记录 | 分类筛选 + 星级评分 | `FoodRecordView.swift` | Main Tab | SwiftData | [module-food-spec.md](./module-food-spec.md) |
| 烹饪 / 菜谱 | 双列网格 + 菜谱详情 + 加入烹饪计划 | `CookRecipeView.swift` | Main Tab | SwiftData / Todo | [module-cook-spec.md](./module-cook-spec.md) |
| 备份 & 局域网同步 | 本地 JSON 备份 / 局域网 HTTP 全量同步 | `LanSyncView.swift` / `LocalBackupSheet.swift` / `BackupSyncUseCase.swift` | Main Tab（我的） | SwiftData + Keychain + LAN HTTP | [module-backup-sync-spec.md](./module-backup-sync-spec.md) |
| Core 通用能力 | Keychain / 生物识别 / OTP / 日期 / 通知 / 扩展 | `Core/*` | 所有业务模块 | 系统框架 | [module-infra-spec.md](./module-infra-spec.md) |

模块间内部依赖：

- `main-tab.HomeView` → `schedule` / `anniversary` / `cook` / `todo`：把这些实体聚合成「今日待办 / 近期待办」
- `password-otp` / `backup-sync` → `infra.LocalAuthService`：所有敏感操作前统一生物识别
- `password-otp` / `backup-sync` → `infra.KeychainManager`：密码/2FA 密钥读写
- `password-otp` → `infra.OTPGenerator`：TOTP 生成
- `anniversary` / `main-tab.HomeView` → `infra.DateCalculator`：农历倒计时、累计天数、相对时间
- `backup-sync` → 所有 `Domain/Models`：扫描全表组装 `SyncPayload`
- `cook.RecipeDetailView` → `TodoItem`：「加入今日烹饪计划」写入待办

## 5. 服务内请求流向

```text
[常态：本地 CRUD]
用户操作
  → View（@Environment(\.modelContext) + @Query）
  → ModelContext.insert / update / delete
  → SwiftData 自动持久化到 SQLite
  → @Query 自动刷新绑定 UI

[敏感读：密码 / 2FA]
用户进入 PasswordView
  → LocalAuthService.authenticate(...)
  → 通过 → 展示；用户点「👁 显示明文」
  → KeychainManager.load(passwordKeychainKey) 取明文

[本地备份导出]
用户「我的 → 数据备份 → 导出」
  → LocalAuthService.authenticate
  → BackupSyncUseCase.buildPayload()（扫描全部 @Model + Keychain）
  → JSONEncoder.encode → 临时目录 JSON 文件
  → ShareLink 分享到文件 App / iCloud Drive

[局域网上传]
用户「我的 → 局域网同步 → 上传」
  → LocalAuthService.authenticate
  → BackupSyncUseCase.upload()
  → buildPayload() → POST http://{host}:8090/sync/upload
  → 头部：X-Sync-Token（v6 起单用户单设备，移除 X-Device-ID）
  → 成功 → AppEnvironment.markSynced() 记录 lastSyncTime

[局域网下载 / 恢复]
用户「我的 → 局域网同步 → 恢复」
  → LocalAuthService.authenticate
  → BackupSyncUseCase.download() → GET /sync/download
  → 解析 SyncResponse<SyncPayload>
  → BackupSyncUseCase.restore(payload)（MVP：暂不覆盖本地）
  → AppEnvironment.markSynced()

[跨页路由]
子页面入口按钮
  → AppRouter.open("schedule" | "anniversary" | ...)
  → NavigationStack.path.append(id)
  → AppModuleRouter.destination(for:) 返回对应 View
```

## 6. 服务级约定

跨模块通用规则，所有模块必须遵守：

- **本地优先：** 日常 CRUD 只走 SwiftData `ModelContext`，禁止在业务代码中直接发起任何网络请求；同步/网络能力必须集中在 `BackupSyncUseCase` + `AppSyncConfig`。
- **敏感数据不落 SQLite：** 密码明文 / 2FA Base32 密钥禁止作为 `@Model` 属性存储；只在 Keychain 保存，`@Model` 只存 `xxxKeychainKey`。同步 JSON 内的 `passwordPlain / secretPlain` 仅在内存中组装、局域网传输时携带，不写入本地文件（用户主动导出 JSON 备份除外）。
- **敏感操作强制生物识别：** 打开密码 / 2FA 页面、导出备份、局域网上传/下载，一律先 `await LocalAuthService.authenticate(reason:)`；模拟器兜底放行。
- **枚举 raw 存储：** SwiftData `@Model` 内的枚举字段一律以 `xxxRaw: String` 存储，业务层通过计算属性读回类型（便于 Codable 与 SQLite schema 稳定）。
- **路由 id 稳定：** `AppModule.id`（如 `"schedule" / "anniversary" / "password" / …`）同时作为 `AppRouter.path` 元素、`AppModuleRouter.destination(for:)` 的 switch key，任何新增模块必须选一个稳定 id 并在 `AppModuleRouter` + `SeedData.seedAppModules` 中注册。
- **主题统一：** UI 颜色只走 `AppColorTheme.*`；圆角 12/8/6、间距 4/8/16/24、字号 20/16/14/12 均遵循 PRD § 2 视觉规范与 `UIConstant`。
- **同步版本兼容：** 修改 `SyncPayload` 结构时必须递增 `SyncMeta.dataVersion`；只增字段、不删字段、不改字段语义。
- **首启种子：** 生产环境下 `SeedData.ensureSeeded(in:)` 通过「查询 `AppModule` 是否为空」判定是否需要注入，避免二次覆盖；新增模块添加 seed 时也要遵循该幂等约束。
