// SettingsView.swift — Identity display, device adding instructions, downloads config.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var worker: Worker
    @Environment(\.dismiss) private var dismiss

    @State private var showPeerIDQR = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identitySection
                    Divider()
                    downloadsSection
                }
                .padding(16)
            }
            .background(Color(NSColor.windowBackgroundColor))

        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings").font(.system(size: 16, weight: .bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Identity", systemImage: "personalhotspot")
                .font(.system(size: 13, weight: .semibold))

            Text("Share your Peer ID with others so they can send you files. It's the same across all your devices.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            HStack {
                Text(worker.myPeerID)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                copyButton
                qrButton
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worker.myPeerID, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help("Copy Peer ID")
    }

    private var qrButton: some View {
        Button { showPeerIDQR = true } label: {
            Image(systemName: "qrcode").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help("Show QR Code")
        .popover(isPresented: $showPeerIDQR, arrowEdge: .trailing) {
            if !worker.myPeerID.isEmpty {
                QRCodeView(content: "peerdrop://connect?id=\(worker.myPeerID)")
            }
        }
    }

    private func stepRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Downloads", systemImage: "arrow.down.circle")
                .font(.system(size: 13, weight: .semibold))

            Text("Received files are saved here.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text(displayDownloadPath)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            HStack {
                Button("Change Folder") { chooseDownloadFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Computed

    private var displayDownloadPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p    = worker.downloadPath.isEmpty
            ? home + "/Downloads/PeerDrop"
            : worker.downloadPath
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}

// MARK: - Actions

extension SettingsView {

    private func revealSeedInFinder() {
        let seed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".peerdrop/seed")
        NSWorkspace.shared.activateFileViewerSelecting([seed])
    }

    private func openDownloadFolder() {
        let url = worker.downloadPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/PeerDrop")
            : URL(fileURLWithPath: worker.downloadPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func chooseDownloadFolder() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles          = false
            panel.canChooseDirectories    = true
            panel.canCreateDirectories    = true
            panel.allowsMultipleSelection = false
            panel.prompt                  = "Choose"
            panel.message                 = "Select a folder for received files"
            if panel.runModal() == .OK, let url = panel.url {
                worker.setDownloadPath(url.path)
            }
        }
    }
}

#Preview {
    SettingsView().environmentObject(Worker())
}
