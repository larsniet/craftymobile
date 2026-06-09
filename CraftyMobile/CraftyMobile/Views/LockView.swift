//
//  LockView.swift
//  CraftyMobile
//
//  Full-screen lock overlay shown while the app is locked. Auto-prompts for
//  authentication on appear; also hides app content from the app switcher
//  snapshot while backgrounded.
//

import SwiftUI

struct LockView: View {
    @EnvironmentObject private var lock: AppLockManager

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: lock.isAuthenticating)

                VStack(spacing: 6) {
                    Text("CraftyMobile is locked")
                        .font(.title3.weight(.semibold))
                    Text("Authenticate to view your servers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let error = lock.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.statusCrashed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    lock.authenticate()
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
                .disabled(lock.isAuthenticating)
            }
            .padding()
        }
        // Deferred so we don't hit the biometric API before the app is active.
        .onAppear { lock.authenticate(deferred: true) }
    }
}
