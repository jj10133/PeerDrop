// app.js — PeerDrop orchestrator with protomux multiplexing.
//
// Each Hyperswarm connection runs two channel types over one Protomux:
//
//   'peerdrop/control'                   — one per connection, JSON signalling
//   'peerdrop/transfer'  id=transferId   — one per file, raw binary data
//
// The receiver pre-registers mux.pair('peerdrop/transfer') on every connection.
// When the sender opens a transfer channel, the pair handler fires synchronously
// and opens the matching receiver channel before any data arrives.
// This eliminates the race condition where the incoming open would be rejected.
//
// fileAccept is no longer needed — channel pairing IS the accept signal.

const Hyperswarm = require('hyperswarm')
const Protomux   = require('protomux')
const c          = require('compact-encoding')
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
    // noiseKeyHex → { mux, controlCh, discoveryKey, displayName, platform, isOwnDevice }
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
    this.swarm.join(this.discoveryPublicKey, { server: true, client: true })

    for (const peer of store.loadSavedPeers()) this._joinTopic(peer.discoveryKey)

    this._emit(CMD_READY, {
      peerID:       this.discoveryPublicKey.toString('hex'),
      downloadPath: store.getDownloadPath()
    })
    this._emitSavedPeers()
  }

  // ── Swift → JS ───────────────────────────────────────────────────────────────

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
      default: reply()
    }
  }

  // ── Peer management ──────────────────────────────────────────────────────────

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

  // ── Connection setup ─────────────────────────────────────────────────────────

  _onConnection (conn, info) {
    const noiseKeyHex = info.publicKey.toString('hex')
    const mux         = new Protomux(conn)

    // Pre-register the transfer channel handler on this mux.
    // This MUST be called before any transfer channels are opened by the remote.
    // The notify callback fires synchronously when an incoming transfer channel
    // arrives, so we open the matching rxCh before protomux can reject it.
    this.transfers.pairTransferChannels(mux, noiseKeyHex)

    this.peers.set(noiseKeyHex, {
      mux, controlCh: null,
      discoveryKey: null, displayName: null, platform: null, isOwnDevice: false
    })

    const controlCh = mux.createChannel({
      protocol: 'peerdrop/control',
      messages: [
        {
          encoding:  c.json,
          onmessage: (msg) => this._onControlMessage(mux, noiseKeyHex, msg)
        }
      ],
      onopen: () => {
        controlCh.messages[0].send({
          type:         'handshake',
          discoveryKey: this.discoveryPublicKey.toString('hex'),
          displayName:  os.hostname(),
          platform:     os.platform()
        })
      },
      onclose: () => {
        const peer = this.peers.get(noiseKeyHex)
        this.peers.delete(noiseKeyHex)
        this._emit(CMD_PEER_DISCONNECTED, {
          noiseKey:     noiseKeyHex,
          discoveryKey: peer?.discoveryKey ?? null
        })
      }
    })

    this.peers.get(noiseKeyHex).controlCh = controlCh
    controlCh.open()

    conn.on('error', (err) => console.error('Connection error:', err.message))
  }

  // ── Control message router ───────────────────────────────────────────────────

  _onControlMessage (mux, noiseKeyHex, msg) {
    switch (msg.type) {

      case 'handshake': {
        const { discoveryKey, displayName, platform } = msg
        const isOwnDevice = discoveryKey === this.discoveryPublicKey.toString('hex')
        const peer = this.peers.get(noiseKeyHex)
        if (peer) {
          peer.discoveryKey = discoveryKey
          peer.displayName  = displayName
          peer.platform     = platform
          peer.isOwnDevice  = isOwnDevice
        }
        if (!isOwnDevice) {
          store.upsertSavedPeer(discoveryKey, { displayName, platform, lastSeen: Date.now() })
          this._emitSavedPeers()
        }
        this._emit(CMD_PEER_CONNECTED, {
          noiseKey: noiseKeyHex, discoveryKey, displayName, platform, isOwnDevice
        })
        break
      }

      case 'batchStart': {
        this.transfers.onBatchStart(msg, noiseKeyHex)
        this._emit(CMD_TRANSFER_STARTED, {
          transferId:  msg.batchId,
          fileName:    msg.dirName,
          fileSize:    msg.totalSize,
          fileCount:   msg.fileCount,
          peerId:      noiseKeyHex,
          direction:   'receiving',
          isDirectory: true
        })
        break
      }

      case 'fileOffer': {
        // Register the offer so that when pairTransferChannels' notify fires,
        // it can attach the write stream to the already-opened rxCh.
        const info = this.transfers.onOffer(msg, noiseKeyHex)
        if (info) {
          this._emit(CMD_TRANSFER_STARTED, {
            ...info,
            direction:   'receiving',
            isDirectory: false,
            fileCount:   0
          })
        }
        break
      }

      case 'batchComplete':
        this.transfers.onBatchComplete(msg)
        break
    }
  }

  // ── Sending ──────────────────────────────────────────────────────────────────

  async _sendFile (filePath, discoveryKey) {
    const peer = this._livePeer(discoveryKey)
    if (!peer) throw new Error('Peer not connected: ' + discoveryKey)
    this.transfers.offer(filePath, peer.mux, peer.controlCh, peer.noiseKey)
  }

  _livePeer (discoveryKey) {
    for (const [noiseKey, peer] of this.peers.entries()) {
      if (peer.discoveryKey === discoveryKey) return { ...peer, noiseKey }
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
