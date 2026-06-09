//
//  StatusPill.swift
//  CraftyMobile
//
//  Glanceable status indicator: a colored dot + label that animates its color
//  as the server's state changes.
//

import SwiftUI

struct StatusPill: View {
    let status: ServerStatus
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .shadow(color: status.color.opacity(0.7), radius: 4)
            if !compact {
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 6)
        .background(status.color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(status.color.opacity(0.35), lineWidth: 1))
        .animation(.easeInOut(duration: 0.35), value: status)
    }
}

#Preview {
    HStack {
        StatusPill(status: .running)
        StatusPill(status: .stopped)
        StatusPill(status: .starting)
        StatusPill(status: .crashed)
    }
    .padding()
    .background(Theme.background)
}
