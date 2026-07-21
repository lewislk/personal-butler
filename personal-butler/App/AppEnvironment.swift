//
//  AppEnvironment.swift
//  全局环境：跨页面通信 / 数据变更通知
//

import Foundation
import Combine

final class AppEnvironment: ObservableObject {
    /// 数据变化通知（同步导入 / 备份恢复后统一广播）
    let dataChanged = PassthroughSubject<Void, Never>()

    /// 应用锁：解锁状态
    @Published var isUnlocked: Bool = true

    /// 最近同步时间（UserDefaults 缓存）
    @Published var lastSyncTime: Date? = {
        if let t = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date { return t }
        return nil
    }()

    func markSynced() {
        lastSyncTime = Date()
        UserDefaults.standard.set(lastSyncTime, forKey: "lastSyncTime")
    }
}
