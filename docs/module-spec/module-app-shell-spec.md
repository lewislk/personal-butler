# PersonalButler · App 骨架 · 模块级 SPEC

> 模块职责：负责 App 启动初始化（SwiftData 容器、全局环境、主题、路由骨架），把 UI 层的 `MainTab` 与业务子页面通过一个常驻 `NavigationStack` 组织起来。它是所有业务模块的公共入口和上下文提供者，本身**不含业务逻辑**。

## 1. 范围与边界

本模块负责：

- App 主入口（`@main`）与 SwiftData `ModelContainer` 初始化
- 全局环境对象 `AppEnvironment`（数据变更广播、应用锁状态、最近同步时间）
- 根路由 `AppRouter`（`NavigationStack.path` 驱动子页面 push/pop）
- 底部三 Tab 枚举 `AppTab`
- 全局主题色 `AppColorTheme`
- 局域网同步的**配置读写**（`AppSyncConfig`，仅 UserDefaults 层，不含业务）
- 常驻根视图 `RootView` 与模块 id → 子页面工厂 `AppModuleRouter`

不覆盖：

- 具体页面 UI（见 [module-main-tab-spec.md](./module-main-tab-spec.md) 与各业务模块 SPEC）
- 同步 HTTP 请求、Payload 组装（见 [module-backup-sync-spec.md](./module-backup-sync-spec.md)）
- 通用工具与敏感存储（见 [module-infra-spec.md](./module-infra-spec.md)）

## 2. 核心概念

### ModelContainer

App 唯一的 SwiftData 容器，一次性注册全部 10 个 `@Model`（Todo/Schedule/Anniversary/Password/OTP/Food/CookRecipe/Note/AppModule/AppSetting）。所有 View 通过 `@Environment(\.modelContext)` 直接读写，不再引入 Repository 层。

对应代码：`App/PersonalButlerApp.swift` · `modelContainer` 闭包。

### AppEnvironment

全局单例 `ObservableObject`（通过 `@StateObject` 注入根视图，作为 `.environmentObject(env)`）。持有 3 类跨页面状态：

- `dataChanged: PassthroughSubject<Void, Never>`：同步/恢复后广播刷新（当前 MVP 未订阅方，只作占位）
- `isUnlocked: Bool`：应用锁状态（PRD 中的 App 级锁，MVP 默认 `true`）
- `lastSyncTime: Date?`：从 UserDefaults 读取 + `markSynced()` 写回

对应代码：`App/AppEnvironment.swift`。

### AppRouter

根级路由，`@Published var path: [String]` 承载 NavigationStack 的 path。约定 path 元素为 **模块 id 字符串**（`"schedule" / "anniversary" / "password" / …`），由 `AppModuleRouter.destination(for:)` 消费。

- `open(id)`：`path.append(id)`
- `back()` / `popToRoot()`：pop
- `isInSubPage`：`!path.isEmpty`

对应代码：`App/AppRouter.swift`、`Presentation/Views/RootView.swift`（`NavigationStack(path: $router.path)`）。

### AppSyncConfig

用 UserDefaults 存三个 key，专供 `LanSyncView` 与 `BackupSyncUseCase` 读取：

| Key | 用途 |
|-----|------|
| `sync.server.host` | 服务器 IP（不含端口） |
| `sync.token` | 静态同步密钥 `X-Sync-Token` |
| `sync.deviceId` | 首次调用时生成的稳定 UUID，作为 `X-Device-ID` |

端口固定 `defaultPort = 8090`。对应代码：`App/AppSyncConfig.swift`。

### AppTab

底部三 Tab 枚举：`.home / .allApp / .mine`。用于 `MainTabView` 内容切换。

### AppColorTheme

全局主色板：`primary #4A86E8` / `text #1D1D1F` / `textSub #757575` / `bg #F5F7FA` / `border #ECEEF2` / `danger` / `success` / `warn` / `cardShadow`。所有页面 UI 通过它获取颜色，不写死 HEX。

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| App 主入口 | `personal-butler/App/PersonalButlerApp.swift` | `@main struct PersonalButlerApp: App`；初始化 ModelContainer、注入 env、锁定简体中文 locale、设置主色 tint |
| 全局环境 | `personal-butler/App/AppEnvironment.swift` | `dataChanged` / `isUnlocked` / `lastSyncTime` / `markSynced()` |
| 根路由 | `personal-butler/App/AppRouter.swift` | `@Published var path: [String]` + `open / back / popToRoot` |
| Tab 枚举 | `personal-butler/App/AppTab.swift` | `enum AppTab { home, allApp, mine }` |
| 同步配置 | `personal-butler/App/AppSyncConfig.swift` | UserDefaults 读写；`deviceID` 首次访问时生成 UUID 落库 |
| 主题 | `personal-butler/App/AppColorTheme.swift` | 全部主色常量 |
| 根视图 | `personal-butler/Presentation/Views/RootView.swift` | 常驻 `NavigationStack(path:)`，root = `MainTabView`，`.navigationDestination(for: String.self)` → `AppModuleRouter.destination` |
| 模块工厂 | `personal-butler/Presentation/Views/AppModuleRouter.swift` | 模块 id → 子页面视图；未注册 id 走 `ComingSoonView` |

## 4. 核心场景

### App 启动初始化

**代码入口：** `App/PersonalButlerApp.swift` · `PersonalButlerApp.body`

**业务规则：**

- 一次性构建包含全部 `@Model` 的 SwiftData Schema
- 挂载唯一 `ModelContainer` 到 SwiftUI 环境（`.modelContainer(...)`）
- 注入唯一 `AppEnvironment`（`@StateObject`），供跨页面广播/状态共享
- 强制 UI locale 为 `zh-Hans`，主题 tint 为 `AppColorTheme.primary`
- 若 SwiftData 初始化失败直接 `fatalError`（本地存储是硬依赖，无兜底）

**实现逻辑：**

1. 声明 `let modelContainer: ModelContainer = { … }()`
2. Schema 中 append 全部 10 个 `@Model` 类型
3. `ModelConfiguration(isStoredInMemoryOnly: false)`（生产模式）
4. WindowGroup 内挂载 `RootView().environmentObject(env)` → `.modelContainer(modelContainer)`

### 首启种子写入

**代码入口：** `Presentation/Views/MainTab/MainTabView.swift` · `.task { SeedData.ensureSeeded(in: context) }`

**业务规则：**

- 只在 `AppModule` 表为空时执行（幂等）
- 写入示例功能模块（10 个，其中 4 个 `comingSoon: true`）、示例日程 / 纪念日 / 密码 / OTP / 美食 / 菜谱 / 笔记 / 默认 Setting
- 目的：让空 App 首次启动就能呈现 UI 效果

**实现逻辑：**

1. `SeedData.ensureSeeded(in: context)`
2. `context.fetch(FetchDescriptor<AppModule>())` 判空
3. 空则依次 `seedAppModules / seedSchedules / …`，最后 `context.save()`

> 该逻辑放在 `MainTabView.task` 而非 `PersonalButlerApp.init()`，因为 `@Environment(\.modelContext)` 需要视图层才能拿到。

### 子页面路由

**代码入口：** `Presentation/Views/RootView.swift` + `AppModuleRouter.swift`

**业务规则：**

- 根视图**永远只有一层** `NavigationStack`，root 是 `MainTabView`
- push 子页面时 tab bar 自动被覆盖，返回时自动恢复（避免自定义 tab bar hiding 引起的内容"上浮"抖动）
- 系统边缘滑动手势自动可用

**实现逻辑：**

1. `MainTabView` 中的 Home / AllApp 内的入口按钮调用 `router.open(module.id)`
2. `AppRouter.path.append(id)` → 触发 `NavigationStack` push
3. `navigationDestination(for: String.self)` 命中 → `AppModuleRouter.destination(for: id)`
4. switch id：
   - `"schedule"` → `ScheduleView()`
   - `"anniversary"` → `AnniversaryView()`
   - `"password"` → `PasswordView()`
   - `"food"` → `FoodRecordView()`
   - `"cook"` → `CookRecipeView()`
   - `"note"` → `NoteView()`
   - 其他 → `ComingSoonView(title: displayName(for: id))`（记账/健康/旅行/观影 4 个二期占位）

### 同步配置读写

**代码入口：** `App/AppSyncConfig.swift`

**业务规则：**

- 服务器地址 / 密钥用户可修改；`deviceID` 稳定永不变
- 无值时返回空字符串（业务层可据此判断"未配置"）
- 所有 UserDefaults 键名统一以 `sync.` 前缀

**实现逻辑：**

1. `host` / `token`：`UserDefaults.string(forKey:) ?? ""` + `set` 写回
2. `deviceID`：首次读取时若无值则 `UUID().uuidString` 并 `set` 落库，之后永远返回相同 UUID
3. `defaultPort` 硬编码 `8090`，不走 UserDefaults

### 数据变更广播

**代码入口：** `App/AppEnvironment.swift` · `dataChanged`

**业务规则（预留）：**

- 场景：局域网恢复完成 / 批量导入完成后，需要全局刷新已展示的页面
- 当前 MVP：`BackupSyncUseCase.restore` 未真正覆盖数据，因此 `dataChanged` 尚无发送方；订阅方留空
- 未来接入：`restore` 完成后 `env.dataChanged.send()`，各页面 `.onReceive(env.dataChanged)` 刷新 `@Query`

## 5. 参考资料

- 代码：
  - `personal-butler/App/PersonalButlerApp.swift`
  - `personal-butler/App/AppEnvironment.swift`
  - `personal-butler/App/AppRouter.swift`
  - `personal-butler/App/AppTab.swift`
  - `personal-butler/App/AppSyncConfig.swift`
  - `personal-butler/App/AppColorTheme.swift`
  - `personal-butler/Presentation/Views/RootView.swift`
  - `personal-butler/Presentation/Views/AppModuleRouter.swift`
- 文档：
  - `docs/PRD.md § 2 全局设计规范`
  - `CLAUDE_BACK.md § 一/§ 三`（历史技术栈与目录规划）
