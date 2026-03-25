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
// Each device has its own identity derived from a mnemonic stored in
// ~/.peerdrop/seed. The profileDiscoveryPublicKey is the Peer ID — share it
// with anyone (person or your own other device) to connect.
//
// There is no concept of "own devices" vs "contacts". Every peer is a peer.

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
  return { discoveryPublicKey: identity.profileDiscoveryPublicKey }
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
//   discoveryKey: string        — their Peer ID / Hyperswarm topic
//   displayName:  string | null — user-assigned label (e.g. "My iPhone", "Alice")
//   hostname:     string | null — last seen hostname from handshake
//   platform:     string | null
//   lastSeen:     number | null
// }
//
// displayName is what the user sets. hostname is what the device advertises.
// UI shows displayName if set, otherwise hostname, otherwise truncated key.

const PEERS_PATH = path.join(ROOT, 'saved-peers.json')

function loadSavedPeers () { return readJSON(PEERS_PATH, []) }

function upsertSavedPeer (discoveryKey, fields = {}) {
  const peers = loadSavedPeers()
  const idx   = peers.findIndex(p => p.discoveryKey === discoveryKey)

  if (idx >= 0) {
    // Never overwrite a user-set displayName with an empty value
    if (fields.hostname)     peers[idx].hostname     = fields.hostname
    if (fields.platform)     peers[idx].platform     = fields.platform
    if (fields.lastSeen)     peers[idx].lastSeen     = fields.lastSeen
    // displayName only updated if explicitly passed (rename command)
    if ('displayName' in fields) peers[idx].displayName = fields.displayName
  } else {
    peers.push({
      discoveryKey,
      displayName: fields.displayName || null,
      hostname:    fields.hostname    || null,
      platform:    fields.platform    || null,
      lastSeen:    fields.lastSeen    || null
    })
  }

  writeJSON(PEERS_PATH, peers)
}

function renamePeer (discoveryKey, displayName) {
  upsertSavedPeer(discoveryKey, { displayName: displayName || null })
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
  renamePeer,
  removeSavedPeer
}
