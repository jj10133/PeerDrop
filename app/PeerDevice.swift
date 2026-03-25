//
//  PeerDevice.swift
//  App
//
//  Created by Janardhan on 2026-03-21.
//


struct PeerDevice: Identifiable {
    let id:           String  // stable: discoveryKey hex
    let discoveryKey: String
    let name:         String
    let systemImage:  String
    var isOnline:     Bool

    var statusLabel: String { isOnline ? "Online" : "Offline" }
}
