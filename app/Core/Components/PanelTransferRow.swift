// PanelTransferRow.swift — Detailed transfer row shown inside the device send panel.

import SwiftUI

struct PanelTransferRow: View {
    let transfer: FileTransfer

    private var isSending: Bool { transfer.direction == .sending }
    private var color: Color    { isSending ? .blue : .green }

    private var icon: String {
        if transfer.isDirectory {
            return isSending ? "folder.fill.badge.plus" : "folder.badge.arrow.down"
        }
        return isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topRow
            progressBar
            bottomRow
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.15), lineWidth: 0.5))
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
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
    }

    private var progressBar: some View {
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
    }

    private var bottomRow: some View {
        HStack {
            Text(transfer.subtitle)
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
}
