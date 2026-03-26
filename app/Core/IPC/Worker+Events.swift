// Worker+Events.swift — Handles all inbound RPC events from the JS runtime.
//
// Each handler has one job: parse the payload and update Worker's published state.
// No business logic here — just mapping JS data → Swift models.

import BareRPC
import Foundation

extension Worker {

    // MARK: - Setup

    func setupEventHandlers() {
        bridge.rpc.onEvent   = { [weak self] event in await self?.handleEvent(event) }
        bridge.rpc.onRequest = { req in req.reply(nil) }
        bridge.rpc.onError   = { error in print("❌ RPC error: \(error)") }
    }

    // MARK: - Dispatch

    func handleEvent(_ event: IncomingEvent) async {
        guard
            let data = event.data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        switch event.command {
        case Cmd.ready:            onReady(json)
        case Cmd.savedPeers:       onSavedPeers(json)
        case Cmd.peerConnected:    onPeerConnected(json)
        case Cmd.peerDisconnected: onPeerDisconnected(json)
        case Cmd.transferStarted:  onTransferStarted(json)
        case Cmd.transferProgress: onTransferProgress(json)
        case Cmd.transferComplete: onTransferComplete(json)
        case Cmd.error:            onError(json)
        default:                   break
        }
    }

    // MARK: - Handlers

    private func onReady(_ data: [String: Any]) {
        guard let peerID = data["peerID"] as? String else { return }
        let downloadPath = data["downloadPath"] as? String ?? ""
        DispatchQueue.main.async {
            self.myPeerID     = peerID
            self.downloadPath = downloadPath
        }
    }

    // Full roster sync from JS. Preserves isOnline for currently live peers.
    private func onSavedPeers(_ data: [String: Any]) {
        guard let peers = data["peers"] as? [[String: Any]] else { return }
        DispatchQueue.main.async {
            self.knownDevices = peers.compactMap { self.makePeerDevice(from: $0) }
        }
    }

    private func makePeerDevice(from p: [String: Any]) -> PeerDevice? {
        guard let dk = p["discoveryKey"] as? String else { return nil }
        let name     = p["displayName"] as? String
        let platform = p["platform"]    as? String
        let isOnline = knownDevices.first(where: { $0.id == dk })?.isOnline ?? false
        return PeerDevice(
            id:           dk,
            discoveryKey: dk,
            name:         name ?? String(dk.prefix(12)) + "...",
            systemImage:  systemImage(for: platform ?? ""),
            isOnline:     isOnline,
            isOwnDevice:  dk == myPeerID
        )
    }

    private func onPeerConnected(_ data: [String: Any]) {
        guard
            let noiseKey     = data["noiseKey"]     as? String,
            let discoveryKey = data["discoveryKey"] as? String,
            let displayName  = data["displayName"]  as? String,
            let platform     = data["platform"]     as? String
        else { return }

        let isOwnDevice = data["isOwnDevice"] as? Bool ?? false

        DispatchQueue.main.async {
            self.noiseToDiscovery[noiseKey] = discoveryKey
            let device = PeerDevice(
                id:           discoveryKey,
                discoveryKey: discoveryKey,
                name:         displayName,
                systemImage:  self.systemImage(for: platform),
                isOnline:     true,
                isOwnDevice:  isOwnDevice
            )
            if let i = self.knownDevices.firstIndex(where: { $0.id == discoveryKey }) {
                self.knownDevices[i] = device
            } else {
                self.knownDevices.append(device)
            }
        }
    }

    private func onPeerDisconnected(_ data: [String: Any]) {
        guard let noiseKey = data["noiseKey"] as? String else { return }
        DispatchQueue.main.async {
            guard let dk = self.noiseToDiscovery.removeValue(forKey: noiseKey) else { return }
            if let i = self.knownDevices.firstIndex(where: { $0.id == dk }) {
                var d = self.knownDevices[i]
                d = PeerDevice(id: d.id, discoveryKey: d.discoveryKey, name: d.name,
                               systemImage: d.systemImage, isOnline: false, isOwnDevice: d.isOwnDevice)
                self.knownDevices[i] = d
            }
        }
    }

    private func onTransferStarted(_ data: [String: Any]) {
        guard
            let id        = data["transferId"] as? String,
            let peerId    = data["peerId"]     as? String,
            let fileName  = data["fileName"]   as? String,
            let fileSize  = data["fileSize"]   as? Int,
            let direction = data["direction"]  as? String
        else { return }

        let transfer = FileTransfer(
            id: id, peerId: peerId, fileName: fileName,
            fileSize: Int64(fileSize), progress: 0,
            direction: direction == "receiving" ? .receiving : .sending
        )
        DispatchQueue.main.async { self.activeTransfers.append(transfer) }
    }

    private func onTransferProgress(_ data: [String: Any]) {
        guard
            let id       = data["transferId"] as? String,
            let progress = data["progress"]   as? Double
        else { return }

        DispatchQueue.main.async {
            if let i = self.activeTransfers.firstIndex(where: { $0.id == id }) {
                self.activeTransfers[i].progress = progress
            }
        }
    }

    private func onTransferComplete(_ data: [String: Any]) {
        guard let id = data["transferId"] as? String else { return }
        DispatchQueue.main.async {
            // Show notification before removing the entry
            if let t = self.activeTransfers.first(where: { $0.id == id }) {
                self.showNotification(
                    title: t.direction == .receiving ? "File Received" : "File Sent",
                    body:  t.direction == .receiving
                        ? "\(t.fileName) saved to Downloads"
                        : "\(t.fileName) sent successfully"
                )
            }
            // Brief delay so the user sees 100% before the row disappears
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.activeTransfers.removeAll { $0.id == id }
            }
        }
    }

    private func onError(_ data: [String: Any]) {
        if let msg = data["message"] as? String { print("❌ JS error: \(msg)") }
    }
}
