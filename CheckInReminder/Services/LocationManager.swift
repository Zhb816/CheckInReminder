//
//  LocationManager.swift
//  后台定位 + 地理围栏：进入 A 区域记「已到访」，离开 30 米触发回调
//

import Foundation
import CoreLocation
import UIKit

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationManager()

    private static let regionId = "ZONE_A_REGION"

    private let manager = CLLocationManager()
    private let settings = AppSettings.shared

    // 回调
    var onEnterZone: (() -> Void)?
    var onExitZone: ((Double) -> Void)?     // 参数：离开时距 A 中心的距离（米）
    var onLocationUpdated: ((CLLocation) -> Void)?

    // MARK: - 对外状态

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    /// 当前是否在 A 区域内
    @Published private(set) var isInsideZone = false
    /// 当前距 A 中心的距离（米），未设置区域时为 nil
    @Published private(set) var distanceToZone: Double?

    private var wasInsideZone = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true   // 需在 Background Modes 勾选 Location
        manager.showsBackgroundLocationIndicator = false
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - 权限

    var hasAlwaysPermission: Bool {
        switch authorizationStatus {
        case .authorizedAlways: return true
        default: return false
        }
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    func requestWhenInUsePermission() {
        manager.requestWhenInUseAuthorization()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 启停

    /// 根据设置重建围栏并启动定位。设置变化时重新调用即可。
    func start() {
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus

        guard CLLocationManager.locationServicesEnabled() else {
            print("[定位] 系统定位总开关未打开")
            return
        }

        // 显著位置变化：省电的后台兜底，App 被挂起/杀掉后系统仍会唤醒
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }

        // 持续定位（精度自适应：离 A 越近精度越高）
        applyAdaptiveAccuracy()
        manager.startUpdatingLocation()

        rebuildRegion()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    /// A 区域或半径变化后调用
    func rebuildRegion() {
        for region in manager.monitoredRegions where region.identifier == Self.regionId {
            manager.stopMonitoring(for: region)
        }
        guard let center = settings.zoneCenter else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let radius = max(10, settings.radius)     // 系统对过小半径会忽略，这里兜底下限
        let region = CLCircularRegion(center: center, radius: radius, identifier: Self.regionId)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    /// 离 A 区域近时提高精度（保证 30 米这种小半径能及时捕捉到出圈），远时降精度省电
    private func applyAdaptiveAccuracy() {
        if let loc = currentLocation, let center = settings.zoneCenter {
            let d = loc.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
            if d < 500 {
                manager.desiredAccuracy = kCLLocationAccuracyBest
                manager.distanceFilter = 3
            } else if d < 2000 {
                manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                manager.distanceFilter = 20
            } else {
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.distanceFilter = 100
            }
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 50
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if hasAlwaysPermission { start() }
    }

    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedAlways || status == .authorizedWhenInUse { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = loc
            self.onLocationUpdated?(loc)
            self.evaluate(location: loc)
            self.applyAdaptiveAccuracy()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionId else { return }
        DispatchQueue.main.async {
            self.isInsideZone = true
            self.wasInsideZone = true
            self.onEnterZone?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.regionId else { return }
        DispatchQueue.main.async {
            self.isInsideZone = false
            self.wasInsideZone = false
            let d = self.currentDistance() ?? AppSettings.shared.radius
            self.onExitZone?(d)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[定位] 失败: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        print("[围栏] 监控失败: \(error.localizedDescription)")
    }

    // MARK: - 距离判定（围栏 + 手动计算双保险）

    private func currentDistance() -> Double? {
        guard let loc = currentLocation, let center = settings.zoneCenter else { return nil }
        return loc.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
    }

    /// 用小半径围栏时，系统回调可能滞后；这里用实时坐标再判一次，出圈立刻响应
    private func evaluate(location: CLLocation) {
        guard let center = settings.zoneCenter else { return }
        let zoneLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let distance = location.distance(from: zoneLoc)
        distanceToZone = distance

        let inside = distance <= settings.radius
        isInsideZone = inside

        if inside {
            wasInsideZone = true
            onEnterZone?()
        } else if wasInsideZone {
            wasInsideZone = false
            onExitZone?(distance)
        }
    }

    /// 手动触发一次判定（比如改了半径之后）
    func reevaluate() {
        if let loc = currentLocation { evaluate(location: loc) }
    }
}
