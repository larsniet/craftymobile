//
//  StatChip.swift
//  CraftyMobile
//
//  Small labeled readout used for CPU%, memory, players, etc. Monospaced value
//  so changing numbers don't jitter the layout.
//

import SwiftUI

struct StatChip: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
        }
    }
}

/// Larger stat tile for the detail screen's stats grid.
struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
    }
}
