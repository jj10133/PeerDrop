// AppEntry.swift — iOS @main entry point

import SwiftUI

@main
struct PeerDropApp: App {

    @StateObject private var worker = Worker()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(worker)
                .onOpenURL { url in
                    // Called when Share Extension opens peerdrop://send
                    if url.scheme == "peerdrop", url.host == "send" {
                        worker.processPendingTransfer()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background: worker.suspend()
                    case .active:
                        worker.resume()
                        // Check for any pending transfer from Share Extension
                        worker.processPendingTransfer()
                    default: break
                    }
                }
        }
    }
}
