//
//  MainTabView.swift
//  自定义底部三 Tab（普通 HStack，非系统 TabView）
//  这样从这里 push 子页面时，NavigationStack 会整体覆盖，tab bar 自动消失
//

import SwiftUI

struct MainTabView: View {
    @State private var current: AppTab = .home

    var body: some View {
        VStack(spacing: 0) {
            // 内容区
            ZStack {
                switch current {
                case .home:   HomeView()
                case .allApp: AllAppView()
                case .mine:   MineView()
                }
            }
            .frame(maxHeight: .infinity)

            // 自定义 tab bar
            tabBar
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var tabBar: some View {
        HStack {
            tabItem(.home,   title: "主页",       icon: "house",             activeIcon: "house.fill")
            tabItem(.allApp, title: "全部应用",   icon: "square.grid.2x2",   activeIcon: "square.grid.2x2.fill")
            tabItem(.mine,   title: "我的",       icon: "person",            activeIcon: "person.fill")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)  // safe area 由外层承担
        .background(
            Color.white
                .overlay(alignment: .top) {
                    Rectangle().fill(AppColorTheme.border).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabItem(_ tab: AppTab, title: String, icon: String, activeIcon: String) -> some View {
        let active = current == tab
        return Button {
            current = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? activeIcon : icon)
                    .font(.system(size: 20, weight: .regular))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(active ? AppColorTheme.primary : Color(hex: 0xB0B4BA))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
