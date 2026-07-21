//
//  LocalAuthService.swift
//  面容/指纹校验
//

import Foundation
import LocalAuthentication

enum LocalAuthService {
    /// 尝试生物识别；模拟器或未配置时直接放行（避免开发阻塞）
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true // 开发阶段兜底：无生物识别设备直接通过
        }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}
