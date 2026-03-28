// SettingsViewiOS.swift — iOS settings tab

import SwiftUI

struct SettingsViewiOS: View {
    @EnvironmentObject var worker: Worker
    @State private var showQR = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {

                // ── Identity ──────────────────────────────────────────────
                Section("MY PEER ID") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(worker.myPeerID.isEmpty ? "Loading..." : worker.myPeerID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = worker.myPeerID
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copied = false
                                }
                            } label: {
                                Label(copied ? "Copied!" : "Copy ID",
                                      systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .tint(copied ? .green : .accentColor)

                            Button {
                                showQR = true
                            } label: {
                                Label("Show QR", systemImage: "qrcode")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── About ─────────────────────────────────────────────────
                Section("ABOUT") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/your-org/peerdrop")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .sheet(isPresented: $showQR) {
                NavigationStack {
                    QRCodeView(content: worker.myPeerID)
                        .navigationTitle("Scan to Connect")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showQR = false }
                            }
                        }
                }
            }
        }
    }
}
