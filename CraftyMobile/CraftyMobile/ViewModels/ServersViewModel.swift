//
//  ServersViewModel.swift
//  CraftyMobile
//
//  Drives the home screen: fetches the server list, then their live stats
//  concurrently, and auto-refreshes every ~10s.
//

import Foundation

@MainActor
final class ServersViewModel: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published private(set) var stats: [String: ServerStats] = [:]   // keyed by server id
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasLoadedOnce = false

    let poller = PollingTask(seconds: 10)
    private let api: CraftyAPI

    init(api: CraftyAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if !hasLoadedOnce { isLoading = true }
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            let list = try await api.listServers()
            self.servers = list
            self.errorMessage = nil
            await loadStats(for: list)
        } catch {
            self.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fetch stats for every server concurrently; a failure for one server
    /// shouldn't blank the others.
    private func loadStats(for servers: [Server]) async {
        await withTaskGroup(of: (String, ServerStats?).self) { group in
            for server in servers {
                group.addTask { [api] in
                    let stat = try? await api.stats(serverID: server.id)
                    return (server.id, stat)
                }
            }
            for await (id, stat) in group {
                if let stat { self.stats[id] = stat }
            }
        }
        // Drop stats for servers that no longer exist.
        let liveIDs = Set(servers.map(\.id))
        stats = stats.filter { liveIDs.contains($0.key) }

        publishWidgetSnapshot()
    }

    /// Push the latest state to the App Group so the home-screen widget can show
    /// it instantly and refresh while the app is open.
    private func publishWidgetSnapshot() {
        let entries: [CraftyWidgetSnapshot.Server] = servers.map { server in
            let stat = stats[server.id]
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
        WidgetSnapshotStore.write(CraftyWidgetSnapshot(generatedAt: Date(), servers: entries))
    }
}
