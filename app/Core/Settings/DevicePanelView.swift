// MARK: - Panel content view

struct DevicePanelView: View {
    let device: PeerDevice
    @EnvironmentObject private var worker: Worker
    @State private var isTargeted = false

    // Transfers for this specific peer only
    // peerId in FileTransfer is the noiseKey — map via worker.noiseToDiscovery
    private var peerTransfers: [FileTransfer] {
        worker.activeTransfers.filter { transfer in
            let dk = worker.noiseToDiscovery[transfer.peerId]
            return dk == device.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dropZone
            if !peerTransfers.isEmpty {
                Divider()
                transferList
            }
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
