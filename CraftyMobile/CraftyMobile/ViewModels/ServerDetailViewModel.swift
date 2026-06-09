//
//  ServerDetailViewModel.swift
//  CraftyMobile
//
//  Drives the detail screen: live stats refreshing every ~5s, plus start/stop/
//  restart/kill/backup actions with their own in-flight state.
//

import Foundation

@MainActor
final class ServerDetailViewModel: ObservableObject {
    let server: Server

    @Published private(set) var stats: ServerStats?
    @Published var errorMessage: String?
    @Published private(set) var actionInFlight: ServerAction?

    let poller = PollingTask(seconds: 5)
    private let api: CraftyAPI

    init(server: Server, api: CraftyAPI = .shared) {
        self.server = server
        self.api = api
    }

    func refresh() async {
        do {
            let stat = try await api.stats(serverID: server.id)
            self.stats = stat
            self.errorMessage = nil
        } catch {
            self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func perform(_ action: ServerAction) async {
        guard actionInFlight == nil else { return }
        actionInFlight = action
        defer { actionInFlight = nil }

        do {
            try await api.performAction(serverID: server.id, action: action)
            Haptics.success()
            // Give Crafty a beat to update state, then refresh.
            try? await Task.sleep(for: .milliseconds(600))
            await refresh()
        } catch {
            Haptics.error()
            self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
