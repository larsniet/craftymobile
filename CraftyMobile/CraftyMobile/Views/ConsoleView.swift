//
//  ConsoleView.swift
//  CraftyMobile
//
//  Terminal console: live log stream on top, a command input pinned to the
//  bottom, and a row of recent commands. Commands post to /stdin (no leading
//  slash needed) and the tail refreshes so the result shows up.
//

import SwiftUI

struct ConsoleView: View {
    let server: Server

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ConsoleViewModel
    @FocusState private var inputFocused: Bool

    init(server: Server) {
        self.server = server
        _viewModel = StateObject(wrappedValue: ConsoleViewModel(serverID: server.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    .padding([.horizontal, .top], Theme.spacing)
            }

            LogStreamView(lines: viewModel.logs.lines, autoScroll: true)
                .refreshable { await viewModel.logs.refresh() }
        }
        .background(Theme.terminalBackground.ignoresSafeArea(edges: .bottom))
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
        .task {
            // Console shares the Logs view model's poller to live-tail output.
            await viewModel.logs.poller.run { await viewModel.logs.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.logs.poller.setActive(phase == .active)
        }
    }

    // MARK: - Quick actions

    /// Common Minecraft-Java commands, one tap away. `prefill` actions drop text
    /// into the input (so you can finish typing) instead of sending immediately.
    private struct QuickAction: Identifiable {
        let label: String
        let icon: String
        let command: String
        var prefill = false
        var id: String { label }
    }

    private let quickActions: [QuickAction] = [
        QuickAction(label: "Players", icon: "person.2.fill", command: "list"),
        QuickAction(label: "Save", icon: "externaldrive.fill", command: "save-all"),
        QuickAction(label: "Day", icon: "sun.max.fill", command: "time set day"),
        QuickAction(label: "Clear weather", icon: "cloud.sun.fill", command: "weather clear"),
        QuickAction(label: "Broadcast…", icon: "megaphone.fill", command: "say ", prefill: true),
    ]

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickActions) { action in
                    Button {
                        if action.prefill {
                            viewModel.input = action.command
                            inputFocused = true
                            Haptics.impact(.light)
                        } else {
                            Haptics.impact(.light)
                            Task { await viewModel.run(action.command) }
                        }
                    } label: {
                        Label(action.label, systemImage: action.icon)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSending)
                }
            }
            .padding(.horizontal, Theme.spacing)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            quickActionsRow

            if !viewModel.history.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.history, id: \.self) { command in
                            Button {
                                viewModel.useHistory(command)
                                inputFocused = true
                            } label: {
                                Text(command)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.elevated, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Theme.spacing)
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.accent)
                    TextField("Type a command (e.g. say Hello)", text: $viewModel.input)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit { send() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))

                Button(action: send) {
                    ZStack {
                        if viewModel.isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.headline)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .background(canSend ? Theme.accent : Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(canSend ? Color.black : Color.secondary)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }

    private func send() {
        guard canSend else { return }
        Task { await viewModel.send() }
    }
}
