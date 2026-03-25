struct PeerDevice: Identifiable {
    let id:           String   // discoveryKey hex — stable unique ID
    let discoveryKey: String   // same as id, explicit for call-site clarity
    let displayName:  String?  // user-set label ("My iPhone", "Alice") — nil if not set
    let hostname:     String?  // device-reported hostname from handshake
    let systemImage:  String
    var isOnline:     Bool

    /// What to show in the UI: user label > hostname > truncated key
    var name: String {
        if let d = displayName, !d.isEmpty { return d }
        if let h = hostname,    !h.isEmpty { return h }
        return String(id.prefix(12)) + "..."
    }

    var statusLabel: String { isOnline ? "Online" : "Offline" }
}
