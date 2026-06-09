//
//  Theme.swift
//  CraftyMobile
//
//  Centralized design tokens: colors, spacing, corner radii, and a couple of
//  reusable view modifiers. Dark-first "control room" aesthetic with one crisp
//  electric-green accent. Colors adapt to light mode where it matters.
//

import SwiftUI

enum Theme {
    // MARK: Accent
    /// Crisp, slightly electric green — refined, not cartoonish.
    static let accent = Color(hex: 0x35E07F)

    // MARK: Status colors
    static let statusRunning = Color(hex: 0x35E07F)   // green
    static let statusStopped = Color(hex: 0x8A8F98)   // gray
    static let statusStarting = Color(hex: 0xFFB23E)  // amber
    static let statusCrashed = Color(hex: 0xFF5A5A)   // red
    static let statusUpdating = Color(hex: 0x4FA9FF)  // blue

    // MARK: Surfaces (adaptive)
    /// Near-black canvas in dark mode, soft off-white in light mode.
    static let background = Color("AppBackground", bundle: nil, fallbackDark: 0x0B0D10, fallbackLight: 0xF2F3F5)
    /// Subtly elevated card surface.
    static let card = Color("AppCard", bundle: nil, fallbackDark: 0x16191F, fallbackLight: 0xFFFFFF)
    /// A second elevation level (insets within cards, log backgrounds).
    static let elevated = Color("AppElevated", bundle: nil, fallbackDark: 0x1E222A, fallbackLight: 0xE9EBEF)
    /// Hairline separators / card borders.
    static let stroke = Color.primary.opacity(0.08)

    // MARK: Terminal
    static let terminalBackground = Color(hex: 0x0A0C0F)
    static let terminalText = Color(hex: 0xD6E2D9)

    // MARK: Layout
    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 12
    static let spacing: CGFloat = 16
}

extension ServerStatus {
    var color: Color {
        switch self {
        case .running:  return Theme.statusRunning
        case .stopped:  return Theme.statusStopped
        case .starting: return Theme.statusStarting
        case .crashed:  return Theme.statusCrashed
        case .updating: return Theme.statusUpdating
        }
    }
}

// MARK: - Card modifier

struct CardSurface: ViewModifier {
    var padding: CGFloat = Theme.spacing
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(padding: CGFloat = Theme.spacing) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Adaptive color that prefers a named asset color but falls back to the
    /// given dark/light hex values, so the app looks right even without an
    /// asset catalog entry.
    init(_ name: String, bundle: Bundle?, fallbackDark: UInt32, fallbackLight: UInt32) {
        self = Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? fallbackDark : fallbackLight
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}
