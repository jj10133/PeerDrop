import SwiftUI
import CoreImage.CIFilterBuiltins

// Cross-platform QR code view — works on macOS and iOS.
// Uses CoreImage which is available on both platforms.

struct QRCodeView: View {
    let content: String

    var body: some View {
        VStack(spacing: 12) {
            if let image = generateQRImage() {
                Image(decorative: image, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .cornerRadius(4)
            }

            Text(content.prefix(16) + "...")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func generateQRImage() -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message         = Data(content.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
