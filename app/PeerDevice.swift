struct PeerDevice: Identifiable {
    let id:           String  // discoveryKey — stable peer/device ID
    let discoveryKey: String  // same as id, explicit for clarity at call sites
    let name:         String  // hostname from last handshake
    let systemImage:  String
    var isOnline:     Bool
    let isOwnDevice:  Bool    // true when discoveryKey == myPeerID (shared mnemonic)

    var statusLabel: String { isOnline ? "Online" : "Offline" }
}
