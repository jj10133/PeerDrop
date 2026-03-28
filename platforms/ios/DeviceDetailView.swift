// DeviceDetailView.swift — tap a device, send files, see transfers

import SwiftUI
import UniformTypeIdentifiers

struct DeviceDetailView: View {
    let peer: PeerDevice
    @EnvironmentObject var worker: Worker
    @State private var showFilePicker = false

    var transfers: [FileTransfer] {
        worker.activeTransfers.filter {
            worker.noiseToDiscovery.values.contains(peer.discoveryKey) ||
            $0.peerId == peer.discoveryKey
        }
    }

    var body: some View {
        List {

            // ── Device header ─────────────────────────────────────────────
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(peer.isOnline
                                  ? Color.accentColor.opacity(0.12)
                                  : Color(.systemGray5))
                            .frame(width: 60, height: 60)
                        Image(systemName: peer.systemImage)
                            .font(.system(size: 28))
                            .foregroundStyle(peer.isOnline ? .accent : .tertiary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(peer.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(peer.isOnline ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(peer.isOnline ? "Available" : "Offline")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // ── Send button ───────────────────────────────────────────────
            if peer.isOnline {
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Send a File")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fontWeight(.medium)
                    }
                }
            }

            // ── Active transfers ──────────────────────────────────────────
            if !transfers.isEmpty {
                Section("TRANSFERS") {
                    ForEach(transfers) { transfer in
                        TransferRowiOS(transfer: transfer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(peer.name)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            worker.sendFile(at: url, to: peer.discoveryKey)
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
    }
}

// MARK: - Transfer row for iOS

struct TransferRowiOS: View {
    let transfer: FileTransfer

    var icon: String {
        transfer.direction == .sending ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }
    var tint: Color {
        transfer.direction == .sending ? .blue : .green
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if transfer.progress < 1.0 {
                    ProgressView(value: transfer.progress)
                        .tint(tint)
                    Text("\(Int(transfer.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
