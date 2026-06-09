//
//  CraftyAPI.swift
//  CraftyMobile
//
//  Typed async/await networking layer for the Crafty Controller v2 API.
//  All requests attach `Authorization: Bearer <token>` and decode the standard
//  `{ status, data }` envelope. Errors are normalized to `APIError`.
//

import Foundation

actor CraftyAPI {
    /// Shared client used throughout the app. It reads `AppSettings.shared` on
    /// every request, so URL/token/trust changes take effect immediately.
    static let shared = CraftyAPI(settings: .shared)

    private let settings: AppSettings
    private let session: URLSession
    private let delegate: TLSDelegate

    /// `settings` is read on each request so changes (URL/token) take effect
    /// immediately without rebuilding the client.
    init(settings: AppSettings) {
        self.settings = settings
        self.delegate = TLSDelegate()

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Public endpoints

    /// `GET /api/v2/crafty/check` — used by the "Test connection" button.
    func checkConnection() async throws {
        _ = try await request("/api/v2/crafty/check", as: EmptyData.self)
    }

    /// `GET /api/v2/servers`
    func listServers() async throws -> [Server] {
        try await request("/api/v2/servers", as: [Server].self)
    }

    /// `GET /api/v2/servers/{id}/stats`
    func stats(serverID: String) async throws -> ServerStats {
        try await request("/api/v2/servers/\(serverID)/stats", as: ServerStats.self)
    }

    /// `GET /api/v2/servers/{id}/logs` — plain string lines (for the log/console view).
    func logs(serverID: String, file: Bool = false) async throws -> [String] {
        try await request("/api/v2/servers/\(serverID)/logs?file=\(file)", as: [String].self)
    }

    /// `POST /api/v2/servers/{id}/stdin` — raw command, no leading slash.
    func sendCommand(serverID: String, command: String) async throws {
        let body = command.data(using: .utf8) ?? Data()
        _ = try await request(
            "/api/v2/servers/\(serverID)/stdin",
            method: "POST",
            body: body,
            contentType: "text/plain",
            as: EmptyData.self,
            allowEmptyEnvelope: true
        )
    }

    /// `POST /api/v2/servers/{id}/action/{action}`
    func performAction(serverID: String, action: ServerAction) async throws {
        _ = try await request(
            "/api/v2/servers/\(serverID)/action/\(action.rawValue)",
            method: "POST",
            as: EmptyData.self,
            allowEmptyEnvelope: true
        )
    }

    // MARK: - Core request

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        as type: T.Type,
        allowEmptyEnvelope: Bool = false
    ) async throws -> T {
        let allowSelfSigned = settings.allowSelfSigned
        let token = settings.apiToken
        let base = settings.normalizedBaseURL
        let configured = settings.isConfigured

        guard configured else { throw APIError.notConfigured }
        guard let base else { throw APIError.invalidURL(settings.baseURLString) }

        // Apply the current trust policy before issuing the request.
        delegate.allowSelfSigned = allowSelfSigned

        guard let url = URL(string: base.absoluteString + path) else {
            throw APIError.invalidURL(base.absoluteString + path)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body { req.httpBody = body }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            switch urlError.code {
            case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .secureConnectionFailed, .clientCertificateRejected:
                throw APIError.tlsTrust
            case .notConnectedToInternet, .dataNotAllowed:
                throw APIError.offline
            default:
                throw APIError.transport(urlError.localizedDescription)
            }
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response.")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            // Try to surface the server's error message from the envelope.
            let message = (try? JSONDecoder().decode(Envelope<EmptyData>.self, from: data))?.error
            throw APIError.server(status: http.statusCode, message: message)
        }

        // Some POSTs (stdin / actions) may return an empty body on success.
        if allowEmptyEnvelope, data.isEmpty, let empty = EmptyData() as? T {
            return empty
        }

        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            // Empty-but-allowed bodies that still failed to decode -> treat as success.
            if allowEmptyEnvelope, let empty = EmptyData() as? T { return empty }
            throw APIError.decoding(error.localizedDescription)
        }

        guard envelope.isOK else {
            if let err = envelope.error, err.lowercased().contains("auth") {
                throw APIError.unauthorized
            }
            throw APIError.apiError(envelope.error ?? "Unknown error")
        }

        if let payload = envelope.data {
            return payload
        }
        if let empty = EmptyData() as? T {
            return empty
        }
        throw APIError.decoding("Response was missing its data payload.")
    }
}

// MARK: - Actions

enum ServerAction: String {
    case start = "start_server"
    case stop = "stop_server"
    case restart = "restart_server"
    case kill = "kill_server"
    case backup = "backup_server"
}

// MARK: - TLS delegate

/// URLSession delegate that can accept self-signed / untrusted server certs when
/// the user opts in. When the toggle is OFF, we fall back to the system's default
/// evaluation by *not* handling the challenge, so trusted certs still work and
/// untrusted ones are correctly rejected.
private final class TLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    // Read/written from the actor before each request and on the delegate queue
    // during a challenge. `@unchecked Sendable` + simple atomic-ish access is
    // acceptable here: writes happen-before the request that triggers the read.
    var allowSelfSigned: Bool = true

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            // Not a server-trust challenge — let the system handle it.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard allowSelfSigned else {
            // User wants strict validation: defer to the system's default policy.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Opted in: trust the presented certificate chain unconditionally.
        // This is intentional for a self-hosted box with a self-signed cert and
        // is gated behind an explicit, off-by-default-able setting.
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}
