//
//  PersonalButlerApp.swift
//  私人管家 主入口
//

import SwiftUI
import SwiftData

@main
struct PersonalButlerApp: App {
    @StateObject private var env = AppEnvironment()

    /// ModelContainer 延迟到 bootstrap 里异步创建，避免首启建库/迁移
    /// 时同步阻塞 App 属性初始化 → SwiftUI 主 Scene 迟迟拿不到首帧，
    /// 用户看到的是系统 UILaunchScreen（若未配置就是白屏）而不是 LaunchView。
    @State private var modelContainer: ModelContainer?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let container = modelContainer {
                    RootView()
                        .environmentObject(env)
                        .environment(\.locale, .init(identifier: "zh-Hans"))
                        .tint(AppColorTheme.primary)
                        .modelContainer(container)
                        .transition(.opacity)
                } else {
                    LaunchView()
                        .environment(\.locale, .init(identifier: "zh-Hans"))
                        .transition(.opacity)
                        .task {
                            await bootstrap()
                        }
                }
            }
            .animation(.easeOut(duration: 0.5), value: modelContainer == nil)
        }
    }

    /// 冷启初始化：SwiftData 建库/迁移 + SeedData 首启灌数据。
    /// 全部走后台任务，SwiftUI 首帧可以立即渲染 LaunchView。
    /// 保底展示 0.5s，避免二次启动 bootstrap 秒完导致切换太生硬；
    /// 更长的保底（走完一个呼吸循环 1.2s）会让日常启动变慢，权衡后不采用。
    @MainActor
    private func bootstrap() async {
        let start = Date()

        // 1. ModelContainer 初始化（首启最耗时的部分，2~3s 白屏元凶）
        //    ModelContainer 是 Sendable，可在后台构造。
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
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("SwiftData 初始化失败: \(error)")
            }
        }.value

        // 2. SeedData 必须在 MainActor（mainContext 主线程访问约束）
        SeedData.ensureSeeded(in: container.mainContext)

        // 3. 保底最小展示时长
        let elapsed = Date().timeIntervalSince(start)
        let minShow: TimeInterval = 0.5
        if elapsed < minShow {
            try? await Task.sleep(nanoseconds: UInt64((minShow - elapsed) * 1_000_000_000))
        }

        modelContainer = container
    }
}
