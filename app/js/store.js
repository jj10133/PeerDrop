// store.js — Persistence layer. Three responsibilities, each clearly separated:
//   1. Identity  — load/generate the mnemonic, derive keys
//   2. Config    — download path setting
//   3. Peers     — saved contacts list

const fs           = require('bare-fs')
const path         = require('bare-path')
const os           = require('bare-os')
const IdentityKeys = require('keet-identity-key')

const ROOT = path.join(os.homedir(), '.peerdrop')

// ─── Utilities ────────────────────────────────────────────────────────────────

function ensureDir (dir) {
  try { fs.mkdirSync(dir, { recursive: true }) } catch (_) {}
}

function readJSON (filePath, fallback) {
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')) }
  catch (_) { return fallback }
}

function writeJSON (filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data))
}

// ─── 1. Identity ──────────────────────────────────────────────────────────────
//
// Mnemonic lives in ~/.peerdrop/seed (mode 0o600, owner-read only).
// profileDiscoveryPublicKey is derived from it — this is the "Peer ID" users share.
// Own devices share the same mnemonic → same Peer ID → Hyperswarm recognises them.

async function loadIdentity () {
  ensureDir(ROOT)
  const seedFile = path.join(ROOT, 'seed')
  let mnemonic

  try {
    mnemonic = fs.readFileSync(seedFile, 'utf8').trim()
  } catch (_) {
    mnemonic = IdentityKeys.generateMnemonic()
    fs.writeFileSync(seedFile, mnemonic, { mode: 0o600 })
  }

  const identity = await IdentityKeys.from({ mnemonic })
  return { discoveryPublicKey: identity.profileDiscoveryPublicKey }
}

// ─── 2. Config ────────────────────────────────────────────────────────────────

const CONFIG_PATH      = path.join(ROOT, 'config.json')
const DEFAULT_DOWNLOAD = path.join(os.homedir(), 'Downloads', 'PeerDrop')

function loadConfig ()       { return readJSON(CONFIG_PATH, {}) }
function saveConfig (patch)  { writeJSON(CONFIG_PATH, Object.assign(loadConfig(), patch)) }
function getDownloadPath ()  { return loadConfig().downloadPath || DEFAULT_DOWNLOAD }
function setDownloadPath (p) { ensureDir(p); saveConfig({ downloadPath: p }) }

// ─── 3. Peers ─────────────────────────────────────────────────────────────────
//
// Schema: { discoveryKey, displayName, platform, lastSeen }
// Keyed by discoveryKey. Own devices identified at runtime (same discoveryKey).

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
