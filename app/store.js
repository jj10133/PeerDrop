const fs           = require('bare-fs')
const path         = require('bare-path')
const os           = require('bare-os')
const IdentityKeys = require('keet-identity-key')

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

// ─── Identity ─────────────────────────────────────────────────────────────────
//
// Identity = mnemonic stored in ~/.peerdrop/seed
// Copy that file to another device → same identity → devices recognise each other.
//
// Two keys are derived from the mnemonic:
//   identityPublicKey        — used internally to detect own devices
//                              (same on all your devices)
//   profileDiscoveryPublicKey — the Hyperswarm topic you announce on and share
//                              as your "Peer ID" (same on all your devices)
//
// No device keypairs, no attestation proofs, no pairing handshakes needed.

async function loadIdentity () {
  ensureDir(ROOT)

  const seedFile = path.join(ROOT, 'seed')
  let mnemonic

  try {
    mnemonic = fs.readFileSync(seedFile, 'utf8').trim()
  } catch (e) {
    mnemonic = IdentityKeys.generateMnemonic()
    fs.writeFileSync(seedFile, mnemonic, { mode: 0o600 })
  }

  const identity = await IdentityKeys.from({ mnemonic })

  return {
    discoveryPublicKey: identity.profileDiscoveryPublicKey
  }
}

// ─── Config ───────────────────────────────────────────────────────────────────

const CONFIG_PATH      = path.join(ROOT, 'config.json')
const DEFAULT_DOWNLOAD = path.join(os.homedir(), 'Downloads', 'PeerDrop')

function loadConfig ()       { return readJSON(CONFIG_PATH, {}) }
function saveConfig (patch)  { writeJSON(CONFIG_PATH, Object.assign(loadConfig(), patch)) }
function getDownloadPath ()  { return loadConfig().downloadPath || DEFAULT_DOWNLOAD }
function setDownloadPath (p) { ensureDir(p); saveConfig({ downloadPath: p }) }

// ─── Saved peers ──────────────────────────────────────────────────────────────
//
// Each entry: {
//   discoveryKey: string   — the topic we join to reach this peer (their Peer ID)
//   displayName:  string | null
//   platform:     string | null
//   lastSeen:     number | null
// }
//
// We key on discoveryKey because that's what the user shares and what we join.
// Own devices are identified at runtime by comparing discoveryKey to ours —
// not stored separately.

const PEERS_PATH = path.join(ROOT, 'saved-peers.json')

function loadSavedPeers () { return readJSON(PEERS_PATH, []) }

function upsertSavedPeer (discoveryKey, fields = {}) {
  const peers = loadSavedPeers()
  const idx   = peers.findIndex(p => p.discoveryKey === discoveryKey)

  if (idx >= 0) {
    if (fields.displayName) peers[idx].displayName = fields.displayName
    if (fields.platform)    peers[idx].platform    = fields.platform
    if (fields.lastSeen)    peers[idx].lastSeen    = fields.lastSeen
  } else {
    peers.push({
      discoveryKey,
      displayName: fields.displayName || null,
      platform:    fields.platform    || null,
      lastSeen:    fields.lastSeen    || null
    })
  }

  writeJSON(PEERS_PATH, peers)
}

function removeSavedPeer (discoveryKey) {
  writeJSON(PEERS_PATH, loadSavedPeers().filter(p => p.discoveryKey !== discoveryKey))
}

module.exports = {
  loadIdentity,
  getDownloadPath,
  setDownloadPath,
  loadSavedPeers,
  upsertSavedPeer,
  removeSavedPeer
}
