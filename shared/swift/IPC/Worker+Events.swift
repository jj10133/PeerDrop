import BareRPC
import Foundation

extension Worker {

    func setupEventHandlers() {
        bridge.rpc.onEvent   = { [weak self] event in await self?.handleEvent(event) }
        bridge.rpc.onRequest = { req in req.reply(nil) }
        bridge.rpc.onError   = { error in print("❌ RPC: \(error)") }
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
        let dl = data["downloadPath"] as? String ?? ""
        DispatchQueue.main.async {
            self.myPeerID     = peerID
            self.downloadPath = dl
        }
    }

    private func onSavedPeers(_ data: [String: Any]) {
        guard let peers = data["peers"] as? [[String: Any]] else { return }
        DispatchQueue.main.async {
            self.knownDevices = peers.compactMap { p in
                guard let dk = p["discoveryKey"] as? String else { return nil }
                let name     = p["displayName"] as? String
                let platform = p["platform"]    as? String
                let isOnline    = self.knownDevices.first(where: { $0.id == dk })?.isOnline ?? false
                let isOwnDevice = dk == self.myPeerID
                return PeerDevice(
                    id:           dk,
                    discoveryKey: dk,
                    name:         name ?? String(dk.prefix(12)) + "...",
                    systemImage:  self.systemImage(for: platform ?? ""),
                    isOnline:     isOnline,
                    isOwnDevice:  isOwnDevice
                )
            }
            self.syncPeersToAppGroup()  // ← keep extension in sync
        }
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
            let updated = PeerDevice(
                id:           discoveryKey,
                discoveryKey: discoveryKey,
                name:         displayName,
                systemImage:  self.systemImage(for: platform),
                isOnline:     true,
                isOwnDevice:  isOwnDevice
            )
            if let i = self.knownDevices.firstIndex(where: { $0.id == discoveryKey }) {
                self.knownDevices[i] = updated
            } else {
                self.knownDevices.append(updated)
            }
            self.syncPeersToAppGroup()  // ← keep extension in sync
        }
    }

    private func onPeerDisconnected(_ data: [String: Any]) {
        guard let noiseKey = data["noiseKey"] as? String else { return }
        DispatchQueue.main.async {
            guard let dk = self.noiseToDiscovery.removeValue(forKey: noiseKey) else { return }
            if let i = self.knownDevices.firstIndex(where: { $0.id == dk }) {
                let d = self.knownDevices[i]
                self.knownDevices[i] = PeerDevice(
                    id:           d.id,
                    discoveryKey: d.discoveryKey,
                    name:         d.name,
                    systemImage:  d.systemImage,
                    isOnline:     false,
                    isOwnDevice:  d.isOwnDevice
                )
            }
            self.syncPeersToAppGroup()  // ← keep extension in sync
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
        DispatchQueue.main.async {
            self.activeTransfers.append(FileTransfer(
                id: id, peerId: peerId, fileName: fileName,
                fileSize: Int64(fileSize), progress: 0,
                direction: direction == "receiving" ? .receiving : .sending
            ))
        }
    }

    private func onTransferProgress(_ data: [String: Any]) {
        guard
            let id       = data["transferId"] as? String,
            let progress = data["progress"]   as? Double
        else { return }
        DispatchQueue.main.async {
            if let i = self.activeTransfers.firstIndex(where: { $0.id == id }) {
                var t = self.activeTransfers[i]; t.progress = progress
                self.activeTransfers[i] = t
            }
        }
    }

    private func onTransferComplete(_ data: [String: Any]) {
        guard let id = data["transferId"] as? String else { return }
        DispatchQueue.main.async {
            if let t = self.activeTransfers.first(where: { $0.id == id }) {
                self.showNotification(
                    title: t.direction == .receiving ? "File Received" : "File Sent",
                    body:  t.direction == .receiving
                        ? "\(t.fileName) saved to downloads folder"
                        : "\(t.fileName) sent successfully"
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.activeTransfers.removeAll { $0.id == id }
            }
        }
    }

    private func onError(_ data: [String: Any]) {
        if let msg = data["message"] as? String { print("❌ JS: \(msg)") }
    }
}
