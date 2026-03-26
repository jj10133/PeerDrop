// Worker.swift — Observable state + public API surface for the SwiftUI layer.
//
// Follows the Facade pattern: SwiftUI views only call Worker methods,
// never touching RPC or IPC directly.
// Event handling is in Worker+Events.swift (Open/Closed principle).

import BareRPC
import Foundation
import AppKit
import UserNotifications

class Worker: ObservableObject {

    // MARK: - Published state (consumed by SwiftUI)

    /// The device's Peer ID (profileDiscoveryPublicKey hex). Share with others to connect.
    @Published var myPeerID:        String         = ""
    @Published var knownDevices:    [PeerDevice]   = []
    @Published var activeTransfers: [FileTransfer] = []
    @Published var downloadPath:    String         = ""

    // MARK: - Derived collections

    /// Devices sharing the same seed file (same discoveryKey as this device)
    var myDevices: [PeerDevice] { knownDevices.filter(\.isOwnDevice) }

    /// External contacts (different discoveryKey)
    var contacts: [PeerDevice] { knownDevices.filter { !$0.isOwnDevice } }

    // MARK: - Internal

    let bridge = IPCBridge()

    /// Maps ephemeral Noise key → stable discoveryKey so disconnect events
    /// can update the right PeerDevice even when we only know the noiseKey.
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

    /// Maps a platform string from the JS side to an SF Symbol name.
    func systemImage(for platform: String) -> String {
        switch platform.lowercased() {
        case "darwin":           return "desktopcomputer"
        case "ios":              return "iphone"
        case "linux":            return "server.rack"
        case "win32", "windows": return "laptopcomputer"
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

    // MARK: - App lifecycle

    func suspend()   { bridge.suspend() }
    func resume()    { bridge.resume() }
    func terminate() { bridge.terminate() }
}
