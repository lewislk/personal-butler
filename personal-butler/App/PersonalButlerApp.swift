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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environment(\.locale, .init(identifier: "zh-Hans"))
                .tint(AppColorTheme.primary)
        }
        .modelContainer(modelContainer)
    }
}
