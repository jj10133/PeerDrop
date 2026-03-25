import BareRPC
import Foundation
import AppKit
import UserNotifications

class Worker: ObservableObject {

    // MARK: - Published state

    /// profileDiscoveryPublicKey hex — share this with others as your Peer ID.
    /// Copy ~/.peerdrop/seed to another device to get the same Peer ID there.
    @Published var myPeerID:      String = ""

    @Published var knownDevices:    [PeerDevice]   = []
    @Published var activeTransfers: [FileTransfer] = []
    @Published var downloadPath:    String = ""

    // MARK: - Computed sections

    var myDevices: [PeerDevice] { knownDevices.filter(\.isOwnDevice) }
    var contacts:  [PeerDevice] { knownDevices.filter { !$0.isOwnDevice } }

    // MARK: - Internal

    let bridge = IPCBridge()

    /// Maps ephemeral noiseKey → stable discoveryKey for disconnect resolution
    var noiseToDiscovery: [String: String] = [:]

    // MARK: - Init

    init() {
        setupEventHandlers()
        Task { await bridge.start() }
    }

    // MARK: - Public API

    func sendFile(at url: URL, to discoveryKey: String) {
        fireAndForget(Cmd.sendFile, body: ["filePath": url.path, "peerId": discoveryKey])
    }

    func connectPeer(peerID: String) {
        fireAndForget(Cmd.connectPeer, body: ["peerID": peerID])
    }

    func forgetPeer(discoveryKey: String) {
        fireAndForget(Cmd.forgetPeer, body: ["peerDiscoveryKey": discoveryKey])
    }

    func setDownloadPath(_ path: String) {
        DispatchQueue.main.async { self.downloadPath = path }
        fireAndForget(Cmd.setDownloadPath, body: ["downloadPath": path])
    }

    // MARK: - Helpers

    func fireAndForget(_ command: UInt, body: [String: Any]) {
        Task {
            do { _ = try await bridge.request(command, body: body) }
            catch { print("❌ RPC \(command): \(error)") }
        }
    }

    func systemImage(for platform: String) -> String {
        switch platform.lowercased() {
        case "darwin":           return "desktopcomputer"
        case "linux":            return "server.rack"
        case "win32", "windows": return "laptopcomputer"
        case "ios":              return "iphone"
        default:                 return "desktopcomputer"
        }
    }

    func showNotification(title: String, body: String) {
        let content   = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        ) { if let e = $0 { print("❌ Notification: \(e)") } }
    }

    // MARK: - Lifecycle
    func suspend()   { bridge.suspend() }
    func resume()    { bridge.resume() }
    func terminate() { bridge.terminate() }
}
