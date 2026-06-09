//
//  PlayerParser.swift
//  CraftyMobile
//
//  Crafty reports the online player list as a *string* rather than structured
//  JSON, and the exact shape depends on the server type / Crafty version.
//  Observed forms include:
//
//      "[]"                          (no players)
//      "['Steve', 'Alex']"           (Python-style list, single quotes)
//      "[\"Steve\", \"Alex\"]"       (JSON-style list, double quotes)
//      "Steve, Alex"                 (bare comma-separated)
//      ""                            (empty / unknown)
//
//  We parse all of these defensively and never throw — worst case we return an
//  empty list and the UI falls back to the online/max counts.
//

import Foundation

enum PlayerParser {
    static func parse(_ raw: String?) -> [String] {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return []
        }

        // Strip a single pair of surrounding brackets, if present.
        if s.hasPrefix("[") { s.removeFirst() }
        if s.hasSuffix("]") { s.removeLast() }

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return [] }

        // Split on commas and clean each token of quotes / whitespace.
        let tokens = s.split(separator: ",").map { token -> String in
            var t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return tokens.filter { !$0.isEmpty }
    }
}

enum DateParsing {
    // Crafty timestamps are not perfectly standardized; try a few formats.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = pattern
            return f
        }
    }()

    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "false", trimmed.lowercased() != "none" else {
            return nil
        }
        if let d = isoFormatter.date(from: trimmed) { return d }
        if let d = isoFormatterNoFraction.date(from: trimmed) { return d }
        for f in fallbackFormatters {
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }
}

enum ByteSizeFormatting {
    /// Renders a size value that may arrive either pre-formatted (e.g. `"42.2MB"`)
    /// or as a bare byte count (e.g. `"4509990912"`). Strings that already carry a
    /// unit are passed through unchanged; bare numbers are formatted as bytes.
    static func humanReadable(_ raw: String?, allowedUnits: ByteCountFormatter.Units) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return "—" }

        // Already has a unit suffix (MB/GB/KiB/…)? Use as-is.
        if trimmed.contains(where: { $0.isLetter }) { return trimmed }

        // Bare, finite number → interpret as bytes and format.
        if let bytes = Double(trimmed), bytes.isFinite {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .memory          // binary (1024) units
            formatter.allowedUnits = allowedUnits
            return formatter.string(fromByteCount: Int64(bytes))
        }
        return trimmed
    }
}

extension TimeInterval {
    /// Compact uptime string, e.g. "3d 4h", "12m", "45s".
    var uptimeString: String {
        let total = Int(self)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}
