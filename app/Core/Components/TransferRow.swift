// TransferRow.swift — Compact transfer row in the main window's ACTIVE TRANSFERS section.

import SwiftUI

struct TransferRow: View {
    let transfer: FileTransfer

    private var isSending: Bool { transfer.direction == .sending }
    private var color: Color    { isSending ? .blue : .green }

    private var icon: String {
        if transfer.isDirectory {
            return isSending ? "folder.fill.badge.plus" : "arrow.down.doc.fill"
        }
        return isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(transfer.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .overlay(progressFill)
    }

    private var progressFill: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(color.opacity(0.08))
                .frame(width: geo.size.width * transfer.progress)
                .animation(.easeInOut(duration: 0.2), value: transfer.progress)
        }
        .cornerRadius(10)
        .allowsHitTesting(false)
    }
}
