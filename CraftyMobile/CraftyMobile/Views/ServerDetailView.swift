//
//  ServerDetailView.swift
//  CraftyMobile
//
//  Per-server control screen: header + status, action buttons (with confirm
//  dialogs for destructive actions), a live stats grid refreshing ~5s, a
//  players section, and links to Logs and Console.
//

import SwiftUI

struct ServerDetailView: View {
    let server: Server

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ServerDetailViewModel

    @State private var confirm: ConfirmAction?

    init(server: Server) {
        self.server = server
        _viewModel = StateObject(wrappedValue: ServerDetailViewModel(server: server))
    }

    private var status: ServerStatus { viewModel.stats?.status ?? .stopped }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.spacing) {
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    }
                    header
                    actionButtons
                    statsGrid
                    playersSection
                    navLinks
                }
                .padding(Theme.spacing)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refresh() }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Haptics.impact(.light)
                        Task { await viewModel.perform(.backup) }
                    } label: {
                        Label("Back up now", systemImage: "externaldrive.fill.badge.plus")
                    }
                    Button(role: .destructive) {
                        confirm = .kill
                    } label: {
                        Label("Force kill", systemImage: "bolt.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(viewModel.actionInFlight != nil)
            }
        }
        .task {
            await viewModel.poller.run { await viewModel.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.poller.setActive(phase == .active)
        }
        .confirmationDialog(
            confirm?.title ?? "",
            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
            titleVisibility: .visible
        ) {
            if let confirm {
                Button(confirm.buttonTitle, role: confirm.isDestructive ? .destructive : nil) {
                    Task { await viewModel.perform(confirm.action) }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(confirm?.message ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.title2.weight(.bold))
                    if let address = addressText {
                        Text(address)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusPill(status: status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var addressText: String? {
        guard let ip = server.ip else { return nil }
        if let port = viewModel.stats?.serverPort ?? server.port {
            return "\(ip):\(port)"
        }
        return ip
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 10) {
            ActionButton(
                title: "Start",
                icon: "play.fill",
                tint: Theme.statusRunning,
                isBusy: viewModel.actionInFlight == .start,
                disabled: status == .running || viewModel.actionInFlight != nil
            ) {
                Haptics.impact()
                Task { await viewModel.perform(.start) }
            }

            ActionButton(
                title: "Stop",
                icon: "stop.fill",
                tint: Theme.statusStopped,
                isBusy: viewModel.actionInFlight == .stop,
                disabled: status == .stopped || viewModel.actionInFlight != nil
            ) {
                confirm = .stop
            }

            ActionButton(
                title: "Restart",
                icon: "arrow.clockwise",
                tint: Theme.statusStarting,
                isBusy: viewModel.actionInFlight == .restart,
                disabled: viewModel.actionInFlight != nil
            ) {
                confirm = .restart
            }
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(icon: "cpu", label: "CPU", value: viewModel.stats.map { String(format: "%.1f%%", $0.cpu) } ?? "—", tint: Theme.statusUpdating)
            StatTile(icon: "memorychip", label: "Memory", value: memoryValue, tint: Theme.statusStarting)
            StatTile(icon: "globe.americas.fill", label: "World", value: viewModel.stats?.worldSizeDisplay ?? "—", tint: Theme.accent)
            StatTile(icon: "shippingbox.fill", label: "Version", value: viewModel.stats?.version ?? "—", tint: Theme.accent)
            StatTile(icon: "clock.fill", label: "Uptime", value: uptimeValue, tint: Theme.statusRunning)
            StatTile(icon: "person.2.fill", label: "Players", value: viewModel.stats.map { "\($0.online)/\($0.max)" } ?? "—", tint: Theme.accent)
        }
    }

    private var memoryValue: String {
        guard let stats = viewModel.stats else { return "—" }
        if stats.memPercent > 0 {
            return "\(stats.memDisplay) · \(String(format: "%.0f%%", stats.memPercent))"
        }
        return stats.memDisplay
    }

    private var uptimeValue: String {
        viewModel.stats?.uptime?.uptimeString ?? "—"
    }

    // MARK: - Players

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Players", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                if let stats = viewModel.stats {
                    Text("\(stats.online)/\(stats.max)")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let players = viewModel.stats?.players, !players.isEmpty {
                FlowChips(items: players)
            } else if status == .running {
                Text("No players online")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Server offline")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Navigation

    private var navLinks: some View {
        VStack(spacing: 10) {
            NavigationLink {
                LogsView(server: server)
            } label: {
                NavRow(icon: "text.alignleft", title: "Logs", subtitle: "Live server output")
            }
            NavigationLink {
                ConsoleView(server: server)
            } label: {
                NavRow(icon: "terminal.fill", title: "Console", subtitle: "Send commands")
            }
        }
    }
}

// MARK: - Confirmations

private struct ConfirmAction: Identifiable {
    let action: ServerAction
    let title: String
    let message: String
    let buttonTitle: String
    let isDestructive: Bool
    var id: String { action.rawValue }

    static let stop = ConfirmAction(action: .stop, title: "Stop server?", message: "This will gracefully stop the server. Players will be disconnected.", buttonTitle: "Stop", isDestructive: true)
    static let restart = ConfirmAction(action: .restart, title: "Restart server?", message: "The server will stop and start again. Players will be disconnected briefly.", buttonTitle: "Restart", isDestructive: true)
    static let kill = ConfirmAction(action: .kill, title: "Force kill server?", message: "This forcibly terminates the process and may cause data loss. Use only if the server is unresponsive.", buttonTitle: "Force Kill", isDestructive: true)
}

// MARK: - Subcomponents

private struct ActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    var isBusy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: icon)
                        .font(.headline)
                        .opacity(isBusy ? 0 : 1)
                    if isBusy { ProgressView().controlSize(.small) }
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(disabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .background(
                (disabled ? Color.secondary.opacity(0.08) : tint.opacity(0.15)),
                in: RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                    .strokeBorder((disabled ? Color.secondary : tint).opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct NavRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .cardSurface(padding: 14)
    }
}

/// Wraps player name chips onto multiple lines.
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { name in
                Text(name)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
