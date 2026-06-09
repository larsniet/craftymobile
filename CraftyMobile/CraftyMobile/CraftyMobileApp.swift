//
//  CraftyMobileApp.swift
//  CraftyMobile
//
//  App entry point. Owns the shared AppSettings store and the AppLockManager,
//  injects them into the environment, and drives the biometric lock from the
//  scene phase (lock when leaving the foreground, prompt when returning).
//

import SwiftUI

@main
struct CraftyMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var lock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(settings)
                    .environmentObject(lock)
                    .tint(Theme.accent)

                // Lock overlay sits above everything — also hides content from
                // the app-switcher snapshot while backgrounded.
                if lock.isLocked {
                    LockView()
                        .environmentObject(lock)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
            .task {
                // Ensure the widget always has fresh config to read.
                settings.syncToSharedContainer()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    lock.reconcile()
                    lock.authenticate(deferred: true)
                    settings.syncToSharedContainer()
                    PushManager.shared.registerIfEnabled()
                case .inactive, .background:
                    lock.lockIfEnabled()
                    // Queue a background check so alerts keep coming while away.
                    BackgroundRefreshManager.shared.scheduleRefresh()
                @unknown default:
                    break
                }
            }
        }
        // `.backgroundTask` is a Scene modifier: it registers + runs the
        // background server-status check. iOS decides when it actually fires.
        .backgroundTask(.appRefresh(BackgroundRefreshManager.taskIdentifier)) {
            await BackgroundRefreshManager.shared.performRefresh()
        }
    }
}
