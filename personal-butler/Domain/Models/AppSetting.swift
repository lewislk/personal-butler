//
//  AppSetting.swift
//

import Foundation
import SwiftData

@Model
final class AppSetting {
    @Attribute(.unique) var id: UUID
    var appLockEnabled: Bool
    var appLockMethod: String     // "faceID" / "passcode"
    var lastBackupAt: Date?

    init(id: UUID = UUID(), appLockEnabled: Bool = true,
         appLockMethod: String = "faceID", lastBackupAt: Date? = nil) {
        self.id = id
        self.appLockEnabled = appLockEnabled
        self.appLockMethod = appLockMethod
        self.lastBackupAt = lastBackupAt
    }
}
