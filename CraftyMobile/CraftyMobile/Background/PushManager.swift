//
//  PushManager.swift
//  CraftyMobile
//
//  Coordinates APNs registration and hands the device token to the companion
//  push server so it can deliver live updates. Registration is gated on the
//  "Live updates" setting + a configured push-server URL.
//

import Foundation
import UIKit

final class PushManager: NSObject, @unchecked Sendable {
    static let shared = PushManager()

    private let settings = AppSettings.shared

    /// Ask iOS for an APNs token if the user enabled push and set a server URL.
    /// Safe to call repeatedly (e.g. every foreground).
    func registerIfEnabled() {
        guard settings.pushConfigured else { return }
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(token: String) {
        settings.deviceToken = token
        Task { await sendTokenToServer(token) }
    }

    func didFailToRegister(_ error: Error) {
        // Surface nothing intrusive; Settings shows registration state.
        NSLog("CraftyMobile push registration failed: \(error.localizedDescription)")
    }

    /// POST the token to the relay's /register endpoint. Sends the existing
    /// pairing code (if any) so it stays stable, and stores the code the relay
    /// returns. Tolerates a self-signed cert when the user enabled that option.
    private func sendTokenToServer(_ token: String) async {
        guard let base = settings.pushServerURL else { return }
        let url = base.appendingPathComponent("register")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "token": token,
            "bundleId": Bundle.main.bundleIdentifier ?? "",
        ]
        let existing = await MainActor.run { settings.pairingCode }
        if !existing.isEmpty { body["code"] = existing }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(
            configuration: .ephemeral,
            delegate: settings.allowSelfSigned ? TrustAllDelegate() : nil,
            delegateQueue: nil
        )
        guard let (data, _) = try? await session.data(for: req) else { return }
        // The relay returns a pairing code; a plain poll-server won't (that's fine).
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["code"] as? String, !code.isEmpty {
            await MainActor.run { settings.pairingCode = code }
        }
    }
}

/// Minimal self-signed-tolerant delegate for the token POST (the push server may
/// share Crafty's self-signed certificate).
private final class TrustAllDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
