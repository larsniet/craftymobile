//
//  ErrorBanner.swift
//  CraftyMobile
//
//  Friendly, dismissible inline banner shown when an API call fails.
//

import SwiftUI

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.statusCrashed)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.statusCrashed.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                .strokeBorder(Theme.statusCrashed.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
