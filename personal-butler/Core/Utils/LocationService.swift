//
//  LocationService.swift
//  一次性抓取当前坐标（Foreground WhenInUse），供美食记录位置录入使用。
//

import Foundation
import CoreLocation

enum LocationError: Error, LocalizedError {
    case denied         // 用户拒绝 / 家长控制限制
    case unavailable    // 系统定位服务关闭 / 无法定位
    case timeout        // 15s 未返回

    var errorDescription: String? {
        switch self {
        case .denied:      return "位置权限未开启"
        case .unavailable: return "无法获取当前位置"
        case .timeout:     return "定位超时，请重试"
        }
    }
}

/// 一次性定位服务：调用 `requestOneShot()` 返回一次坐标后自动 `stopUpdatingLocation`。
/// 不做持续监听，不订阅方向 / 大范围变化，不申请 `Always` 权限。
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // 餐厅粒度足够
    }

    func requestOneShot() async throws -> CLLocationCoordinate2D {
        // 已在跑一次抓取：拒绝并发调用
        if continuation != nil {
            throw LocationError.unavailable
        }

        // 权限检查 / 申请
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // 等待用户回应；didChangeAuthorization 会驱动后续
        case .denied, .restricted:
            throw LocationError.denied
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            throw LocationError.unavailable
        }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            // 只有已授权时才立即请求；未定则等 didChangeAuthorization 回调再请求
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }

            // 15s 超时兜底
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                await MainActor.run {
                    self?.finish(with: .failure(LocationError.timeout))
                }
            }
        }
    }

    private func finish(with result: Result<CLLocationCoordinate2D, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let cont = continuation else { return }
        continuation = nil
        switch result {
        case .success(let c): cont.resume(returning: c)
        case .failure(let e): cont.resume(throwing: e)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                // 用户刚同意：真正发起请求
                if self.continuation != nil { self.manager.requestLocation() }
            case .denied, .restricted:
                self.finish(with: .failure(LocationError.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor [weak self] in
            self?.finish(with: .success(coord))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: .failure(LocationError.unavailable))
        }
    }
}
