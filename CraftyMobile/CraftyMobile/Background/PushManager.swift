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

    /// POST the token to the push server's /register endpoint so it knows where
    /// to deliver. Tolerates a self-signed server cert (homelab) when the user
    /// has that option enabled.
    private func sendTokenToServer(_ token: String) async {
        guard let base = settings.pushServerURL else { return }
        let url = base.appendingPathComponent("register")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "token": token,
            "bundleId": Bundle.main.bundleIdentifier ?? "",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(
            configuration: .ephemeral,
            delegate: settings.allowSelfSigned ? TrustAllDelegate() : nil,
            delegateQueue: nil
        )
        _ = try? await session.data(for: req)
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
