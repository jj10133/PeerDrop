import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var worker: Worker
    @Environment(\.dismiss) private var dismiss

    @State private var showQR = false

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identitySection
                    Divider()
                    multiDeviceSection
                    Divider()
                    downloadsSection
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 540)
    }

    // MARK: - Sections

    private var settingsHeader: some View {
        HStack {
            Text("Settings").font(.system(size: 16, weight: .bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Identity", systemImage: "personalhotspot")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Peer ID")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Share this with others so they can connect to you.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                HStack {
                    Text(worker.myPublicKey)
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
    }

    private var multiDeviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Multi-Device", systemImage: "apps.iphone")
                .font(.system(size: 13, weight: .semibold))

            Text("To use the same identity on another device, copy your seed file to the same path on that device.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack {
                Text("~/.peerdrop/seed")
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Reveal in Finder") { revealSeedFile() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
            }
            .padding(8)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(6)
        }
    }

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Downloads", systemImage: "arrow.down.circle")
                .font(.system(size: 13, weight: .semibold))

            Text("Received files are saved here. You can change this to any folder you like.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            downloadPathRow
            downloadActionRow
        }
    }

    private var downloadPathRow: some View {
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
    }

    private var downloadActionRow: some View {
        HStack {
            Button("Change Folder…") { chooseDownloadFolder() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)
            Spacer()
            Button("Open") { openDownloadFolder() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Small button views

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worker.myPublicKey, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help("Copy Peer ID")
    }

    private var qrButton: some View {
        Button { showQR = true } label: {
            Image(systemName: "qrcode").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help("Show QR Code")
        .popover(isPresented: $showQR, arrowEdge: .trailing) {
            if !worker.myPublicKey.isEmpty {
                QRCodeView(string: worker.myPublicKey)
            }
        }
    }

    // MARK: - Computed

    private var displayDownloadPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p    = worker.downloadPath.isEmpty ? (home + "/Downloads/PeerDrop") : worker.downloadPath
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}

// MARK: - Actions extension

extension SettingsView {

    func revealSeedFile() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".peerdrop")
            .appendingPathComponent("seed")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openDownloadFolder() {
        let url = worker.downloadPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
                .appendingPathComponent("PeerDrop")
            : URL(fileURLWithPath: worker.downloadPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func chooseDownloadFolder() {
        // Must use runModal() — SettingsView is a popover and has no NSWindow
        // to attach a sheet to, so beginSheetModal silently does nothing.
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
