import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Extension entry point

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(
            rootView: ShareView(context: extensionContext)
        )
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}

// MARK: - Share UI

struct ShareView: View {
    let context: NSExtensionContext?
    @State private var peers: [AppGroupPeer] = []
    @State private var fileURL: URL?

    var contacts:  [AppGroupPeer] { peers.filter { !$0.isOwnDevice } }
    var myDevices: [AppGroupPeer] { peers.filter {  $0.isOwnDevice } }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if peers.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if !myDevices.isEmpty {
                                bubblesSection(title: "MY DEVICES", peers: myDevices)
                            }
                            if !contacts.isEmpty {
                                bubblesSection(title: "PEOPLE", peers: contacts)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                }
            }
            .navigationTitle("PeerDrop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        context?.completeRequest(returningItems: nil)
                    }
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - Bubbles

    @ViewBuilder
    func bubblesSection(title: String, peers: [AppGroupPeer]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .kerning(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(peers, id: \.discoveryKey) { peer in
                        PeerBubble(peer: peer) { sendToPeer(peer) }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Empty state

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No contacts yet")
                .font(.headline)
            Text("Open PeerDrop and add contacts first")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Data loading

    func loadData() async {
        peers   = AppGroup.readPeers()
        fileURL = await extractFileURL()
    }

    func extractFileURL() async -> URL? {
        guard let items = context?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = try? await provider.loadItem(
                       forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                    return url
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                   let url = try? await provider.loadItem(
                       forTypeIdentifier: UTType.data.identifier) as? URL {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: - Send

    func sendToPeer(_ peer: AppGroupPeer) {
        guard let fileURL else { return }
        AppGroup.writePendingTransfer(PendingTransfer(
            fileURL:  fileURL.absoluteString,
            peerKey:  peer.discoveryKey,
            peerName: peer.displayName
        ))
        let url = URL(string: "peerdrop://send")!
        context?.open(url) { _ in
            self.context?.completeRequest(returningItems: nil)
        }
    }
}

// MARK: - Bubble

struct PeerBubble: View {
    let peer: AppGroupPeer
    let onTap: () -> Void

    var icon: String {
        switch peer.platform.lowercased() {
        case "darwin":           return "laptopcomputer"
        case "ios":              return "iphone"
        case "win32", "windows": return "pc"
        default:                 return "desktopcomputer"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 26))
                            .foregroundStyle(.primary)
                    )
                Text(peer.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
    }
}
