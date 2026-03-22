import BareKit
import SwiftUI

@main
struct App: SwiftUI.App {
    
    @StateObject private var worker = Worker()
    
    var body: some Scene {
        MenuBarExtra("PeerDrop", systemImage: "sharedwithyou") {
            VStack {
                ContentView()
            }
//            .frame(width: 320, height: 420)
            .edgesIgnoringSafeArea(.all)
        }
        .menuBarExtraStyle(.window)
    }
}
