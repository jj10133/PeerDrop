const crypto = require('hypercore-crypto')
const fs     = require('bare-fs')
const path   = require('bare-path')

const {
  CMD_TRANSFER_STARTED,
  CMD_TRANSFER_PROGRESS,
  CMD_TRANSFER_COMPLETE,
  CMD_ERROR
} = require('./commands')

// 1 MB chunks — large enough to amortise per-chunk overhead,
// small enough to give smooth progress on any file size.
const CHUNK_SIZE = 1024 * 1024

// Minimum ms between progress events emitted to Swift.
// Prevents flooding the UI on fast local transfers.
const PROGRESS_THROTTLE_MS = 100

class TransferManager {
  constructor (emit, getDownloadPath) {
    this._emit            = emit
    this._getDownloadPath = getDownloadPath
    this._transfers       = new Map()
  }

  // ─── Sending ───────────────────────────────────────────────────────────────

  offer (filePath, conn, noiseKey) {
    const stats      = fs.statSync(filePath)
    const transferId = crypto.randomBytes(16).toString('hex')
    const fileName   = path.basename(filePath)

    conn.write(JSON.stringify({
      type:        'fileOffer',
      transferId,
      fileName,
      fileSize:    stats.size,
      isDirectory: stats.isDirectory()
    }) + '\n')

    this._transfers.set(transferId, {
      transferId, filePath, fileName,
      fileSize: stats.size,
      sent:     0,
      conn,
      lastProgressAt: 0
    })

    // Notify Swift so the sending transfer appears in the active transfers UI
    this._emit(CMD_TRANSFER_STARTED, {
      transferId,
      peerId:   noiseKey || '',  // noiseKey of the remote peer — same as receiver uses
      fileName,
      fileSize: stats.size,
      direction: 'sending'
    })

    return transferId
  }

  onAccept (transferId, conn) {
    const transfer = this._transfers.get(transferId)
    if (!transfer) return
    this._stream(transfer, conn)
  }

  _stream (transfer, conn) {
    const stream = fs.createReadStream(transfer.filePath, {
      highWaterMark: CHUNK_SIZE
    })

    // Backpressure: pause reading when the connection buffer is full.
    // This prevents unbounded memory growth for large files.
    stream.on('data', (chunk) => {
      const msg = JSON.stringify({
        type:       'fileChunk',
        transferId: transfer.transferId,
        data:       chunk.toString('base64')
      }) + '\n'

      const ok = conn.write(msg)

      transfer.sent += chunk.length
      this._emitProgress(transfer)

      if (!ok) {
        // Pause reading until the connection drains
        stream.pause()
        conn.once('drain', () => stream.resume())
      }
    })

    stream.on('end', () => {
      conn.write(JSON.stringify({
        type:       'fileComplete',
        transferId: transfer.transferId
      }) + '\n')

      this._emitProgress(transfer, true) // force final 100%
      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId: transfer.transferId,
        direction:  'sending'
      })
      this._transfers.delete(transfer.transferId)
    })

    stream.on('error', (err) => {
      this._emitError(transfer.transferId, err.message)
      this._transfers.delete(transfer.transferId)
    })
  }

  // ─── Receiving ─────────────────────────────────────────────────────────────

  onOffer (msg, conn, senderNoiseKey) {
    const { transferId, fileName, fileSize } = msg
    const downloadPath = this._getDownloadPath()

    try { fs.mkdirSync(downloadPath, { recursive: true }) } catch (e) {}

    // Resolve a unique destination path — never silently overwrite
    const destPath = this._uniquePath(downloadPath, fileName)

    // Open a write stream immediately — chunks go straight to disk, no RAM buffer
    let writeStream
    let writeError = null
    try {
      writeStream = fs.createWriteStream(destPath)
    } catch (err) {
      this._emitError(transferId, 'Cannot open destination: ' + err.message)
      return { transferId, fileName, fileSize, peerId: senderNoiseKey }
    }

    writeStream.on('error', (err) => {
      writeError = err
      this._emitError(transferId, 'Write error: ' + err.message)
      this._transfers.delete(transferId)
    })

    this._transfers.set(transferId, {
      transferId,
      destPath,
      peerId: senderNoiseKey,
      fileName,
      fileSize,
      received:       0,
      writeStream,
      writeError,
      lastProgressAt: 0
    })

    conn.write(JSON.stringify({ type: 'fileAccept', transferId }) + '\n')

    return { transferId, fileName, fileSize, peerId: senderNoiseKey }
  }

  onChunk (msg) {
    const transfer = this._transfers.get(msg.transferId)
    if (!transfer || transfer.writeError) return

    const chunk = Buffer.from(msg.data, 'base64')

    // Write to disk — if the write stream signals backpressure we just let it
    // buffer internally (write stream has its own highWaterMark queue).
    // For very high throughput you'd pause the conn here too, but for our
    // use case (local network, single transfer) this is sufficient.
    transfer.writeStream.write(chunk)

    transfer.received += chunk.length
    this._emitProgress(transfer)
  }

  onComplete (msg) {
    const transfer = this._transfers.get(msg.transferId)
    if (!transfer) return

    // End the write stream — flushes buffered data and closes the fd.
    // Use the 'finish' event rather than an .end() callback — bare-stream
    // Writables emit 'finish' reliably but may not support a callback arg.
    transfer.writeStream.once('finish', () => {
      if (transfer.writeError) return // already reported

      this._emitProgress(transfer, true) // force final 100%
      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId: msg.transferId,
        direction:  'received',
        filePath:   transfer.destPath,
        fileName:   transfer.fileName
      })
      this._transfers.delete(msg.transferId)
    })
    transfer.writeStream.end()
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  // Throttled progress — emits at most once per PROGRESS_THROTTLE_MS,
  // plus always emits when forced (start/end).
  _emitProgress (transfer, force = false) {
    const now = Date.now()
    if (!force && now - transfer.lastProgressAt < PROGRESS_THROTTLE_MS) return
    transfer.lastProgressAt = now

    const total    = transfer.fileSize || 1
    const done     = transfer.sent ?? transfer.received ?? 0
    const progress = Math.min(done / total, 1)

    this._emit(CMD_TRANSFER_PROGRESS, {
      transferId: transfer.transferId,
      progress
    })
  }

  _emitError (transferId, message) {
    this._emit(CMD_ERROR, { transferId, message })
  }

  // Returns a path that doesn't already exist.
  // "photo.jpg" → "photo (2).jpg" → "photo (3).jpg" etc.
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

  _fileExists (filePath) {
    try { fs.statSync(filePath); return true } catch (e) { return false }
  }
}

module.exports = TransferManager
