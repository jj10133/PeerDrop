import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var worker: Worker

    @State private var query        = ""
    @State private var showSettings = false
    @State private var connectError: String?

    // MARK: - Derived state

    private var queryIsPeerID: Bool {
        query.count == 64 && query.allSatisfy(\.isHexDigit)
    }

    private var sortedDevices: [PeerDevice] {
        let source = query.isEmpty
            ? worker.knownDevices
            : worker.knownDevices.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.discoveryKey.localizedCaseInsensitiveContains(query)
            }
        // Online first, then alphabetical within each group
        return source.sorted {
            if $0.isOnline != $1.isOnline { return $0.isOnline }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private var onlineCount: Int {
        worker.knownDevices.filter(\.isOnline).count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollContent
        }
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            titleBar
            connectBar
            if !worker.myPublicKey.isEmpty { myIDChip }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var titleBar: some View {
        HStack {
            Text("PeerDrop").font(.system(size: 14, weight: .bold))
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gear") }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .popover(isPresented: $showSettings) {
                    SettingsView().environmentObject(worker)
                }
        }
    }

    private var connectBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: queryIsPeerID ? "personalhotspot" : "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(queryIsPeerID ? .blue : .secondary)

                TextField("Search or paste a Peer ID to connect", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { attemptConnect() }

                if queryIsPeerID {
                    Button("Connect") { attemptConnect() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(queryIsPeerID ? Color.blue.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 0.5)
            )

            if let err = connectError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var myIDChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "personalhotspot").font(.system(size: 8))
            Text("My ID: \(worker.myPublicKey.prefix(12))...")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worker.myPublicKey, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !worker.activeTransfers.isEmpty { transfersSection }
                devicesSection
                resourcesSection
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var transfersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "ACTIVE TRANSFERS").padding(.horizontal, 4)
            ForEach(worker.activeTransfers) { TransferRow(transfer: $0) }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "DEVICES").padding(.horizontal, 4)
                Spacer()
                if !worker.knownDevices.isEmpty {
                    Text("\(onlineCount) online")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            if sortedDevices.isEmpty {
                emptyDevicesPlaceholder
            } else {
                ForEach(sortedDevices) { device in
                    DeviceRow(device: device)
                        .onTapGesture {
                            DevicePanelController.show(device: device, worker: worker)
                        }
                        .contextMenu {
                            Button {
                                DevicePanelController.show(device: device, worker: worker)
                            } label: {
                                Label("Open Send Panel", systemImage: "arrow.up.circle")
                            }
                            Divider()
                            Button(role: .destructive) {
                                worker.forgetPeer(discoveryKey: device.discoveryKey)
                            } label: {
                                Label("Forget Device", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "RESOURCES").padding(.horizontal, 4)
            ActionLink(title: "Open Downloads Folder", icon: "folder") { openDownloadsFolder() }
            ActionLink(title: "Tell someone about PeerDrop", icon: "square.and.arrow.up") {}
        }
    }

    private var emptyDevicesPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text(query.isEmpty ? "No devices yet" : "No matching devices")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if query.isEmpty {
                Text("Paste a Peer ID above to connect to someone")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Actions

    private func attemptConnect() {
        guard queryIsPeerID else { return }
        connectError = nil
        worker.connectPeer(discoveryKey: query)
        query = ""
    }



    private func openDownloadsFolder() {
        let url = worker.downloadPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
                .appendingPathComponent("PeerDrop")
            : URL(fileURLWithPath: worker.downloadPath)
        NSWorkspace.shared.open(url)
    }
}
