//
//  AppSettings.swift
//  CraftyMobile
//
//  Observable store for connection configuration. To let the **widget** read the
//  same configuration, everything is persisted to a shared App Group container
//  (`group.com.larsniet.CraftyMobile`) rather than the app's private defaults.
//
//  Security note: the API token lives in the App Group's UserDefaults so the
//  widget extension can fetch live data. On a non-jailbroken device this
//  container is sandboxed to apps signed by the same team that declare the same
//  App Group entitlement — an acceptable trade-off for a personal, sideloaded
//  homelab controller. (Earlier builds stored the token in the Keychain; the
//  initializer migrates that value over once.)
//

import Foundation
import Combine

/// App Group identifier shared by the app and the widget extension.
/// Must match the value in both targets' `.entitlements` files.
let appGroupID = "group.com.larsniet.CraftyMobile"

final class AppSettings: ObservableObject, @unchecked Sendable {
    static let shared = AppSettings()

    private enum Keys {
        static let baseURL = "baseURL"
        static let allowSelfSigned = "allowSelfSigned"
        static let apiToken = "apiToken"
        static let requireBiometrics = "requireBiometrics"
        static let alertsEnabled = "alertsEnabled"
        static let pushEnabled = "pushEnabled"
        static let pushServerURL = "pushServerURL"
        static let deviceToken = "deviceToken"
        static let commandHistory = "commandHistory"
        static let didMigrate = "didMigrateToAppGroup_v1"
    }

    /// No server is hardcoded — the field starts empty and shows an example as
    /// placeholder text. The user enters their own URL in Settings.
    static let defaultBaseURL = ""

    /// Shared container defaults. Falls back to `.standard` only if the App Group
    /// can't be opened (e.g. entitlement missing), so the app still functions.
    /// Assigned once in `init`.
    private let defaults: UserDefaults

    @Published var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Keys.baseURL) }
    }

    @Published var allowSelfSigned: Bool {
        didSet { defaults.set(allowSelfSigned, forKey: Keys.allowSelfSigned) }
    }

    @Published var apiToken: String {
        didSet { defaults.set(apiToken, forKey: Keys.apiToken) }
    }

    /// Require Face ID / Touch ID / passcode to open the app.
    @Published var requireBiometrics: Bool {
        didSet { defaults.set(requireBiometrics, forKey: Keys.requireBiometrics) }
    }

    /// Background server-status alerts (crash / recovery local notifications).
    @Published var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    /// Live push updates via the companion push server (near-real-time widget +
    /// instant alerts).
    @Published var pushEnabled: Bool {
        didSet { defaults.set(pushEnabled, forKey: Keys.pushEnabled) }
    }

    /// Base URL of the companion push server (separate from the Crafty URL).
    @Published var pushServerURLString: String {
        didSet { defaults.set(pushServerURLString, forKey: Keys.pushServerURL) }
    }

    /// Last APNs device token (hex). Shown in Settings; sent to the push server.
    @Published var deviceToken: String {
        didSet { defaults.set(deviceToken, forKey: Keys.deviceToken) }
    }

    private init() {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        self.defaults = defaults

        Self.migrateIfNeeded(into: defaults)

        self.baseURLString = defaults.string(forKey: Keys.baseURL) ?? AppSettings.defaultBaseURL
        // `object(forKey:)` distinguishes "unset" (default ON) from an explicit false.
        self.allowSelfSigned = (defaults.object(forKey: Keys.allowSelfSigned) as? Bool) ?? true
        self.apiToken = defaults.string(forKey: Keys.apiToken) ?? ""
        self.requireBiometrics = (defaults.object(forKey: Keys.requireBiometrics) as? Bool) ?? false
        self.alertsEnabled = (defaults.object(forKey: Keys.alertsEnabled) as? Bool) ?? false
        self.pushEnabled = (defaults.object(forKey: Keys.pushEnabled) as? Bool) ?? false
        self.pushServerURLString = defaults.string(forKey: Keys.pushServerURL) ?? ""
        self.deviceToken = defaults.string(forKey: Keys.deviceToken) ?? ""
    }

    /// Normalized push-server base URL (trailing slash removed), or nil.
    var pushServerURL: URL? {
        var trimmed = pushServerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    /// True when push updates are enabled and a valid server URL is set.
    var pushConfigured: Bool {
        pushEnabled && pushServerURL != nil
    }

    /// One-time migration from the pre-App-Group storage (standard UserDefaults
    /// for the URL/flag, Keychain for the token).
    private static func migrateIfNeeded(into shared: UserDefaults) {
        guard !shared.bool(forKey: Keys.didMigrate) else { return }

        let std = UserDefaults.standard
        if let oldURL = std.string(forKey: Keys.baseURL) {
            shared.set(oldURL, forKey: Keys.baseURL)
        }
        if let oldFlag = std.object(forKey: Keys.allowSelfSigned) as? Bool {
            shared.set(oldFlag, forKey: Keys.allowSelfSigned)
        }
        if let oldHistory = std.stringArray(forKey: Keys.commandHistory) {
            shared.set(oldHistory, forKey: Keys.commandHistory)
        }
        if let oldToken = KeychainHelper.get(), !oldToken.isEmpty {
            shared.set(oldToken, forKey: Keys.apiToken)
            KeychainHelper.set(nil) // clear the old Keychain copy
        }
        shared.set(true, forKey: Keys.didMigrate)
    }

    /// Whether the shared App Group container is actually reachable. If this is
    /// false, the App Groups capability isn't provisioned for the installed app,
    /// so the widget can't read the config no matter what we write.
    var sharedContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// Force-write the current config into the shared suite. Defensive: covers
    /// migration / `didSet` timing edge cases so the widget always has data the
    /// moment the App Group becomes available.
    func syncToSharedContainer() {
        defaults.set(baseURLString, forKey: Keys.baseURL)
        defaults.set(allowSelfSigned, forKey: Keys.allowSelfSigned)
        defaults.set(apiToken, forKey: Keys.apiToken)
    }

    /// True once we have enough to make a request.
    var isConfigured: Bool {
        !baseURLString.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Normalized base URL with any trailing slash removed.
    var normalizedBaseURL: URL? {
        var trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    // MARK: - Recent command history (for the console)

    private(set) var commandHistory: [String] {
        get { defaults.stringArray(forKey: Keys.commandHistory) ?? [] }
        set { defaults.set(newValue, forKey: Keys.commandHistory) }
    }

    func rememberCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = commandHistory.filter { $0 != trimmed }
        history.insert(trimmed, at: 0)
        commandHistory = Array(history.prefix(12))
    }
}
