const Hyperswarm   = require('hyperswarm')
const os           = require('bare-os')
const RPC          = require('bare-rpc')

const cmds            = require('./commands')
const store           = require('./store')
const TransferManager = require('./transfers')

const {
  CMD_READY, CMD_PEER_CONNECTED, CMD_PEER_DISCONNECTED,
  CMD_SAVED_PEERS, CMD_ERROR,
  CMD_SEND_FILE, CMD_CONNECT_PEER, CMD_SET_DOWNLOAD_PATH,
  CMD_FORGET_PEER, CMD_RENAME_PEER,
  CMD_TRANSFER_STARTED
} = cmds

class PeerDrop {
  constructor () {
    this.swarm              = null
    this.discoveryPublicKey = null  // this device's Peer ID and Hyperswarm topic

    // noiseKeyHex → { conn, discoveryKey, hostname, platform }
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
    const { discoveryPublicKey } = await store.loadIdentity()
    this.discoveryPublicKey = discoveryPublicKey

    this.swarm = new Hyperswarm()
    this.swarm.on('connection', (conn, info) => this._onConnection(conn, info))

    // Announce so others can find us by joining our discoveryPublicKey as client
    this.swarm.join(this.discoveryPublicKey, { server: true, client: false })

    // Reconnect to all saved peers from previous sessions
    for (const peer of store.loadSavedPeers()) {
      this._joinTopic(peer.discoveryKey)
    }

    this._emit(CMD_READY, {
      peerID:       this.discoveryPublicKey.toString('hex'),
      downloadPath: store.getDownloadPath()
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

      case CMD_RENAME_PEER:
        store.renamePeer(body.peerDiscoveryKey, body.displayName)
        this._emitSavedPeers()
        reply()
        break

      default: reply()
    }
  }

  // ─── Peer management ─────────────────────────────────────────────────────

  async _connectToPeer (discoveryKeyHex) {
    if (!/^[0-9a-f]{64}$/i.test(discoveryKeyHex)) {
      throw new Error('Invalid Peer ID — must be a 64-character hex string')
    }
    // Save immediately so it persists even before they connect
    store.upsertSavedPeer(discoveryKeyHex)
    this._joinTopic(discoveryKeyHex)
    this._emitSavedPeers()
  }

  _forgetPeer (discoveryKeyHex) {
    try { this.swarm.leave(Buffer.from(discoveryKeyHex, 'hex')) } catch (e) {}
    store.removeSavedPeer(discoveryKeyHex)
    this._emitSavedPeers()
  }

  _joinTopic (hex) {
    this.swarm.join(Buffer.from(hex, 'hex'), { server: false, client: true })
  }

  // ─── Connection handling ──────────────────────────────────────────────────

  _onConnection (conn, info) {
    const noiseKeyHex = info.publicKey.toString('hex')

    conn.write(JSON.stringify({
      type:         'handshake',
      discoveryKey: this.discoveryPublicKey.toString('hex'),
      hostname:     os.hostname(),
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
        const { discoveryKey, hostname, platform } = msg

        this.peers.set(noiseKeyHex, {
          conn, discoveryKey, hostname, platform, lastSeen: Date.now()
        })

        // Update hostname/platform — never overwrite user-set displayName
        store.upsertSavedPeer(discoveryKey, {
          hostname, platform, lastSeen: Date.now()
        })

        this._emitSavedPeers()
        this._emit(CMD_PEER_CONNECTED, {
          noiseKey: noiseKeyHex, discoveryKey, hostname, platform
        })
        break
      }

      case 'fileOffer': {
        const info = this.transfers.onOffer(msg, conn, noiseKeyHex)
        this._emit(CMD_TRANSFER_STARTED, { ...info, direction: 'receiving' })
        break
      }

      case 'fileAccept':   this.transfers.onAccept(msg.transferId, conn); break
      case 'fileChunk':    this.transfers.onChunk(msg);                   break
      case 'fileComplete': this.transfers.onComplete(msg);                break
    }
  }

  // ─── File sending ─────────────────────────────────────────────────────────

  async _sendFile (filePath, discoveryKey) {
    const { peer, noiseKey } = this._liveConn(discoveryKey)
    if (!peer) throw new Error('Peer not connected: ' + discoveryKey)
    this.transfers.offer(filePath, peer.conn, noiseKey)
  }

  _liveConn (discoveryKey) {
    for (const [noiseKey, peer] of this.peers.entries()) {
      if (peer.discoveryKey === discoveryKey) return { peer, noiseKey }
    }
    return { peer: null, noiseKey: null }
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
