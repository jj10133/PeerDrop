const Hyperswarm   = require('hyperswarm')
const os           = require('bare-os')
const RPC          = require('bare-rpc')
const IdentityKeys = require('keet-identity-key')
const crypto       = require('hypercore-crypto')

const cmds            = require('./commands')
const store           = require('./store')
const TransferManager = require('./transfers')

const {
  CMD_READY, CMD_PEER_CONNECTED, CMD_PEER_DISCONNECTED,
  CMD_SAVED_PEERS, CMD_PAIRING_COMPLETE,
  CMD_SEND_FILE, CMD_CONNECT_PEER, CMD_SET_DOWNLOAD_PATH,
  CMD_FORGET_PEER, CMD_GENERATE_INVITE, CMD_ACCEPT_INVITE,
  CMD_TRANSFER_STARTED
} = cmds

// z-base-32 — URL-safe, human-friendly, same alphabet as pear:// URLs
const ZBASE32 = 'ybndrfg8ejkmcpqxot1uwisza345h769'

function zEncode (buf) {
  let bits = ''; for (const b of buf) bits += b.toString(2).padStart(8, '0')
  let out = ''; for (let i = 0; i + 5 <= bits.length; i += 5) out += ZBASE32[parseInt(bits.slice(i, i + 5), 2)]
  return out
}

function zDecode (str) {
  const lu = new Uint8Array(256).fill(255)
  for (let i = 0; i < ZBASE32.length; i++) lu[ZBASE32.charCodeAt(i)] = i
  let bits = ''; for (const ch of str) bits += lu[ch.charCodeAt(0)].toString(2).padStart(5, '0')
  const bytes = []; for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2))
  return Buffer.from(bytes)
}

class PeerDrop {
  constructor () {
    this.swarm              = null
    this.identity           = null  // only set on primary device (has mnemonic)
    this.deviceKeyPair      = null
    this.attestationProof   = null
    this.identityPublicKey  = null  // the root signing key — used for proof verification
    this.discoveryPublicKey = null  // profileDiscoveryPublicKey — the Hyperswarm topic
                                    // this is also what users share as their "Peer ID"

    // noiseKeyHex → { conn, identityKey, discoveryKey, deviceName, platform }
    this.peers = new Map()

    // nonce hex → { ephemeralTopic } — active pairing slots waiting for Device B
    this.pendingPairings = new Map()

    this.rpc = new RPC(BareKit.IPC, (req) => this._onRequest(req))
    this.transfers = new TransferManager(
      (cmd, payload) => this._emit(cmd, payload),
      () => store.getDownloadPath()
    )

    this._init()
  }

  // ─── Init ─────────────────────────────────────────────────────────────────

  async _init () {
    const result = await store.loadIdentity()
    this.identity           = result.identity
    this.deviceKeyPair      = result.deviceKeyPair
    this.attestationProof   = result.attestationProof
    this.identityPublicKey  = result.identityPublicKey
    this.discoveryPublicKey = result.discoveryPublicKey

    this.swarm = new Hyperswarm()
    this.swarm.on('connection', (conn, info) => this._onConnection(conn, info))

    if (result.unpaired) {
      // Fresh Device B — no identity yet. Just start the swarm and wait.
      // Swift will show the "Pair this device" screen (empty peerID signals this).
      // The user pastes the invite URL → _acceptPairingInvite() takes over.
      this._emit(CMD_READY, { peerID: '', myIdentityKey: '', downloadPath: store.getDownloadPath() })
      return
    }

    // Announce ourselves so others can find us by joining our discoveryPublicKey
    this.swarm.join(this.discoveryPublicKey, { server: true, client: false })

    // Reconnect to all saved contacts and own devices from previous sessions
    for (const peer of store.loadSavedPeers()) {
      if (peer.discoveryKey) this._joinPeerTopic(peer.discoveryKey)
    }

    this._emit(CMD_READY, {
      peerID:        this.discoveryPublicKey.toString('hex'),
      myIdentityKey: this.identityPublicKey.toString('hex'),
      downloadPath:  store.getDownloadPath()
    })

    this._emitSavedPeers()
  }

  // ─── Swift → JS requests ─────────────────────────────────────────────────

  _onRequest (req) {
    if (req.id === undefined) return
    const body  = req.data ? JSON.parse(req.data.toString()) : {}
    const reply = (err) => err ? req.reply(Buffer.from(err.message)) : req.reply()

    switch (req.command) {
      case CMD_SEND_FILE:
        this._sendFile(body.filePath, body.peerId).then(() => reply()).catch(reply)
        break

      case CMD_CONNECT_PEER:
        // body.peerID is the other person's discoveryPublicKey (their "Peer ID")
        this._connectToPeer(body.peerID).then(() => reply()).catch(reply)
        break

      case CMD_SET_DOWNLOAD_PATH:
        store.setDownloadPath(body.downloadPath)
        reply()
        break

      case CMD_FORGET_PEER:
        this._forgetPeer(body.peerIdentityKey)
        reply()
        break

      case CMD_GENERATE_INVITE:
        this._generatePairingInvite()
          .then(url => req.reply(Buffer.from(url)))
          .catch(reply)
        break

      case CMD_ACCEPT_INVITE:
        this._acceptPairingInvite(body.inviteUrl).then(() => reply()).catch(reply)
        break

      default: reply()
    }
  }

  // ─── Connecting to other people ───────────────────────────────────────────
  //
  // The user pastes the other person's "Peer ID" (discoveryPublicKey hex).
  // We join that as a Hyperswarm client topic — Hyperswarm finds their
  // server announcement and connects us. Their handshake proof confirms
  // who they are. If they have multiple devices, we connect to all of them
  // but they show as ONE person in the UI (same identityKey).

  async _connectToPeer (discoveryKeyHex) {
    if (!/^[0-9a-f]{64}$/i.test(discoveryKeyHex)) {
      throw new Error('Invalid Peer ID — must be a 64-character hex string')
    }
    store.upsertSavedPeer(null, { discoveryKey: discoveryKeyHex })
    this._joinPeerTopic(discoveryKeyHex)
  }

  _joinPeerTopic (hex) {
    this.swarm.join(Buffer.from(hex, 'hex'), { server: false, client: true })
  }

  _forgetPeer (identityKeyHex) {
    const saved = store.loadSavedPeers().find(p => p.identityKey === identityKeyHex)
    if (saved?.discoveryKey) {
      try { this.swarm.leave(Buffer.from(saved.discoveryKey, 'hex')) } catch (e) {}
    }
    store.removeSavedPeer(identityKeyHex)
    this._emitSavedPeers()
  }

  // ─── Adding your own devices (Device A — generates QR) ───────────────────
  //
  // Pairing invite = 48 bytes: [ephemeralTopic (32)] + [nonce (16)]
  // Encoded as z-base-32 → 76 chars → pear://peerdrop/<76chars> → compact QR
  //
  // ephemeralTopic: random, one-use topic. NOT our real discoveryKey.
  // nonce: ties the QR to a specific pending slot on Device A.
  // Expires after 5 minutes if unused.
  //
  // Hyperswarm connections are Noise-encrypted end-to-end.
  // No extra encryption layer needed — mnemonic never leaves Device A.

  async _generatePairingInvite () {
    if (!this.identity) {
      throw new Error('Only the primary device can generate pairing invites')
    }

    const ephemeralTopic = crypto.randomBytes(32)
    const nonce          = crypto.randomBytes(16)
    const nonceHex       = nonce.toString('hex')

    this.swarm.join(ephemeralTopic, { server: true, client: false })
    this.pendingPairings.set(nonceHex, { ephemeralTopic, createdAt: Date.now() })

    setTimeout(() => {
      if (this.pendingPairings.has(nonceHex)) {
        this.pendingPairings.delete(nonceHex)
        try { this.swarm.leave(ephemeralTopic) } catch (e) {}
      }
    }, 5 * 60 * 1000)

    return 'pear://peerdrop/' + zEncode(Buffer.concat([ephemeralTopic, nonce]))
  }

  // ─── Adding your own devices (Device B — scans QR) ───────────────────────

  async _acceptPairingInvite (inviteUrl) {
    const encoded = inviteUrl.replace('pear://peerdrop/', '')
    const payload = zDecode(encoded)

    if (payload.length < 48) throw new Error('Invalid invite')

    const ephemeralTopic    = payload.slice(0, 32)
    const nonce             = payload.slice(32, 48)
    const ephemeralTopicHex = ephemeralTopic.toString('hex')

    // Fresh keypair for this device — secretKey never leaves here
    const deviceBKeyPair = crypto.keyPair()
    this._pendingAccept  = { deviceBKeyPair, nonce, ephemeralTopicHex, sent: false }

    this.swarm.join(ephemeralTopic, { server: false, client: true })
  }

  // ─── Connection handling ──────────────────────────────────────────────────

  _onConnection (conn, info) {
    const noiseKeyHex = info.publicKey.toString('hex')

    // Only send pairRequest if this connection came in on our ephemeral pairing topic.
    // info.topics contains the topics this connection is associated with (client mode).
    const connTopics = (info.topics || []).map(t => t.toString('hex'))
    const isPairingConn = this._pendingAccept &&
      !this._pendingAccept.sent &&
      connTopics.includes(this._pendingAccept.ephemeralTopicHex)

    if (isPairingConn) {
      // Device B: send our fresh public key + nonce to Device A
      this._pendingAccept.sent = true
      conn.write(JSON.stringify({
        type:      'pairRequest',
        deviceKey: this._pendingAccept.deviceBKeyPair.publicKey.toString('hex'),
        nonce:     this._pendingAccept.nonce.toString('hex')
      }) + '\n')
    } else if (this.attestationProof) {
      // Normal handshake — only if we have an identity (primary or paired device)
      conn.write(JSON.stringify({
        type:             'handshake',
        attestationProof: this.attestationProof.toString('base64'),
        discoveryKey:     this.discoveryPublicKey.toString('hex'),
        deviceName:       os.hostname(),
        platform:         os.platform()
      }) + '\n')
    }
    // else: unpaired Device B connecting on ephemeral topic — pairRequest already sent above

    let buf = ''
    conn.on('data', (data) => {
      buf += data.toString()
      const lines = buf.split('\n')
      buf = lines.pop()
      for (const line of lines) {
        if (!line.trim()) continue
        try { this._onPeerMessage(conn, noiseKeyHex, JSON.parse(line)) }
        catch (e) { console.error('Parse error:', e) }
      }
    })

    conn.on('close', () => {
      const peer = this.peers.get(noiseKeyHex)
      this.peers.delete(noiseKeyHex)
      this._emit(CMD_PEER_DISCONNECTED, {
        noiseKey:    noiseKeyHex,
        identityKey: peer?.identityKey ?? null
      })
    })

    conn.on('error', (err) => console.error('Connection error:', err))
  }

  _onPeerMessage (conn, noiseKeyHex, msg) {
    switch (msg.type) {

      // ── Normal handshake — both contacts and own devices use this ─────────
      case 'handshake': {
        const { attestationProof, discoveryKey, deviceName, platform } = msg

        // Verify the proof chains back to a real identity
        let verifiedIdentityKey = null
        try {
          const info = IdentityKeys.verify(Buffer.from(attestationProof, 'base64'), null)
          if (info) verifiedIdentityKey = info.identityPublicKey.toString('hex')
        } catch (e) {}

        if (!verifiedIdentityKey) {
          console.warn('Rejecting handshake: invalid proof from', noiseKeyHex.slice(0, 16))
          conn.destroy(); return
        }

        // Is this one of our own devices?
        const isOwnDevice = verifiedIdentityKey === this.identityPublicKey.toString('hex')

        this.peers.set(noiseKeyHex, {
          conn, identityKey: verifiedIdentityKey,
          discoveryKey, deviceName, platform,
          isOwnDevice, lastSeen: Date.now()
        })

        store.upsertSavedPeer(verifiedIdentityKey, {
          discoveryKey, deviceName, platform,
          lastSeen: Date.now()
        })

        // Ensure we stay connected to this peer in future sessions
        if (!isOwnDevice) this._joinPeerTopic(discoveryKey)

        this._emitSavedPeers()
        this._emit(CMD_PEER_CONNECTED, {
          noiseKey:     noiseKeyHex,
          identityKey:  verifiedIdentityKey,
          discoveryKey, deviceName, platform,
          isOwnDevice
        })
        break
      }

      // ── Pairing step 1: Device A receives Device B's public key ──────────
      case 'pairRequest': {
        if (!this.identity) { conn.destroy(); return }

        const { deviceKey, nonce } = msg
        const pending = this.pendingPairings.get(nonce)

        if (!pending) {
          console.warn('Rejecting pairRequest: unknown or expired nonce')
          conn.destroy(); return
        }

        this.pendingPairings.delete(nonce)
        try { this.swarm.leave(pending.ephemeralTopic) } catch (e) {}

        // Attest Device B using our device keypair — mnemonic not needed
        const proofB = IdentityKeys.attestDevice(
          Buffer.from(deviceKey, 'hex'),
          this.deviceKeyPair,
          this.attestationProof
        )

        conn.write(JSON.stringify({
          type:              'pairResponse',
          attestationProof:  proofB.toString('base64'),
          identityPublicKey: this.identityPublicKey.toString('hex'),
          discoveryKey:      this.discoveryPublicKey.toString('hex')
        }) + '\n')

        // Device A also introduces itself with a normal handshake so Device B
        // can add Device A to its own-devices list immediately after pairing
        conn.write(JSON.stringify({
          type:             'handshake',
          attestationProof: this.attestationProof.toString('base64'),
          discoveryKey:     this.discoveryPublicKey.toString('hex'),
          deviceName:       os.hostname(),
          platform:         os.platform()
        }) + '\n')
        break
      }

      // ── Pairing step 2: Device B receives its attestation ────────────────
      case 'pairResponse': {
        if (!this._pendingAccept) return
        const { deviceBKeyPair } = this._pendingAccept

        const proofBuf           = Buffer.from(msg.attestationProof, 'base64')
        const identityPublicKey  = Buffer.from(msg.identityPublicKey, 'hex')
        const discoveryPublicKey = Buffer.from(msg.discoveryKey, 'hex')

        // Verify the proof we received actually attests our key
        const info = IdentityKeys.verify(proofBuf, null)
        if (!info || !info.devicePublicKey.equals(deviceBKeyPair.publicKey)) {
          console.error('pairResponse: proof mismatch')
          conn.destroy(); return
        }

        store.writePairingResult({
          deviceKeyPair: deviceBKeyPair,
          attestationProof: proofBuf,
          discoveryPublicKey
        })

        this.deviceKeyPair      = deviceBKeyPair
        this.attestationProof   = proofBuf
        this.identityPublicKey  = identityPublicKey
        this.discoveryPublicKey = discoveryPublicKey
        this._pendingAccept     = null

        // Announce on the shared discoveryKey — we're now part of this identity
        this.swarm.join(this.discoveryPublicKey, { server: true, client: false })

        this._emit(CMD_PAIRING_COMPLETE, {
          peerID:        this.discoveryPublicKey.toString('hex'),
          myIdentityKey: this.identityPublicKey.toString('hex')
        })

        // Switch to normal handshake so we appear in each other's device list
        conn.write(JSON.stringify({
          type:             'handshake',
          attestationProof: this.attestationProof.toString('base64'),
          discoveryKey:     this.discoveryPublicKey.toString('hex'),
          deviceName:       os.hostname(),
          platform:         os.platform()
        }) + '\n')
        break
      }

      // ── File transfer ────────────────────────────────────────────────────
      case 'fileOffer': {
        const tinfo = this.transfers.onOffer(msg, conn, noiseKeyHex)
        this._emit(CMD_TRANSFER_STARTED, { ...tinfo, direction: 'receiving' })
        break
      }
      case 'fileAccept':   this.transfers.onAccept(msg.transferId, conn); break
      case 'fileChunk':    this.transfers.onChunk(msg);                   break
      case 'fileComplete': this.transfers.onComplete(msg);                break
    }
  }

  // ─── File sending ─────────────────────────────────────────────────────────

  // peerId here is identityKey. If the person has multiple devices online,
  // we pick the first live connection — they all share the same identityKey.
  async _sendFile (filePath, identityKey) {
    const peer = this._liveConnForIdentityKey(identityKey)
    if (!peer) throw new Error('Peer not connected: ' + identityKey)
    this.transfers.offer(filePath, peer.conn)
  }

  _liveConnForIdentityKey (identityKey) {
    for (const peer of this.peers.values()) {
      if (peer.identityKey === identityKey) return peer
    }
    return null
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  _emitSavedPeers () {
    this._emit(CMD_SAVED_PEERS, { peers: store.loadSavedPeers() })
  }

  _emit (command, payload) {
    this.rpc.event(command).send(Buffer.from(JSON.stringify(payload)))
  }
}

new PeerDrop()
