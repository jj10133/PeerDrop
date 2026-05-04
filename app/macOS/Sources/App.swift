import SwiftUI

@main
struct App: SwiftUI.App {

    @StateObject private var worker = Worker()

    var body: some Scene {
        MenuBarExtra("PeerDrop", systemImage: "drop.fill") {
            VStack {
                ContentView()
                    .environmentObject(worker)
            }
            .frame(height: 300)
            .edgesIgnoringSafeArea(.all)
        }
        .menuBarExtraStyle(.window)
    }
}
