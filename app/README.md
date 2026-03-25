# PeerDrop

A secure, privacy-focused P2P file sharing app for macOS, inspired by Blip.

## Features

- 🔐 **End-to-end encrypted** file transfers using Hyperswarm
- 🔑 **Identity-based authentication** with keet-identity-keys for multi-device support
- 📱 **Cross-platform** - Works across macOS, Linux, Windows, iOS, Android
- 🚀 **Auto-discovery** - Finds peers automatically on the network
- 📥 **Auto-download** - Received files automatically save to ~/Downloads/PeerDrop
- 🎯 **Drag & Drop** - Simple drag files onto devices in the menu bar
- 🔒 **Privacy-first** - No servers, no tracking, P2P only

## Architecture

### Technology Stack

**Frontend (macOS)**
- Swift + SwiftUI for native macOS menu bar app
- BareKit for JavaScript runtime integration

**Backend (P2P Layer)**
- Bare Runtime - Lightweight JavaScript runtime
- Hyperswarm - P2P networking and discovery
- Hypercore/Hyperdrive - Data replication
- keet-identity-keys - Multi-device identity management

### How It Works

1. **Identity Management**
   - Each user has one identity keypair stored in `~/.peerdrop/identity`
   - Multiple devices can share the same identity
   - Public key is used as the peer ID

2. **Peer Discovery**
   - All devices join the same Hyperswarm topic (`peerdrop-v1`)
   - Peers automatically discover each other on local network and internet
   - Each connection performs a handshake to exchange device info

3. **File Transfer**
   - Sender drags file onto peer device in menu bar
   - File is chunked and sent over encrypted P2P connection
   - Receiver auto-accepts and saves to Downloads folder
   - Progress updates shown in real-time

4. **Security**
   - All connections are encrypted by Hyperswarm
   - Identity keys ensure only authorized devices connect
   - No centralized servers - everything is P2P

## Project Structure

```
PeerDrop/
├── App.swift                 # Main SwiftUI app entry
├── ContentView.swift         # Menu bar UI
├── Worker.swift              # Swift ↔ JavaScript bridge
├── PeerDevice.swift          # Device model
├── FileTransfer.swift        # Transfer state model
├── app.js                    # JavaScript P2P backend
└── package.json              # Node dependencies
```

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Build and run in Xcode

3. Files will auto-download to: `~/Downloads/PeerDrop/`

## Multi-Device Support

PeerDrop uses keet-identity-keys to manage user identity:

- **One identity per user** - Your public key is your ID
- **Multiple devices** - Each device shares the same identity
- **Seamless sync** - All your devices appear as one peer to others
- **Device names** - Each device shows its hostname for easy identification

To use the same identity across devices:
1. Copy `~/.peerdrop/identity/` folder to new device
2. Launch PeerDrop - it will use the same peer ID

## Security Considerations

✅ **What we protect:**
- File contents (encrypted in transit)
- Peer discovery (DHT-based, no central server)
- Identity verification (cryptographic keys)

⚠️ **What to know:**
- Peers on the network can see you're online
- File metadata (names, sizes) visible during transfer
- Identity folder should be kept secure

## Future Enhancements

- [ ] Folder transfer support
- [ ] Transfer queue and history
- [ ] Custom download location
- [ ] Contact list / favorites
- [ ] Transfer resume on disconnect
- [ ] QR code pairing for mobile devices
- [ ] End-to-end encryption with per-transfer keys
- [ ] iOS/Android companion apps

## License

MIT
