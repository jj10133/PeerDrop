// RootView.swift — iOS tab bar root

import SwiftUI

struct RootView: View {
    @EnvironmentObject var worker: Worker

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Devices", systemImage: "person.2.fill")
                }

            TransferListView()
                .tabItem {
                    Label("Transfers", systemImage: "arrow.up.arrow.down")
                }
                .badge(worker.activeTransfers.count > 0 ? worker.activeTransfers.count : 0)

            ReceivedFilesView()
                .tabItem {
                    Label("Received", systemImage: "tray.and.arrow.down.fill")
                }

            SettingsViewiOS()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
