//
//  AppGroup.swift
//  App
//
//  Created by Janardhan on 2026-03-28.
//

// AppGroup.swift — shared container between main app and Share Extension.
// Both targets declare group.to.foss.peerdrop in their entitlements.

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
    public let fileURL:       String   // file:// URL of the item to send
    public let peerKey:       String   // discoveryKey of target peer
    public let peerName:      String   // display name for UX

    public init(fileURL: String, peerKey: String, peerName: String) {
        self.fileURL  = fileURL
        self.peerKey  = peerKey
        self.peerName = peerName
    }
}

public enum AppGroup {
    static let id          = "group.to.foss.peerdrop"
    static let peersKey    = "peerdrop.peers"
    static let transferKey = "peerdrop.pendingTransfer"

    static var container: UserDefaults? {
        UserDefaults(suiteName: id)
    }

    // MARK: - Peers (written by main app, read by extension)

    public static func writePeers(_ peers: [AppGroupPeer]) {
        guard let data = try? JSONEncoder().encode(peers) else { return }
        container?.set(data, forKey: peersKey)
    }

    public static func readPeers() -> [AppGroupPeer] {
        guard let data = container?.data(forKey: peersKey),
              let peers = try? JSONDecoder().decode([AppGroupPeer].self, from: data)
        else { return [] }
        return peers
    }

    // MARK: - Pending transfer (written by extension, read by main app)

    public static func writePendingTransfer(_ transfer: PendingTransfer) {
        guard let data = try? JSONEncoder().encode(transfer) else { return }
        container?.set(data, forKey: transferKey)
    }

    public static func readPendingTransfer() -> PendingTransfer? {
        guard let data = container?.data(forKey: transferKey),
              let transfer = try? JSONDecoder().decode(PendingTransfer.self, from: data)
        else { return nil }
        return transfer
    }

    public static func clearPendingTransfer() {
        container?.removeObject(forKey: transferKey)
    }
}
