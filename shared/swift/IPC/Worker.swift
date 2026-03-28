import BareRPC
import Foundation
#if canImport(AppKit)
import AppKit
import UserNotifications
#elseif canImport(UIKit)
import UIKit
#endif

class Worker: ObservableObject {

    // MARK: - Published state

    @Published var myPeerID:        String         = ""
    @Published var knownDevices:    [PeerDevice]   = []
    @Published var activeTransfers: [FileTransfer] = []
    @Published var downloadPath:    String         = ""

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

    // MARK: - Pending transfer from Share Extension

    func processPendingTransfer() {
        guard let pending = AppGroup.readPendingTransfer() else { return }
        AppGroup.clearPendingTransfer()
        guard let url = URL(string: pending.fileURL) else { return }
        sendFile(at: url, to: pending.peerKey)
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
        case "darwin":           return "laptopcomputer"
        case "linux":            return "server.rack"
        case "win32", "windows": return "laptopcomputer"
        case "ios":              return "iphone"
        default:                 return "desktopcomputer"
        }
    }

    // MARK: - App Group sync
    // Called after every knownDevices update so the Share Extension
    // always has a fresh peer list without needing the app to be running.

    func syncPeersToAppGroup() {
        let appGroupPeers = knownDevices.map { device in
            AppGroupPeer(
                discoveryKey: device.discoveryKey,
                displayName:  device.name,
                platform:     device.systemImage,
                isOnline:     device.isOnline,
                isOwnDevice:  device.isOwnDevice
            )
        }
        AppGroup.writePeers(appGroupPeers)
    }

    // MARK: - Notifications

    func showNotification(title: String, body: String) {
        #if canImport(AppKit)
        let content   = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        ) { if let e = $0 { print("❌ Notification: \(e)") } }
        #endif
    }

    // MARK: - Lifecycle

    func suspend()   { bridge.suspend() }
    func resume()    { bridge.resume() }
    func terminate() { bridge.terminate() }
}
