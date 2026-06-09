//
//  LogsView.swift
//  CraftyMobile
//
//  Full-screen terminal log viewer with a "Live tail" toggle (polls ~3s) and
//  pull-to-refresh.
//

import SwiftUI

struct LogsView: View {
    let server: Server

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: LogsViewModel

    init(server: Server) {
        self.server = server
        _viewModel = StateObject(wrappedValue: LogsViewModel(serverID: server.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    .padding([.horizontal, .top], Theme.spacing)
            }

            // `.refreshable` flows into LogStreamView's inner ScrollView via the
            // environment, giving pull-to-refresh without nesting scroll views.
            LogStreamView(lines: viewModel.lines, autoScroll: viewModel.liveTail)
                .refreshable { await viewModel.refresh() }
        }
        .background(Theme.terminalBackground.ignoresSafeArea(edges: .bottom))
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $viewModel.liveTail) {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .toggleStyle(.button)
                .tint(Theme.accent)
            }
        }
        .task {
            await viewModel.poller.run { await viewModel.tailIfLive() }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.poller.setActive(phase == .active)
        }
    }
}
