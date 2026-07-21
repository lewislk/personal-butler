//
//  AppModule.swift
//  首页功能宫格 & 全部应用列表的数据源
//

import Foundation
import SwiftData

@Model
final class AppModule {
    @Attribute(.unique) var id: String    // key 稳定标识：schedule/anniversary/...
    var name: String
    var tag: String                       // 副标题（"计划 / 提醒"）
    var iconSystemName: String            // SF Symbol
    var order: Int                        // 排序序号（0 起）
    var comingSoon: Bool                  // 二期功能

    init(id: String, name: String, tag: String, iconSystemName: String,
         order: Int, comingSoon: Bool = false) {
        self.id = id
        self.name = name
        self.tag = tag
        self.iconSystemName = iconSystemName
        self.order = order
        self.comingSoon = comingSoon
    }
}
