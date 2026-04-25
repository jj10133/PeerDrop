// TransferListView.swift — all active transfers tab

import SwiftUI

struct TransferListView: View {
    @EnvironmentObject var worker: Worker

    var body: some View {
        NavigationStack {
            Group {
                if worker.activeTransfers.isEmpty {
                    emptyState
                } else {
                    List(worker.activeTransfers) { transfer in
                        transferRow(transfer)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Transfers")
        }
    }

    @ViewBuilder
    func transferRow(_ transfer: FileTransfer) -> some View {
        HStack(spacing: 14) {
            Image(systemName: transfer.direction == .sending
                  ? "arrow.up.circle.fill"
                  : "arrow.down.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(transfer.direction == .sending ? .blue : .green)

            VStack(alignment: .leading, spacing: 6) {
                Text(transfer.fileName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(peerName(for: transfer.peerId))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: transfer.progress)
                    .tint(transfer.direction == .sending ? .blue : .green)

                Text("\(Int(transfer.progress * 100))%  ·  \(formattedSize(transfer.fileSize))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("No active transfers")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Transfers will appear here\nwhile they're in progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func peerName(for peerId: String) -> String {
        worker.knownDevices.first { $0.discoveryKey == peerId }?.name ?? peerId
    }

    func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
