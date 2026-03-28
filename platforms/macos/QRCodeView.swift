//
//  QRCodeView.swift
//  App
//
//  Created by Janardhan on 2026-03-25.
//


import SwiftUI
import CoreImage.CIFilterBuiltins

// Renders a QR code for the given string using CoreImage.
// No external dependencies — CIFilter.qrCodeGenerator() is built into macOS.

struct QRCodeView: View {
    let string: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Scan to Connect")
                .font(.system(size: 12, weight: .semibold))

            if let image = generateQRImage() {
                Image(nsImage: image)
                    .interpolation(.none)   // keep pixels crisp, no blur
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .cornerRadius(4)
            }

            Text(string.prefix(16) + "...")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(16)
    }

    // MARK: - Private

    private func generateQRImage() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message         = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        // Scale up 8× so the image renders sharply at display size
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))

        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: scaled.extent.size)
    }
}