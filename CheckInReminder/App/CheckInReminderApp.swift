//
//  CheckInReminderApp.swift
//

import SwiftUI
import UserNotifications

@main
struct CheckInReminderApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings = AppSettings.shared
    @StateObject private var location = LocationManager.shared
    @StateObject private var engine   = ReminderEngine.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 通知授权 + 注册「我已打卡」按钮
        NotificationService.shared.requestAuthorization { granted in
            print("[通知] 授权结果: \(granted)")
        }
        UNUserNotificationCenter.current().delegate = self

        // 绑定定位回调 → 提醒引擎
        ReminderEngine.shared.bind()
        LocationManager.shared.start()

        return true
    }

    // App 在前台时也要弹出提醒
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // 处理通知上的按钮
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ReminderEngine.shared.handleNotificationAction(response.actionIdentifier)
        completionHandler()
    }
}
