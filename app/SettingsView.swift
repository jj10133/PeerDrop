import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var worker: Worker
    @Environment(\.dismiss) private var dismiss

    @State private var showQR        = false
    @State private var showInviteQR  = false
    @State private var inviteURL     = ""
    @State private var isGenerating  = false
    @State private var inviteInput   = ""
    @State private var isPairing     = false
    @State private var pairingDone   = false
    @State private var pairingError: String?

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identitySection
                    Divider()
                    addDeviceSection
                    Divider()
                    downloadsSection
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 580)
        .onChange(of: worker.myPeerID) { newID in
            // Fires when JS emits CMD_PAIRING_COMPLETE and Worker updates myPeerID
            if isPairing && !newID.isEmpty {
                isPairing   = false
                pairingDone = true
                inviteInput = ""
            }
        }
    }

    // MARK: - Header

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

    // MARK: - Identity section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Identity", systemImage: "personalhotspot")
                .font(.system(size: 13, weight: .semibold))

            Text("Share your Peer ID with others so they can send you files. It's the same across all your devices.")
                .font(.system(size: 10)).foregroundColor(.secondary)

            HStack {
                Text(worker.myPeerID)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(worker.myPeerID, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundColor(.secondary).help("Copy Peer ID")

                Button { showQR = true } label: {
                    Image(systemName: "qrcode").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundColor(.secondary).help("Show QR Code")
                .popover(isPresented: $showQR, arrowEdge: .trailing) {
                    if !worker.myPeerID.isEmpty { QRCodeView(string: worker.myPeerID) }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
    }

    // MARK: - Add device section
    //
    // Device A side: generates a one-time pear://peerdrop/ invite URL → shown as QR.
    // Device B side: pastes the URL → JS starts the pairing handshake.
    //
    // The mnemonic never leaves Device A. Device B receives only its own
    // fresh device keypair + an attestation proof linking it to the identity.

    private var addDeviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add Your Device", systemImage: "plus.square.on.square")
                .font(.system(size: 13, weight: .semibold))

            // ── Device A: show pairing QR ─────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("On this device, generate a QR code and scan it on your other device.")
                    .font(.system(size: 11)).foregroundColor(.secondary)

                if showInviteQR && !inviteURL.isEmpty {
                    inviteQRView
                } else {
                    generateButton
                }
            }

            Divider().padding(.vertical, 2)

            // ── Device B: paste invite URL ────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("On the other device, paste the invite URL shown on your existing device.")
                    .font(.system(size: 11)).foregroundColor(.secondary)

                if pairingDone {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paired successfully!")
                                .font(.system(size: 11, weight: .medium))
                            Text("This device now shares your identity.")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
                } else {
                    pasteField

                    if let err = pairingError {
                        Text(err).font(.system(size: 10)).foregroundColor(.red)
                    }

                    pairButton
                }
            }
        }
    }

    private var generateButton: some View {
        Button { generateInvite() } label: {
            HStack(spacing: 8) {
                if isGenerating { ProgressView().scaleEffect(0.7) }
                else { Image(systemName: "qrcode.viewfinder").font(.system(size: 13)) }
                Text(isGenerating ? "Generating…" : "Show Pairing QR")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(Color.blue.opacity(0.1)).cornerRadius(8).foregroundColor(.blue)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || worker.myPeerID.isEmpty)
    }

    private var inviteQRView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Scan on your other device").font(.system(size: 11, weight: .medium))
                Spacer()
                // Copy the invite URL — useful on Mac where scanning isn't an option
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(inviteURL, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundColor(.blue)

                Button("Done") { showInviteQR = false; inviteURL = "" }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.leading, 8)
            }
            QRCodeView(string: inviteURL)
            Text("One-time use. Generate a new one for each device.")
                .font(.system(size: 9)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var pasteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.system(size: 11)).foregroundColor(.secondary)
            TextField("pear://peerdrop/…", text: $inviteInput)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .truncationMode(.middle)
            if !inviteInput.isEmpty {
                Button {
                    inviteInput  = ""
                    pairingError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(Color.primary.opacity(0.04)).cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(inviteInput.hasPrefix("pear://peerdrop/")
                    ? Color.blue.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var pairButton: some View {
        Button { acceptInvite() } label: {
            HStack(spacing: 6) {
                if isPairing { ProgressView().scaleEffect(0.7) }
                else { Image(systemName: "personalhotspot").font(.system(size: 11)) }
                Text(isPairing ? "Connecting…" : "Pair This Device")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(inviteInput.hasPrefix("pear://peerdrop/")
                ? Color.blue.opacity(0.1) : Color.primary.opacity(0.04))
            .cornerRadius(8)
            .foregroundColor(inviteInput.hasPrefix("pear://peerdrop/") ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!inviteInput.hasPrefix("pear://peerdrop/") || isPairing)
    }

    // MARK: - Downloads section

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Downloads", systemImage: "arrow.down.circle")
                .font(.system(size: 13, weight: .semibold))

            Text("Received files are saved here.")
                .font(.system(size: 11)).foregroundColor(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundColor(.blue)
                Text(displayDownloadPath)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2).truncationMode(.middle)
                Spacer()
            }
            .padding(10).background(Color.primary.opacity(0.04)).cornerRadius(8)

            HStack {
                Button("Change Folder…") { chooseDownloadFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.blue)
                Spacer()
                Button("Open") { openDownloadFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundColor(.secondary)
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

// MARK: - Actions

extension SettingsView {

    func generateInvite() {
        isGenerating = true
        Task {
            do {
                let url = try await worker.generatePairingInvite()
                await MainActor.run {
                    inviteURL    = url
                    showInviteQR = true
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    print("❌ generateInvite: \(error)")
                }
            }
        }
    }

    func acceptInvite() {
        guard inviteInput.hasPrefix("pear://peerdrop/") else { return }
        isPairing    = true
        pairingError = nil
        // Pass the raw URL string — JS decodes it
        worker.acceptPairingInvite(url: inviteInput)
        // Timeout after 10s if pairing never completes
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if isPairing {
                await MainActor.run {
                    isPairing    = false
                    pairingError = "Timed out. Make sure the other device is open and the QR is still valid."
                }
            }
        }
    }

    func openDownloadFolder() {
        let url = worker.downloadPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads").appendingPathComponent("PeerDrop")
            : URL(fileURLWithPath: worker.downloadPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func chooseDownloadFolder() {
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
