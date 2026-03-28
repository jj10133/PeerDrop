// ContentView.swift — Root view for the menu-bar popover.
// Displays own devices, contacts, active transfers, and the connect bar.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var worker: Worker

    @State private var query        = ""
    @State private var showSettings = false
    @State private var connectError: String?

    // A valid Peer ID is exactly 64 hex chars
    private var queryIsPeerID: Bool {
        query.count == 64 && query.allSatisfy(\.isHexDigit)
    }

    // Only filter contacts — own devices are always shown unfiltered
    private var filteredContacts: [PeerDevice] {
        let source = query.isEmpty
            ? worker.contacts
            : worker.contacts.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.discoveryKey.localizedCaseInsensitiveContains(query)
              }
        return source.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private var sortedOwnDevices: [PeerDevice] {
        worker.myDevices.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            mainList
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            titleBar
            connectBar
        }
        .padding(16)
    }

    private var titleBar: some View {
        HStack {
            Text("PeerDrop")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gear")
            }
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
                Image(systemName: queryIsPeerID ? "person.badge.plus" : "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(queryIsPeerID ? .blue : .secondary)

                TextField("Paste someone's Peer ID to connect", text: $query)
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
                    .stroke(queryIsPeerID ? Color.blue.opacity(0.4) : Color.primary.opacity(0.1),
                            lineWidth: 0.5)
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

    // MARK: - Main list

    private var mainList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !worker.activeTransfers.isEmpty {
                    transfersSection
                }
                
                peopleSection
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sections

    private var transfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "ACTIVE TRANSFERS").padding(.horizontal, 4)
            ForEach(worker.activeTransfers) { TransferRow(transfer: $0) }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "PEOPLE").padding(.horizontal, 4)
                Spacer()
                if !worker.contacts.isEmpty {
                    let onlineCount = worker.contacts.filter(\.isOnline).count
                    Text("\(onlineCount) online")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }

            if filteredContacts.isEmpty {
                emptyContactsPlaceholder
            } else {
                ForEach(filteredContacts) { device in
                    DeviceRow(device: device)
                        .onTapGesture { DevicePanelController.show(device: device, worker: worker) }
                        .contextMenu { peerContextMenu(for: device) }
                }
            }
        }
    }

    private var emptyContactsPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.slash")
                .font(.system(size: 24)).foregroundColor(.secondary)
            Text(query.isEmpty ? "No contacts yet" : "No matching contacts")
                .font(.system(size: 12)).foregroundColor(.secondary)
            if query.isEmpty {
                Text("Paste someone's Peer ID above to connect")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func peerContextMenu(for device: PeerDevice) -> some View {
        Button {
            DevicePanelController.show(device: device, worker: worker)
        } label: {
            Label("Send Files…", systemImage: "arrow.up.circle")
        }
        Divider()
        Button(role: .destructive) {
            worker.forgetPeer(discoveryKey: device.id)
        } label: {
            Label(device.isOwnDevice ? "Remove This Device" : "Remove Contact",
                  systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func attemptConnect() {
        guard queryIsPeerID else { return }
        connectError = nil
        worker.connectPeer(peerID: query)
        query = ""
    }
}
