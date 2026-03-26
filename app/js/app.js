// app.js — Orchestrator. Wires Hyperswarm connections to the RPC bridge.
//
// Responsibilities:
//   • Boot identity and swarm
//   • Route Swift→JS RPC commands to the right handler
//   • Manage peer connections (handshake, disconnect, saved peers)
//   • Delegate file transfers entirely to TransferManager

const Hyperswarm = require('hyperswarm')
const os         = require('bare-os')
const RPC        = require('bare-rpc')

const cmds   = require('./commands')
const store  = require('./store')
const TransferManager = require('./transfers')

const {
  CMD_READY, CMD_PEER_CONNECTED, CMD_PEER_DISCONNECTED,
  CMD_SAVED_PEERS, CMD_TRANSFER_STARTED,
  CMD_SEND_FILE, CMD_CONNECT_PEER, CMD_SET_DOWNLOAD_PATH, CMD_FORGET_PEER
} = cmds

class PeerDrop {
  constructor () {
    this.swarm              = null
    this.discoveryPublicKey = null

    // noiseKeyHex → { conn, discoveryKey, displayName, platform, isOwnDevice }
    this.peers = new Map()

    this.rpc = new RPC(BareKit.IPC, (req) => this._onRequest(req))
    this.transfers = new TransferManager(
      (cmd, payload) => this._emit(cmd, payload),
      () => store.getDownloadPath()
    )

    this._init()
  }

  // ── Boot ────────────────────────────────────────────────────────────────────

  async _init () {
    const { discoveryPublicKey } = await store.loadIdentity()
    this.discoveryPublicKey = discoveryPublicKey

    this.swarm = new Hyperswarm()
    this.swarm.on('connection', (conn, info) => this._onConnection(conn, info))

    // server+client so own devices (same discoveryKey) find each other too
    this.swarm.join(this.discoveryPublicKey, { server: true, client: true })

    for (const peer of store.loadSavedPeers()) {
      this._joinTopic(peer.discoveryKey)
    }

    this._emit(CMD_READY, {
      peerID:       this.discoveryPublicKey.toString('hex'),
      downloadPath: store.getDownloadPath()
    })

    this._emitSavedPeers()
  }

  // ── Swift → JS request router ───────────────────────────────────────────────

  _onRequest (req) {
    if (req.id === undefined) return
    const body  = req.data ? JSON.parse(req.data.toString()) : {}
    const reply = (err) => err
      ? req.reply(Buffer.from(String(err.message ?? err)))
      : req.reply()

    switch (req.command) {
      case CMD_SEND_FILE:
        this._sendFile(body.filePath, body.peerId).then(() => reply()).catch(reply)
        break
      case CMD_CONNECT_PEER:
        this._connectToPeer(body.peerID).then(() => reply()).catch(reply)
        break
      case CMD_SET_DOWNLOAD_PATH:
        store.setDownloadPath(body.downloadPath)
        reply()
        break
      case CMD_FORGET_PEER:
        this._forgetPeer(body.peerDiscoveryKey)
        reply()
        break
      default:
        reply()
    }
  }

  // ── Peer management ─────────────────────────────────────────────────────────

  async _connectToPeer (discoveryKeyHex) {
    if (!/^[0-9a-f]{64}$/i.test(discoveryKeyHex)) {
      throw new Error('Invalid Peer ID — must be 64 hex characters')
    }
    store.upsertSavedPeer(discoveryKeyHex)
    this._joinTopic(discoveryKeyHex)
    this._emitSavedPeers()
  }

  _forgetPeer (discoveryKeyHex) {
    try { this.swarm.leave(Buffer.from(discoveryKeyHex, 'hex')) } catch (_) {}
    store.removeSavedPeer(discoveryKeyHex)
    this._emitSavedPeers()
  }

  _joinTopic (hex) {
    this.swarm.join(Buffer.from(hex, 'hex'), { server: false, client: true })
  }

  // ── Connection lifecycle ─────────────────────────────────────────────────────

  _onConnection (conn, info) {
    const noiseKey = info.publicKey.toString('hex')

    conn.write(JSON.stringify({
      type:         'handshake',
      discoveryKey: this.discoveryPublicKey.toString('hex'),
      displayName:  os.hostname(),
      platform:     os.platform()
    }) + '\n')

    let buf = ''
    conn.on('data', (chunk) => {
      buf += chunk.toString()
      const lines = buf.split('\n')
      buf = lines.pop()                        // keep incomplete last line
      for (const line of lines) {
        if (!line.trim()) continue
        try { this._onPeerMessage(conn, noiseKey, JSON.parse(line)) }
        catch (e) { console.error('Message parse error:', e.message) }
      }
    })

    conn.on('close', () => {
      const peer = this.peers.get(noiseKey)
      this.peers.delete(noiseKey)
      this._emit(CMD_PEER_DISCONNECTED, {
        noiseKey,
        discoveryKey: peer?.discoveryKey ?? null
      })
    })

    conn.on('error', (err) => console.error('Connection error:', err.message))
  }

  _onPeerMessage (conn, noiseKey, msg) {
    switch (msg.type) {

      case 'handshake': {
        const { discoveryKey, displayName, platform } = msg
        const isOwnDevice = discoveryKey === this.discoveryPublicKey.toString('hex')

        this.peers.set(noiseKey, {
          conn, discoveryKey, displayName, platform, isOwnDevice, lastSeen: Date.now()
        })

        if (!isOwnDevice) {
          store.upsertSavedPeer(discoveryKey, { displayName, platform, lastSeen: Date.now() })
          this._emitSavedPeers()
        }

        this._emit(CMD_PEER_CONNECTED, {
          noiseKey, discoveryKey, displayName, platform, isOwnDevice
        })
        break
      }

      case 'fileOffer': {
        const info = this.transfers.onOffer(msg, conn, noiseKey)
        this._emit(CMD_TRANSFER_STARTED, { ...info, direction: 'receiving' })
        break
      }

      case 'fileAccept':   this.transfers.onAccept(msg.transferId, conn); break
      case 'fileChunk':    this.transfers.onChunk(msg);                   break
      case 'fileComplete': this.transfers.onComplete(msg);                break
    }
  }

  // ── File sending ─────────────────────────────────────────────────────────────

  async _sendFile (filePath, discoveryKey) {
    const result = this._liveConn(discoveryKey)
    if (!result) throw new Error('Peer not connected: ' + discoveryKey)
    // Pass noiseKey so TransferManager can tag the transfer for UI filtering
    this.transfers.offer(filePath, result.conn, result.noiseKey)
  }

  // Returns { conn, noiseKey } for the first live connection matching discoveryKey
  _liveConn (discoveryKey) {
    for (const [noiseKey, peer] of this.peers.entries()) {
      if (peer.discoveryKey === discoveryKey) return { conn: peer.conn, noiseKey }
    }
    return null
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  _emitSavedPeers () {
    this._emit(CMD_SAVED_PEERS, { peers: store.loadSavedPeers() })
  }

  _emit (command, payload) {
    this.rpc.event(command).send(Buffer.from(JSON.stringify(payload)))
  }
}

new PeerDrop()
