//
//  ServersListView.swift
//  CraftyMobile
//
//  Home screen: a scrollable list of server cards. Pull-to-refresh + ~10s
//  auto-refresh (paused when the app is backgrounded). Tapping a card pushes
//  the detail screen.
//

import SwiftUI

struct ServersListView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = ServersViewModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Servers")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.poller.run { await viewModel.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.poller.setActive(phase == .active)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !settings.isConfigured {
            notConfiguredState
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    }

                    if viewModel.servers.isEmpty && viewModel.hasLoadedOnce && viewModel.errorMessage == nil {
                        emptyState
                    }

                    ForEach(viewModel.servers) { server in
                        NavigationLink(value: server) {
                            ServerCard(server: server, stats: viewModel.stats[server.id])
                        }
                        .buttonStyle(.plain)
                    }

                    if !viewModel.hasLoadedOnce && viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    }
                }
                .padding(Theme.spacing)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refresh() }
            .navigationDestination(for: Server.self) { server in
                ServerDetailView(server: server)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No servers found",
            systemImage: "server.rack",
            description: Text("Your Crafty instance didn’t return any servers.")
        )
        .padding(.top, 60)
    }

    private var notConfiguredState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Not connected")
                .font(.title2.weight(.semibold))
            Text("Add your Crafty server URL and API token in Settings to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
