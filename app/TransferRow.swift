//
//  TransferRow.swift
//  App
//
//  Created by Janardhan on 2026-03-25.
//


import SwiftUI

struct TransferRow: View {
    let transfer: FileTransfer

    private var isSending: Bool { transfer.direction == .sending }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(isSending ? .blue : .green)

            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(transfer.progressPercentage)%")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(transfer.formattedSize)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .overlay(progressBar)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(isSending ? Color.blue.opacity(0.08) : Color.green.opacity(0.08))
                .frame(width: geo.size.width * transfer.progress)
        }
        .cornerRadius(10)
        .allowsHitTesting(false)
    }
}