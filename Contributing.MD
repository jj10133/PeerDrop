# Contributing to PeerDrop

Thanks for your interest in contributing. This document covers everything you need to go from zero to a working dev build, understand the codebase, and submit a pull request.

---

## Table of Contents

- [Architecture overview](#architecture-overview)
- [Getting your environment set up](#getting-your-environment-set-up)
- [Project structure](#project-structure)
- [The transfer protocol](#the-transfer-protocol)
- [Adding a new RPC command](#adding-a-new-rpc-command)
- [Working on JS code](#working-on-js-code)
- [Working on Swift code](#working-on-swift-code)
- [Code style](#code-style)
- [Submitting a pull request](#submitting-a-pull-request)

---

## Architecture overview

PeerDrop has two layers that talk to each other over an in-process RPC bridge:

```
┌─────────────────────────────────────┐
│  Swift / SwiftUI  (UI + state)      │
│  Worker.swift, ContentView, etc.    │
│               ↕ bare-rpc            │
│  JS / Bare runtime  (networking)    │
│  app.js, transfers.js, store.js     │
└─────────────────────────────────────┘
         ↕ Hyperswarm (P2P)
         ↕ Protomux channels
    Remote peer's PeerDrop
```

**Swift side** owns all UI and published state. It calls into JS for anything that touches the network. It never touches Hyperswarm directly.

**JS side** (running inside a [BareKit](https://github.com/holepunchto/bare-kit) worklet) owns all networking. It fires events back to Swift when state changes — peer connected, transfer progress, etc. It never touches UIKit or SwiftUI.

**The bridge** is `IPCBridge.swift` on the Swift side and `bare-rpc` on the JS side. Integer command IDs defined in `commands.js` / `Commands.swift` identify each message type. Both files must always be in sync.

---

## Getting your environment set up

### Prerequisites

- macOS 15+
- Xcode 16+
- Node.js 18+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [GitHub CLI](https://cli.github.com): `brew install gh`

### Steps

**1. Clone and install JS dependencies**

```sh
git clone https://github.com/your-org/peerdrop
cd peerdrop
npm install
```

**2. Download BareKit**

BareKit is the Swift package that embeds the Bare JS runtime inside a macOS app. You need its prebuilt framework.

```sh
gh release download --repo holepunchto/bare-kit <version>
```

Unpack `prebuilds.zip` and move `macos/BareKit.xcframework` into `app/frameworks/`:

```
app/
  frameworks/
    BareKit.xcframework/   ← here
```

**3. Generate the Xcode project**

```sh
xcodegen generate
```

Re-run this any time you edit `project.yml`.

**4. Build and run**

Open `App.xcodeproj` in Xcode and press **⌘R**.

The pre-build scheme action runs automatically and does two things:
- `bare-link` — links native addons for the target platform into `app/addons/`
- `bare-pack` — bundles `app/js/app.js` and all its dependencies into `app/app.bundle`

You don't need to run these manually.

---

## Project structure

```
PeerDrop/
├── app/
│   ├── js/
│   │   ├── app.js           # Orchestrator — Hyperswarm + Protomux wiring
│   │   ├── transfers.js     # File and directory transfer engine
│   │   ├── store.js         # Identity, config, saved peers (disk persistence)
│   │   └── commands.js      # RPC command ID constants — must mirror Commands.swift
│   │
│   ├── App.swift                    # @main — MenuBarExtra entry point
│   ├── Commands.swift               # RPC command IDs — must mirror commands.js
│   ├── IPCBridge.swift              # BareKit worklet + bare-rpc setup
│   ├── Worker.swift                 # ObservableObject — published state + public API
│   ├── Worker+Events.swift          # All inbound JS→Swift event handlers
│   │
│   ├── PeerDevice.swift             # Model: a known peer or own device
│   ├── FileTransfer.swift           # Model: an in-progress file/folder transfer
│   │
│   ├── ContentView.swift            # Menu bar popover — devices, contacts, transfers
│   ├── DevicePanelView.swift        # Floating send panel — drop zone + transfer list
│   ├── DevicePanelController.swift  # NSPanel lifecycle
│   ├── DeviceRow.swift              # Row in MY DEVICES / PEOPLE list
│   ├── TransferRow.swift            # Compact transfer row in main window
│   ├── PanelTransferRow.swift       # Detailed transfer row in send panel
│   ├── SettingsView.swift           # Identity, seed file, downloads folder
│   ├── QRCodeView.swift             # QR code for Peer ID sharing
│   ├── SectionHeader.swift          # Reusable section label component
│   └── ActionLink.swift             # Tappable icon + label row component
│
├── project.yml              # XcodeGen project config + entitlements
└── package.json             # JS dependencies
```

---

## The transfer protocol

Understanding this section will help you reason about `app.js` and `transfers.js`.

### Peer connections

Each Hyperswarm connection gets one [Protomux](https://github.com/mafintosh/protomux) multiplexer. Two channel types run over it:

| Channel | Protocol name | Content |
|---------|--------------|---------|
| Control | `peerdrop/control` | JSON signalling messages |
| Data | `peerdrop/transfer` (one per file) | Raw binary file bytes |

### Control messages

All peer signalling travels as JSON on the control channel:

| Type | Direction | Purpose |
|------|-----------|---------|
| `handshake` | both ways on connect | Exchange identity + platform |
| `fileOffer` | sender → receiver | "I'm going to send you a file" |
| `batchStart` | sender → receiver | "I'm going to send you a folder" |
| `batchComplete` | sender → receiver | "All files in the folder are done" |

### Data channels

When the sender wants to transfer a file:

1. Opens a `peerdrop/transfer` channel with `id = Buffer.from(transferId)`
2. Sends a `fileOffer` control message with the transferId, filename, size
3. Receiver's `mux.pair()` handler fires synchronously → opens the matching receive channel
4. Both channels open → sender streams raw binary chunks, no base64 encoding
5. Sender sends `{ done: true }` on message slot [1] → receiver finalises the file

For directories, up to 4 files are transferred concurrently over separate data channels. Progress is tracked as a fraction of total bytes.

### Why `mux.pair()` matters

Protomux rejects any incoming channel open with no matching local channel — silently, with no retry. If the receiver tried to open its channel after the sender's open frame arrived, the session would be gone. `mux.pair()` is called on every new connection to register a handler that fires synchronously the moment any `peerdrop/transfer` channel arrives. `rxCh.open()` is called inside that handler before the function returns — this is the only ordering protomux accepts.

### RPC command IDs

The Swift/JS bridge uses integer command IDs defined in both `commands.js` and `Commands.swift`. They must always match. JS→Swift messages are called events. Swift→JS messages are requests (they expect a reply).

---

## Adding a new RPC command

This is the most common change. Follow these steps exactly.

**1. Pick an unused integer and add it to both files:**

`app/js/commands.js`:
```js
CMD_YOUR_COMMAND: 13   // next available number
```

`app/Commands.swift`:
```swift
static let yourCommand = UInt(13)
```

**2a. If it's a JS → Swift event** (JS tells Swift something happened):

In `app/js/app.js` (or `transfers.js`), emit it:
```js
this._emit(CMD_YOUR_COMMAND, { someField: value })
```

In `app/Worker+Events.swift`, add a case and handler:
```swift
case Cmd.yourCommand: onYourCommand(json)
```
```swift
private func onYourCommand(_ data: [String: Any]) {
    // parse data, update published state on DispatchQueue.main
}
```

**2b. If it's a Swift → JS request** (Swift asks JS to do something):

In `app/Worker.swift`, add a public method:
```swift
func yourAction(value: String) {
    fireAndForget(Cmd.yourCommand, body: ["value": value])
}
```

In `app/js/app.js`, add a case to `_onRequest`:
```js
case CMD_YOUR_COMMAND:
    this._handleYourCommand(body)
    reply()
    break
```

---

## Working on JS code

### The Bare runtime

The JS side runs in [Bare](https://github.com/holepunchto/bare) — a lightweight V8-based runtime built by Holepunch. It's close to Node.js but uses `bare-*` packages for builtins:

| Node.js | Bare equivalent |
|---------|----------------|
| `fs` | `bare-fs` |
| `path` | `bare-path` |
| `os` | `bare-os` |
| `crypto` | `hypercore-crypto` |

Most npm packages that don't use native addons work in Bare. Anything that calls `process.nextTick`, `EventEmitter`, or streams should also work — Bare implements these.

### Iterating without a full rebuild

The `bare-pack` step runs automatically before every Xcode build, so just building in Xcode picks up JS changes. For pure logic that doesn't involve the Swift bridge, you can test JS modules in isolation with Node.js — most `bare-*` packages work in Node.js too.

### Key constraints in transfers.js

`transfers.js` is intentionally decoupled from `app.js`. It receives `emit` and `getDownloadPath` in its constructor and knows nothing about Hyperswarm, Protomux, or the Swift bridge. Keep it that way. It should be testable in isolation.

When adding new channel types, follow the same `mux.pair()` pattern — register the pair handler in `pairTransferChannels` before anything else on the connection.

---

## Working on Swift code

### State lives in Worker

`Worker.swift` is the single source of truth for SwiftUI. All `@Published` properties live there. Views read from Worker and call its methods — they never touch RPC or IPC directly.

`Worker+Events.swift` contains all inbound event handlers. Each handler has one job: parse the JSON payload and update `Worker`'s published state on `DispatchQueue.main`. No business logic in event handlers.

### DevicePanelView uses a live device lookup

`DevicePanelView` receives a `deviceID: String` (the discoveryKey), not a `PeerDevice` struct. It looks up the live device from `worker.knownDevices` in a computed property. This means `isOnline` is always current — the panel updates in real time when a peer disconnects.

### Dispatch rules

All mutations to `@Published` properties must happen on the main queue. Use `DispatchQueue.main.async { ... }` in event handlers. Swift UI updates that happen off the main queue will crash.

---

## Code style

**JS:**
- 2-space indentation
- Single quotes
- Align related assignments with spaces for readability
- `const` for everything that doesn't reassign
- Descriptive names over comments — comments explain *why*, not *what*

**Swift:**
- Standard SwiftUI conventions
- `// MARK: - Section Name` dividers between logical sections
- Private computed properties for sub-views rather than inline
- Value types (`struct`) for models; `class` only for things that need reference semantics (Worker, IPCBridge, DevicePanelController)

---

## Submitting a pull request

1. Fork the repo and create a branch: `git checkout -b your-feature`
2. Make your changes — keep commits focused and descriptive
3. Test on a real Mac — the Xcode simulator won't exercise Hyperswarm networking
4. If you changed the transfer protocol, test with two real machines
5. If you changed `commands.js`, make sure `Commands.swift` matches
6. Open a PR with a clear description of what changed and why

If you're unsure about the approach before writing code, open an issue first.

---

## License

Apache-2.0
