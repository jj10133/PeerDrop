// transfers.js — File and directory transfer engine using protomux binary channels.
//
// Protocol:
//   Control messages (JSON) travel over the shared 'peerdrop/control' channel
//   managed by app.js. transfers.js only SENDS control signals through controlCh
//   (fileOffer, batchStart, batchComplete). Receives are dispatched by app.js.
//
//   File data travels over per-transfer binary channels:
//     protocol: 'peerdrop/transfer', id: Buffer.from(transferId)
//     message[0]: c.buffer  → raw file bytes  (no base64, no JSON)
//     message[1]: c.json    → { done: true }  completion signal
//
//   Backpressure: message[0].send() returns mux.drained (bool).
//   When false, we pause the read stream and resume on the channel's ondrain.
//
//   Directory batches send up to MAX_CONCURRENT files simultaneously,
//   each on its own binary channel.

const crypto   = require('hypercore-crypto')
const fs       = require('bare-fs')
const path     = require('bare-path')
const c        = require('compact-encoding')

const {
  CMD_TRANSFER_STARTED,
  CMD_TRANSFER_PROGRESS,
  CMD_TRANSFER_COMPLETE,
  CMD_ERROR
} = require('./commands')

const CHUNK_SIZE        = 1024 * 1024  // 1 MB read buffer
const PROGRESS_THROTTLE = 100          // ms between UI progress events
const MAX_CONCURRENT    = 4            // max simultaneous file channels per batch

class TransferManager {
  constructor (emit, getDownloadPath) {
    this._emit            = emit
    this._getDownloadPath = getDownloadPath
    this._transfers       = new Map()  // transferId → file state
    this._batches         = new Map()  // batchId    → directory state
  }

  // ── Public entry point ───────────────────────────────────────────────────────

  offer (filePath, mux, controlCh, noiseKey) {
    let stat
    try { stat = fs.statSync(filePath) }
    catch (err) {
      this._emit(CMD_ERROR, { message: 'Cannot read path: ' + err.message })
      return
    }

    if (stat.isDirectory()) {
      this._offerDirectory(filePath, mux, controlCh, noiseKey)
    } else {
      this._offerSingleFile(filePath, mux, controlCh, noiseKey, null, null)
    }
  }

  // ── Single file — sender ─────────────────────────────────────────────────────

  _offerSingleFile (filePath, mux, controlCh, noiseKey, batchId, relativePath) {
    const transferId = crypto.randomBytes(16).toString('hex')
    const fileName   = path.basename(relativePath || filePath)
    let   fileSize
    try { fileSize = fs.statSync(filePath).size }
    catch (err) {
      this._emit(CMD_ERROR, { message: 'Cannot stat file: ' + err.message })
      return null
    }

    // Announce the file via the shared control channel
    controlCh.messages[0].send({
      type: 'fileOffer', transferId, fileName, fileSize,
      isDirectory:  false,
      batchId:      batchId      || null,
      relativePath: relativePath || null
    })

    this._transfers.set(transferId, {
      transferId, filePath, fileName, fileSize,
      sent: 0, mux, controlCh, noiseKey,
      batchId:       batchId || null,
      lastProgressAt: 0
    })

    // Notify Swift so the outgoing transfer row appears immediately
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

  // Sender: called by app.js when fileAccept arrives — open the binary channel and stream
  onAccept (transferId, mux) {
    const t = this._transfers.get(transferId)
    if (!t) return

    const txCh = mux.createChannel({
      protocol: 'peerdrop/transfer',
      id:        Buffer.from(transferId),
      messages: [
        { encoding: c.buffer },  // [0] raw file data
        { encoding: c.json   }   // [1] done signal
      ],
      ondrain: () => {},  // handled per-stream in _streamFile
      onopen:  () => this._streamFile(t, txCh),
      onclose: () => {}
    })

    txCh.open()
  }

  _streamFile (transfer, txCh) {
    const stream = fs.createReadStream(transfer.filePath, { highWaterMark: CHUNK_SIZE })
    const msg0   = txCh.messages[0]

    stream.on('data', (chunk) => {
      transfer.sent += chunk.length
      this._reportSendProgress(transfer)

      const drained = msg0.send(chunk)  // raw Buffer — no base64, no JSON
      if (!drained) {
        stream.pause()
        // Resume when the underlying mux stream drains
        txCh._mux.stream.once('drain', () => stream.resume())
      }
    })

    stream.on('end', () => {
      txCh.messages[1].send({ done: true })
      this._reportSendProgress(transfer, true)

      if (!transfer.batchId) {
        this._emit(CMD_TRANSFER_COMPLETE, {
          transferId:  transfer.transferId,
          direction:   'sending',
          isDirectory: false
        })
        this._transfers.delete(transfer.transferId)
      } else {
        this._onBatchFileSent(transfer)
      }

      txCh.close()
    })

    stream.on('error', (err) => {
      this._emit(CMD_ERROR, {
        transferId: transfer.batchId || transfer.transferId,
        message:    err.message
      })
      this._transfers.delete(transfer.transferId)
      txCh.close()
    })
  }

  // ── Single file — receiver ───────────────────────────────────────────────────

  // Called by app.js on fileOffer. Opens the receiver-side binary channel so
  // it is ready before app.js sends fileAccept back to the sender.
  // Returns info object for standalone files, null for batch files.
  onOffer (msg, mux, senderNoiseKey) {
    const { transferId, fileName, fileSize, batchId, relativePath } = msg
    const downloadPath = this._getDownloadPath()
    let   destPath

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
    if (!writeStream) {
      return batchId ? null : { transferId, fileName, fileSize, peerId: senderNoiseKey }
    }

    this._transfers.set(transferId, {
      transferId, destPath, fileName, fileSize,
      peerId:        senderNoiseKey,
      received:      0,
      batchId:       batchId || null,
      writeStream,
      lastProgressAt: 0
    })

    // Open receiver channel now — before fileAccept is sent — so both sides
    // are ready at the same moment and no frames are dropped
    const rxCh = mux.createChannel({
      protocol: 'peerdrop/transfer',
      id:        Buffer.from(transferId),
      messages: [
        {
          encoding:  c.buffer,
          onmessage: (chunk) => this._onRawChunk(transferId, chunk)
        },
        {
          encoding:  c.json,
          onmessage: () => this._onTransferComplete(transferId)
        }
      ],
      onclose: () => {}
    })

    rxCh.open()

    return batchId ? null : { transferId, fileName, fileSize, peerId: senderNoiseKey }
  }

  _onRawChunk (transferId, chunk) {
    const t = this._transfers.get(transferId)
    if (!t?.writeStream) return

    t.writeStream.write(chunk)
    t.received += chunk.length
    this._reportReceiveProgress(t)
  }

  _onTransferComplete (transferId) {
    const t = this._transfers.get(transferId)
    if (!t?.writeStream) return

    t.writeStream.once('finish', () => {
      if (t.batchId) {
        this._onBatchFileReceived(t)
      } else {
        this._reportReceiveProgress(t, true)
        this._emit(CMD_TRANSFER_COMPLETE, {
          transferId:  t.transferId,
          direction:   'received',
          filePath:    t.destPath,
          fileName:    t.fileName,
          isDirectory: false
        })
      }
      this._transfers.delete(t.transferId)
    })

    t.writeStream.end()
  }

  // ── Directory — sender ───────────────────────────────────────────────────────

  _offerDirectory (dirPath, mux, controlCh, noiseKey) {
    const batchId   = crypto.randomBytes(16).toString('hex')
    const dirName   = path.basename(dirPath)
    const files     = this._walkDir(dirPath)
    const totalSize = files.reduce((s, f) => s + f.size, 0)

    if (files.length === 0) {
      controlCh.messages[0].send({
        type: 'batchStart', batchId, dirName, fileCount: 0, totalSize: 0
      })
      controlCh.messages[0].send({ type: 'batchComplete', batchId })
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
      files, nextIndex: 0,
      activeCount: 0,
      mux, controlCh, noiseKey,
      lastProgressAt: 0
    })

    controlCh.messages[0].send({
      type: 'batchStart', batchId, dirName,
      fileCount: files.length, totalSize
    })

    this._emit(CMD_TRANSFER_STARTED, {
      transferId: batchId, fileName: dirName, fileSize: totalSize,
      fileCount: files.length, peerId: noiseKey, direction: 'sending', isDirectory: true
    })

    // Start up to MAX_CONCURRENT files immediately
    this._fillBatchSlots(batchId)
  }

  _fillBatchSlots (batchId) {
    const batch = this._batches.get(batchId)
    if (!batch) return

    while (batch.activeCount < MAX_CONCURRENT && batch.nextIndex < batch.files.length) {
      const { fullPath, relativePath } = batch.files[batch.nextIndex++]
      batch.activeCount++
      this._offerSingleFile(fullPath, batch.mux, batch.controlCh, batch.noiseKey, batchId, relativePath)
    }
  }

  _onBatchFileSent (transfer) {
    const batch = this._batches.get(transfer.batchId)
    if (!batch) return

    batch.filesSent++
    batch.activeCount--
    batch.bytesFromDoneFiles += transfer.fileSize
    this._transfers.delete(transfer.transferId)

    const progress = Math.min(batch.bytesFromDoneFiles / (batch.totalSize || 1), 0.99)
    this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })

    if (batch.filesSent >= batch.fileCount) {
      // All done — tell the receiver
      batch.controlCh.messages[0].send({ type: 'batchComplete', batchId: batch.batchId })
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress: 1 })
      this._emit(CMD_TRANSFER_COMPLETE, {
        transferId: batch.batchId, direction: 'sending', isDirectory: true
      })
      this._batches.delete(batch.batchId)
    } else {
      // Free up a concurrency slot — offer the next file
      this._fillBatchSlots(transfer.batchId)
    }
  }

  // ── Directory — receiver ─────────────────────────────────────────────────────

  onBatchStart (msg, senderNoiseKey) {
    const { batchId, dirName, fileCount, totalSize } = msg
    const downloadPath = this._getDownloadPath()
    const destDir = this._uniquePath(downloadPath, dirName)
    try { fs.mkdirSync(destDir, { recursive: true }) } catch (_) {}

    this._batches.set(batchId, {
      batchId, destDir, dirName,
      fileCount, totalSize,
      filesReceived: 0,
      senderNoiseKey,
      lastProgressAt: 0
    })
  }

  _onBatchFileReceived (t) {
    const batch = this._batches.get(t.batchId)
    if (!batch) return

    batch.filesReceived++
    const progress = Math.min(batch.filesReceived / batch.fileCount, 0.99)
    this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
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

  // ── Progress reporting ───────────────────────────────────────────────────────

  _reportSendProgress (transfer, force = false) {
    const now = Date.now()
    if (!force && now - transfer.lastProgressAt < PROGRESS_THROTTLE) return
    transfer.lastProgressAt = now

    if (transfer.batchId) {
      const batch = this._batches.get(transfer.batchId)
      if (!batch) return
      const done     = batch.bytesFromDoneFiles + transfer.sent
      const progress = Math.min(done / (batch.totalSize || 1), 0.99)
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
    } else {
      const progress = Math.min(transfer.sent / (transfer.fileSize || 1), 1)
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: transfer.transferId, progress })
    }
  }

  _reportReceiveProgress (t, force = false) {
    const now = Date.now()
    if (!force && now - t.lastProgressAt < PROGRESS_THROTTLE) return
    t.lastProgressAt = now

    if (t.batchId) {
      const batch = this._batches.get(t.batchId)
      if (!batch) return
      // Approximate: completed files + fraction of current file
      const progress = Math.min(
        (batch.filesReceived + (t.received / (t.fileSize || 1))) / batch.fileCount,
        0.99
      )
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: batch.batchId, progress })
    } else {
      const progress = Math.min(t.received / (t.fileSize || 1), 1)
      this._emit(CMD_TRANSFER_PROGRESS, { transferId: t.transferId, progress })
    }
  }

  // ── Utilities ────────────────────────────────────────────────────────────────

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

  // Walk directory, returning flat list of files with paths relative to dirPath
  _walkDir (dirPath) {
    const results = []

    const walk = (dir) => {
      let entries
      try { entries = fs.readdirSync(dir) } catch (_) { return }

      for (const entry of entries) {
        if (entry.startsWith('.')) continue  // skip .DS_Store, hidden files

        const full = path.join(dir, entry)
        let stat
        try { stat = fs.statSync(full) } catch (_) { continue }

        if (stat.isDirectory()) {
          walk(full)
        } else {
          results.push({
            fullPath:     full,
            relativePath: path.relative(dirPath, full),  // relative to inside the folder
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
