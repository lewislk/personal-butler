# PersonalButler · App 骨架 · 模块级 SPEC

> 模块职责：负责 App 启动初始化（SwiftData 容器、全局环境、主题、路由骨架），把 UI 层的 `MainTab` 与业务子页面通过一个常驻 `NavigationStack` 组织起来。它是所有业务模块的公共入口和上下文提供者，本身**不含业务逻辑**。

## 1. 范围与边界

本模块负责：

- App 主入口（`@main`）与 SwiftData `ModelContainer` **异步**初始化
- **系统启动屏**（`LaunchScreen.storyboard`）与 SwiftUI 层过渡视图（`LaunchView`）两段接力，覆盖冷启全过程
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

**初始化位置**：`PersonalButlerApp.bootstrap()` 中 **异步** 构造（`Task.detached(priority: .userInitiated)`）。**不要**再改回 `let modelContainer: ModelContainer = { … }()` 属性初始化——那会让 SwiftUI Scene 拿不到首帧，冷启时用户看到的是系统 `UILaunchStoryboardName` 指定的启动屏（而不是 `LaunchView`），首启建库耗时（2~3s）全在这一段。`ModelContainer` 本身是 `Sendable`，可以在后台线程构造；只有 `mainContext` 访问必须回主线程。

`.modelContainer(_:)` modifier 挂载在 **`RootView`** 上（不是 Scene），因为容器延迟到 `bootstrap()` 就绪后才存在。

对应代码：`App/PersonalButlerApp.swift` · `bootstrap()`。

### 启动屏两段接力（LaunchScreen + LaunchView）

冷启视觉分两段，任一段缺失都会出现白屏：

| 段 | 显示者 | 覆盖时段 | 能力 |
|----|--------|----------|------|
| 系统启动屏 | `personal-butler/LaunchScreen.storyboard` | App 进程冷启 → SwiftUI 首帧（约 2~3s，首启为主） | 静态：白底 + 主色 `#4A86E8` 圆角方块 + SF Symbol + 双行文字。**不能**放动画/`ProgressView`/自定义类/runtime attribute |
| SwiftUI 过渡页 | `Presentation/Views/LaunchView.swift` | SwiftUI 首帧 → `ModelContainer` 就绪（`bootstrap()` 完成） | 动态：Logo 呼吸动画 + `ProgressView` 菊花 + 保底 0.6s 展示时长 |

两段构图刻意对齐（同位置的 Logo、同标题），交接时用户视觉上是"Logo 突然开始呼吸 + 菊花出现"，无跳变。

**pbxproj 配置**：Debug/Release 两份都必须是 `INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;`，**不能**同时保留 `INFOPLIST_KEY_UILaunchScreen_Generation = YES;`（互斥）。

**踩坑速查**（详见 [[knowledge/2026-07-22-launch-white-screen]]）：

- LaunchScreen.storyboard 不允许 `<userDefinedRuntimeAttribute>`（`layer.cornerRadius` 等）→ 圆角方块用 `app.fill` SF Symbol 染色实现
- iOS 会给启动屏拍快照缓存，改 storyboard 后**必须卸载重装或重启设备**才看得到新效果

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
| App 主入口 | `personal-butler/App/PersonalButlerApp.swift` | `@main struct PersonalButlerApp: App`；`bootstrap()` 异步建 ModelContainer + 跑 SeedData；就绪前渲染 `LaunchView`、就绪后切 `RootView` |
| 系统启动屏 | `personal-butler/LaunchScreen.storyboard` | 冷启（进程加载 → SwiftUI 首帧）阶段展示；视觉与 `LaunchView` 静态部分对齐；`INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen` 引用 |
| SwiftUI 过渡页 | `personal-butler/Presentation/Views/LaunchView.swift` | SwiftUI 首帧 → 业务就绪阶段展示；Logo 呼吸动画 + ProgressView 菊花 |
| 全局环境 | `personal-butler/App/AppEnvironment.swift` | `dataChanged` / `isUnlocked` / `lastSyncTime` / `markSynced()` |
| 根路由 | `personal-butler/App/AppRouter.swift` | `@Published var path: [String]` + `open / back / popToRoot` |
| Tab 枚举 | `personal-butler/App/AppTab.swift` | `enum AppTab { home, allApp, mine }` |
| 同步配置 | `personal-butler/App/AppSyncConfig.swift` | UserDefaults 读写；`deviceID` 首次访问时生成 UUID 落库 |
| 主题 | `personal-butler/App/AppColorTheme.swift` | 全部主色常量 |
| 根视图 | `personal-butler/Presentation/Views/RootView.swift` | 常驻 `NavigationStack(path:)`，root = `MainTabView`，`.navigationDestination(for: String.self)` → `AppModuleRouter.destination` |
| 模块工厂 | `personal-butler/Presentation/Views/AppModuleRouter.swift` | 模块 id → 子页面视图；未注册 id 走 `ComingSoonView` |

## 4. 核心场景

### App 启动初始化

**代码入口：** `App/PersonalButlerApp.swift` · `PersonalButlerApp.body` + `bootstrap()`

**业务规则：**

- 冷启用户视觉：**系统启动屏（storyboard）→ `LaunchView`（SwiftUI）→ 淡入 `RootView` 主页**，全程无白屏
- `ModelContainer` 建库 / 迁移必须在**后台**执行，不能阻塞 SwiftUI 首帧
- `SeedData.ensureSeeded` 必须在 `ModelContainer` 就绪且回到 `@MainActor` 后执行（`mainContext` 是主线程约束）
- 保底展示 `LaunchView` 最少 0.6s，避免二次启动秒过导致视觉突兀
- 若 SwiftData 初始化失败直接 `fatalError`（本地存储是硬依赖，无兜底）
- 强制 UI locale 为 `zh-Hans`，主题 tint 为 `AppColorTheme.primary`

**实现逻辑：**

1. `@State private var modelContainer: ModelContainer?`（未就绪为 nil）
2. `WindowGroup` body：`modelContainer` 非 nil → `RootView().modelContainer(container)`；否则 `LaunchView().task { await bootstrap() }`。切换用 `.transition(.opacity)` + `.animation(_:value:)` 淡入淡出
3. `bootstrap()`：
   1. `Task.detached(priority: .userInitiated) { … }` 后台构造 `ModelContainer`（`Schema([TodoItem.self, …])` + `ModelConfiguration(isStoredInMemoryOnly: false)`）
   2. 回主线程后调 `SeedData.ensureSeeded(in: container.mainContext)`
   3. 若耗时 < 0.6s 补 `Task.sleep`
   4. 赋值 `modelContainer = container` → SwiftUI 切换到 `RootView`

> **重要**：`SeedData` 由 `PersonalButlerApp.bootstrap()` 集中调用，请**不要**同时在 `MainTabView.task` 里重复调用（虽然幂等，但违反单一起点原则）。

### 冷启白屏兜底（系统启动屏）

**代码入口：** `personal-butler/LaunchScreen.storyboard` + `project.pbxproj · INFOPLIST_KEY_UILaunchStoryboardName`

**业务规则：**

- 系统启动屏必须存在且配置生效（`INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen`），**不能**回退到自动生成的空白启动屏（`INFOPLIST_KEY_UILaunchScreen_Generation = YES`）
- 视觉与 `LaunchView` 的静态部分对齐（背景色、Logo 尺寸/位置/颜色、标题文案），交接时用户无跳变
- storyboard 内**只能**静态图片、系统色、SF Symbol、AutoLayout；**不能**放动画、`ProgressView`、自定义类、user-defined runtime attribute
- 若需圆角/阴影：用 SF Symbol（如 `app.fill`）染色叠加代替 `layer.cornerRadius`

**实现逻辑：**

1. 底层 `UIImageView`：`app.fill` SF Symbol，`tintColor` 设为主色 `#4A86E8`，96×96 居中偏上
2. 上层 `UIImageView`：`person.crop.circle.badge.checkmark` SF Symbol，白色，46×46 居中于底层
3. 下方 `UILabel`：主标题「私人管家」24pt semibold + 副标题「你的生活，尽在掌握」13pt
4. `project.pbxproj` Debug/Release 两份 build settings 里删除 `INFOPLIST_KEY_UILaunchScreen_Generation = YES`，加 `INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen`

### 首启种子写入

**代码入口：** `App/PersonalButlerApp.swift` · `bootstrap()` 内 `SeedData.ensureSeeded(in: container.mainContext)`

**业务规则：**

- 只在 `AppModule` 表为空时执行（幂等）
- 写入示例功能模块（10 个，其中 4 个 `comingSoon: true`）、示例日程 / 纪念日 / 密码 / OTP / 美食 / 菜谱 / 笔记 / 默认 Setting
- 目的：让空 App 首次启动就能呈现 UI 效果

**实现逻辑：**

1. `bootstrap()` 拿到 `ModelContainer` 后调 `SeedData.ensureSeeded(in: container.mainContext)`
2. `context.fetch(FetchDescriptor<AppModule>())` 判空
3. 空则依次 `seedAppModules / seedSchedules / …`，最后 `context.save()`

> 该逻辑之前放在 `MainTabView.task`（历史文档中的旧描述）；已迁移到 `PersonalButlerApp.bootstrap()`，与 `ModelContainer` 就绪时机原子对齐——这样 `LaunchView` 关闭时数据一定就绪，主页首帧不会看到空态。

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
  - `personal-butler/Presentation/Views/LaunchView.swift`
  - `personal-butler/LaunchScreen.storyboard`
- 文档：
  - `docs/PRD.md § 2 全局设计规范`
  - `CLAUDE_BACK.md § 一/§ 三`（历史技术栈与目录规划）
  - `knowledge/2026-07-22-launch-white-screen.md`（冷启白屏 / 启动屏两段接力踩坑）
