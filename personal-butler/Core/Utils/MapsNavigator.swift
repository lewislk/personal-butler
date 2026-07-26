//
//  MapsNavigator.swift
//  地图导航：弹出选择面板让用户选择本机已安装的地图 App
//
//  Apple 地图始终可用；高德 / 百度 / Google Maps 需要本机已安装。
//  由于 LSApplicationQueriesSchemes 白名单需要 Info.plist 配置（项目用 INFOPLIST_KEY_*，
//  不便配置数组类型），这里不依赖 canOpenURL，直接弹固定列表让用户选；
//  若选了未安装的 App，UIApplication.shared.open 的 completion 会回 false，
//  弹 alert 提示用户去 App Store 安装。
//

import UIKit
import SwiftUI

enum MapsNavigator {
    /// 支持的地图 App
    enum MapsApp: String, CaseIterable, Identifiable {
        case apple = "Apple 地图"
        case amap = "高德地图"
        case baidu = "百度地图"
        case google = "Google Maps"

        var id: String { rawValue }
    }

    /// 构造各 App 的导航 URL
    static func url(for app: MapsApp,
                    latitude: Double,
                    longitude: Double,
                    name: String? = nil) -> URL? {
        let q = (name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch app {
        case .apple:
            // http:// 比 maps:// 兼容性更好；未装 Maps 时系统兜底走 Web
            return URL(string: "http://maps.apple.com/?q=\(q)&ll=\(latitude),\(longitude)")
        case .amap:
            // 高德：dev=0 表示传入 wgs84 坐标，高德会自动转 gcj02
            return URL(string: "iosamap://viewMap?sourceApplication=personal-butler&poiname=\(q)&lat=\(latitude)&lon=\(longitude)&dev=0")
        case .baidu:
            // 百度：coord_type=wgs84 让百度地图按 wgs84 解析
            return URL(string: "baidumap://map/marker?location=\(latitude),\(longitude)&title=\(q)&content=\(q)&coord_type=wgs84&src=webapp.personalButler")
        case .google:
            // Google Maps：center 是坐标，q 是地点名
            return URL(string: "comgooglemaps://?q=\(q)&center=\(latitude),\(longitude)")
        }
    }

    /// 直接拉起指定 App；若未安装，completion 回调 false
    static func open(_ app: MapsApp,
                     latitude: Double,
                     longitude: Double,
                     name: String? = nil,
                     completion: ((Bool) -> Void)? = nil) {
        guard let url = url(for: app, latitude: latitude, longitude: longitude, name: name) else {
            completion?(false)
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            completion?(success)
        }
    }
}

// MARK: - SwiftUI 导航选择面板

/// 导航 App 选择修饰器：弹 confirmationDialog 让用户选 Apple / 高德 / 百度 / Google Maps
struct MapsNavigatorPicker: ViewModifier {
    @Binding var isPresented: Bool
    let latitude: Double
    let longitude: Double
    let name: String?
    /// 打开失败的提示
    @State private var failedApp: MapsNavigator.MapsApp?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("选择导航应用",
                                isPresented: $isPresented,
                                titleVisibility: .visible) {
                ForEach(MapsNavigator.MapsApp.allCases) { app in
                    Button(app.rawValue) {
                        MapsNavigator.open(app,
                                           latitude: latitude,
                                           longitude: longitude,
                                           name: name) { ok in
                            if !ok {
                                DispatchQueue.main.async { failedApp = app }
                            }
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("未安装「\(failedApp?.rawValue ?? "")」",
                   isPresented: Binding(get: { failedApp != nil },
                                        set: { if !$0 { failedApp = nil } })) {
                Button("好", role: .cancel) { failedApp = nil }
            } message: {
                Text("请先在 App Store 安装该应用，或选择其它导航应用。")
            }
    }
}

extension View {
    /// 弹出导航 App 选择面板（Apple 地图 / 高德 / 百度 / Google Maps）
    func mapsNavigatorPicker(isPresented: Binding<Bool>,
                             latitude: Double,
                             longitude: Double,
                             name: String?) -> some View {
        modifier(MapsNavigatorPicker(isPresented: isPresented,
                                     latitude: latitude,
                                     longitude: longitude,
                                     name: name))
    }
}
