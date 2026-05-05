// App.swift — macOS @main entry point

import SwiftUI
import AppKit

@main
struct App: SwiftUI.App {

    @StateObject private var worker = Worker()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        MenuBarExtra("PeerDrop", systemImage: "drop.fill") {
            ContentView()
                .environmentObject(worker)
                .onAppear {
                    if !hasCompletedOnboarding {
                        openOnboardingWindow()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }

    func openOnboardingWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask:   [.titled, .closable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        window.title           = "Welcome to PeerDrop"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true

        var isPresented = true
        let binding = Binding<Bool>(
            get:  { isPresented },
            set:  { newVal in
                isPresented = newVal
                if !newVal {
                    hasCompletedOnboarding = true
                    window.close()
                }
            }
        )

        window.contentView = NSHostingView(
            rootView: OnboardingView(isPresented: binding)
                .environmentObject(worker)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
