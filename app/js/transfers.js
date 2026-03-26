// transfers.js — File transfer engine supporting both single files and directories.
//
// Directory transfer protocol (batch):
//   1. Sender walks the directory tree → collects { fullPath, relativePath, size }
//   2. One CMD_TRANSFER_STARTED emitted for the whole batch (totalSize, fileCount)
//   3. Each file sent as a normal fileOffer/fileChunk/fileComplete sequence,
//      tagged with { batchId, relativePath } so the receiver recreates the tree
//   4. After all files: sender sends batchComplete → receiver emits CMD_TRANSFER_COMPLETE
//
// Single file transfers are unchanged — batchId/relativePath absent means plain file.

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
const PROGRESS_THROTTLE = 100          // ms between UI progress updates

class TransferManager {
  constructor (emit, getDownloadPath) {
    this._emit            = emit
    this._getDownloadPath = getDownloadPath
    this._active          = new Map()  // transferId → transfer state
    this._batches         = new Map()  // batchId → batch state
  }

  // ── Sending ────────────────────────────────────────────────────────────────

  offer (filePath, conn, noiseKey) {
    const stats = fs.statSync(filePath)

    if (stats.isDirectory()) {
      this._offerDirectory(filePath, conn, noiseKey)
    } else {
      this._offerFile(filePath, conn, noiseKey)
    }
  }

  // Single file
  _offerFile (filePath, conn, noiseKey, batchId = null, relativePath = null) {
    const transferId = crypto.randomBytes(16).toString('hex')
    const fileName   = relativePath ? path.basename(relativePath) : path.basename(filePath)
    const fileSize   = fs.statSync(filePath).size

    conn.write(JSON.stringify({
      type: 'fileOffer', transferId, fileName, fileSize,
      isDirectory: false,
      batchId,
      relativePath  // null for single files, e.g. "src/utils/helper.js" for batches
    }) + '\n')

    this._active.set(transferId, {
      transferId, filePath, fileName, fileSize,
      sent: 0, conn, noiseKey,
      batchId, lastProgressAt: 0
    })

    // Only emit CMD_TRANSFER_STARTED for standalone files (batches emit their own)
    if (!batchId) {
      this._emit(CMD_TRANSFER_STARTED, {
        transferId, fileName, fileSize,
        peerId:      noiseKey,
        direction:   'sending',
        isDirectory: false
      })
    }

    return transferId
  }

  // Directory — walk tree, send all files as a tagged batch
  _offerDirectory (dirPath, conn, noiseKey) {
    const batchId   = crypto.randomBytes(16).toString('hex')
    const dirName   = path.basename(dirPath)
    const files     = this._walkDir(dirPath)
    const totalSize = files.reduce((sum, f) => sum + f.size, 0)

    if (files.length === 0) {
      // Empty directory — just send the mkdir signal and complete immediately
      conn.write(JSON.stringify({
        type: 'batchStart', batchId, dirName,
        fileCount: 0, totalSize: 0
      }) + '\n')
      conn.write(JSON.stringify({ type: 'batchComplete', batchId }) + '\n')
      return
    }

    this._batches.set(batchId, {
      batchId, dirName, totalSize,
      fileCount:     files.length,
      filesSent:     0,
      bytesSent:     0,
      conn, noiseKey,
      pendingIds:    new Set(),
      lastProgressAt: 0
    })

    // Tell the receiver a directory batch is starting
    conn.write(JSON.stringify({
      type: 'batchStart', batchId, dirName,
      fileCount: files.length, totalSize
    }) + '\n')

    // Notify Swift — one row in the UI for the whole directory
    this._emit(CMD_TRANSFER_STARTED, {
      transferId:  batchId,
      fileName:    dirName,
      fileSize:    totalSize,
      fileCount:   files.length,
      peerId:      noiseKey,
      direction:   'sending',
      isDirectory: true
    })

    // Queue each file — they are sent sequentially to avoid flooding the conn
    this._sendNextBatchFile(batchId, files, 0)
  }

  _sendNextBatchFile (batchId, files, index) {
    if (index >= files.length) return  // all dispatched via onAccept chain

    const batch = this._batches.get(batchId)
    if (!batch) return  // cancelled

    const { fullPath, relativePath } = files[index]
    const transferId = this._offerFile(fullPath, batch.conn, batch.noiseKey, batchId, relativePath)
    batch.pendingIds.add(transferId)

    // Next file is queued after this one is accepted (see onAccept)
    batch._nextFiles   = files
    batch._nextIndex   = index + 1
  }

  // Remote accepted a file — start streaming
  onAccept (transferId, conn) {
    const t = this._active.get(transferId)
    if (t) this._streamFile(t, conn)
  }

  _streamFile (transfer, conn) {
    const stream = fs.createReadStream(transfer.filePath, { highWaterMark: CHUNK_SIZE })

    stream.on('data', (chunk) => {
      const ok = conn.write(JSON.stringify({
        type:       'fileChunk',
        transferId: transfer.transferId,
        data:       chunk.toString('base64')
      }) + '\n')

      transfer.sent += chunk.length
      this._onBytesSent(transfer)

      if (!ok) {
        stream.pause()
        conn.once('drain', () => stream.resume())
      }
    })

    stream.on('end', () => {
      conn.write(JSON.stringify({
        type:       'fileComplete',
        transferId: transfer.transferId
      }) + '\n')

      // For standalone files, complete immediately
      if (!transfer.batchId) {
        this._emitProgress(transfer, true)
        this._emit(CMD_TRANSFER_COMPLETE, {
          transferId: transfer.transferId,
          direction:  'sending'
        })
        this._active.delete(transfer.transferId)
      }
      // For batch files, completion is tracked in onFileSentInBatch
    })

    stream.on('error', (err) => {
      this._emitError(transfer.batchId ?? transfer.transferId, err.message)
      this._active.delete(transfer.transferId)
    })
  }

  // Called when sender finishes streaming one file in a batch
  _onFileSentInBatch (transferId) {
    const transfer = this._active.get(transferId)
    if (!transfer?.batchId) return

    const batch = this._batches.get(transfer.batchId)
    if (!batch) return

    batch.pendingIds.delete(transferId)
    batch.filesSent++
    this._active.delete(transferId)

    // Send next file in the batch
    if (batch._nextFiles && batch._nextIndex < batch._nextFiles.length) {
      this._sendNextBatchFile(transfer.batchId, batch._nextFiles, batch._nextIndex)
    }

    // All files streamed — send batchComplete
    if (batch.filesSent === batch.fileCount) {
      batch.conn.write(JSON.stringify({
        type: 'batchComplete', batchId: transfer.batchId
      }) + '\n')

      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId:  transfer.batchId,
        direction:   'sending',
        isDirectory: true
      })
      this._batches.delete(transfer.batchId)
    }
  }

  // Track bytes sent across all files in a batch (or standalone file)
  _onBytesSent (transfer) {
    if (transfer.batchId) {
      const batch = this._batches.get(transfer.batchId)
      if (batch) {
        batch.bytesSent += CHUNK_SIZE  // approximate — corrected at file end
        const progress = Math.min(batch.bytesSent / (batch.totalSize || 1), 0.99)
        const now = Date.now()
        if (now - batch.lastProgressAt >= PROGRESS_THROTTLE) {
          batch.lastProgressAt = now
          this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
        }
      }
    } else {
      this._emitProgress(transfer)
    }
  }

  // ── Receiving ──────────────────────────────────────────────────────────────

  onBatchStart (msg) {
    const { batchId, dirName, fileCount, totalSize } = msg
    const downloadPath = this._getDownloadPath()

    // Pre-create the root directory
    const destDir = this._uniquePath(downloadPath, dirName)
    try { fs.mkdirSync(destDir, { recursive: true }) } catch (_) {}

    this._batches.set(batchId, {
      batchId, destDir, dirName,
      fileCount, totalSize,
      received:  0, filesReceived: 0,
      lastProgressAt: 0
    })
  }

  onOffer (msg, conn, senderNoiseKey) {
    const { transferId, fileName, fileSize, batchId, relativePath } = msg
    const downloadPath = this._getDownloadPath()

    // Determine destination path
    let destPath
    if (batchId) {
      const batch = this._batches.get(batchId)
      if (batch) {
        // Preserve relative path inside the directory
        destPath = path.join(batch.destDir, relativePath)
        // Ensure parent dirs exist
        try { fs.mkdirSync(path.dirname(destPath), { recursive: true }) } catch (_) {}
      } else {
        // Batch not started yet (shouldn't happen) — fall back to flat
        try { fs.mkdirSync(downloadPath, { recursive: true }) } catch (_) {}
        destPath = this._uniquePath(downloadPath, fileName)
      }
    } else {
      try { fs.mkdirSync(downloadPath, { recursive: true }) } catch (_) {}
      destPath = this._uniquePath(downloadPath, fileName)
    }

    const writeStream = this._openWriteStream(transferId, destPath)
    if (!writeStream) {
      return { transferId, fileName, fileSize, peerId: senderNoiseKey }
    }

    this._active.set(transferId, {
      transferId, destPath, fileName, fileSize,
      peerId: senderNoiseKey,
      received: 0, batchId,
      writeStream, lastProgressAt: 0
    })

    conn.write(JSON.stringify({ type: 'fileAccept', transferId }) + '\n')

    // Only emit CMD_TRANSFER_STARTED for standalone files
    if (!batchId) {
      return { transferId, fileName, fileSize, peerId: senderNoiseKey }
    }
    return null  // batch: app.js should not emit CMD_TRANSFER_STARTED
  }

  onChunk (msg) {
    const t = this._active.get(msg.transferId)
    if (!t?.writeStream) return

    const chunk = Buffer.from(msg.data, 'base64')
    t.writeStream.write(chunk)
    t.received += chunk.length

    if (t.batchId) {
      const batch = this._batches.get(t.batchId)
      if (batch) {
        batch.received += chunk.length
        const progress = Math.min(batch.received / (batch.totalSize || 1), 0.99)
        const now = Date.now()
        if (now - batch.lastProgressAt >= PROGRESS_THROTTLE) {
          batch.lastProgressAt = now
          this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
        }
      }
    } else {
      this._emitProgress(t)
    }
  }

  onComplete (msg) {
    const t = this._active.get(msg.transferId)
    if (!t?.writeStream) return

    t.writeStream.once('finish', () => {
      if (t.batchId) {
        // Let onBatchComplete handle the final emit
        const batch = this._batches.get(t.batchId)
        if (batch) {
          batch.filesReceived++
          this._emit(CMD_TRANSFER_PROGRESS, {
            transferId: t.batchId,
            progress: Math.min(batch.filesReceived / batch.fileCount, 0.99)
          })
        }
      } else {
        this._emitProgress(t, true)
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

  onBatchComplete (msg) {
    const { batchId } = msg
    const batch = this._batches.get(batchId)
    if (!batch) return

    this._emit(CMD_TRANSFER_PROGRESS, { transferId: batchId, progress: 1 })
    this._emit(CMD_TRANSFER_COMPLETE, {
      transferId:  batchId,
      direction:   'received',
      filePath:    batch.destDir,
      fileName:    batch.dirName,
      isDirectory: true
    })
    this._batches.delete(batchId)
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

  _emitProgress (transfer, force = false) {
    const now = Date.now()
    if (!force && now - transfer.lastProgressAt < PROGRESS_THROTTLE) return
    transfer.lastProgressAt = now
    const total    = transfer.fileSize || 1
    const done     = transfer.sent ?? transfer.received ?? 0
    this._emit(CMD_TRANSFER_PROGRESS, {
      transferId: transfer.transferId,
      progress:   Math.min(done / total, 1)
    })
  }

  _emitError (transferId, message) {
    this._emit(CMD_ERROR, { transferId, message })
  }

  // Recursively walk a directory, returning flat list of files with relative paths
  _walkDir (dirPath) {
    const results = []
    const base    = path.dirname(dirPath)  // strip so relative paths start at dirName

    const walk = (dir) => {
      let entries
      try { entries = fs.readdirSync(dir) } catch (_) { return }

      for (const entry of entries) {
        // Skip hidden files and macOS metadata
        if (entry.startsWith('.')) continue

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
