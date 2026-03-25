//
//  store.js
//  App
//
//  Created by Janardhan on 2026-03-25.
//


const fs   = require('bare-fs')
const path = require('bare-path')
const os   = require('bare-os')
const IdentityKeys = require('keet-identity-key')

const ROOT = path.join(os.homedir(), '.peerdrop')

// ─── Helpers ─────────────────────────────────────────────────────────────────

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
  return IdentityKeys.from({ mnemonic })
}

// ─── Config ───────────────────────────────────────────────────────────────────

const CONFIG_PATH = path.join(ROOT, 'config.json')
const DEFAULT_DOWNLOAD_PATH = path.join(os.homedir(), 'Downloads', 'PeerDrop')

function loadConfig () {
  return readJSON(CONFIG_PATH, {})
}

function saveConfig (patch) {
  const current = loadConfig()
  writeJSON(CONFIG_PATH, Object.assign(current, patch))
}

function getDownloadPath () {
  return loadConfig().downloadPath || DEFAULT_DOWNLOAD_PATH
}

function setDownloadPath (newPath) {
  ensureDir(newPath)
  saveConfig({ downloadPath: newPath })
}

// ─── Saved peers ──────────────────────────────────────────────────────────────
// Each entry: { discoveryKey: string, deviceName: string|null, platform: string|null }

const PEERS_PATH = path.join(ROOT, 'saved-peers.json')

function loadSavedPeers () {
  return readJSON(PEERS_PATH, [])
}

function upsertSavedPeer (discoveryKey, { deviceName = null, platform = null } = {}) {
  const peers = loadSavedPeers()
  const idx   = peers.findIndex(p => p.discoveryKey === discoveryKey)
  if (idx >= 0) {
    if (deviceName) peers[idx].deviceName = deviceName
    if (platform)   peers[idx].platform   = platform
  } else {
    peers.push({ discoveryKey, deviceName, platform })
  }
  writeJSON(PEERS_PATH, peers)
}

function removeSavedPeer (discoveryKey) {
  const peers = loadSavedPeers().filter(p => p.discoveryKey !== discoveryKey)
  writeJSON(PEERS_PATH, peers)
}

module.exports = {
  loadIdentity,
  getDownloadPath,
  setDownloadPath,
  loadSavedPeers,
  upsertSavedPeer,
  removeSavedPeer
}