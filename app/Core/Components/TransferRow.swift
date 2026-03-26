// TransferRow.swift — Compact transfer row shown in the main window's ACTIVE TRANSFERS section.

import SwiftUI

struct TransferRow: View {
    let transfer: FileTransfer

    private var isSending: Bool  { transfer.direction == .sending }
    private var color: Color     { isSending ? .blue : .green }

    var body: some View {
        HStack(spacing: 10) {
            directionIcon
            transferInfo
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        // Progress shown as a translucent background fill
        .overlay(progressFill)
    }

    private var directionIcon: some View {
        Image(systemName: isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
            .font(.system(size: 16))
            .foregroundColor(color)
    }

    private var transferInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(transfer.fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text("\(transfer.progressPercentage)%")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("·")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(transfer.formattedSize)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
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
