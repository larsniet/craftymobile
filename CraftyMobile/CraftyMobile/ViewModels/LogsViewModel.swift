//
//  LogsViewModel.swift
//  CraftyMobile
//
//  Shared backing for both the Logs viewer and the Console (both tail the same
//  stdout log stream). Live tail polls every ~3s; a cap keeps very large logs
//  from bloating memory / the scroll view.
//

import Foundation

@MainActor
final class LogsViewModel: ObservableObject {
    @Published private(set) var lines: [LogLine] = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var liveTail = true

    let poller = PollingTask(seconds: 3)
    private let api: CraftyAPI
    private let serverID: String

    /// Keep at most this many lines in memory for smooth scrolling.
    private let maxLines = 1_000

    init(serverID: String, api: CraftyAPI = .shared) {
        self.serverID = serverID
        self.api = api
    }

    func refresh() async {
        if lines.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let raw = try await api.logs(serverID: serverID, file: false)
            self.lines = Self.makeLines(raw, cap: maxLines)
            self.errorMessage = nil
        } catch {
            self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Called by the live-tail loop; respects the `liveTail` toggle.
    func tailIfLive() async {
        guard liveTail else { return }
        await refresh()
    }

    private static func makeLines(_ raw: [String], cap: Int) -> [LogLine] {
        let trimmed = raw.count > cap ? Array(raw.suffix(cap)) : raw
        return trimmed.enumerated().map { LogLine(id: $0.offset, text: $0.element) }
    }
}

/// Stable identity for log rows so SwiftUI can diff efficiently.
struct LogLine: Identifiable, Equatable {
    let id: Int
    let text: String
}
