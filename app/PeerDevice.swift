//
//  PeerDevice.swift
//  App
//
//  Created by Janardhan on 2026-03-21.
//

struct PeerDevice: Identifiable {
    let id:           String  // identityKey — stable person/device-group ID
    let discoveryKey: String  // Hyperswarm topic
    let name:         String  // last seen device name
    let systemImage:  String
    var isOnline:     Bool
    let isOwnDevice:  Bool    // true when identityKey == myIdentityKey (own device)

    var statusLabel: String { isOnline ? "Online" : "Offline" }
}
