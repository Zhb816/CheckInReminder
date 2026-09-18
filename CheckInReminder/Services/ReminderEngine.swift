//
//  ReminderEngine.swift
//  提醒决策核心：
//  ① 当天必须到过 A 区域  ② 必须在 17:30–19:00 窗口内  ③ 必须离开 A 区域 30 米外
//  三个条件同时满足才提醒；已打卡或当天没去过 A 区域 → 不触发
//

import Foundation
import UserNotifications

final class ReminderEngine: ObservableObject {

    static let shared = ReminderEngine()

    private let settings = AppSettings.shared
    private let location = LocationManager.shared
    private let notifier = NotificationService.shared

    /// 首页展示的最近运行日志（仅内存，方便调试）
    @Published private(set) var logs: [String] = []

    private init() {}

    // MARK: - 绑定

    func bind() {
        location.onEnterZone = { [weak self] in self?.handleEnterZone() }
        location.onExitZone  = { [weak self] distance in self?.handleExitZone(distance: distance) }
        location.onLocationUpdated = { [weak self] _ in self?.refreshScheduling() }
    }

    // MARK: - 事件

    private func handleEnterZone() {
        settings.rolloverIfNeeded()
        settings.markVisited()
        log("进入 A 区域 → 今日已到访")
        refreshScheduling()
    }

    /// 离开 A 区域（超过设定半径）时调用
    private func handleExitZone(distance: Double) {
        settings.rolloverIfNeeded()

        guard settings.enabled else {
            log("离开 A 区域 \(Int(distance))m，但任务已关闭")
            return
        }
        guard settings.visitedToday else {
            // 需求核心：这天没去过 A 区域 → 不做这个任务
            log("离开 A 区域 \(Int(distance))m，但今天从未进入 A 区域 → 不提醒")
            return
        }
        guard !settings.checkedInToday else {
            log("离开 A 区域 \(Int(distance))m，但今天已打卡 → 不提醒")
            return
        }
        guard settings.isInTimeWindow() else {
            log("离开 A 区域 \(Int(distance))m，不在 \(settings.windowText) 时间窗内 → 不提醒")
            return
        }
        guard settings.canTriggerAgain() else {
            log("离开 A 区域 \(Int(distance))m，节流中（\(settings.repeatMinutes) 分钟内已提醒过）")
            return
        }

        settings.markTriggered()
        notifier.fireCheckInReminder(distance: distance)
        log("✅ 触发提醒：离开 A 区域 \(Int(distance))m，位于 \(settings.windowText) 窗口内")

        scheduleRepeatIfNeeded()
    }

    /// 已触发过一次且开启了「持续提醒」时，用本地定时通知做续提醒
    private func scheduleRepeatIfNeeded() {
        guard settings.repeatMinutes > 0, !settings.checkedInToday else { return }
        let next = Date().addingTimeInterval(Double(settings.repeatMinutes) * 60)
        guard next < settings.dateToday(atMinute: settings.windowEndMinute) else { return }
        notifier.scheduleTailReminder(at: next)   // 复用定时通道，内容会随状态更新
    }

    /// 时间窗 / 到访状态变化后，重新安排「窗口结束前兜底提醒」
    func refreshScheduling() {
        guard settings.enabled,
              settings.tailReminderEnabled,
              settings.visitedToday,
              !settings.checkedInToday else { return }

        let end = settings.dateToday(atMinute: settings.windowEndMinute)
        let tail = end.addingTimeInterval(-10 * 60)
        guard tail > Date() else { return }
        notifier.scheduleTailReminder(at: tail)
    }

    // MARK: - 打卡

    func checkIn() {
        settings.markCheckedIn()
        log("🙌 已打卡，今日提醒结束")
    }

    // MARK: - 通知按钮回调

    func handleNotificationAction(_ identifier: String) {
        switch identifier {
        case NotificationService.actionDoneId:
            checkIn()
        case NotificationService.actionSnooze:
            notifier.scheduleTailReminder(at: Date().addingTimeInterval(10 * 60))
            log("稍后提醒：10 分钟后再响一次")
        default:
            break
        }
    }

    // MARK: - 测试

    /// 首页「测试提醒」按钮：立刻来一次铃声 + 震动
    func testReminder() {
        notifier.fireCheckInReminder(distance: settings.radius)
        log("🔔 测试提醒已发送（若没声音请检查手机是否静音）")
    }

    // MARK: - 日志

    private func log(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: Date()))  \(text)"
        DispatchQueue.main.async {
            self.logs.insert(line, at: 0)
            if self.logs.count > 30 { self.logs.removeLast() }
        }
        print("[引擎] \(line)")
    }
}
