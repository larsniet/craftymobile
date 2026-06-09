//
//  CraftyWidget.swift
//  CraftyWidget
//
//  Home-screen widget showing server status at a glance. The timeline provider
//  fetches live state on WidgetKit's schedule (and falls back to the snapshot
//  the app writes), so the widget stays useful without opening the app.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct CraftyEntry: TimelineEntry {
    let date: Date
    let servers: [WServer]
    let lastUpdated: Date?
    let configured: Bool
    let isLive: Bool
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CraftyEntry {
        CraftyEntry(date: Date(), servers: Self.sample, lastUpdated: Date(), configured: true, isLive: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (CraftyEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CraftyEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            // Ask for frequent refreshes; iOS throttles widgets to a daily budget,
            // so this is a ceiling, not a guarantee. When the live fetch failed we
            // retry sooner so the widget recovers from a transient blip quickly.
            let minutes = entry.isLive ? 5 : 2
            let next = Date().addingTimeInterval(Double(minutes) * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func makeEntry() async -> CraftyEntry {
        guard WConfig.load() != nil else {
            return CraftyEntry(date: Date(), servers: [], lastUpdated: nil, configured: false, isLive: false)
        }
        if let live = await WidgetAPI.fetch() {
            return CraftyEntry(date: Date(), servers: live, lastUpdated: Date(), configured: true, isLive: true)
        }
        // Fall back to the app's last snapshot.
        if let snap = WSnapshot.read() {
            return CraftyEntry(date: Date(), servers: snap.rows, lastUpdated: snap.generatedAt, configured: true, isLive: false)
        }
        return CraftyEntry(date: Date(), servers: [], lastUpdated: nil, configured: true, isLive: false)
    }

    static let sample: [WServer] = [
        WServer(id: "1", name: "Survival", status: .running, online: 3, max: 20, cpu: 18, memory: "2.1 GB"),
        WServer(id: "2", name: "Creative", status: .stopped, online: 0, max: 10, cpu: 0, memory: "0 MB"),
        WServer(id: "3", name: "Modded SMP", status: .starting, online: 0, max: 16, cpu: 64, memory: "4.2 GB"),
    ]
}

// MARK: - Widget

struct CraftyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CraftyWidget", provider: Provider()) { entry in
            // Background is chosen per-family inside the view (accessory/Lock
            // Screen widgets need a clear / AccessoryWidgetBackground, not a
            // colored gradient).
            CraftyWidgetView(entry: entry)
        }
        .configurationDisplayName("Crafty Servers")
        .description("Monitor your Minecraft servers at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

// MARK: - Views

struct CraftyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CraftyEntry

    private let accent = Color(hex: 0x35E07F)

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        if !entry.configured {
            notConfigured
        } else if entry.servers.isEmpty {
            empty
        } else {
            switch family {
            case .systemSmall:          smallView
            case .accessoryInline:      inlineView
            case .accessoryCircular:    circularView
            case .accessoryRectangular: rectangularView
            default:                    listView(limit: family == .systemLarge ? 6 : 3)
            }
        }
    }

    /// Lock Screen (accessory) widgets render monochrome/tinted, so they use a
    /// neutral system background rather than the Home Screen's dark gradient.
    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            AccessoryWidgetBackground()
        case .accessoryInline:
            Color.clear
        default:
            LinearGradient(
                colors: [Color(hex: 0x14171D), Color(hex: 0x0A0C0F)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: Lock Screen — inline (single line above the clock)

    private var inlineView: some View {
        let running = entry.servers.filter { $0.status == .running }.count
        let players = entry.servers.reduce(0) { $0 + $1.online }
        return Label("\(running)/\(entry.servers.count) up · \(players) on", systemImage: "cube.fill")
    }

    // MARK: Lock Screen — circular (ring of running servers)

    private var circularView: some View {
        let running = entry.servers.filter { $0.status == .running }.count
        let total = Swift.max(entry.servers.count, 1)
        return Gauge(value: Double(running), in: 0...Double(total)) {
            Image(systemName: "cube.fill")
        } currentValueLabel: {
            Text("\(running)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    // MARK: Lock Screen — rectangular (compact summary)

    private var rectangularView: some View {
        let running = entry.servers.filter { $0.status == .running }.count
        let players = entry.servers.reduce(0) { $0 + $1.online }
        return VStack(alignment: .leading, spacing: 1) {
            Label("Crafty", systemImage: "cube.fill")
                .font(.caption2.weight(.bold))
                .widgetAccentable()
            Text("\(running)/\(entry.servers.count) servers up")
                .font(.caption)
            Text("\(players) players online")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Small — aggregate summary

    private var smallView: some View {
        let running = entry.servers.filter { $0.status == .running }.count
        let players = entry.servers.reduce(0) { $0 + $1.online }
        return VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            Text("\(running)/\(entry.servers.count)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(running == 1 ? "server up" : "servers up")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Label("\(players) online", systemImage: "person.2.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
            updatedFooter
        }
    }

    // MARK: Medium / Large — per-server list

    private func listView(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(entry.servers.prefix(limit)) { server in
                serverRow(server)
            }
            if entry.servers.count > limit {
                Text("+\(entry.servers.count - limit) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            updatedFooter
        }
    }

    private func serverRow(_ server: WServer) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(server.status.color)
                .frame(width: 9, height: 9)
                .shadow(color: server.status.color.opacity(0.7), radius: 3)
            Text(server.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            if server.status == .running {
                Text("\(server.online)/\(server.max)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", server.cpu))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(accent)
                    .frame(width: 38, alignment: .trailing)
            } else {
                Text(server.status.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(server.status.color)
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "cube.fill").foregroundStyle(accent)
            Text("Crafty").font(.caption.weight(.bold)).foregroundStyle(.white)
            Spacer()
            if entry.isLive {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(accent.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private var updatedFooter: some View {
        if let updated = entry.lastUpdated {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text(updated, style: .relative)
                if !entry.isLive { Text("(cached)") }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }

    @ViewBuilder
    private var notConfigured: some View {
        switch family {
        case .accessoryInline:
            Label("Crafty: set up", systemImage: "cube.fill")
        case .accessoryCircular:
            Image(systemName: "cube.fill").font(.title3).widgetAccentable()
        case .accessoryRectangular:
            Label("Open CraftyMobile", systemImage: "cube.fill")
                .font(.caption).widgetAccentable()
        default:
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(accent)
                Text("Open CraftyMobile to connect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryInline, .accessoryRectangular:
            Label("No servers", systemImage: "cube.fill")
                .font(isAccessory ? .caption : .body)
        case .accessoryCircular:
            Image(systemName: "xmark").font(.title3)
        default:
            VStack(spacing: 8) {
                Image(systemName: "server.rack").font(.title2).foregroundStyle(.secondary)
                Text("No servers").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
