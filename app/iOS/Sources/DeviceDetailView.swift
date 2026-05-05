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
        ScrollView {
            VStack(spacing: 24) {

                // ── Device card ───────────────────────────────────────────
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(peer.isOnline
                                  ? Color.accentColor.opacity(0.1)
                                  : Color(.systemGray5))
                            .frame(width: 80, height: 80)
                        Image(systemName: peer.systemImage)
                            .font(.system(size: 36))
                            .foregroundStyle(peer.isOnline ? Color.accentColor : .secondary)
                    }

                    Text(peer.name)
                        .font(.title2).fontWeight(.bold)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(peer.isOnline ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(peer.isOnline ? "Available" : "Offline")
                            .font(.subheadline)
                            .foregroundStyle(peer.isOnline ? Color.green : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)

                // ── Send button ───────────────────────────────────────────
                if peer.isOnline {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                            Text("Send Files")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                        Text("Peer is offline — transfers will start when they reconnect")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // ── Active transfers ──────────────────────────────────────
                if !transfers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACTIVE TRANSFERS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(transfers) { transfer in
                                TransferRowiOS(transfer: transfer)
                                    .padding(14)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(peer.name)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handlePickedFiles(result)
        }
    }

    private func handlePickedFiles(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get() else { return }
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: url, to: tmp)
                worker.sendFile(at: tmp, to: peer.discoveryKey)
            } catch {
                print("❌ Failed to copy file: \(error)")
            }
        }
    }
}

// MARK: - Transfer row

struct TransferRowiOS: View {
    let transfer: FileTransfer

    var isSending: Bool { transfer.direction == .sending }
    var tint: Color { isSending ? .blue : .green }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(transfer.fileName)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)

                ProgressView(value: transfer.progress)
                    .tint(tint)

                Text(transfer.progress >= 1.0
                     ? "Complete ✓"
                     : "\(Int(transfer.progress * 100))%  ·  \(transfer.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(transfer.progress >= 1.0 ? tint : .secondary)
            }
        }
    }
}
