//
//  PollingTask.swift
//  CraftyMobile
//
//  Centralized polling so timers only run while a screen is visible AND the app
//  is in the foreground — we never hammer the API in the background.
//
//  Usage from a view:
//      .task { await viewModel.poller.run { await viewModel.refresh() } }
//      .onChange(of: scenePhase) { _, phase in
//          viewModel.poller.setActive(phase == .active)
//      }
//
//  Because the loop lives inside SwiftUI's `.task`, it is automatically
//  cancelled when the view disappears; `setActive` additionally pauses ticks
//  while the app is backgrounded without tearing the loop down.
//

import Foundation

@MainActor
final class PollingTask {
    private let interval: Duration
    private var active = true

    init(seconds: Double) {
        self.interval = .seconds(seconds)
    }

    func setActive(_ active: Bool) {
        self.active = active
    }

    /// Runs `tick` immediately, then every `interval` until the surrounding
    /// task is cancelled. Skips ticks while inactive (backgrounded).
    func run(_ tick: @escaping () async -> Void) async {
        // Fire once up front so the screen isn't empty while waiting.
        if active { await tick() }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                break // cancelled
            }
            guard !Task.isCancelled else { break }
            if active { await tick() }
        }
    }
}
