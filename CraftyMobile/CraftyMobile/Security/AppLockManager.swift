//
//  AppLockManager.swift
//  CraftyMobile
//
//  Optional biometric (Face ID / Touch ID) app lock with passcode fallback.
//  When enabled in Settings, the app locks on launch and whenever it returns
//  from the background, protecting the stored API token behind the device owner.
//

import SwiftUI
import LocalAuthentication

@MainActor
final class AppLockManager: ObservableObject {
    /// Whether the lock screen is currently covering the app.
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let settings: AppSettings
    /// Guards the single silent auto-retry per lock cycle.
    private var autoRetried = false

    init(settings: AppSettings = .shared) {
        self.settings = settings
        // Start locked if the user requires biometrics.
        self.isLocked = settings.requireBiometrics
    }

    /// The biometry kind available, for labeling the unlock button.
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Passcode"
        }
    }

    /// Re-lock when leaving the foreground (call on `.inactive`/`.background`).
    func lockIfEnabled() {
        if settings.requireBiometrics {
            isLocked = true
            autoRetried = false
            errorMessage = nil
        }
    }

    /// If the user turned the setting off while locked, clear the lock.
    func reconcile() {
        if !settings.requireBiometrics { isLocked = false }
    }

    /// Prompt for Face ID / Touch ID / passcode.
    ///
    /// `deferred` waits briefly before evaluating. Calling the biometric API the
    /// instant the app becomes active (or in `onAppear` at launch) intermittently
    /// returns `LAError.biometryNotAvailable` (code 6) because the subsystem isn't
    /// ready yet — so automatic triggers defer, while the manual button doesn't.
    func authenticate(deferred: Bool = false) {
        guard settings.requireBiometrics, isLocked, !isAuthenticating else { return }
        isAuthenticating = true   // set now so overlapping triggers are ignored
        Task { @MainActor in
            if deferred { try? await Task.sleep(for: .milliseconds(400)) }
            // The user may have unlocked or cancelled during the delay.
            guard isLocked else { isAuthenticating = false; return }
            evaluate()
        }
    }

    private func evaluate() {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"

        var policyError: NSError?
        // `deviceOwnerAuthentication` falls back to the passcode if biometrics
        // are unavailable, so a user without Face ID enrolled isn't locked out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            isAuthenticating = false
            // No biometrics AND no passcode set — don't trap the user out.
            if (policyError as? LAError)?.code == .passcodeNotSet { isLocked = false }
            errorMessage = nil
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock CraftyMobile") { [weak self] success, evalError in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthenticating = false
                if success {
                    self.isLocked = false
                    self.errorMessage = nil
                    Haptics.success()
                } else {
                    self.handleFailure(evalError)
                }
            }
        }
    }

    private func handleFailure(_ error: Error?) {
        guard let code = (error as? LAError)?.code else {
            errorMessage = nil
            return
        }
        switch code {
        case .biometryNotAvailable, .systemCancel, .appCancel:
            // Fired too early / interrupted by the system. Retry once, silently —
            // no scary banner; the Unlock button remains as a manual fallback.
            errorMessage = nil
            if !autoRetried {
                autoRetried = true
                authenticate(deferred: true)
            }
        case .userCancel, .userFallback:
            errorMessage = nil   // user dismissed; let them tap Unlock
        case .biometryLockout:
            errorMessage = "Biometry is locked out. Tap Unlock to use your passcode."
        case .authenticationFailed:
            errorMessage = "Authentication failed. Tap Unlock to try again."
        default:
            errorMessage = nil
        }
    }
}
