// PeerDevice.swift — Value type representing a known peer.

struct PeerDevice: Identifiable, Equatable {
    let id:           String   // discoveryKey hex — stable, unique
    let discoveryKey: String
    let name:         String   // display name (hostname or user label)
    let systemImage:  String   // SF Symbol name based on platform
    var isOnline:     Bool
    let isOwnDevice:  Bool     // true when discoveryKey == myPeerID

    var statusLabel: String { isOnline ? "Online" : "Offline" }
}
