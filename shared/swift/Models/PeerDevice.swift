struct PeerDevice: Identifiable, Hashable {
    let id:           String
    let discoveryKey: String
    let name:         String
    let systemImage:  String
    var isOnline:     Bool
    let isOwnDevice:  Bool

    var statusLabel: String { isOnline ? "Online" : "Offline" }
}
