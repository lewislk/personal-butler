//
//  AppRouter.swift
//  根级路由：驱动子页面 NavigationStack 的 path
//

import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    /// 子页面导航路径。空 = 展示 TabView 主界面。
    /// 元素为模块 id（"schedule" / "anniversary" / ...），支持继续 push 更深页面。
    @Published var path: [String] = []

    var isInSubPage: Bool { !path.isEmpty }

    func open(_ id: String) { path.append(id) }
    func back() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
