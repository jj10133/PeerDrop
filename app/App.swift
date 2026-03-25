import SwiftUI

@main
struct App: SwiftUI.App {

    @StateObject private var worker = Worker()

    var body: some Scene {
        MenuBarExtra("PeerDrop", systemImage: "sharedwithyou") {
            VStack {
                ContentView()
                    .environmentObject(worker)
            }
            .edgesIgnoringSafeArea(.all)
        }
        .menuBarExtraStyle(.window)
    }
}
