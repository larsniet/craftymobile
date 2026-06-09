//
//  AppDelegate.swift
//  CraftyMobile
//
//  Bridges UIKit-only push APIs into the SwiftUI app via @UIApplicationDelegateAdaptor.
//  Handles APNs registration (device token) and incoming pushes — silent pushes
//  refresh the widget; alert pushes are presented by the system.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // If push is already configured, make sure we're registered each launch.
        PushManager.shared.registerIfEnabled()
        return true
    }

    // MARK: APNs registration

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushManager.shared.didRegister(token: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.didFailToRegister(error)
    }

    // MARK: Incoming pushes

    /// Silent / data push: refresh the widget (and apply any embedded snapshot).
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Parse the (non-Sendable) payload synchronously here, then hand only the
        // Sendable result across the async boundary.
        let servers = BackgroundRefreshManager.snapshotServers(from: userInfo as? [String: Any])
        Task {
            await BackgroundRefreshManager.shared.performPushRefresh(servers: servers)
            completionHandler(.newData)
        }
    }

    // MARK: Foreground presentation

    /// Show alert pushes even while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
