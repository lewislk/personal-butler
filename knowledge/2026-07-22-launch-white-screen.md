# App 启动白屏：系统启动屏未配置 + ModelContainer 同步初始化阻塞 SwiftUI 首帧

日期：2026-07-22
类型：bugfix
服务：personal-butler（iOS SwiftUI 单端 App）
模块：App 骨架（`App/PersonalButlerApp.swift`）+ Launch Screen 资源
影响面：首次安装后冷启用户体验；表现为「白屏 2~3 秒 → 启动过渡页闪现 <1 秒 → 主页」

相关文件：
- `personal-butler/App/PersonalButlerApp.swift`
- `personal-butler/LaunchScreen.storyboard`（新增）
- `personal-butler/Presentation/Views/LaunchView.swift`
- `personal-butler.xcodeproj/project.pbxproj`

## 背景与目标

期望：**App 一打开就显示启动过渡页**，等必要启动依赖（SwiftData 建库/迁移、SeedData 首启灌数据）完成后再进入主页。

实际：首次安装打开出现 2~3 秒**白屏**，然后 `LaunchView` 只闪不到 1 秒就跳到主页。用户体验为"启动崩了 → 启动很急"，与预期完全相反。

## 现象与定位

- 现象：冷启白屏 2~3s → `LaunchView` 闪现 < 1s → 主页
- 复现条件：**首次安装**冷启最明显（涉及 SwiftData 建 SQLite 文件 + 表结构初始化）；二次冷启也有 500ms~1s 的白屏但没那么显著
- 关键证据：
  - `PersonalButlerApp` 的 `modelContainer` 用 `let ... = { ... }()` 属性初始化 → **同步阻塞**，`ModelContainer(for:configurations:)` 建库那段耗时全在 SwiftUI Scene 拿到首帧之前
  - Info.plist 侧只配了 `INFOPLIST_KEY_UILaunchScreen_Generation = YES`（Xcode 自动生成的空白启动屏 = 纯白）
  - `LaunchView` 的 `.task { bootstrap() }` 里还有个 0.6s 保底 sleep → 二次启动 SeedData 幂等秒完，只显示这 0.6s

## 根因

**一句话根因**：SwiftUI App 阶段的启动分为两段——「App 进程冷启 → SwiftUI 首帧」由系统启动屏（`UILaunchScreen` / `UILaunchStoryboardName`）负责；「SwiftUI 首帧 → 业务就绪」由 App 自己的过渡视图负责。本项目**只做了后一段**，前一段的 2~3 秒被空白启动屏占据，还进一步被 `let modelContainer = { … }()` **同步阻塞属性初始化**放大。

展开：

- iOS 生命周期上，`ModelContainer` 属性用 `let ... = { ... }()` 初始化时，是**同步**在 App struct 初始化里执行的。SwiftUI 直到 struct 就绪才会渲染 `WindowGroup` 的第一帧。首启建 SQLite 文件 + 建表 + `@Attribute(.unique)` 索引写入耗时全在这里，2~3s 起步。
- 这 2~3s 内，SwiftUI 视图（包括 `LaunchView`）根本没机会显示。此时屏幕上放什么由系统启动屏决定：`INFOPLIST_KEY_UILaunchScreen_Generation = YES` 且没配任何 `UILaunchScreen` 子项就是纯白。
- 用户以为"`LaunchView` 显示得太晚"，其实 `LaunchView` 出现时机不错——是它**前面还有一段本该被系统启动屏覆盖但没覆盖**的白屏。

## 解决方案

### 改动 1：`ModelContainer` 改为异步创建，让 SwiftUI 首帧立刻画 LaunchView

```swift
// Before
let modelContainer: ModelContainer = { ... }()   // 同步阻塞
@State private var launchFinished = false

// After
@State private var modelContainer: ModelContainer?

var body: some Scene {
    WindowGroup {
        ZStack {
            if let container = modelContainer {
                RootView().modelContainer(container)     // 就绪 → 主页
            } else {
                LaunchView().task { await bootstrap() }  // 未就绪 → 过渡页
            }
        }
    }
}

@MainActor
private func bootstrap() async {
    let container: ModelContainer = await Task.detached(priority: .userInitiated) {
        // ModelContainer 是 Sendable，可在后台线程构造，最耗时的建库/迁移搬出主 Actor
        let schema = Schema([TodoItem.self, ScheduleEvent.self, ...])
        return try! ModelContainer(for: schema, configurations: [...])
    }.value
    SeedData.ensureSeeded(in: container.mainContext)   // 必须回主线程
    // ...保底 0.6s...
    modelContainer = container   // 触发切到 RootView
}
```

**关键点**：
- `.modelContainer(_:)` modifier 从 Scene 级挪到 `RootView` 上（因为容器现在延迟到 View 层才拿到）
- `ModelContainer` 是 `Sendable`，可以 `Task.detached` 后台构造，只有 `mainContext` 使用必须回 `@MainActor`

### 改动 2：新增 `LaunchScreen.storyboard` 覆盖冷启阶段

- 路径：`personal-butler/LaunchScreen.storyboard`
- 白底、居中主色 `#4A86E8` 圆角方块 + 白色 SF Symbol `person.crop.circle.badge.checkmark` + 双行文字「私人管家 / 你的生活，尽在掌握」，视觉与 `LaunchView` 静态部分对齐

**踩坑：storyboard 不允许 user-defined runtime attribute**
- 原本用 `<userDefinedRuntimeAttribute keyPath="layer.cornerRadius" value="24"/>` 给方块加圆角，编译报错 `Launch screens may not contain user-defined runtime attributes`
- 换成叠两个 SF Symbol：底层 `app.fill`（自带圆角方形，`tintColor` 染主色）+ 上层 `person.crop.circle.badge.checkmark`（白色）

### 改动 3：`project.pbxproj` 切换启动屏配置

Debug/Release 两份 build settings 都改：

```diff
- INFOPLIST_KEY_UILaunchScreen_Generation = YES;
+ INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;
```

工程用的是 Xcode 16 `PBXFileSystemSynchronizedRootGroup`（`objectVersion = 77`），新增 storyboard 文件自动纳入 target，**不需要**手动加 file reference / build phase。

## 验证与回归

- **`xcodebuild build`（Debug）**：`** BUILD SUCCEEDED **`
- **`ibtool --errors --warnings /path/to/LaunchScreen.storyboard`**：无输出（干净）
- **手动验证清单**（用户在真机/模拟器执行）：
  - **必须卸载旧版重装**再测冷启——iOS 会缓存启动屏快照，直接覆盖安装可能还是看到旧的白屏
  - 冷启：立即看到 storyboard 启动屏（静态 Logo + 文字）→ 无缝切到 `LaunchView`（同一位置的 Logo 开始呼吸 + 底部菊花）→ 淡入主页
  - 二次冷启：storyboard 阶段短（<1s）→ `LaunchView` 保底 0.6s（可在 `bootstrap()` 里调）→ 主页
- **回归清单**：
  - `RootView` 现在拿的是"`bootstrap` 里创建的" ModelContainer，`@Query`/`@Environment(\.modelContext)` 一切照旧生效
  - `SeedData.ensureSeeded` 从原本 `MainTabView.task` 挪到了 `bootstrap()`；`MainTabView.task` 的 seed 调用如果还留着会重复执行（幂等，不出错但没必要，需要清理）

## 经验与复用

- **iOS App 启动白屏问题的排查顺序**：
  1. 先看 `INFOPLIST_KEY_UILaunchScreen*` / `UILaunchStoryboardName`——系统启动屏没配好，SwiftUI 视图永远救不了那段
  2. 再看 `@main App struct` 里有没有**同步阻塞**的属性初始化（`ModelContainer` / `NSPersistentContainer` / 大文件读取 / 网络等待）
  3. 最后才是自家过渡页时长/切换动画
- **SwiftUI App 启动屏必须两层配合**：系统启动屏负责「进程冷启 → SwiftUI 首帧」，自家 `LaunchView` 负责「SwiftUI 首帧 → 业务就绪」。任一缺失都会有断层
- **`ModelContainer` 后台构造技巧**：`ModelContainer` 是 `Sendable`，可以 `Task.detached` 到后台线程构造；只有 `mainContext` 访问必须回 `@MainActor`。`ModelActor` 场景可以在后台 actor 里用容器创建独立 `ModelContext`
- **Xcode 16 `PBXFileSystemSynchronizedRootGroup` 的便利**：在同步组下新增文件自动纳入 target，不用改 pbxproj 的 file reference / build phase，改工程文件的心智负担大幅下降。但**改 build settings 还是要动 pbxproj**（如 `INFOPLIST_KEY_*`）
- **LaunchScreen.storyboard 限制**：
  - 不允许 user-defined runtime attribute（→ 圆角/阴影需要用 SF Symbol / 图片资源实现）
  - 不允许自定义类、代码、动画、`ProgressView`
  - `INFOPLIST_KEY_UILaunchScreen_Generation = YES` 与 `INFOPLIST_KEY_UILaunchStoryboardName` **互斥**，只能配一个（否则冲突）
- **iOS 启动屏快照缓存**：iOS 会给启动屏拍快照缓存，改了 storyboard 后**必须卸载重装或至少重启设备**才看得到新效果，覆盖安装未必刷新

## 引用

- 项目规范：[[AGENTS]] § 4 数据流心智模型（SwiftData 层次）
- 相关 spec：[[docs/module-spec/module-app-shell-spec]] § 4 · App 启动初始化
- 苹果文档：[Specifying Your App's Launch Screen](https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen)
