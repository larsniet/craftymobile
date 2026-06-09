//
//  ConsoleViewModel.swift
//  CraftyMobile
//
//  Console terminal: tails the same log stream as the Logs viewer and sends
//  commands to /stdin. After sending, it refreshes the tail so the result shows
//  up, and records a small recent-command history.
//

import Foundation

@MainActor
final class ConsoleViewModel: ObservableObject {
    let logs: LogsViewModel

    @Published var input = ""
    @Published var errorMessage: String?
    @Published private(set) var isSending = false
    @Published private(set) var history: [String] = []

    private let api: CraftyAPI
    private let serverID: String
    private let settings: AppSettings

    init(serverID: String, api: CraftyAPI = .shared, settings: AppSettings = .shared) {
        self.serverID = serverID
        self.api = api
        self.settings = settings
        self.logs = LogsViewModel(serverID: serverID, api: api)
        self.history = settings.commandHistory
    }

    /// Send whatever is currently typed in the input field.
    func send() async {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        await deliver(command, clearInput: true)
    }

    /// Send a specific command (used by the quick-action buttons).
    func run(_ command: String) async {
        await deliver(command, clearInput: false)
    }

    private func deliver(_ command: String, clearInput: Bool) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        do {
            try await api.sendCommand(serverID: serverID, command: command)
            Haptics.impact(.light)
            settings.rememberCommand(command)
            history = settings.commandHistory
            if clearInput { input = "" }
            // Refresh the tail so the command's output appears.
            try? await Task.sleep(for: .milliseconds(400))
            await logs.refresh()
        } catch {
            Haptics.error()
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func useHistory(_ command: String) {
        input = command
    }
}
