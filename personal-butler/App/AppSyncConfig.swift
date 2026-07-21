//
//  AppSyncConfig.swift
//  局域网同步全局配置
//

import Foundation

enum AppSyncConfig {
    static let defaultPort = 8090
    static let syncTokenKey = "sync.token"
    static let serverHostKey = "sync.server.host"

    static var host: String {
        get { UserDefaults.standard.string(forKey: serverHostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: serverHostKey) }
    }

    static var token: String {
        get { UserDefaults.standard.string(forKey: syncTokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: syncTokenKey) }
    }

    /// 稳定的设备唯一 ID
    static var deviceID: String {
        let key = "sync.deviceId"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}
