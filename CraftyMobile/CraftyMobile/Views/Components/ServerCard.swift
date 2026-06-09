//
//  ServerCard.swift
//  CraftyMobile
//
//  One card per server on the home screen: name, status pill, player count,
//  and compact CPU/memory readouts.
//

import SwiftUI

struct ServerCard: View {
    let server: Server
    let stats: ServerStats?

    private var status: ServerStatus { stats?.status ?? .stopped }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let type = server.type {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusPill(status: status)
            }

            HStack(spacing: 18) {
                StatChip(
                    icon: "person.2.fill",
                    label: "Players",
                    value: stats.map { "\($0.online)/\($0.max)" } ?? "—",
                    tint: Theme.accent
                )
                StatChip(
                    icon: "cpu",
                    label: "CPU",
                    value: stats.map { String(format: "%.0f%%", $0.cpu) } ?? "—",
                    tint: Theme.statusUpdating
                )
                StatChip(
                    icon: "memorychip",
                    label: "Memory",
                    value: stats?.memDisplay ?? "—",
                    tint: Theme.statusStarting
                )
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .cardSurface()
    }
}
