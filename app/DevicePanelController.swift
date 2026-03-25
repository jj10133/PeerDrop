//
//  DevicePanelController.swift
//  App
//
//  Created by Janardhan on 2026-03-25.
//


import SwiftUI
import AppKit

// MARK: - Panel host
// Opens a floating NSPanel for a specific device.
// NSPanel (rather than a sheet/popover) is required so the window:
//   • stays visible when the user switches to Finder to drag files
//   • accepts drag-and-drop while another app is frontmost

final class DevicePanelController: NSWindowController {

    static var open: [String: DevicePanelController] = [:]  // discoveryKey → controller

    static func show(device: PeerDevice, worker: Worker) {
        if let existing = open[device.discoveryKey] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DevicePanelController(device: device, worker: worker)
        open[device.discoveryKey] = controller
        controller.showWindow(nil)
    }

    private init(device: PeerDevice, worker: Worker) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.title                   = device.name
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel         = true   // stays above Finder
        panel.worksWhenModal          = true
        panel.center()

        let view = DevicePanelView(device: device)
            .environmentObject(worker)
        panel.contentView = NSHostingView(rootView: view)

        super.init(window: panel)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            DevicePanelController.open.removeValue(forKey: device.discoveryKey)
            _ = self  // retain until closed
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Panel content view

struct DevicePanelView: View {
    let device: PeerDevice
    @EnvironmentObject private var worker: Worker
    @State private var isTargeted = false

    // Transfers for this specific peer only
    private var peerTransfers: [FileTransfer] {
        worker.activeTransfers.filter { $0.peerId == device.discoveryKey }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(device.isOnline ? Color.blue.opacity(0.12) : Color.primary.opacity(0.06))
                    .frame(width: 36, height: 36)
                Image(systemName: device.systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(device.isOnline ? .blue : .secondary)
                Circle()
                    .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }

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

                Text(device.isOnline ? "Drop files here to send" : "Peer is offline")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isTargeted ? .blue : .secondary)

                if device.isOnline {
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
            guard device.isOnline else { return false }
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
                    ForEach(peerTransfers) { transfer in
                        PanelTransferRow(transfer: transfer)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: - Drop handler

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { urlData, _ in
                guard
                    let data = urlData as? Data,
                    let url  = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                DispatchQueue.main.async {
                    worker.sendFile(at: url, to: device.discoveryKey)
                }
            }
        }
        return true
    }
}

// MARK: - Transfer row for the panel

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

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * transfer.progress, height: 5)
                        .animation(.easeInOut(duration: 0.2), value: transfer.progress)
                }
            }
            .frame(height: 5)

            HStack {
                Text(transfer.formattedSize)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                if transfer.isComplete {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.15), lineWidth: 0.5))
    }
}