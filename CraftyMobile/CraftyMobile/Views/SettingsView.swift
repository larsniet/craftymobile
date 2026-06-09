//
//  SettingsView.swift
//  CraftyMobile
//
//  Connection configuration: base URL, API token (obscured), self-signed toggle,
//  and a "Test connection" button that hits /crafty/check.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var showToken = false
    @State private var testState: TestState = .idle
    @State private var alertsNote: String?
    @State private var suppressAlertsChange = false
    @State private var pushNote: String?
    @State private var suppressPushChange = false

    enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://crafty.example.com:8443", text: $settings.baseURLString)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: settings.baseURLString) { _, _ in testState = .idle }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Connection")
            } footer: {
                Text("Include the port if Crafty isn’t behind a reverse proxy, e.g. https://crafty.example.com:8443")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Group {
                            if showToken {
                                TextField("Paste your API token", text: $settings.apiToken)
                            } else {
                                SecureField("Paste your API token", text: $settings.apiToken)
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: settings.apiToken) { _, _ in testState = .idle }

                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Authentication")
            } footer: {
                Text("Generate a token in Crafty’s panel. It’s stored securely in your device’s Keychain.")
            }

            Section {
                Toggle(isOn: $settings.allowSelfSigned) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow self-signed certificates")
                        Text("Required for many self-hosted Crafty setups.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
                .onChange(of: settings.allowSelfSigned) { _, _ in testState = .idle }

                Toggle(isOn: $settings.requireBiometrics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Require Face ID / Passcode")
                        Text("Lock the app — and your stored token — behind biometric authentication.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
            } header: {
                Text("Security")
            }

            Section {
                Toggle(isOn: $settings.alertsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Server status alerts")
                        Text("Get notified when a server crashes or comes back online.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
                .onChange(of: settings.alertsEnabled) { _, isOn in
                    if suppressAlertsChange { suppressAlertsChange = false; return }
                    Task { await handleAlertsToggle(isOn) }
                }

                if settings.alertsEnabled {
                    Button {
                        BackgroundRefreshManager.shared.sendTestNotification()
                    } label: {
                        Label("Send a test alert", systemImage: "bell.badge")
                    }
                }

                if let note = alertsNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.statusStarting)
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Delivered in the background on iOS’s schedule (often every 15–60 min, sometimes longer) — not real-time. They pause if you force-quit the app. For instant alerts, turn on Live updates below.")
            }

            Section {
                Toggle(isOn: $settings.pushEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live updates (push)")
                        Text("Near-real-time widget + instant alerts via your push server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
                .onChange(of: settings.pushEnabled) { _, isOn in
                    if suppressPushChange { suppressPushChange = false; return }
                    Task { await handlePushToggle(isOn) }
                }

                if settings.pushEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Push server URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://crafty.example.com:8099", text: $settings.pushServerURLString)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onChange(of: settings.pushServerURLString) { _, _ in
                                PushManager.shared.registerIfEnabled()
                            }
                    }
                    .padding(.vertical, 2)

                    HStack {
                        Text("Device registered")
                        Spacer()
                        if settings.deviceToken.isEmpty {
                            Text("Pending…").foregroundStyle(.secondary)
                        } else {
                            Label("Yes", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.statusRunning)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .font(.subheadline)
                }

                if let note = pushNote {
                    Text(note).font(.caption).foregroundStyle(Theme.statusStarting)
                }
            } header: {
                Text("Live updates")
            } footer: {
                Text("Requires the companion push server (see the project README) running next to Crafty, plus a one-time Apple Push Notifications key. Status changes (up/down/crash) arrive instantly; routine widget refreshes are as frequent as Apple allows.")
            }

            Section {
                Button(action: runTest) {
                    HStack {
                        testStatusIcon
                        Text(testButtonTitle)
                        Spacer()
                    }
                }
                .disabled(!settings.isConfigured || testState == .testing)

                if case .failure(let message) = testState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.statusCrashed)
                }
                if testState == .success {
                    Text("Connected successfully.")
                        .font(.caption)
                        .foregroundStyle(Theme.statusRunning)
                }
            }

            Section {
                HStack {
                    Label("Widget data sharing", systemImage: "square.grid.2x2")
                    Spacer()
                    if settings.sharedContainerAvailable {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.statusRunning)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Label("Unavailable", systemImage: "xmark.circle.fill")
                            .foregroundStyle(Theme.statusCrashed)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            } header: {
                Text("Widget")
            } footer: {
                if settings.sharedContainerAvailable {
                    Text("The App Group is reachable — the home-screen widget can read your servers.")
                } else {
                    Text("The App Group isn’t provisioned. In Xcode, select each target (CraftyMobile and CraftyWidget) → Signing & Capabilities → + Capability → App Groups, enable “group.com.larsniet.CraftyMobile” for both, then rebuild.")
                }
            }

            Section {
                LabeledContent("App", value: "CraftyMobile")
                LabeledContent("Crafty API", value: "v2")
            } footer: {
                Text("A lightweight monitor for your self-hosted Crafty Controller. Connects only to the server you configure above.")
            }
        }
        .navigationTitle("Settings")
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Alerts

    @MainActor
    private func handleAlertsToggle(_ isOn: Bool) async {
        guard isOn else {
            BackgroundRefreshManager.shared.cancelScheduled()
            return
        }
        alertsNote = nil
        let granted = await BackgroundRefreshManager.shared.requestAuthorization()
        if granted {
            BackgroundRefreshManager.shared.scheduleRefresh()
        } else {
            // Revert without re-triggering the onChange handler.
            suppressAlertsChange = true
            settings.alertsEnabled = false
            alertsNote = "Enable notifications for CraftyMobile in iOS Settings → Notifications to receive alerts."
        }
    }

    @MainActor
    private func handlePushToggle(_ isOn: Bool) async {
        guard isOn else {
            UIApplication.shared.unregisterForRemoteNotifications()
            pushNote = nil
            return
        }
        pushNote = nil
        let granted = await BackgroundRefreshManager.shared.requestAuthorization()
        if granted {
            if settings.pushServerURL == nil {
                pushNote = "Enter your push server URL to finish setup."
            }
            PushManager.shared.registerIfEnabled()
        } else {
            suppressPushChange = true
            settings.pushEnabled = false
            pushNote = "Enable notifications for CraftyMobile in iOS Settings → Notifications first."
        }
    }

    // MARK: - Test connection

    @ViewBuilder
    private var testStatusIcon: some View {
        switch testState {
        case .idle:
            Image(systemName: "bolt.horizontal.circle").foregroundStyle(Theme.accent)
        case .testing:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.statusRunning)
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.statusCrashed)
        }
    }

    private var testButtonTitle: String {
        switch testState {
        case .idle:    return "Test connection"
        case .testing: return "Testing…"
        case .success: return "Connection OK"
        case .failure: return "Test connection"
        }
    }

    private func runTest() {
        testState = .testing
        Task {
            do {
                try await CraftyAPI.shared.checkConnection()
                testState = .success
                Haptics.success()
            } catch {
                let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
                testState = .failure(message)
                Haptics.error()
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environmentObject(AppSettings.shared)
}
