//
//  BackgroundRefreshManager.swift
//  CraftyMobile
//
//  Best-effort background server-status alerts, with no backend. A
//  BGAppRefreshTask wakes on iOS's schedule, fetches each server's stats,
//  compares them to the last-known snapshot, and fires a *local* notification
//  when a server crashes or recovers. It also refreshes the widget snapshot.
//
//  Honest limitations (surfaced to the user in Settings): iOS decides when these
//  run — typically every 15–60 min, sometimes much longer — and they don't run
//  at all if the user force-quits the app. For real-time alerts you'd need a
//  push backend (APNs), which a sideloaded personal app doesn't have.
//

import Foundation
import BackgroundTasks
import UserNotifications
import WidgetKit

final class BackgroundRefreshManager: @unchecked Sendable {
    static let shared = BackgroundRefreshManager()

    /// Must match the entry in Info.plist `BGTaskSchedulerPermittedIdentifiers`
    /// and the `.backgroundTask(.appRefresh(...))` modifier in the App.
    static let taskIdentifier = "com.larsniet.CraftyMobile.refresh"

    private let settings: AppSettings
    private let api: CraftyAPI

    init(settings: AppSettings = .shared, api: CraftyAPI = .shared) {
        self.settings = settings
        self.api = api
    }

    // MARK: - Notification authorization

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Scheduling

    /// Ask iOS to run the refresh task no earlier than ~15 minutes from now.
    /// (15 min is the practical floor; iOS frequently waits longer.)
    func scheduleRefresh() {
        guard settings.alertsEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // Submission can throw on Simulator or when the user disabled Background
        // App Refresh; that's non-fatal, so we ignore it.
        try? BGTaskScheduler.shared.submit(request)
    }

    func cancelScheduled() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    // MARK: - The work

    /// BGAppRefreshTask entry point. Schedules the next run, then refreshes.
    /// When the push server is handling alerts, we don't also fire local ones.
    func performRefresh() async {
        scheduleRefresh()
        guard settings.alertsEnabled || settings.pushConfigured else { return }
        await runRefresh(fireAlerts: settings.alertsEnabled && !settings.pushConfigured)
    }

    /// Silent-push entry point. If the push carried a fresh snapshot we apply it
    /// directly (no fetch); otherwise we fetch. Alerts come from the server's
    /// push, so we never fire local ones here. `servers` is parsed by the caller
    /// (synchronously) so only Sendable values cross the async boundary.
    func performPushRefresh(servers: [CraftyWidgetSnapshot.Server]?) async {
        if let servers, !servers.isEmpty {
            WidgetSnapshotStore.write(CraftyWidgetSnapshot(generatedAt: Date(), servers: servers))
            return
        }
        guard settings.isConfigured else { return }
        await runRefresh(fireAlerts: false)
    }

    /// Decode the compact `snapshot.servers` array a push may embed, so the
    /// widget updates without an extra round-trip to Crafty.
    static func snapshotServers(from payload: [String: Any]?) -> [CraftyWidgetSnapshot.Server]? {
        guard let snap = payload?["snapshot"] as? [String: Any],
              let raw = snap["servers"] as? [[String: Any]], !raw.isEmpty else { return nil }
        return raw.map { s in
            CraftyWidgetSnapshot.Server(
                id: (s["id"] as? String) ?? "",
                name: (s["name"] as? String) ?? "Server",
                status: (s["status"] as? String) ?? ServerStatus.stopped.rawValue,
                online: (s["online"] as? Int) ?? 0,
                max: (s["max"] as? Int) ?? 0,
                cpu: (s["cpu"] as? Double) ?? 0,
                memory: (s["memory"] as? String) ?? "—"
            )
        }
    }

    private func runRefresh(fireAlerts: Bool) async {
        guard settings.isConfigured else { return }

        // Previous statuses come from the last snapshot we wrote.
        let previous = WidgetSnapshotStore.read()
        let prevStatus = Dictionary(
            uniqueKeysWithValues: (previous?.servers ?? []).map { ($0.id, $0.status) }
        )

        guard let servers = try? await api.listServers() else { return }

        var rows: [CraftyWidgetSnapshot.Server] = []
        await withTaskGroup(of: CraftyWidgetSnapshot.Server?.self) { group in
            for server in servers {
                group.addTask { [api] in
                    let stat = try? await api.stats(serverID: server.id)
                    return CraftyWidgetSnapshot.Server(
                        id: server.id,
                        name: server.name,
                        status: (stat?.status ?? .stopped).rawValue,
                        online: stat?.online ?? 0,
                        max: stat?.max ?? 0,
                        cpu: stat?.cpu ?? 0,
                        memory: stat?.memDisplay ?? "—"
                    )
                }
            }
            for await row in group { if let row { rows.append(row) } }
        }
        // Preserve server order.
        let order = Dictionary(uniqueKeysWithValues: servers.enumerated().map { ($1.id, $0) })
        rows.sort { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }

        // Diff against the previous statuses and notify on meaningful transitions.
        if fireAlerts {
            for row in rows {
                guard let old = prevStatus[row.id], old != row.status else { continue }
                if row.status == ServerStatus.crashed.rawValue {
                    notify(title: "⚠️ \(row.name) crashed", body: "The server stopped unexpectedly.")
                } else if row.status == ServerStatus.running.rawValue,
                          old == ServerStatus.crashed.rawValue || old == ServerStatus.stopped.rawValue {
                    notify(title: "✅ \(row.name) is back online", body: "The server is running again.")
                }
            }
        }

        // Persist the new state (also reloads the widget timeline).
        WidgetSnapshotStore.write(CraftyWidgetSnapshot(generatedAt: Date(), servers: rows))
    }

    // MARK: - Local notifications

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // nil trigger delivers immediately.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Used by the "Send a test alert" button in Settings.
    func sendTestNotification() {
        notify(title: "CraftyMobile alerts are on",
               body: "You’ll be notified when a server crashes or comes back online.")
    }
}
