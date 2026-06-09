//
//  CraftyModels.swift
//  CraftyMobile
//
//  Codable models for the Crafty Controller v2 API.
//  These are intentionally *tolerant*: Crafty's JSON varies between versions and
//  some fields are occasionally missing, null, or typed oddly (e.g. numbers sent
//  as strings). Every field that isn't strictly required is optional and decoded
//  through helpers that won't throw on surprising input.
//

import Foundation

// MARK: - Envelope

/// Every Crafty response is shaped like `{ "status": "ok", "data": ... }` or
/// `{ "status": "error", "error": "..." }`. `Envelope` decodes the wrapper and
/// the typed payload in one pass.
struct Envelope<Payload: Decodable>: Decodable {
    let status: String
    let data: Payload?
    let error: String?
    let errorData: String?

    var isOK: Bool { status.lowercased() == "ok" }

    enum CodingKeys: String, CodingKey {
        case status, data, error
        case errorData = "error_data"
    }
}

/// Some endpoints (e.g. `/crafty/check`) return `{ "status": "ok" }` with no
/// data payload. This lets us decode the envelope without caring about `data`.
struct EmptyData: Decodable {}

// MARK: - Server

/// A server as returned by `GET /api/v2/servers`.
struct Server: Identifiable, Decodable, Hashable {
    let id: String          // server_id (UUID string)
    let name: String        // server_name
    let type: String?       // e.g. "minecraft-java"
    let ip: String?         // server_ip
    let port: Int?          // server_port

    enum CodingKeys: String, CodingKey {
        case id = "server_id"
        case name = "server_name"
        case type
        case ip = "server_ip"
        case port = "server_port"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // server_id can occasionally arrive as a number; coerce to String.
        self.id = try c.decodeFlexibleString(forKey: .id) ?? UUID().uuidString
        self.name = (try c.decodeIfPresent(String.self, forKey: .name)) ?? "Unnamed server"
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.ip = try c.decodeFlexibleString(forKey: .ip)
        self.port = try c.decodeFlexibleInt(forKey: .port)
    }
}

// MARK: - Server stats

/// Live stats from `GET /api/v2/servers/{id}/stats`.
///
/// Note: in Crafty the `server_id` field of the stats payload is itself an
/// *object* (the embedded server record), not a string — so we don't try to
/// decode it here; we only pull the runtime fields we display.
struct ServerStats: Decodable, Equatable {
    let running: Bool
    let crashed: Bool
    let waitingStart: Bool
    let updating: Bool

    let cpu: Double         // percent
    let mem: String         // human string, e.g. "42.2MB"
    let memPercent: Double

    let worldName: String?
    let worldSize: String?
    let version: String?
    let serverPort: Int?

    let online: Int         // current players
    let max: Int            // max players
    let playersRaw: String? // raw players string, parsed lazily

    let started: String?    // ISO-ish start timestamp, used for uptime

    enum CodingKeys: String, CodingKey {
        case running, crashed, updating, cpu, mem, online, max, version, started
        case waitingStart = "waiting_start"
        case memPercent = "mem_percent"
        case worldName = "world_name"
        case worldSize = "world_size"
        case serverPort = "server_port"
        case players
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.running = c.decodeFlexibleBool(forKey: .running)
        self.crashed = c.decodeFlexibleBool(forKey: .crashed)
        self.waitingStart = c.decodeFlexibleBool(forKey: .waitingStart)
        self.updating = c.decodeFlexibleBool(forKey: .updating)

        self.cpu = (try? c.decodeFlexibleDouble(forKey: .cpu)) ?? 0
        self.mem = (try? c.decodeFlexibleString(forKey: .mem)) ?? "—"
        self.memPercent = (try? c.decodeFlexibleDouble(forKey: .memPercent)) ?? 0

        self.worldName = try? c.decodeFlexibleString(forKey: .worldName)
        self.worldSize = try? c.decodeFlexibleString(forKey: .worldSize)
        self.version = try? c.decodeFlexibleString(forKey: .version)
        self.serverPort = try? c.decodeFlexibleInt(forKey: .serverPort)

        self.online = (try? c.decodeFlexibleInt(forKey: .online)) ?? 0
        self.max = (try? c.decodeFlexibleInt(forKey: .max)) ?? 0
        self.playersRaw = try? c.decodeFlexibleString(forKey: .players)

        self.started = try? c.decodeFlexibleString(forKey: .started)
    }

    /// Derived high-level status used to drive the UI (pill color, etc.).
    var status: ServerStatus {
        if crashed { return .crashed }
        if updating { return .updating }
        if waitingStart { return .starting }
        if running { return .running }
        return .stopped
    }

    /// Human-readable memory string.
    ///
    /// Crafty is inconsistent here: some versions send a pre-formatted string
    /// like `"42.2MB"`, others send a raw byte *count* (e.g. `4509990912`).
    /// If the value already contains units (any letter) we pass it through;
    /// if it's a bare number we treat it as bytes and format it.
    var memDisplay: String {
        ByteSizeFormatting.humanReadable(mem, allowedUnits: [.useMB, .useGB])
    }

    /// Human-readable world size. Same Crafty inconsistency as `mem` — sometimes
    /// a formatted string, sometimes a raw byte count.
    var worldSizeDisplay: String {
        ByteSizeFormatting.humanReadable(worldSize, allowedUnits: [.useKB, .useMB, .useGB])
    }

    /// Players parsed from the raw `players` string. See `PlayerParser`.
    var players: [String] { PlayerParser.parse(playersRaw) }

    /// Uptime computed from `started`, if it parses. Best-effort only.
    var uptime: TimeInterval? {
        guard let started, let date = DateParsing.parse(started) else { return nil }
        let interval = Date().timeIntervalSince(date)
        return interval >= 0 ? interval : nil
    }
}

// MARK: - Status

enum ServerStatus: String {
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
}

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    /// Decodes a value that *should* be a String but might be a number or bool.
    func decodeFlexibleString(forKey key: Key) throws -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return String(b) }
        return nil
    }

    /// Decodes a value that should be an Int but might arrive as a String or Double.
    func decodeFlexibleInt(forKey key: Key) throws -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            if let i = Int(s) { return i }
            // Never feed NaN/inf to Int(_:) — that traps. Guard finiteness.
            if let d = Double(s), d.isFinite { return Int(d) }
        }
        return nil
    }

    /// Decodes a value that should be a Double but might arrive as a String or Int.
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    /// Decodes a Bool that might arrive as a Bool, an Int (0/1), or a string.
    /// Returns `false` when the key is missing or unrecognizable.
    func decodeFlexibleBool(forKey key: Key) -> Bool {
        // `try?` flattens the optional, so each binding yields the unwrapped value.
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return ["true", "1", "yes"].contains(s.lowercased())
        }
        return false
    }
}
