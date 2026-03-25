import SwiftUI
import AppKit

// MARK: - Panel host

final class DevicePanelController: NSWindowController {

    static var open: [String: DevicePanelController] = [:]

    static func show(device: PeerDevice, worker: Worker) {
        if let existing = open[device.discoveryKey] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DevicePanelController(device: device, worker: worker, mode: .send)
        open[device.discoveryKey] = controller
        controller.showWindow(nil)
    }

    static func showRename(device: PeerDevice, worker: Worker) {
        // If panel already open, bring it to front (rename accessible via panel too)
        if let existing = open[device.discoveryKey] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DevicePanelController(device: device, worker: worker, mode: .rename)
        open[device.discoveryKey] = controller
        controller.showWindow(nil)
    }

    enum Mode { case send, rename }

    private init(device: PeerDevice, worker: Worker, mode: Mode) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.title                          = device.name
        panel.titlebarAppearsTransparent     = true
        panel.isMovableByWindowBackground    = true
        panel.isFloatingPanel                = true
        panel.worksWhenModal                 = true
        panel.center()

        let view = DevicePanelView(device: device, initialMode: mode)
            .environmentObject(worker)
        panel.contentView = NSHostingView(rootView: view)

        super.init(window: panel)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object:  panel,
            queue:   .main
        ) { [weak self] _ in
            DevicePanelController.open.removeValue(forKey: device.discoveryKey)
            _ = self
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Panel content

struct DevicePanelView: View {
    let device: PeerDevice
    let initialMode: DevicePanelController.Mode

    @EnvironmentObject private var worker: Worker
    @State private var isTargeted   = false
    @State private var showRename   = false
    @State private var renameText   = ""

    private var currentDevice: PeerDevice {
        worker.knownDevices.first(where: { $0.id == device.id }) ?? device
    }

    private var peerTransfers: [FileTransfer] {
        worker.activeTransfers.filter { transfer in
            worker.noiseToDiscovery[transfer.peerId] == device.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showRename {
                renameView
            } else {
                dropZone
                if !peerTransfers.isEmpty {
                    Divider()
                    transferList
                }
            }
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if initialMode == .rename {
                renameText = currentDevice.displayName ?? ""
                showRename = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(currentDevice.isOnline ? Color.blue.opacity(0.12) : Color.primary.opacity(0.06))
                    .frame(width: 36, height: 36)
                Image(systemName: currentDevice.systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(currentDevice.isOnline ? .blue : .secondary)
                Circle()
                    .fill(currentDevice.isOnline ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(currentDevice.name)
                    .font(.system(size: 14, weight: .semibold))
                Text(currentDevice.isOnline ? "Ready to receive files" : "Offline — reconnecting…")
                    .font(.system(size: 11))
                    .foregroundColor(currentDevice.isOnline ? .secondary : .orange)
            }

            Spacer()

            // Rename button
            Button {
                renameText = currentDevice.displayName ?? ""
                showRename.toggle()
            } label: {
                Image(systemName: showRename ? "xmark.circle" : "pencil")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(showRename ? "Cancel rename" : "Rename peer")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    // MARK: - Rename

    private var renameView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Label this peer")
                    .font(.system(size: 12, weight: .medium))
                Text("Give this peer a memorable name. This is only visible to you.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("e.g. My iPhone, Alice's Mac…", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(9)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                .onSubmit { saveRename() }

            HStack(spacing: 10) {
                Button("Cancel") {
                    showRename = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

                Spacer()

                if currentDevice.displayName != nil {
                    Button("Clear label") {
                        renameText = ""
                        saveRename()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }

                Button("Save") { saveRename() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(16)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.blue : Color.primary.opacity(0.15),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.blue.opacity(0.06) : Color.primary.opacity(0.02))
                )
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 36))
                    .foregroundColor(isTargeted ? .blue : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)
                Text(currentDevice.isOnline ? "Drop files here to send" : "Peer is offline")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isTargeted ? .blue : .secondary)
                if currentDevice.isOnline {
                    Text("Supports any file type or folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding(16)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard currentDevice.isOnline else { return false }
            return handleDrop(providers)
        }
    }

    // MARK: - Transfer list

    private var transferList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRANSFERS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(peerTransfers) { PanelTransferRow(transfer: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: - Actions

    private func saveRename() {
        worker.renamePeer(discoveryKey: device.id, displayName: renameText.trimmingCharacters(in: .whitespaces))
        showRename = false
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { urlData, _ in
                guard
                    let data = urlData as? Data,
                    let url  = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                DispatchQueue.main.async {
                    worker.sendFile(at: url, to: device.id)
                }
            }
        }
        return true
    }
}

// MARK: - Transfer row

struct PanelTransferRow: View {
    let transfer: FileTransfer

    private var isSending: Bool { transfer.direction == .sending }
    private var color: Color { isSending ? .blue : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(transfer.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(transfer.progressPercentage)%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * transfer.progress, height: 5)
                        .animation(.easeInOut(duration: 0.2), value: transfer.progress)
                }
            }
            .frame(height: 5)
            HStack {
                Text(transfer.formattedSize)
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                if transfer.isComplete {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundColor(.green)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.15), lineWidth: 0.5))
    }
}
