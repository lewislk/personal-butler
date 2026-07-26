//
//  MapsNavigator.swift
//  Apple Maps 拉起（供 EditFoodSheet 与 FoodRecordView 位置行共用）
//

import UIKit

enum MapsNavigator {
    /// 用 http://maps.apple.com/ 拉起 Apple Maps；未装 Maps 时系统兜底走 Web。
    /// 相比 maps://，http:// 有更强的可用性保证。
    static func openInMaps(latitude: Double, longitude: Double, name: String? = nil) {
        let q = (name ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(latitude),\(longitude)") else {
            return
        }
        UIApplication.shared.open(url)
    }
}
