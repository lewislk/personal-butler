//
//  AppModuleRouter.swift
//  统一路由到子页面
//

import SwiftUI

enum AppModuleRouter {
    @ViewBuilder
    static func destination(for moduleID: String) -> some View {
        switch moduleID {
        case "schedule":    ScheduleView()
        case "anniversary": AnniversaryView()
        case "password":    PasswordView()
        case "food":        FoodRecordView()
        case "cook":        CookRecipeView()
        case "note":        NoteView()
        default:            ComingSoonView(title: displayName(for: moduleID))
        }
    }

    static func displayName(for id: String) -> String {
        switch id {
        case "ledger": return "记账本"
        case "health": return "健康记录"
        case "travel": return "旅行清单"
        case "movie":  return "观影记录"
        default:       return "敬请期待"
        }
    }
}

struct ComingSoonView: View {
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(AppColorTheme.primary.opacity(0.6))
            Text(title).font(.system(size: 16, weight: .semibold))
            Text("二期功能，敬请期待").font(.system(size: 13)).foregroundStyle(AppColorTheme.textSub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
