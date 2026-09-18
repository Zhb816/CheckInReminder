//
//  AppSettings.swift
//  打卡提醒 - 全局设置与当日状态持久化
//

import Foundation
import CoreLocation

/// 所有配置都存 UserDefaults，App 被系统杀掉后重新启动依然生效
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum K {
        static let zoneLat        = "zone.lat"
        static let zoneLon        = "zone.lon"
        static let zoneAddress    = "zone.address"
        static let radius         = "zone.radius"
        static let enabled        = "task.enabled"
        static let windowStart    = "window.start"      // 距 0:00 的分钟数
        static let windowEnd      = "window.end"        // 距 0:00 的分钟数
        static let repeatMinutes  = "remind.repeat"     // 0 = 只提醒一次
        static let soundEnabled   = "remind.sound"
        static let soundFile      = "remind.soundFile"
        static let vibrateEnabled = "remind.vibrate"
        static let tailReminder   = "remind.tailReminder"
        static let dayKey         = "day.key"
        static let visitedToday   = "day.visited"
        static let checkedInToday = "day.checkedIn"
        static let lastTrigger    = "day.lastTrigger"
    }

    private let ud = UserDefaults.standard

    // MARK: - A 区域

    @Published var zoneLatitude: Double? {
        didSet { ud.set(zoneLatitude, forKey: K.zoneLat) }
    }
    @Published var zoneLongitude: Double? {
        didSet { ud.set(zoneLongitude, forKey: K.zoneLon) }
    }
    /// A 区域的名称/地址（搜索选点时记录，方便辨认）
    @Published var zoneAddress: String? {
        didSet { ud.set(zoneAddress, forKey: K.zoneAddress) }
    }
    /// 离开 A 中心多少米后触发提醒，默认 30 米
    @Published var radius: Double {
        didSet { ud.set(radius, forKey: K.radius) }
    }

    // MARK: - 任务开关与时间窗

    @Published var enabled: Bool {
        didSet { ud.set(enabled, forKey: K.enabled) }
    }
    @Published var windowStartMinute: Int {
        didSet { ud.set(windowStartMinute, forKey: K.windowStart) }
    }
    @Published var windowEndMinute: Int {
        didSet { ud.set(windowEndMinute, forKey: K.windowEnd) }
    }
    /// 触发后每隔多少分钟再提醒一次（0 = 只提醒一次）
    @Published var repeatMinutes: Int {
        didSet { ud.set(repeatMinutes, forKey: K.repeatMinutes) }
    }
    /// 窗口结束前 10 分钟，若当天来过 A 但还没打卡，兜底提醒一次
    @Published var tailReminderEnabled: Bool {
        didSet { ud.set(tailReminderEnabled, forKey: K.tailReminder) }
    }

    // MARK: - 提醒方式

    @Published var soundEnabled: Bool {
        didSet { ud.set(soundEnabled, forKey: K.soundEnabled) }
    }
    /// 当前选中的铃声文件名（内置或自定义，都带扩展名）
    @Published var selectedSound: String {
        didSet { ud.set(selectedSound, forKey: K.soundFile) }
    }
    @Published var vibrateEnabled: Bool {
        didSet { ud.set(vibrateEnabled, forKey: K.vibrateEnabled) }
    }

    // MARK: - 当日状态

    /// 今天是否到过 A 区域（没有到过 → 整天都不提醒）
    @Published private(set) var visitedToday: Bool {
        didSet { ud.set(visitedToday, forKey: K.visitedToday) }
    }
    /// 今天是否已打卡（打卡后不再提醒）
    @Published private(set) var checkedInToday: Bool {
        didSet { ud.set(checkedInToday, forKey: K.checkedInToday) }
    }
    private var lastTriggerDate: Date? {
        didSet { ud.set(lastTriggerDate?.timeIntervalSince1970, forKey: K.lastTrigger) }
    }
    private var dayKey: String {
        didSet { ud.set(dayKey, forKey: K.dayKey) }
    }

    // MARK: - Init

    private init() {
        // 没有存过经纬度时 UserDefaults 返回 0，这里用 object(forKey:) 判空
        self.zoneLatitude      = ud.object(forKey: K.zoneLat) as? Double
        self.zoneLongitude     = ud.object(forKey: K.zoneLon) as? Double
        self.zoneAddress       = ud.string(forKey: K.zoneAddress)
        self.radius            = ud.object(forKey: K.radius) as? Double ?? 30
        self.enabled           = ud.object(forKey: K.enabled) as? Bool ?? true
        self.windowStartMinute = ud.object(forKey: K.windowStart) as? Int ?? (17 * 60 + 30)
        self.windowEndMinute   = ud.object(forKey: K.windowEnd) as? Int ?? (19 * 60)
        self.repeatMinutes     = ud.object(forKey: K.repeatMinutes) as? Int ?? 5
        self.soundEnabled      = ud.object(forKey: K.soundEnabled) as? Bool ?? true
        self.selectedSound     = ud.string(forKey: K.soundFile) ?? "reminder.wav"
        self.vibrateEnabled    = ud.object(forKey: K.vibrateEnabled) as? Bool ?? true
        self.tailReminderEnabled = ud.object(forKey: K.tailReminder) as? Bool ?? true

        let storedDay = ud.string(forKey: K.dayKey) ?? ""
        let today = Self.todayKey()
        if storedDay == today {
            self.dayKey         = storedDay
            self.visitedToday   = ud.bool(forKey: K.visitedToday)
            self.checkedInToday = ud.bool(forKey: K.checkedInToday)
            let ts = ud.double(forKey: K.lastTrigger)
            self.lastTriggerDate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        } else {
            // 跨天：清空当日状态
            self.dayKey         = today
            self.visitedToday   = false
            self.checkedInToday = false
            self.lastTriggerDate = nil
        }
    }

    // MARK: - A 区域

    var zoneCenter: CLLocationCoordinate2D? {
        guard let lat = zoneLatitude, let lon = zoneLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var coordinateText: String {
        guard let lat = zoneLatitude, let lon = zoneLongitude else { return "未设置" }
        return String(format: "%.5f, %.5f", lat, lon)
    }

    var zoneName: String {
        guard zoneCenter != nil else { return "未设置" }
        if let addr = zoneAddress, !addr.isEmpty { return addr }
        return coordinateText
    }

    /// 手动选点（地图长按）：清掉之前的地址名
    func setZone(_ coordinate: CLLocationCoordinate2D) {
        zoneLatitude = coordinate.latitude
        zoneLongitude = coordinate.longitude
        zoneAddress = nil
    }

    /// 搜索选点：记录地点名称
    func setZone(_ coordinate: CLLocationCoordinate2D, name: String?) {
        zoneLatitude = coordinate.latitude
        zoneLongitude = coordinate.longitude
        zoneAddress = name
    }

    func clearZone() {
        zoneLatitude = nil
        zoneLongitude = nil
        zoneAddress = nil
    }

    // MARK: - 当日状态流转

    /// 每次定位回调前调用：跨天自动重置
    func rolloverIfNeeded() {
        let today = Self.todayKey()
        guard dayKey != today else { return }
        dayKey = today
        visitedToday = false
        checkedInToday = false
        lastTriggerDate = nil
    }

    func markVisited() {
        rolloverIfNeeded()
        if !visitedToday { visitedToday = true }
    }

    func markCheckedIn() {
        rolloverIfNeeded()
        checkedInToday = true
        // 打卡后主动撤掉所有待送达的提醒
        NotificationService.shared.cancelAllPending()
    }

    /// 判断此刻是否允许触发提醒（节流用）
    func canTriggerAgain(now: Date = Date()) -> Bool {
        guard repeatMinutes > 0 else { return lastTriggerDate == nil }
        guard let last = lastTriggerDate else { return true }
        return now.timeIntervalSince(last) >= Double(repeatMinutes) * 60
    }

    func markTriggered(now: Date = Date()) {
        lastTriggerDate = now
    }

    func resetTodayForDebug() {
        visitedToday = false
        checkedInToday = false
        lastTriggerDate = nil
        NotificationService.shared.cancelAllPending()
    }

    // MARK: - 时间窗

    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 把「分钟数」换算成今天的 Date
    func dateToday(atMinute minute: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = minute / 60
        comps.minute = minute % 60
        comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    /// 当前是否落在 17:30–19:00（默认）这个时间窗内
    func isInTimeWindow(now: Date = Date()) -> Bool {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let m = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if windowStartMinute <= windowEndMinute {
            return m >= windowStartMinute && m <= windowEndMinute
        }
        // 跨零点的情况（例如 22:00–01:00）
        return m >= windowStartMinute || m <= windowEndMinute
    }

    var windowText: String {
        "\(Self.hhmm(windowStartMinute)) – \(Self.hhmm(windowEndMinute))"
    }

    static func hhmm(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
