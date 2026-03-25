import SwiftUI
import AppKit

struct DeviceRow: View {
    let device: PeerDevice

    var body: some View {
        HStack(spacing: 12) {
            deviceIcon
            deviceInfo
            Spacer()
            if device.isOnline { dropHint }
        }
        .padding(10)
        .background(device.isOnline ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(device.isOnline ? Color.blue.opacity(0.2) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .opacity(device.isOnline ? 1.0 : 0.6)
    }

    // MARK: - Sub-views

    private var deviceIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(device.isOnline ? Color.blue.opacity(0.12) : Color.primary.opacity(0.06))
                .frame(width: 34, height: 34)

            Image(systemName: device.systemImage)
                .font(.system(size: 14))
                .foregroundColor(device.isOnline ? .blue : .secondary)

            Circle()
                .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }

    private var deviceInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(device.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(device.isOnline ? .primary : .secondary)

            Text(device.statusLabel)
                .font(.system(size: 11))
                .foregroundColor(device.isOnline ? .green : .secondary)
        }
    }

    private var dropHint: some View {
        Image(systemName: "arrow.up.circle")
            .font(.system(size: 13))
            .foregroundColor(.secondary.opacity(0.4))
            .help("Click to open send panel")
    }
}
