// transfers.js — File and directory transfer engine.
//
// Single file: unchanged from original — fileOffer → fileChunk × N → fileComplete
//
// Directory (batch):
//   batchStart   { batchId, dirName, fileCount, totalSize }
//   fileOffer    { ..., batchId, relativePath }   ← one per file
//   fileChunk × N
//   fileComplete
//   (repeat for each file sequentially)
//   batchComplete { batchId }
//
// Files in a batch are sent ONE AT A TIME. The next file is offered only
// after the previous file's stream 'end' fires. This keeps things simple
// and naturally handles backpressure.

const crypto = require('hypercore-crypto')
const fs     = require('bare-fs')
const path   = require('bare-path')

const {
  CMD_TRANSFER_STARTED,
  CMD_TRANSFER_PROGRESS,
  CMD_TRANSFER_COMPLETE,
  CMD_ERROR
} = require('./commands')

const CHUNK_SIZE        = 1024 * 1024  // 1 MB
const PROGRESS_THROTTLE = 100          // ms between progress events

class TransferManager {
  constructor (emit, getDownloadPath) {
    this._emit            = emit
    this._getDownloadPath = getDownloadPath
    this._transfers       = new Map()  // transferId → file state
    this._batches         = new Map()  // batchId    → directory state
  }

  // ── Sending ────────────────────────────────────────────────────────────────

  offer (filePath, conn, noiseKey) {
    let stat
    try { stat = fs.statSync(filePath) }
    catch (err) {
      this._emit(CMD_ERROR, { message: 'Cannot read path: ' + err.message })
      return
    }

    if (stat.isDirectory()) {
      this._offerDirectory(filePath, conn, noiseKey)
    } else {
      this._offerFile(filePath, conn, noiseKey)
    }
  }

  // ── Single file ─────────────────────────────────────────────────────────

  // batchId and relativePath are null for standalone files
  _offerFile (filePath, conn, noiseKey, batchId, relativePath) {
    const transferId = crypto.randomBytes(16).toString('hex')
    const fileName   = path.basename(relativePath || filePath)
    let   fileSize
    try { fileSize = fs.statSync(filePath).size }
    catch (err) {
      this._emit(CMD_ERROR, { message: 'Cannot stat file: ' + err.message })
      return null
    }

    conn.write(JSON.stringify({
      type: 'fileOffer', transferId, fileName, fileSize,
      isDirectory: false,
      batchId:      batchId      || null,
      relativePath: relativePath || null
    }) + '\n')

    this._transfers.set(transferId, {
      transferId, filePath, fileName, fileSize,
      sent: 0, conn, noiseKey,
      batchId: batchId || null,
      lastProgressAt: 0
    })

    // Standalone file: emit CMD_TRANSFER_STARTED immediately so the sender UI updates
    if (!batchId) {
      this._emit(CMD_TRANSFER_STARTED, {
        transferId, fileName, fileSize,
        peerId:      noiseKey,
        direction:   'sending',
        isDirectory: false,
        fileCount:   0
      })
    }

    return transferId
  }

  onAccept (transferId, conn) {
    const transfer = this._transfers.get(transferId)
    if (transfer) this._stream(transfer, conn)
  }

  _stream (transfer, conn) {
    const stream = fs.createReadStream(transfer.filePath, { highWaterMark: CHUNK_SIZE })

    stream.on('data', (chunk) => {
      const ok = conn.write(JSON.stringify({
        type:       'fileChunk',
        transferId: transfer.transferId,
        data:       chunk.toString('base64')
      }) + '\n')

      transfer.sent += chunk.length
      this._reportSendProgress(transfer)

      if (!ok) {
        stream.pause()
        conn.once('drain', () => stream.resume())
      }
    })

    stream.on('end', () => {
      conn.write(JSON.stringify({
        type: 'fileComplete', transferId: transfer.transferId
      }) + '\n')

      if (!transfer.batchId) {
        // Standalone file — complete
        this._reportSendProgress(transfer, true)
        this._emit(CMD_TRANSFER_COMPLETE, {
          transferId: transfer.transferId,
          direction:  'sending',
          isDirectory: false
        })
        this._transfers.delete(transfer.transferId)
      } else {
        // Batch file — advance the batch
        this._onBatchFileSent(transfer)
      }
    })

    stream.on('error', (err) => {
      const id = transfer.batchId || transfer.transferId
      this._emit(CMD_ERROR, { transferId: id, message: err.message })
      this._transfers.delete(transfer.transferId)
    })
  }

  // ── Directory ────────────────────────────────────────────────────────────

  _offerDirectory (dirPath, conn, noiseKey) {
    const batchId   = crypto.randomBytes(16).toString('hex')
    const dirName   = path.basename(dirPath)
    const files     = this._walkDir(dirPath)
    const totalSize = files.reduce((s, f) => s + f.size, 0)

    // Empty directory — start and immediately complete
    if (files.length === 0) {
      conn.write(JSON.stringify({
        type: 'batchStart', batchId, dirName, fileCount: 0, totalSize: 0
      }) + '\n')
      conn.write(JSON.stringify({ type: 'batchComplete', batchId }) + '\n')
      this._emit(CMD_TRANSFER_STARTED, {
        transferId: batchId, fileName: dirName, fileSize: 0,
        fileCount: 0, peerId: noiseKey, direction: 'sending', isDirectory: true
      })
      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId: batchId, direction: 'sending', isDirectory: true
      })
      return
    }

    this._batches.set(batchId, {
      batchId, dirName, totalSize,
      fileCount: files.length, filesSent: 0,
      bytesFromDoneFiles: 0,
      files,               // full array
      nextFileIndex: 0,    // which file to offer next
      conn, noiseKey,
      lastProgressAt: 0
    })

    // Tell receiver what's coming
    conn.write(JSON.stringify({
      type: 'batchStart', batchId, dirName,
      fileCount: files.length, totalSize
    }) + '\n')

    // Sender UI row
    this._emit(CMD_TRANSFER_STARTED, {
      transferId: batchId, fileName: dirName, fileSize: totalSize,
      fileCount: files.length, peerId: noiseKey, direction: 'sending', isDirectory: true
    })

    // Kick off the first file
    this._offerNextFile(batchId)
  }

  _offerNextFile (batchId) {
    const batch = this._batches.get(batchId)
    if (!batch) return
    if (batch.nextFileIndex >= batch.files.length) return

    const { fullPath, relativePath } = batch.files[batch.nextFileIndex]
    batch.nextFileIndex++
    this._offerFile(fullPath, batch.conn, batch.noiseKey, batchId, relativePath)
  }

  _onBatchFileSent (transfer) {
    const batch = this._batches.get(transfer.batchId)
    if (!batch) return

    batch.filesSent++
    batch.bytesFromDoneFiles += transfer.fileSize
    this._transfers.delete(transfer.transferId)

    const progress = Math.min(batch.bytesFromDoneFiles / (batch.totalSize || 1), 0.99)
    this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })

    if (batch.filesSent >= batch.fileCount) {
      // All done — tell receiver
      batch.conn.write(JSON.stringify({ type: 'batchComplete', batchId: batch.batchId }) + '\n')
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress: 1 })
      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId: batch.batchId, direction: 'sending', isDirectory: true
      })
      this._batches.delete(batch.batchId)
    } else {
      // Offer next file
      this._offerNextFile(transfer.batchId)
    }
  }

  // ── Receiving ──────────────────────────────────────────────────────────────

  onBatchStart (msg, senderNoiseKey) {
    const { batchId, dirName, fileCount, totalSize } = msg
    const downloadPath = this._getDownloadPath()
    const destDir = this._uniquePath(downloadPath, dirName)
    try { fs.mkdirSync(destDir, { recursive: true }) } catch (_) {}

    this._batches.set(batchId, {
      batchId, destDir, dirName,
      fileCount, totalSize,
      filesReceived: 0, bytesReceived: 0,
      senderNoiseKey, lastProgressAt: 0
    })
  }

  // Returns the info object for standalone files, null for batch files.
  // app.js uses the return value to decide whether to emit CMD_TRANSFER_STARTED.
  onOffer (msg, conn, senderNoiseKey) {
    const { transferId, fileName, fileSize, batchId, relativePath } = msg
    const downloadPath = this._getDownloadPath()
    let destPath

    if (batchId) {
      const batch = this._batches.get(batchId)
      if (batch && relativePath) {
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

    this._transfers.set(transferId, {
      transferId, destPath, fileName, fileSize,
      peerId: senderNoiseKey,
      received: 0, batchId: batchId || null,
      writeStream, lastProgressAt: 0
    })

    conn.write(JSON.stringify({ type: 'fileAccept', transferId }) + '\n')

    return batchId ? null : { transferId, fileName, fileSize, peerId: senderNoiseKey }
  }

  onChunk (msg) {
    const t = this._transfers.get(msg.transferId)
    if (!t?.writeStream) return

    const chunk = Buffer.from(msg.data, 'base64')
    t.writeStream.write(chunk)
    t.received += chunk.length
    this._reportReceiveProgress(t)
  }

  onComplete (msg) {
    const t = this._transfers.get(msg.transferId)
    if (!t?.writeStream) return

    t.writeStream.once('finish', () => {
      if (t.batchId) {
        const batch = this._batches.get(t.batchId)
        if (batch) {
          batch.filesReceived++
          const progress = Math.min(batch.filesReceived / batch.fileCount, 0.99)
          this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
        }
      } else {
        this._reportReceiveProgress(t, true)
        this._emit(CMD_TRANSFER_COMPLETE, {
          transferId: t.transferId,
          direction:  'received',
          filePath:   t.destPath,
          fileName:   t.fileName,
          isDirectory: false
        })
      }
      this._transfers.delete(t.transferId)
    })

    t.writeStream.end()
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

  // ── Progress helpers ───────────────────────────────────────────────────────

  _reportSendProgress (transfer, force = false) {
    const now = Date.now()
    if (!force && now - transfer.lastProgressAt < PROGRESS_THROTTLE) return
    transfer.lastProgressAt = now

    if (transfer.batchId) {
      const batch = this._batches.get(transfer.batchId)
      if (batch) {
        const done = batch.bytesFromDoneFiles + transfer.sent
        const progress = Math.min(done / (batch.totalSize || 1), 0.99)
        this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
      }
    } else {
      const progress = Math.min(transfer.sent / (transfer.fileSize || 1), 1)
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: transfer.transferId, progress })
    }
  }

  _reportReceiveProgress (transfer, force = false) {
    const now = Date.now()
    if (!force && now - transfer.lastProgressAt < PROGRESS_THROTTLE) return
    transfer.lastProgressAt = now

    if (transfer.batchId) {
      const batch = this._batches.get(transfer.batchId)
      if (batch) {
        batch.bytesReceived += 0  // updated in onChunk via t.received
        const progress = Math.min(transfer.received / (transfer.fileSize || 1), 0.99)
        // Use per-file progress as a proxy — batches use filesReceived in onComplete
        this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress: progress * (1 / batch.fileCount) })
      }
    } else {
      const progress = Math.min(transfer.received / (transfer.fileSize || 1), 1)
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: transfer.transferId, progress })
    }
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  _openWriteStream (transferId, destPath) {
    try {
      const ws = fs.createWriteStream(destPath)
      ws.on('error', (err) => {
        this._emit(CMD_ERROR, { transferId, message: 'Write error: ' + err.message })
        this._transfers.delete(transferId)
      })
      return ws
    } catch (err) {
      this._emit(CMD_ERROR, { transferId, message: 'Cannot open: ' + err.message })
      return null
    }
  }

  // Walk directory, return flat list skipping hidden files
  _walkDir (dirPath) {
    const results = []
    const base    = dirPath  // relative paths are INSIDE the folder, not including it

    const walk = (dir) => {
      let entries
      try { entries = fs.readdirSync(dir) } catch (_) { return }

      for (const entry of entries) {
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
