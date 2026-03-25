const fs           = require('bare-fs')
const path         = require('bare-path')
const os           = require('bare-os')
const IdentityKeys = require('keet-identity-key')
const crypto       = require('hypercore-crypto')

const ROOT = path.join(os.homedir(), '.peerdrop')

// ─── Helpers ──────────────────────────────────────────────────────────────────

function ensureDir (dir) {
  try { fs.mkdirSync(dir, { recursive: true }) } catch (e) {}
}

function readJSON (filePath, fallback) {
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')) }
  catch (e) { return fallback }
}

function writeJSON (filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data))
}

function fileExists (filePath) {
  try { fs.statSync(filePath); return true } catch (e) { return false }
}

// ─── Identity ─────────────────────────────────────────────────────────────────
//
// Case A — Primary device (has mnemonic in ~/.peerdrop/seed):
//   Derives identity from mnemonic, generates/loads a deviceKeyPair,
//   bootstraps an attestation proof, stores it.
//
// Case B — Added device (paired via QR, no mnemonic):
//   Loads deviceKeyPair + proof written by writePairingResult().
//   Extracts identityPublicKey from the proof itself.
//   Loads discoveryPublicKey from discovery.hex written during pairing.
//
// Security: mnemonic never leaves the primary device via the network.

async function loadIdentity () {
  ensureDir(ROOT)

  const seedFile   = path.join(ROOT, 'seed')
  const deviceFile = path.join(ROOT, 'device.json')
  const proofFile  = path.join(ROOT, 'proof.b64')

  const hasSeed   = fileExists(seedFile)
  const hasProof  = fileExists(proofFile)
  const hasDevice = fileExists(deviceFile)

  // Case B: paired device
  if (!hasSeed && hasProof && hasDevice) {
    return _loadPairedDevice(deviceFile, proofFile)
  }

  // Case A: primary device
  let mnemonic
  try {
    mnemonic = fs.readFileSync(seedFile, 'utf8').trim()
  } catch (e) {
    mnemonic = IdentityKeys.generateMnemonic()
    fs.writeFileSync(seedFile, mnemonic, { mode: 0o600 })
  }

  const identity = await IdentityKeys.from({ mnemonic })

  // Device keypair — unique to this machine
  let deviceKeyPair
  try {
    const saved = JSON.parse(fs.readFileSync(deviceFile, 'utf8'))
    deviceKeyPair = {
      publicKey: Buffer.from(saved.publicKey, 'hex'),
      secretKey: Buffer.from(saved.secretKey, 'hex')
    }
  } catch (e) {
    deviceKeyPair = crypto.keyPair()
    fs.writeFileSync(deviceFile, JSON.stringify({
      publicKey: deviceKeyPair.publicKey.toString('hex'),
      secretKey: deviceKeyPair.secretKey.toString('hex')
    }), { mode: 0o600 })
  }

  // Attestation proof: links this deviceKeyPair back to the identity
  let attestationProof
  try {
    attestationProof = Buffer.from(fs.readFileSync(proofFile, 'utf8').trim(), 'base64')
    if (!IdentityKeys.verify(attestationProof, null)) throw new Error('stale')
  } catch (e) {
    attestationProof = await identity.bootstrap(deviceKeyPair.publicKey)
    fs.writeFileSync(proofFile, attestationProof.toString('base64'))
  }

  return {
    identity,
    deviceKeyPair,
    attestationProof,
    identityPublicKey:  identity.identityPublicKey,
    discoveryPublicKey: identity.profileDiscoveryPublicKey
  }
}

function _loadPairedDevice (deviceFile, proofFile) {
  const saved = JSON.parse(fs.readFileSync(deviceFile, 'utf8'))
  const deviceKeyPair = {
    publicKey: Buffer.from(saved.publicKey, 'hex'),
    secretKey: Buffer.from(saved.secretKey, 'hex')
  }

  const attestationProof = Buffer.from(fs.readFileSync(proofFile, 'utf8').trim(), 'base64')
  const info = IdentityKeys.verify(attestationProof, null)
  if (!info) throw new Error('Invalid pairing proof — re-pair this device')

  const discoveryHex = fs.readFileSync(path.join(ROOT, 'discovery.hex'), 'utf8').trim()

  return {
    identity:           null,
    deviceKeyPair,
    attestationProof,
    identityPublicKey:  info.identityPublicKey,
    discoveryPublicKey: Buffer.from(discoveryHex, 'hex')
  }
}

// Written on Device B after receiving the pairResponse
function writePairingResult ({ deviceKeyPair, attestationProof, discoveryPublicKey }) {
  ensureDir(ROOT)
  fs.writeFileSync(path.join(ROOT, 'device.json'), JSON.stringify({
    publicKey: deviceKeyPair.publicKey.toString('hex'),
    secretKey: deviceKeyPair.secretKey.toString('hex')
  }), { mode: 0o600 })
  fs.writeFileSync(path.join(ROOT, 'proof.b64'),      attestationProof.toString('base64'))
  fs.writeFileSync(path.join(ROOT, 'discovery.hex'),  discoveryPublicKey.toString('hex'))
}

// ─── Config ───────────────────────────────────────────────────────────────────

const CONFIG_PATH         = path.join(ROOT, 'config.json')
const DEFAULT_DOWNLOAD    = path.join(os.homedir(), 'Downloads', 'PeerDrop')

function loadConfig ()        { return readJSON(CONFIG_PATH, {}) }
function saveConfig (patch)   { writeJSON(CONFIG_PATH, Object.assign(loadConfig(), patch)) }
function getDownloadPath ()   { return loadConfig().downloadPath || DEFAULT_DOWNLOAD }
function setDownloadPath (p)  { ensureDir(p); saveConfig({ downloadPath: p }) }

// ─── Saved peers ──────────────────────────────────────────────────────────────
//
// Each entry: {
//   identityKey:  string | null  — verified after handshake; null if only pasted so far
//   discoveryKey: string         — the Hyperswarm topic we join to reach this peer
//   deviceName:   string | null  — last seen device name
//   platform:     string | null
//   lastSeen:     number | null  — unix ms
// }

const PEERS_PATH = path.join(ROOT, 'saved-peers.json')

function loadSavedPeers () { return readJSON(PEERS_PATH, []) }

function upsertSavedPeer (identityKey, fields = {}) {
  const peers = loadSavedPeers()

  // Match on identityKey if we have one, otherwise on discoveryKey
  const idx = identityKey
    ? peers.findIndex(p => p.identityKey === identityKey)
    : peers.findIndex(p => p.discoveryKey === fields.discoveryKey)

  if (idx >= 0) {
    const p = peers[idx]
    if (identityKey)         p.identityKey  = identityKey
    if (fields.discoveryKey) p.discoveryKey = fields.discoveryKey
    if (fields.deviceName)   p.deviceName   = fields.deviceName
    if (fields.platform)     p.platform     = fields.platform
    if (fields.lastSeen)     p.lastSeen     = fields.lastSeen
  } else {
    peers.push({
      identityKey:  identityKey  || null,
      discoveryKey: fields.discoveryKey || null,
      deviceName:   fields.deviceName   || null,
      platform:     fields.platform     || null,
      lastSeen:     fields.lastSeen     || null
    })
  }

  writeJSON(PEERS_PATH, peers)
}

function removeSavedPeer (identityKey) {
  writeJSON(PEERS_PATH, loadSavedPeers().filter(p => p.identityKey !== identityKey))
}

module.exports = {
  loadIdentity,
  writePairingResult,
  getDownloadPath,
  setDownloadPath,
  loadSavedPeers,
  upsertSavedPeer,
  removeSavedPeer
}
