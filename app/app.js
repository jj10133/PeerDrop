const Hyperswarm   = require('hyperswarm')
const os           = require('bare-os')
const RPC          = require('bare-rpc')

const cmds           = require('./commands')
const store          = require('./store')
const TransferManager = require('./transfers')

const {
  CMD_READY, CMD_PEER_CONNECTED, CMD_PEER_DISCONNECTED,
  CMD_SAVED_PEERS, CMD_ERROR,
  CMD_SEND_FILE, CMD_CONNECT_PEER, CMD_SET_DOWNLOAD_PATH, CMD_FORGET_PEER,
  CMD_TRANSFER_STARTED
} = cmds

class PeerDrop {
  constructor () {
    this.swarm    = null
    this.identity = null

    // noiseKeyHex → { conn, discoveryKey, deviceName, platform, lastSeen }
    this.peers = new Map()

    this.rpc = new RPC(BareKit.IPC, (req) => this._onRequest(req))

    this.transfers = new TransferManager(
      (cmd, payload) => this._emit(cmd, payload),
      () => store.getDownloadPath()
    )

    this._init()
  }

  // ─── Init ─────────────────────────────────────────────────────────────────

  async _init () {
    this.identity = await store.loadIdentity()

    this.swarm = new Hyperswarm()
    this.swarm.on('connection', (conn, info) => this._onConnection(conn, info))

    // Announce ourselves so others can find and connect to us
    this.swarm.join(this.identity.profileDiscoveryPublicKey, { server: true, client: false })

    // Reconnect to all peers from previous sessions
    for (const peer of store.loadSavedPeers()) {
      this._joinPeerTopic(peer.discoveryKey)
    }

    this._emit(CMD_READY, {
      publicKey:    this.identity.profileDiscoveryPublicKey.toString('hex'),
      downloadPath: store.getDownloadPath()
    })
    this._emitSavedPeers()
  }

  // ─── Swift → JS requests ─────────────────────────────────────────────────

  _onRequest (req) {
    if (req.id === undefined) return  // IncomingEvent, not a request

    const body = req.data ? JSON.parse(req.data.toString()) : {}
    const reply = (err) => err
      ? req.reply(Buffer.from(err.message))
      : req.reply()

    switch (req.command) {
      case CMD_SEND_FILE:
        this._sendFile(body.filePath, body.peerId).then(() => reply()).catch(reply)
        break

      case CMD_CONNECT_PEER:
        this._connectToPeer(body.peerDiscoveryKey).then(() => reply()).catch(reply)
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

  // ─── Peer discovery ───────────────────────────────────────────────────────

  async _connectToPeer (hex) {
    if (!/^[0-9a-f]{64}$/i.test(hex)) {
      throw new Error('Invalid peer ID — must be a 64-character hex string')
    }
    store.upsertSavedPeer(hex)
    this._emitSavedPeers()
    this._joinPeerTopic(hex)
  }

  _joinPeerTopic (hex) {
    this.swarm.join(Buffer.from(hex, 'hex'), { server: false, client: true })
  }

  _forgetPeer (hex) {
    store.removeSavedPeer(hex)
    this._emitSavedPeers()
    try { this.swarm.leave(Buffer.from(hex, 'hex')) } catch (e) {}
  }

  // ─── Connection handling ──────────────────────────────────────────────────

  _onConnection (conn, info) {
    const noiseKeyHex = info.publicKey.toString('hex')

    // Introduce ourselves
    conn.write(JSON.stringify({
      type:         'handshake',
      discoveryKey: this.identity.profileDiscoveryPublicKey.toString('hex'),
      deviceName:   os.hostname(),
      platform:     os.platform()
    }) + '\n')

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
        noiseKey:     noiseKeyHex,
        discoveryKey: peer?.discoveryKey ?? null
      })
    })

    conn.on('error', (err) => console.error('Connection error:', err))
  }

  _onPeerMessage (conn, noiseKeyHex, msg) {
    switch (msg.type) {
      case 'handshake': {
        const { discoveryKey, deviceName, platform } = msg

        this.peers.set(noiseKeyHex, {
          conn, discoveryKey, deviceName, platform, lastSeen: Date.now()
        })

        // Persist / update this peer's record (handles both client and server mode)
        store.upsertSavedPeer(discoveryKey, { deviceName, platform })
        this._emitSavedPeers()

        this._emit(CMD_PEER_CONNECTED, { noiseKey: noiseKeyHex, discoveryKey, deviceName, platform })
        break
      }

      case 'fileOffer': {
        const info = this.transfers.onOffer(msg, conn, noiseKeyHex)
        this._emit(CMD_TRANSFER_STARTED, { ...info, direction: 'receiving' })
        break
      }

      case 'fileAccept':
        this.transfers.onAccept(msg.transferId, conn)
        break

      case 'fileChunk':
        this.transfers.onChunk(msg)
        break

      case 'fileComplete':
        this.transfers.onComplete(msg)
        break
    }
  }

  // ─── File sending (public, called via RPC) ────────────────────────────────

  async _sendFile (filePath, discoveryKey) {
    const peer = this._liveConnForDiscoveryKey(discoveryKey)
    if (!peer) throw new Error('Peer not connected: ' + discoveryKey)
    this.transfers.offer(filePath, peer.conn)
  }

  _liveConnForDiscoveryKey (discoveryKey) {
    for (const peer of this.peers.values()) {
      if (peer.discoveryKey === discoveryKey) return peer
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
