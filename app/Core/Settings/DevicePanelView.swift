// DevicePanelView.swift — Content of the floating send panel.
//
// Bug fixed: was capturing `device` at construction time so `isOnline`
// was always stale. Now reads the live version from worker.knownDevices.

import SwiftUI

struct DevicePanelView: View {
    let deviceID: String                  // discoveryKey — stable reference
    @EnvironmentObject private var worker: Worker
    @State private var isTargeted = false

    // Always reflects the current live state from Worker
    private var device: PeerDevice? {
        worker.knownDevices.first(where: { $0.id == deviceID })
    }

    // Transfers for this peer: noiseKey → discoveryKey via noiseToDiscovery
    private var peerTransfers: [FileTransfer] {
        worker.activeTransfers.filter { t in
            worker.noiseToDiscovery[t.peerId] == deviceID
        }
    }

    var body: some View {
        Group {
            if let device = device {
                VStack(spacing: 0) {
                    panelHeader(device: device)
                    Divider()
                    // When transfers are active, show them inside the drop zone
                    // so the user sees progress immediately where they dropped.
                    // The zone returns to its idle state once all transfers finish.
                    if peerTransfers.isEmpty {
                        dropZone(device: device)
                    } else {
                        activeTransferZone(device: device)
                    }
                }
            } else {
                // Device was removed while the panel was open
                Text("Device no longer available")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private func panelHeader(device: PeerDevice) -> some View {
        HStack(spacing: 10) {
            onlineIndicator(device: device, size: 36, iconSize: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 14, weight: .semibold))
                Text(device.isOnline ? "Ready to receive files" : "Offline — reconnecting…")
                    .font(.system(size: 11))
                    .foregroundColor(device.isOnline ? .secondary : .orange)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    // MARK: - Drop zone

    private func dropZone(device: PeerDevice) -> some View {
        ZStack {
            dropZoneBackground
            dropZoneContent(device: device)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding(16)
        .onDrop(of: [.fileURL, .folder], isTargeted: $isTargeted) { providers in
            guard device.isOnline else { return false }
            return handleDrop(providers)
        }
    }

    private var dropZoneBackground: some View {
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
    }

    private func dropZoneContent(device: PeerDevice) -> some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 36))
                .foregroundColor(isTargeted ? .blue : .secondary)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            Text(device.isOnline ? "Drop files here to send" : "Peer is offline")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isTargeted ? .blue : .secondary)

            if device.isOnline {
                Text("Drop any file or folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    // MARK: - Active transfer zone (replaces drop zone while transfers are in progress)

    private func activeTransferZone(device: PeerDevice) -> some View {
        VStack(spacing: 0) {
            // Compact drop target still visible so user can queue more files
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 16))
                    .foregroundColor(isTargeted ? .blue : .secondary)
                Text(device.isOnline ? "Drop more files to queue" : "Peer is offline")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isTargeted ? Color.blue.opacity(0.06) : Color.primary.opacity(0.02))
            .onDrop(of: [.fileURL, .folder], isTargeted: $isTargeted) { providers in
                guard device.isOnline else { return false }
                return handleDrop(providers)
            }

            Divider()

            // Transfer rows — directly visible, no scrolling needed for short lists
            VStack(spacing: 8) {
                ForEach(peerTransfers) { PanelTransferRow(transfer: $0) }
            }
            .padding(16)
        }
    }

    // MARK: - Transfer list (kept for reference, no longer used in body)

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

    // MARK: - Shared sub-view

    private func onlineIndicator(device: PeerDevice, size: CGFloat, iconSize: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(device.isOnline ? Color.blue.opacity(0.12) : Color.primary.opacity(0.06))
                .frame(width: size, height: size)
            Image(systemName: device.systemImage)
                .font(.system(size: iconSize))
                .foregroundColor(device.isOnline ? .blue : .secondary)
            Circle()
                .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }

    // MARK: - Drop handler

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url  = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                DispatchQueue.main.async { self.worker.sendFile(at: url, to: self.deviceID) }
            }
        }
        return true
    }
}
