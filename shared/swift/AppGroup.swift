// AppGroup.swift — shared container between main app and Share Extension.
// Uses file-based JSON storage instead of UserDefaults to avoid
// CFPrefsPlistSource issues across extension process boundaries.

import Foundation

public struct AppGroupPeer: Codable {
    public let discoveryKey: String
    public let displayName:  String
    public let platform:     String
    public let isOnline:     Bool
    public let isOwnDevice:  Bool

    public init(discoveryKey: String, displayName: String, platform: String,
                isOnline: Bool, isOwnDevice: Bool) {
        self.discoveryKey = discoveryKey
        self.displayName  = displayName
        self.platform     = platform
        self.isOnline     = isOnline
        self.isOwnDevice  = isOwnDevice
    }
}

public struct PendingTransfer: Codable {
    public let fileURL:  String
    public let peerKey:  String
    public let peerName: String

    public init(fileURL: String, peerKey: String, peerName: String) {
        self.fileURL  = fileURL
        self.peerKey  = peerKey
        self.peerName = peerName
    }
}

public enum AppGroup {
    static let id = "group.to.foss.peerdrop"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: id
        )
    }

    static var peersFileURL: URL? {
        containerURL?.appendingPathComponent("peerdrop-peers.json")
    }

    static var transferFileURL: URL? {
        containerURL?.appendingPathComponent("peerdrop-transfer.json")
    }

    // MARK: - Peers

    public static func writePeers(_ peers: [AppGroupPeer]) {
        guard let url = peersFileURL else {
            NSLog("❌ [AppGroup] containerURL is nil — check entitlements")
            return
        }
        guard let data = try? JSONEncoder().encode(peers) else { return }
        do {
            try data.write(to: url, options: .atomic)
            NSLog("✅ [AppGroup] wrote %d peers to %@", peers.count, url.path)
        } catch {
            NSLog("❌ [AppGroup] write error: %@", error.localizedDescription)
        }
    }

    public static func readPeers() -> [AppGroupPeer] {
        guard let url = peersFileURL else {
            NSLog("❌ [AppGroup] containerURL is nil — check entitlements")
            return []
        }
        NSLog("📦 [AppGroup] reading peers from %@", url.path)
        guard let data = try? Data(contentsOf: url),
              let peers = try? JSONDecoder().decode([AppGroupPeer].self, from: data)
        else {
            NSLog("⚠️ [AppGroup] no peers file or decode failed")
            return []
        }
        NSLog("✅ [AppGroup] read %d peers", peers.count)
        return peers
    }

    // MARK: - Pending transfer

    public static func writePendingTransfer(_ transfer: PendingTransfer) {
        guard let url = transferFileURL,
              let data = try? JSONEncoder().encode(transfer) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func readPendingTransfer() -> PendingTransfer? {
        guard let url = transferFileURL,
              let data = try? Data(contentsOf: url),
              let transfer = try? JSONDecoder().decode(PendingTransfer.self, from: data)
        else { return nil }
        return transfer
    }

    public static func clearPendingTransfer() {
        guard let url = transferFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}