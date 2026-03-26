// transfers.js — File transfer engine supporting single files and directories.
//
// Directory protocol (batch):
//   Sender → batchStart { batchId, dirName, fileCount, totalSize }
//   Sender → fileOffer  { ..., batchId, relativePath }  ← one per file, sequential
//   Sender → fileChunk  (repeated)
//   Sender → fileComplete
//   ... repeat fileOffer/fileChunk/fileComplete for each file ...
//   Sender → batchComplete { batchId }
//
//   Files are sent ONE AT A TIME (sequential) — the next file is offered only
//   after the current file's stream.on('end') fires. This keeps backpressure
//   simple and ensures the receiver can always keep up.

const crypto = require('hypercore-crypto')
const fs     = require('bare-fs')
const path   = require('bare-path')

const {
  CMD_TRANSFER_STARTED,
  CMD_TRANSFER_PROGRESS,
  CMD_TRANSFER_COMPLETE,
  CMD_ERROR
} = require('./commands')

const CHUNK_SIZE        = 1024 * 1024  // 1 MB chunks
const PROGRESS_THROTTLE = 100          // ms between UI progress events

class TransferManager {
  constructor (emit, getDownloadPath) {
    this._emit            = emit
    this._getDownloadPath = getDownloadPath
    this._active          = new Map()  // transferId  → individual file state
    this._batches         = new Map()  // batchId     → directory batch state
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  offer (filePath, conn, noiseKey) {
    const stats = fs.statSync(filePath)
    if (stats.isDirectory()) {
      this._offerDirectory(filePath, conn, noiseKey)
    } else {
      this._offerSingleFile(filePath, conn, noiseKey)
    }
  }

  onAccept (transferId, conn) {
    const t = this._active.get(transferId)
    if (t) this._streamFile(t, conn)
  }

  onChunk (msg) {
    const t = this._active.get(msg.transferId)
    if (!t?.writeStream) return

    const chunk = Buffer.from(msg.data, 'base64')
    t.writeStream.write(chunk)
    t.received += chunk.length
    this._trackReceiveProgress(t)
  }

  onComplete (msg) {
    const t = this._active.get(msg.transferId)
    if (!t?.writeStream) return

    t.writeStream.once('finish', () => {
      if (t.batchId) {
        this._onBatchFileReceived(t)
      } else {
        // Standalone file — emit completion
        this._emitFileProgress(t, true)
        this._emit(CMD_TRANSFER_COMPLETE, {
          transferId: t.transferId,
          direction:  'received',
          filePath:   t.destPath,
          fileName:   t.fileName
        })
      }
      this._active.delete(t.transferId)
    })

    t.writeStream.end()
  }

  onBatchStart (msg) {
    const { batchId, dirName, fileCount, totalSize } = msg
    const downloadPath = this._getDownloadPath()
    const destDir = this._uniquePath(downloadPath, dirName)
    try { fs.mkdirSync(destDir, { recursive: true }) } catch (_) {}

    this._batches.set(batchId, {
      batchId, destDir, dirName,
      fileCount, totalSize,
      filesReceived: 0,
      bytesReceived: 0,
      lastProgressAt: 0
    })
  }

  onBatchComplete (msg) {
    const batch = this._batches.get(msg.batchId)
    if (!batch) return

    this._emit(CMD_TRANSFER_PROGRESS, { transferId: msg.batchId, progress: 1 })
    this._emit(CMD_TRANSFER_COMPLETE, {
      transferId:  msg.batchId,
      direction:   'received',
      filePath:    batch.destDir,
      fileName:    batch.dirName,
      isDirectory: true
    })
    this._batches.delete(msg.batchId)
  }

  onOffer (msg, conn, senderNoiseKey) {
    const { transferId, fileName, fileSize, batchId, relativePath } = msg
    const downloadPath = this._getDownloadPath()
    let destPath

    if (batchId) {
      const batch = this._batches.get(batchId)
      if (batch) {
        destPath = path.join(batch.destDir, relativePath)
        try { fs.mkdirSync(path.dirname(destPath), { recursive: true }) } catch (_) {}
      } else {
        try { fs.mkdirSync(downloadPath, { recursive: true }) } catch (_) {}
        destPath = this._uniquePath(downloadPath, fileName)
      }
    } else {
      try { fs.mkdirSync(downloadPath, { recursive: true }) } catch (_) {}
      destPath = this._uniquePath(downloadPath, fileName)
    }

    const writeStream = this._openWriteStream(transferId, destPath)
    if (!writeStream) return { transferId, fileName, fileSize, peerId: senderNoiseKey }

    this._active.set(transferId, {
      transferId, destPath, fileName, fileSize,
      peerId: senderNoiseKey,
      received: 0, batchId,
      writeStream, lastProgressAt: 0
    })

    conn.write(JSON.stringify({ type: 'fileAccept', transferId }) + '\n')

    // Return value signals app.js whether to emit CMD_TRANSFER_STARTED.
    // Batch files: null (batch already started). Standalone: the info object.
    return batchId ? null : { transferId, fileName, fileSize, peerId: senderNoiseKey }
  }

  // ── Sender — single file ───────────────────────────────────────────────────

  _offerSingleFile (filePath, conn, noiseKey, batchId = null, relativePath = null) {
    const transferId = crypto.randomBytes(16).toString('hex')
    const fileName   = path.basename(relativePath ?? filePath)
    const fileSize   = fs.statSync(filePath).size

    conn.write(JSON.stringify({
      type: 'fileOffer', transferId, fileName, fileSize,
      isDirectory: false, batchId, relativePath
    }) + '\n')

    this._active.set(transferId, {
      transferId, filePath, fileName, fileSize,
      sent: 0, conn, noiseKey, batchId,
      lastProgressAt: 0
    })

    if (!batchId) {
      this._emit(CMD_TRANSFER_STARTED, {
        transferId, fileName, fileSize,
        peerId: noiseKey, direction: 'sending', isDirectory: false
      })
    }

    return transferId
  }

  // ── Sender — directory ─────────────────────────────────────────────────────

  _offerDirectory (dirPath, conn, noiseKey) {
    const batchId   = crypto.randomBytes(16).toString('hex')
    const dirName   = path.basename(dirPath)
    const files     = this._walkDir(dirPath)
    const totalSize = files.reduce((s, f) => s + f.size, 0)

    if (files.length === 0) {
      // Empty directory — nothing to stream
      conn.write(JSON.stringify({ type: 'batchStart', batchId, dirName, fileCount: 0, totalSize: 0 }) + '\n')
      conn.write(JSON.stringify({ type: 'batchComplete', batchId }) + '\n')
      this._emit(CMD_TRANSFER_STARTED,  { transferId: batchId, fileName: dirName, fileSize: 0, fileCount: 0, peerId: noiseKey, direction: 'sending', isDirectory: true })
      this._emit(CMD_TRANSFER_COMPLETE, { transferId: batchId, direction: 'sending', isDirectory: true })
      return
    }

    this._batches.set(batchId, {
      batchId, dirName, totalSize,
      fileCount: files.length, filesSent: 0,
      totalBytesSent: 0,
      files,            // full list kept for sequential dispatch
      currentIndex: 0,  // index of the file currently being offered
      conn, noiseKey,
      lastProgressAt: 0
    })

    conn.write(JSON.stringify({ type: 'batchStart', batchId, dirName, fileCount: files.length, totalSize }) + '\n')

    this._emit(CMD_TRANSFER_STARTED, {
      transferId: batchId, fileName: dirName, fileSize: totalSize,
      fileCount: files.length, peerId: noiseKey, direction: 'sending', isDirectory: true
    })

    // Offer the first file — subsequent files offered one by one in _onBatchFileSent
    this._offerNextBatchFile(batchId)
  }

  // Offer the next file in the batch (called after previous file finishes streaming)
  _offerNextBatchFile (batchId) {
    const batch = this._batches.get(batchId)
    if (!batch) return

    if (batch.currentIndex >= batch.files.length) return  // all offered

    const { fullPath, relativePath } = batch.files[batch.currentIndex]
    batch.currentIndex++
    this._offerSingleFile(fullPath, batch.conn, batch.noiseKey, batchId, relativePath)
  }

  _streamFile (transfer, conn) {
    const stream = fs.createReadStream(transfer.filePath, { highWaterMark: CHUNK_SIZE })

    stream.on('data', (chunk) => {
      const ok = conn.write(JSON.stringify({
        type: 'fileChunk', transferId: transfer.transferId,
        data: chunk.toString('base64')
      }) + '\n')

      transfer.sent += chunk.length
      this._trackSendProgress(transfer)

      if (!ok) {
        stream.pause()
        conn.once('drain', () => stream.resume())
      }
    })

    stream.on('end', () => {
      conn.write(JSON.stringify({ type: 'fileComplete', transferId: transfer.transferId }) + '\n')

      if (!transfer.batchId) {
        // Standalone file — done
        this._emitFileProgress(transfer, true)
        this._emit(CMD_TRANSFER_COMPLETE, { transferId: transfer.transferId, direction: 'sending' })
        this._active.delete(transfer.transferId)
      } else {
        // Batch file — advance the batch
        this._onBatchFileSent(transfer.transferId)
      }
    })

    stream.on('error', (err) => {
      this._emitError(transfer.batchId ?? transfer.transferId, err.message)
      this._active.delete(transfer.transferId)
    })
  }

  // Called when a batch file finishes streaming (sender side)
  _onBatchFileSent (transferId) {
    const transfer = this._active.get(transferId)
    if (!transfer?.batchId) return

    const batch = this._batches.get(transfer.batchId)
    if (!batch) return

    batch.filesSent++
    batch.totalBytesSent += transfer.fileSize
    this._active.delete(transferId)

    // Emit accurate progress based on completed files
    const progress = Math.min(batch.totalBytesSent / (batch.totalSize || 1), 0.99)
    this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })

    if (batch.filesSent >= batch.fileCount) {
      // All files sent — close out the batch
      batch.conn.write(JSON.stringify({ type: 'batchComplete', batchId: batch.batchId }) + '\n')
      this._emit(CMD_TRANSFER_PROGRESS,  { transferId: batch.batchId, progress: 1 })
      this._emit(CMD_TRANSFER_COMPLETE,  { transferId: batch.batchId, direction: 'sending', isDirectory: true })
      this._batches.delete(batch.batchId)
    } else {
      // Offer the next file
      this._offerNextBatchFile(transfer.batchId)
    }
  }

  // ── Receiver — progress tracking ───────────────────────────────────────────

  _onBatchFileReceived (t) {
    const batch = this._batches.get(t.batchId)
    if (!batch) return

    batch.filesReceived++
    const progress = Math.min(batch.filesReceived / batch.fileCount, 0.99)
    this._emit(CMD_TRANSFER_PROGRESS, { transferId: t.batchId, progress })
  }

  _trackReceiveProgress (t) {
    if (t.batchId) {
      const batch = this._batches.get(t.batchId)
      if (batch) {
        batch.bytesReceived += CHUNK_SIZE
        const progress = Math.min(batch.bytesReceived / (batch.totalSize || 1), 0.98)
        const now = Date.now()
        if (now - batch.lastProgressAt >= PROGRESS_THROTTLE) {
          batch.lastProgressAt = now
          this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
        }
      }
    } else {
      this._emitFileProgress(t)
    }
  }

  _trackSendProgress (transfer) {
    if (transfer.batchId) {
      const batch = this._batches.get(transfer.batchId)
      if (batch) {
        // Use actual bytes sent (transfer.sent), not the constant CHUNK_SIZE
        const completedBytes = batch.totalBytesSent
        const inFlightBytes  = transfer.sent
        const progress = Math.min((completedBytes + inFlightBytes) / (batch.totalSize || 1), 0.99)
        const now = Date.now()
        if (now - batch.lastProgressAt >= PROGRESS_THROTTLE) {
          batch.lastProgressAt = now
          this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
        }
      }
    } else {
      this._emitFileProgress(transfer)
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  _emitFileProgress (transfer, force = false) {
    const now = Date.now()
    if (!force && now - transfer.lastProgressAt < PROGRESS_THROTTLE) return
    transfer.lastProgressAt = now
    const total = transfer.fileSize || 1
    const done  = transfer.sent ?? transfer.received ?? 0
    this._emit(CMD_TRANSFER_PROGRESS, {
      transferId: transfer.transferId,
      progress:   Math.min(done / total, 1)
    })
  }

  _openWriteStream (transferId, destPath) {
    try {
      const ws = fs.createWriteStream(destPath)
      ws.on('error', (err) => {
        this._emitError(transferId, 'Write error: ' + err.message)
        this._active.delete(transferId)
      })
      return ws
    } catch (err) {
      this._emitError(transferId, 'Cannot open: ' + err.message)
      return null
    }
  }

  _emitError (transferId, message) {
    this._emit(CMD_ERROR, { transferId, message })
  }

  // Walk directory tree, skip hidden files and macOS metadata
  _walkDir (dirPath) {
    const results = []
    const base    = path.dirname(dirPath)

    const walk = (dir) => {
      let entries
      try { entries = fs.readdirSync(dir) } catch (_) { return }

      for (const entry of entries) {
        if (entry.startsWith('.')) continue  // skip .DS_Store etc

        const full = path.join(dir, entry)
        let stat
        try { stat = fs.statSync(full) } catch (_) { continue }

        if (stat.isDirectory()) {
          walk(full)
        } else {
          results.push({
            fullPath:     full,
            relativePath: path.relative(base, full),
            size:         stat.size
          })
        }
      }
    }

    walk(dirPath)
    return results
  }

  _uniquePath (dir, name) {
    const ext  = path.extname(name)
    const base = path.basename(name, ext)
    let   dest = path.join(dir, name)
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
