// store.js — Persistence layer.

const fs           = require('bare-fs')
const path         = require('bare-path')
const os           = require('bare-os')
const IdentityKeys = require('keet-identity-key')

const platform = os.platform()

// On iOS use Documents/ which is always writable and visible in Files app.
// On macOS/Linux use ~/.peerdrop at home directory.
const ROOT = platform === 'ios'
  ? path.join(os.homedir(), 'Documents', '.peerdrop')
  : path.join(os.homedir(), '.peerdrop')

const DEFAULT_DOWNLOAD = platform === 'ios'
  ? path.join(os.homedir(), 'Documents', 'PeerDrop')
  : path.join(os.homedir(), 'Downloads', 'PeerDrop')

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

const CONFIG_PATH = path.join(ROOT, 'config.json')

function loadConfig ()       { return readJSON(CONFIG_PATH, {}) }
function saveConfig (patch)  { writeJSON(CONFIG_PATH, Object.assign(loadConfig(), patch)) }
function getDownloadPath ()  { return loadConfig().downloadPath || DEFAULT_DOWNLOAD }
function setDownloadPath (p) { ensureDir(p); saveConfig({ downloadPath: p }) }

// ─── 3. Peers ─────────────────────────────────────────────────────────────────

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