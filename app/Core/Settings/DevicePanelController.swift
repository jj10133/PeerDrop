// DevicePanelController.swift — Manages floating NSPanel windows for device send panels.
//
// Uses deviceID (discoveryKey) as the key so only one panel opens per peer.
// NSPanel stays above Finder so users can drag files from Finder into it.

import SwiftUI
import AppKit

final class DevicePanelController: NSWindowController {

    // One panel per device. Key = discoveryKey.
    static var open: [String: DevicePanelController] = [:]

    static func show(device: PeerDevice, worker: Worker) {
        if let existing = open[device.discoveryKey] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DevicePanelController(deviceID: device.discoveryKey,
                                               title: device.name,
                                               worker: worker)
        open[device.discoveryKey] = controller
        controller.showWindow(nil)
    }

    private let deviceID: String

    private init(deviceID: String, title: String, worker: Worker) {
        self.deviceID = deviceID

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.title                          = title
        panel.titlebarAppearsTransparent     = true
        panel.isMovableByWindowBackground    = true
        panel.isFloatingPanel                = true
        panel.worksWhenModal                 = true
        panel.center()

        // Pass deviceID, not the PeerDevice struct — the view looks up the live
        // version from worker.knownDevices so isOnline is always current.
        let view = DevicePanelView(deviceID: deviceID).environmentObject(worker)
        panel.contentView = NSHostingView(rootView: view)

        super.init(window: panel)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object:  panel,
            queue:   .main
        ) { [weak self] _ in
            guard let self else { return }
            DevicePanelController.open.removeValue(forKey: self.deviceID)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use DevicePanelController.show()") }
}
