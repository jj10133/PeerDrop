// RPC command IDs — must match commands.js exactly.

enum Cmd {
    // JS → Swift events
    static let ready             = UInt(1)
    static let peerConnected     = UInt(2)
    static let peerDisconnected  = UInt(3)
    static let transferStarted   = UInt(4)
    static let transferProgress  = UInt(5)
    static let transferComplete  = UInt(6)
    static let error             = UInt(7)
    static let savedPeers        = UInt(11)

    // Swift → JS requests
    static let sendFile          = UInt(8)
    static let connectPeer       = UInt(9)
    static let setDownloadPath   = UInt(10)
    static let forgetPeer        = UInt(12)
}
