//
//  transfers.js
//  App
//
//  Created by Janardhan on 2026-03-25.
//


const crypto = require('hypercore-crypto')
const fs     = require('bare-fs')
const path   = require('bare-path')

const {
  CMD_TRANSFER_PROGRESS,
  CMD_TRANSFER_COMPLETE,
  CMD_ERROR
} = require('./commands')

const CHUNK_SIZE = 64 * 1024 // 64 KB

class TransferManager {
  /**
   * @param {(command: number, payload: object) => void} emit  RPC emit helper
   * @param {() => string} getDownloadPath                     Current download folder
   */
  constructor (emit, getDownloadPath) {
    this._emit            = emit
    this._getDownloadPath = getDownloadPath
    this._transfers       = new Map()
  }

  // ─── Sending ───────────────────────────────────────────────────────────────

  /**
   * Initiate a send by writing a fileOffer message to the peer connection.
   * Returns the transferId so the caller can track it.
   */
  offer (filePath, conn) {
    const stats      = fs.statSync(filePath)
    const transferId = crypto.randomBytes(16).toString('hex')
    const fileName   = path.basename(filePath)

    this._transfers.set(transferId, {
      transferId, filePath, fileName,
      fileSize: stats.size,
      sent: 0,
      active: false
    })

    conn.write(JSON.stringify({
      type: 'fileOffer',
      transferId,
      fileName,
      fileSize:    stats.size,
      isDirectory: stats.isDirectory()
    }) + '\n')

    return transferId
  }

  /** Called when the remote accepts our offer — start streaming. */
  onAccept (transferId, conn) {
    const transfer = this._transfers.get(transferId)
    if (!transfer) return
    transfer.active = true
    this._stream(transfer, conn)
  }

  _stream (transfer, conn) {
    const stream = fs.createReadStream(transfer.filePath, { highWaterMark: CHUNK_SIZE })

    stream.on('data', (chunk) => {
      conn.write(JSON.stringify({
        type: 'fileChunk',
        transferId: transfer.transferId,
        data: chunk.toString('base64')
      }) + '\n')
      transfer.sent += chunk.length
      this._emit(CMD_TRANSFER_PROGRESS, {
        transferId: transfer.transferId,
        progress:   transfer.sent / transfer.fileSize
      })
    })

    stream.on('end', () => {
      conn.write(JSON.stringify({ type: 'fileComplete', transferId: transfer.transferId }) + '\n')
      this._emit(CMD_TRANSFER_COMPLETE, { transferId: transfer.transferId, direction: 'sent' })
      this._transfers.delete(transfer.transferId)
    })

    stream.on('error', (err) => {
      this._emit(CMD_ERROR, { transferId: transfer.transferId, message: err.message })
    })
  }

  // ─── Receiving ─────────────────────────────────────────────────────────────

  /** Called when a remote peer offers us a file — accept immediately. */
  onOffer (msg, conn, senderPeerId) {
    const { transferId, fileName, fileSize } = msg
    const downloadPath = this._getDownloadPath()

    try { fs.mkdirSync(downloadPath, { recursive: true }) } catch (e) {}

    this._transfers.set(transferId, {
      transferId,
      filePath: path.join(downloadPath, fileName),
      peerId: senderPeerId,
      fileName,
      fileSize,
      received: 0,
      chunks:   [],
      active:   true
    })

    conn.write(JSON.stringify({ type: 'fileAccept', transferId }) + '\n')

    return { transferId, fileName, fileSize, peerId: senderPeerId }
  }

  onChunk (msg) {
    const transfer = this._transfers.get(msg.transferId)
    if (!transfer) return

    const chunk = Buffer.from(msg.data, 'base64')
    transfer.chunks.push(chunk)
    transfer.received += chunk.length

    this._emit(CMD_TRANSFER_PROGRESS, {
      transferId: msg.transferId,
      progress:   transfer.received / transfer.fileSize
    })
  }

  onComplete (msg) {
    const transfer = this._transfers.get(msg.transferId)
    if (!transfer) return

    fs.writeFileSync(transfer.filePath, Buffer.concat(transfer.chunks))

    this._emit(CMD_TRANSFER_COMPLETE, {
      transferId: msg.transferId,
      direction:  'received',
      filePath:   transfer.filePath
    })

    this._transfers.delete(msg.transferId)
  }
}

module.exports = TransferManager
