//
//  LogStreamView.swift
//  CraftyMobile
//
//  Dark, monospace, terminal-style scroller. Newest line at the bottom; auto-
//  scrolls to the bottom when new lines arrive (using a stable bottom anchor so
//  we don't fight the user if they scroll up to read history).
//

import SwiftUI

struct LogStreamView: View {
    let lines: [LogLine]
    var autoScroll: Bool = true

    private let bottomAnchor = "log-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty {
                        Text("No output yet.")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.terminalText.opacity(0.5))
                            .padding(.vertical, 8)
                    }
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.terminalText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Zero-height marker we can scroll to.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(12)
            }
            .background(Theme.terminalBackground)
            .onChange(of: lines.last?.id) { _, _ in
                guard autoScroll else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }
}
