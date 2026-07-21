//
//  RootView.swift
//  根视图：NavigationStack 常驻，root 是 TabView，子页面通过 push 打开。
//  这样系统边缘滑动手势、返回按钮、pop 动画全部原生。
//

import SwiftUI

struct RootView: View {
    @StateObject private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            MainTabView()
                .navigationDestination(for: String.self) { moduleID in
                    AppModuleRouter.destination(for: moduleID)
                }
        }
        .environmentObject(router)
    }
}
