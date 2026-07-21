//
//  PersonalButlerApp.swift
//  私人管家 主入口
//

import SwiftUI
import SwiftData

@main
struct PersonalButlerApp: App {
    // SwiftData 容器：底层 SQLite，开启文件保护
    let modelContainer: ModelContainer = {
        do {
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
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData 初始化失败: \(error)")
        }
    }()

    @StateObject private var env = AppEnvironment()

    /// 启动过渡页是否已结束（SeedData 等初始化完成后置 true）
    @State private var launchFinished = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if launchFinished {
                    RootView()
                        .environmentObject(env)
                        .environment(\.locale, .init(identifier: "zh-Hans"))
                        .tint(AppColorTheme.primary)
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
            .animation(.easeInOut(duration: 0.35), value: launchFinished)
        }
        .modelContainer(modelContainer)
    }

    /// 冷启初始化：SeedData 首启灌数据；异步执行避免阻塞主线程。
    /// 同时保底展示 0.6s，避免二次启动时启动页只闪一下反而突兀。
    @MainActor
    private func bootstrap() async {
        let start = Date()
        let context = modelContainer.mainContext

        // 数据种子放到后台优先级，避免与首帧渲染争主线程
        await Task.detached(priority: .userInitiated) {
            await MainActor.run {
                SeedData.ensureSeeded(in: context)
            }
        }.value

        // 保底最小展示时长
        let elapsed = Date().timeIntervalSince(start)
        let minShow: TimeInterval = 0.6
        if elapsed < minShow {
            try? await Task.sleep(nanoseconds: UInt64((minShow - elapsed) * 1_000_000_000))
        }

        launchFinished = true
    }
}
