import BareKit
import SwiftUI

@main
struct App: SwiftUI.App {
    private var worklet = Worklet()
    @State private var isWorkletStarted = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    worklet.start(name: "app", ofType: "bundle")
                    isWorkletStarted = true
                }
                .onDisappear {
                    worklet.terminate()
                    isWorkletStarted = false
                }
        }
        .onChange(of: scenePhase) { phase in
            guard isWorkletStarted else { return }
            
            switch phase {
            case .background:
                worklet.suspend()
            case .active:
                worklet.resume()
            default:
                break
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Hello Apple!")
    }
}
