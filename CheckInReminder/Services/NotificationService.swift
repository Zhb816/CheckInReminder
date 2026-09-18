//
//  NotificationService.swift
//  本地通知：铃声 + 震动，带「我已打卡」快捷操作
//

import Foundation
import UserNotifications
import UIKit
import AVFoundation

final class NotificationService {

    static let shared = NotificationService()

    static let categoryId   = "CHECKIN_CATEGORY"
    static let actionDoneId = "CHECKIN_ACTION_DONE"
    static let actionSnooze = "CHECKIN_ACTION_SNOOZE"

    private init() {}

    // MARK: - 授权

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("[通知] 授权失败: \(error)") }
            DispatchQueue.main.async { completion?(granted) }
        }
        registerCategory()
    }

    func registerCategory() {
        let done   = UNNotificationAction(identifier: Self.actionDoneId,
                                          title: "我已打卡",
                                          options: [.foreground])
        let snooze = UNNotificationAction(identifier: Self.actionSnooze,
                                          title: "10 分钟后再提醒",
                                          options: [])
        let category = UNNotificationCategory(identifier: Self.categoryId,
                                              actions: [done, snooze],
                                              intentIdentifiers: [],
                                              options: [.customDismissAction])
        UNUserNotificationCenter.current()
            .setNotificationCategories([category])
    }

    // MARK: - 发送提醒

    /// 触发打卡提醒（立即送达，铃声 + 震动）
    func fireCheckInReminder(distance: Double? = nil) {
        let settings = AppSettings.shared
        let content = UNMutableNotificationContent()
        content.title = "该打卡啦 ⏰"
        if let d = distance {
            content.body = "已离开 A 区域 \(Int(d)) 米，别忘了打卡～"
        } else {
            content.body = "已离开 A 区域，别忘了打卡～"
        }
        content.categoryIdentifier = Self.categoryId
        content.badge = 1

        content.sound = currentSound()

        let request = UNNotificationRequest(identifier: "checkin-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)   // nil = 立即送达
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("[通知] 发送失败: \(error)") }
        }

        // 通知送达时系统会自动震动；这里在 App 前台时补一次震动，保证手上有感觉
        if settings.vibrateEnabled { vibrate() }
    }

    /// 窗口结束前的兜底提醒（定时送达）
    func scheduleTailReminder(at date: Date) {
        guard date > Date() else { return }   // 已经过了就不排了
        let settings = AppSettings.shared
        let content = UNMutableNotificationContent()
        content.title = "打卡时间快结束了"
        content.body = "今天来过 A 区域，但还没打卡，\(AppSettings.hhmm(settings.windowEndMinute)) 前记得打一下～"
        content.categoryIdentifier = Self.categoryId
        content.sound = currentSound()
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "checkin-tail", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("[通知] 兜底提醒排期失败: \(error)") }
        }
    }

    func cancelAllPending() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = 0 }
    }

    // MARK: - 声音 / 震动

    /// 当前铃声：内置包内文件 → 自定义 Library/Sounds 文件 → 系统默认
    private func currentSound() -> UNNotificationSound? {
        guard AppSettings.shared.soundEnabled else { return nil }
        let name = SoundStore.shared.notificationSoundName
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension

        if Bundle.main.path(forResource: base, ofType: ext) != nil {
            return UNNotificationSound(named: UNNotificationSoundName(name))
        }
        let customURL = SoundStore.shared.soundsDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: customURL.path) {
            return UNNotificationSound(named: UNNotificationSoundName(name))
        }
        return .default
    }

    /// 单纯震动一下（App 在前台时用于补充提示）
    func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
