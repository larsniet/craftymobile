//
//  WidgetData.swift
//  CraftyWidget
//
//  Self-contained data layer for the widget extension. It reads the shared
//  config (URL/token/TLS flag) from the App Group, fetches live server state on
//  the widget's timeline, and falls back to the snapshot the app last wrote.
//
//  This intentionally duplicates a little of the app's networking so the widget
//  target stays independent (no cross-target source membership).
//

import Foundation
import SwiftUI

let widgetAppGroupID = "group.com.larsniet.CraftyMobile"

// MARK: - Status

enum WStatus: String {
    case running, stopped, starting, crashed, updating

    var label: String {
        switch self {
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .starting: return "Starting"
        case .crashed:  return "Crashed"
        case .updating: return "Updating"
        }
    }

    var color: Color {
        switch self {
        case .running:  return Color(hex: 0x35E07F)
        case .stopped:  return Color(hex: 0x8A8F98)
        case .starting: return Color(hex: 0xFFB23E)
        case .crashed:  return Color(hex: 0xFF5A5A)
        case .updating: return Color(hex: 0x4FA9FF)
        }
    }
}

// MARK: - View model row

struct WServer: Identifiable {
    let id: String
    let name: String
    let status: WStatus
    let online: Int
    let max: Int
    let cpu: Double
    let memory: String
}

// MARK: - Shared config

struct WConfig {
    let baseURL: URL
    let token: String
    let allowSelfSigned: Bool

    static func load() -> WConfig? {
        guard let d = UserDefaults(suiteName: widgetAppGroupID) else { return nil }
        var urlString = (d.string(forKey: "baseURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        while urlString.hasSuffix("/") { urlString.removeLast() }
        let token = (d.string(forKey: "apiToken") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), url.host != nil, !token.isEmpty else { return nil }
        let allow = (d.object(forKey: "allowSelfSigned") as? Bool) ?? true
        return WConfig(baseURL: url, token: token, allowSelfSigned: allow)
    }
}

// MARK: - Snapshot fallback (mirrors the app's CraftyWidgetSnapshot JSON)

struct WSnapshot: Codable {
    var generatedAt: Date
    var servers: [Server]
    struct Server: Codable {
        var id: String
        var name: String
        var status: String
        var online: Int
        var max: Int
        var cpu: Double
        var memory: String
    }

    static func read() -> WSnapshot? {
        guard let d = UserDefaults(suiteName: widgetAppGroupID),
              let data = d.data(forKey: "widgetSnapshot") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WSnapshot.self, from: data)
    }

    var rows: [WServer] {
        servers.map {
            WServer(id: $0.id, name: $0.name,
                    status: WStatus(rawValue: $0.status) ?? .stopped,
                    online: $0.online, max: $0.max, cpu: $0.cpu, memory: $0.memory)
        }
    }
}

// MARK: - Live fetch

enum WidgetAPI {
    /// Fetches server list + stats. Returns nil if not configured or on failure
    /// (the caller falls back to the snapshot).
    static func fetch() async -> [WServer]? {
        guard let cfg = WConfig.load() else { return nil }
        let session = makeSession(allowSelfSigned: cfg.allowSelfSigned)

        guard let servers: [WRawServer] = try? await get("/api/v2/servers", cfg: cfg, session: session) else {
            return nil
        }

        // Fetch stats concurrently.
        var rows: [WServer] = []
        await withTaskGroup(of: WServer?.self) { group in
            for s in servers {
                group.addTask {
                    let stat: WRawStats? = try? await get("/api/v2/servers/\(s.id)/stats", cfg: cfg, session: session)
                    return WServer(
                        id: s.id,
                        name: s.name,
                        status: stat?.status ?? .stopped,
                        online: stat?.online ?? 0,
                        max: stat?.max ?? 0,
                        cpu: stat?.cpu ?? 0,
                        memory: stat?.memoryDisplay ?? "—"
                    )
                }
            }
            for await row in group { if let row { rows.append(row) } }
        }
        // Preserve the server list order.
        let order = Dictionary(uniqueKeysWithValues: servers.enumerated().map { ($1.id, $0) })
        return rows.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    private static func get<T: Decodable>(_ path: String, cfg: WConfig, session: URLSession) async throws -> T {
        guard let url = URL(string: cfg.baseURL.absoluteString + path) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(WEnvelope<T>.self, from: data).data
    }

    private static func makeSession(allowSelfSigned: Bool) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config,
                          delegate: allowSelfSigned ? WTLSDelegate() : nil,
                          delegateQueue: nil)
    }
}

private struct WEnvelope<T: Decodable>: Decodable { let data: T }

private struct WRawServer: Decodable {
    let id: String
    let name: String
    enum CodingKeys: String, CodingKey { case id = "server_id", name = "server_name" }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String((try? c.decode(Int.self, forKey: .id)) ?? 0) }
        name = (try? c.decode(String.self, forKey: .name)) ?? "Server"
    }
}

private struct WRawStats: Decodable {
    let status: WStatus
    let online: Int
    let max: Int
    let cpu: Double
    let memoryDisplay: String

    enum CodingKeys: String, CodingKey {
        case running, crashed, updating, cpu, mem, online, max
        case waitingStart = "waiting_start"
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let running = (try? c.decode(Bool.self, forKey: .running)) ?? false
        let crashed = (try? c.decode(Bool.self, forKey: .crashed)) ?? false
        let updating = (try? c.decode(Bool.self, forKey: .updating)) ?? false
        let waiting = (try? c.decode(Bool.self, forKey: .waitingStart)) ?? false
        if crashed { status = .crashed }
        else if updating { status = .updating }
        else if waiting { status = .starting }
        else if running { status = .running }
        else { status = .stopped }

        online = (try? c.decode(Int.self, forKey: .online)) ?? 0
        max = (try? c.decode(Int.self, forKey: .max)) ?? 0
        if let dv = try? c.decode(Double.self, forKey: .cpu) { cpu = dv }
        else { cpu = Double((try? c.decode(String.self, forKey: .cpu)) ?? "") ?? 0 }

        // mem may be a formatted string or a raw byte count.
        let rawMem: String
        if let s = try? c.decode(String.self, forKey: .mem) { rawMem = s }
        else if let n = try? c.decode(Double.self, forKey: .mem) { rawMem = String(n) }
        else { rawMem = "" }
        memoryDisplay = WidgetAPI.humanBytes(rawMem)
    }
}

extension WidgetAPI {
    /// Same logic as the app: pass through values that already carry a unit,
    /// format bare numbers as bytes.
    static func humanBytes(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "—" }
        if t.contains(where: { $0.isLetter }) { return t }
        if let bytes = Double(t), bytes.isFinite {
            let f = ByteCountFormatter()
            f.countStyle = .memory
            f.allowedUnits = [.useMB, .useGB]
            return f.string(fromByteCount: Int64(bytes))
        }
        return t
    }
}

// MARK: - TLS delegate (self-signed)

private final class WTLSDelegate: NSObject, URLSessionDelegate {
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

// MARK: - Color helper

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
