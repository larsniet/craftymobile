//
//  WidgetSnapshot.swift
//  CraftyMobile
//
//  A compact, Codable snapshot of server state that the app writes to the shared
//  App Group container after each refresh. The widget reads it for an instant
//  first paint and as an offline fallback when its own live fetch fails.
//
//  NOTE: the widget target has a matching `CraftyWidgetSnapshot` decoder. The two
//  must keep identical JSON keys — they're tiny and intentionally duplicated so
//  each target stays self-contained.
//

import Foundation
import WidgetKit

struct CraftyWidgetSnapshot: Codable {
    var generatedAt: Date
    var servers: [Server]

    struct Server: Codable, Identifiable {
        var id: String
        var name: String
        var status: String      // ServerStatus.rawValue
        var online: Int
        var max: Int
        var cpu: Double
        var memory: String      // already human-readable
    }
}

enum WidgetSnapshotStore {
    private static let key = "widgetSnapshot"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    /// Persist a snapshot and ask WidgetKit to refresh, so the home-screen
    /// widget tracks the app while it's open.
    static func write(_ snapshot: CraftyWidgetSnapshot) {
        guard let data = try? JSONEncoder.crafty.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> CraftyWidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.crafty.decode(CraftyWidgetSnapshot.self, from: data)
    }
}

extension JSONEncoder {
    static var crafty: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var crafty: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
