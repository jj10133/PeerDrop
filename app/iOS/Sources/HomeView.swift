// HomeView.swift — iOS device list (MY DEVICES + PEOPLE)

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var worker: Worker
    @State private var showAddContact = false
    @State private var selectedPeer: PeerDevice?

    var body: some View {
        NavigationStack {
            Group {
                if worker.knownDevices.isEmpty {
                    emptyState
                } else {
                    List {
                        if !worker.myDevices.isEmpty {
                            Section("MY DEVICES") {
                                ForEach(worker.myDevices) { device in
                                    deviceRow(device)
                                }
                            }
                        }
                        if !worker.contacts.isEmpty {
                            Section("PEOPLE") {
                                ForEach(worker.contacts) { device in
                                    deviceRow(device)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("PeerDrop")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddContact = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showAddContact) {
                AddContactView()
                    .environmentObject(worker)
            }
            .navigationDestination(for: PeerDevice.self) { peer in
                DeviceDetailView(peer: peer)
            }
//            .navigationDestination(item: $selectedPeer) { peer in
//                DeviceDetailView(peer: peer)
//                    .environmentObject(worker)
//            }
        }
    }

    @ViewBuilder
    func deviceRow(_ device: PeerDevice) -> some View {
        Button {
            selectedPeer = device
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(device.isOnline
                              ? Color.accentColor.opacity(0.12)
                              : Color(.systemGray5))
                        .frame(width: 44, height: 44)
                    Image(systemName: device.systemImage)
                        .font(.system(size: 20))
                        .foregroundStyle(device.isOnline ? .secondary : .tertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(device.isOnline ? "Available" : "Offline")
                        .font(.caption)
                        .foregroundStyle(device.isOnline ? Color.green : .secondary)
                }

                Spacer()

                if device.isOnline {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("No contacts yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add someone's Peer ID to start\nsending files directly to them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAddContact = true
            } label: {
                Label("Add Contact", systemImage: "person.badge.plus")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Add Contact

struct AddContactView: View {
    @EnvironmentObject var worker: Worker
    @Environment(\.dismiss) private var dismiss
    @State private var peerID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Peer ID (64 hex characters)", text: $peerID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Enter Peer ID")
                } footer: {
                    Text("Ask the other person to share their Peer ID from PeerDrop Settings.")
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        worker.connectPeer(peerID: peerID.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(peerID.trimmingCharacters(in: .whitespaces).count != 64)
                }
            }
        }
    }
}
