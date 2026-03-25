import BareRPC
import Foundation
import AppKit
import UserNotifications

class Worker: ObservableObject {

    // MARK: - Published state

    /// profileDiscoveryPublicKey — what you copy and share with others as your "Peer ID"
    @Published var myPeerID:      String = ""

    /// identityPublicKey — used internally to detect which connected peers are your own devices
    @Published var myIdentityKey: String = ""

    @Published var knownDevices:    [PeerDevice]   = []
    @Published var activeTransfers: [FileTransfer] = []
    @Published var downloadPath:    String = ""

    // MARK: - Computed device sections

    /// Your own devices (same identityKey as you)
    var myDevices: [PeerDevice] {
        knownDevices.filter { $0.isOwnDevice }
    }

    /// Other people (different identityKey)
    var contacts: [PeerDevice] {
        knownDevices.filter { !$0.isOwnDevice }
    }

    // MARK: - Internal

    let bridge = IPCBridge()

    /// Maps ephemeral noiseKey → stable identityKey for the current session
    var noiseToIdentity: [String: String] = [:]

    // MARK: - Init

    init() {
        setupEventHandlers()
        Task { await bridge.start() }
    }

    // MARK: - Public API

    /// Send a file to a peer. peerId = identityKey (stable, same across all their devices).
    /// If they have multiple devices online, routes to the first available connection.
    func sendFile(at url: URL, to identityKey: String) {
        fireAndForget(Cmd.sendFile, body: ["filePath": url.path, "peerId": identityKey])
    }

    /// Connect to another person. peerID = their discoveryPublicKey (their "Peer ID").
    func connectPeer(peerID: String) {
        fireAndForget(Cmd.connectPeer, body: ["peerID": peerID])
    }

    /// Remove a contact or own device entry.
    func forgetPeer(identityKey: String) {
        fireAndForget(Cmd.forgetPeer, body: ["peerIdentityKey": identityKey])
    }

    /// Change where received files are saved.
    func setDownloadPath(_ path: String) {
        DispatchQueue.main.async { self.downloadPath = path }
        fireAndForget(Cmd.setDownloadPath, body: ["downloadPath": path])
    }

    /// Device A: generate a pairing QR invite URL.
    func generatePairingInvite() async throws -> String {
        guard let data = try await bridge.request(Cmd.generateInvite, body: [:]),
              let url = String(data: data, encoding: .utf8), !url.isEmpty
        else { throw PeerDropError.noInviteReturned }
        return url
    }

    /// Device B: submit the pasted invite URL to start pairing.
    func acceptPairingInvite(url: String) {
        fireAndForget(Cmd.acceptInvite, body: ["inviteUrl": url])
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

enum PeerDropError: Error {
    case noInviteReturned
}
