// transfers.js — File transfer engine.
//
// Single Responsibility breakdown:
//   TransferManager   — coordinates send/receive, owns the transfer map
//   _streamFile()     — sender: reads file → chunks → connection (with backpressure)
//   _openReceiver()   — receiver: opens write stream to disk immediately
//   _emitProgress()   — throttled progress reporting to Swift
//
// Key design decisions:
//   • Receiver writes chunks directly to disk — never buffers in RAM.
//   • Sender pauses the read stream when conn.write() signals back-pressure.
//   • CMD_TRANSFER_STARTED is emitted for BOTH sender and receiver so the UI
//     shows outgoing transfers too.
//   • writeStream completion uses the 'finish' event (not an .end() callback)
//     because bare-fs WriteStreams emit 'finish' but may not honour a callback arg.

const crypto = require('hypercore-crypto')
const fs     = require('bare-fs')
const path   = require('bare-path')

const {
  CMD_TRANSFER_STARTED,
  CMD_TRANSFER_PROGRESS,
  CMD_TRANSFER_COMPLETE,
  CMD_ERROR
} = require('./commands')

const CHUNK_SIZE          = 1024 * 1024  // 1 MB — good balance of throughput vs granularity
const PROGRESS_THROTTLE   = 100          // ms between progress UI updates

class TransferManager {
  constructor (emit, getDownloadPath) {
    this._emit            = emit
    this._getDownloadPath = getDownloadPath
    this._active          = new Map()  // transferId → transfer state
  }

  // ── Sending ────────────────────────────────────────────────────────────────

  // Called by app.js when the user drops a file. noiseKey identifies the peer
  // so DevicePanelView can filter transfers to the right panel.
  offer (filePath, conn, noiseKey) {
    const stats      = fs.statSync(filePath)
    const transferId = crypto.randomBytes(16).toString('hex')
    const fileName   = path.basename(filePath)
    const fileSize   = stats.size

    // Tell the remote peer a file is coming
    conn.write(JSON.stringify({
      type: 'fileOffer', transferId, fileName, fileSize,
      isDirectory: stats.isDirectory()
    }) + '\n')

    this._active.set(transferId, {
      transferId, filePath, fileName, fileSize,
      sent: 0, conn, noiseKey, lastProgressAt: 0
    })

    // Notify Swift so the outgoing transfer appears in the UI immediately
    this._emit(CMD_TRANSFER_STARTED, {
      transferId, fileName, fileSize,
      peerId:    noiseKey,
      direction: 'sending'
    })
  }

  // Remote accepted — start streaming
  onAccept (transferId, conn) {
    const t = this._active.get(transferId)
    if (t) this._streamFile(t, conn)
  }

  _streamFile (transfer, conn) {
    const stream = fs.createReadStream(transfer.filePath, { highWaterMark: CHUNK_SIZE })

    stream.on('data', (chunk) => {
      const ok = conn.write(
        JSON.stringify({
          type: 'fileChunk',
          transferId: transfer.transferId,
          data: chunk.toString('base64')
        }) + '\n'
      )

      transfer.sent += chunk.length
      this._emitProgress(transfer)

      // Back-pressure: stop reading until the socket drains
      if (!ok) {
        stream.pause()
        conn.once('drain', () => stream.resume())
      }
    })

    stream.on('end', () => {
      conn.write(JSON.stringify({ type: 'fileComplete', transferId: transfer.transferId }) + '\n')
      this._emitProgress(transfer, true)  // force 100%
      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId: transfer.transferId,
        direction:  'sending'
      })
      this._active.delete(transfer.transferId)
    })

    stream.on('error', (err) => {
      this._emitError(transfer.transferId, err.message)
      this._active.delete(transfer.transferId)
    })
  }

  // ── Receiving ──────────────────────────────────────────────────────────────

  onOffer (msg, conn, senderNoiseKey) {
    const { transferId, fileName, fileSize } = msg
    const downloadPath = this._getDownloadPath()

    try { fs.mkdirSync(downloadPath, { recursive: true }) } catch (_) {}

    const destPath   = this._uniquePath(downloadPath, fileName)
    const writeStream = this._openWriteStream(transferId, destPath)

    if (!writeStream) {
      return { transferId, fileName, fileSize, peerId: senderNoiseKey }
    }

    this._active.set(transferId, {
      transferId, destPath, fileName, fileSize,
      peerId: senderNoiseKey,
      received: 0,
      writeStream,
      lastProgressAt: 0
    })

    conn.write(JSON.stringify({ type: 'fileAccept', transferId }) + '\n')

    return { transferId, fileName, fileSize, peerId: senderNoiseKey }
  }

  onChunk (msg) {
    const t = this._active.get(msg.transferId)
    if (!t || !t.writeStream) return

    const chunk = Buffer.from(msg.data, 'base64')
    t.writeStream.write(chunk)
    t.received += chunk.length
    this._emitProgress(t)
  }

  onComplete (msg) {
    const t = this._active.get(msg.transferId)
    if (!t || !t.writeStream) return

    // 'finish' is the reliable completion signal in bare-fs WriteStreams.
    // The .end(callback) form may not fire the callback in all bare-fs versions.
    t.writeStream.once('finish', () => {
      this._emitProgress(t, true)  // force 100%
      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId: msg.transferId,
        direction:  'received',
        filePath:   t.destPath,
        fileName:   t.fileName
      })
      this._active.delete(msg.transferId)
    })

    t.writeStream.end()
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  _openWriteStream (transferId, destPath) {
    try {
      const ws = fs.createWriteStream(destPath)
      ws.on('error', (err) => {
        this._emitError(transferId, 'Write error: ' + err.message)
        this._active.delete(transferId)
      })
      return ws
    } catch (err) {
      this._emitError(transferId, 'Cannot open destination: ' + err.message)
      return null
    }
  }

  // Throttled — emits at most once per PROGRESS_THROTTLE ms.
  // Pass force=true to always emit (used at start/end of transfer).
  _emitProgress (transfer, force = false) {
    const now = Date.now()
    if (!force && now - transfer.lastProgressAt < PROGRESS_THROTTLE) return
    transfer.lastProgressAt = now

    const total    = transfer.fileSize || 1
    const done     = transfer.sent ?? transfer.received ?? 0
    const progress = Math.min(done / total, 1)

    this._emit(CMD_TRANSFER_PROGRESS, { transferId: transfer.transferId, progress })
  }

  _emitError (transferId, message) {
    this._emit(CMD_ERROR, { transferId, message })
  }

  // Avoids silent overwrites: "file.jpg" → "file (2).jpg" → "file (3).jpg"
  _uniquePath (dir, fileName) {
    const ext  = path.extname(fileName)
    const base = path.basename(fileName, ext)
    let   dest = path.join(dir, fileName)
    let   n    = 2

    while (this._fileExists(dest)) {
      dest = path.join(dir, `${base} (${n})${ext}`)
      n++
    }
    return dest
  }

  _fileExists (p) {
    try { fs.statSync(p); return true } catch (_) { return false }
  }
}

module.exports = TransferManager
