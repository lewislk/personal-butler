//
//  OTPGenerator.swift
//  轻量 TOTP 生成（RFC 6238），避免额外依赖
//

import Foundation
import CryptoKit

enum OTPGenerator {
    /// 生成 6 位 TOTP（Base32 密钥）
    static func totp(secretBase32: String, period: Int = 30, digits: Int = 6, at date: Date = Date()) -> String {
        guard let key = base32Decode(secretBase32.uppercased()) else { return "------" }
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(period)
        var big = counter.bigEndian
        let counterData = Data(bytes: &big, count: MemoryLayout<UInt64>.size)

        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: key))
        let mac = Data(hmac)
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let bin = (UInt32(mac[offset] & 0x7f) << 24)
               | (UInt32(mac[offset + 1] & 0xff) << 16)
               | (UInt32(mac[offset + 2] & 0xff) << 8)
               | (UInt32(mac[offset + 3] & 0xff))
        let mod = UInt32(pow(10.0, Double(digits)))
        let code = bin % mod
        return String(format: "%0\(digits)d", code)
    }

    /// 距离下次刷新的剩余秒数
    static func remainingSeconds(period: Int = 30, at date: Date = Date()) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }

    private static func base32Decode(_ s: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let trimmed = s.replacingOccurrences(of: " ", with: "")
                       .replacingOccurrences(of: "=", with: "")
        if trimmed.isEmpty { return nil }
        var buffer: UInt64 = 0
        var bits = 0
        var out = Data()
        for ch in trimmed {
            guard let idx = alphabet.firstIndex(of: ch) else { return nil }
            let val = alphabet.distance(from: alphabet.startIndex, to: idx)
            buffer = (buffer << 5) | UInt64(val)
            bits += 5
            if bits >= 8 {
                bits -= 8
                let byte = UInt8((buffer >> UInt64(bits)) & 0xff)
                out.append(byte)
            }
        }
        return out
    }
}
