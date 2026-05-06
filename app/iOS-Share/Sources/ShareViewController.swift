import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

final class ShareModel: ObservableObject {
    @Published var peers:   [AppGroupPeer] = []
    @Published var fileURL: URL?           = nil
    @Published var loaded:  Bool           = false
}

// MARK: - Extension entry point

@objc(ShareViewController)
class ShareViewController: UIViewController {

    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("📦 [PeerDrop Share] viewDidLoad")

        let peers = AppGroup.readPeers()
        NSLog("📦 [PeerDrop Share] loaded %d peers", peers.count)
        model.peers  = peers
        model.loaded = true

        let host = UIHostingController(
            rootView: ShareView(
                model:   model,
                context: extensionContext,
                onSend:  { [weak self] peer in self?.send(to: peer) }
            )
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

        Task {
            let url = await extractFileURL()
            await MainActor.run { self.model.fileURL = url }
        }
    }

    // MARK: - Send

    func send(to peer: AppGroupPeer) {
        guard let fileURL = model.fileURL else {
            NSLog("❌ [PeerDrop Share] no fileURL")
            return
        }

        // Copy file into App Group container so main app can access it
        guard let container = AppGroup.containerURL else {
            NSLog("❌ [PeerDrop Share] no container URL")
            return
        }
        let dest = container.appendingPathComponent(fileURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: fileURL, to: dest)
        } catch {
            NSLog("❌ [PeerDrop Share] copy error: %@", error.localizedDescription)
            return
        }

        AppGroup.writePendingTransfer(PendingTransfer(
            fileURL:  dest.absoluteString,
            peerKey:  peer.discoveryKey,
            peerName: peer.displayName
        ))

        // Walk responder chain to open URL — works from share extensions
        let url = URL(string: "peerdrop://send")!
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                NSLog("📦 [PeerDrop Share] opened peerdrop://send via responder chain")
                break
            }
            responder = r.next
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - File extraction

    func extractFileURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
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
}

// MARK: - Share UI

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let context: NSExtensionContext?
    let onSend:  (AppGroupPeer) -> Void

    var contacts:  [AppGroupPeer] { model.peers.filter { !$0.isOwnDevice } }
    var myDevices: [AppGroupPeer] { model.peers.filter {  $0.isOwnDevice } }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Button("Cancel") {
                    context?.completeRequest(returningItems: nil)
                }
                .foregroundStyle(.blue)
                Spacer()
                Text("PeerDrop").font(.headline)
                Spacer()
                Text("Cancel").opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Content
            if !model.loaded {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            } else if model.peers.isEmpty {
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
                    .padding(20)
                }
            }
        }
    }

    @ViewBuilder
    func bubblesSection(title: String, peers: [AppGroupPeer]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(peers, id: \.discoveryKey) { peer in
                        PeerBubble(peer: peer) { onSend(peer) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.slash")
                .font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("No contacts yet").font(.headline)
            Text("Open PeerDrop and add contacts first")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Peer bubble

struct PeerBubble: View {
    let peer:  AppGroupPeer
    let onTap: () -> Void

    var icon: String {
        switch peer.platform {
        case "laptopcomputer": return "laptopcomputer"
        case "iphone":         return "iphone"
        case "server.rack":    return "server.rack"
        default:               return "desktopcomputer"
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
                    .font(.caption).fontWeight(.medium)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
    }
}