//
//  RootView.swift
//  CraftyMobile
//
//  Top-level tab navigation: Servers (home) and Settings. The Servers tab owns
//  its own navigation stack so detail / logs / console push on top.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            NavigationStack {
                ServersListView()
            }
            .tabItem {
                Label("Servers", systemImage: "server.rack")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppSettings.shared)
}
