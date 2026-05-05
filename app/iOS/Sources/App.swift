// AppEntry.swift — iOS @main entry point

import SwiftUI

@main
struct PeerDropApp: App {

    @StateObject private var worker = Worker()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(worker)
                .onAppear {
                    if !hasCompletedOnboarding { showOnboarding = true }
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                        .environmentObject(worker)
                        .onDisappear { hasCompletedOnboarding = true }
                }
                .onOpenURL { url in
                    if url.scheme == "peerdrop", url.host == "send" {
                        worker.processPendingTransfer()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background: worker.suspend()
                    case .active:
                        worker.resume()
                        worker.processPendingTransfer()
                    default: break
                    }
                }
        }
    }
}
