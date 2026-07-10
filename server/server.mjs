// EEAccess Tesla relay — MULTI-TENANT. One shared Tesla Developer app (this
// server's Client ID/secret) so users never register their own — but each
// user gets their OWN Tesla OAuth session (own refresh token, own vehicles),
// stored in their own file under users/. Auth to THIS server is a random
// per-user API key, auto-provisioned during Tesla sign-in via a server-
// mediated OAuth exchange — no human-chosen username/password anywhere.
//
// Run:  node server.mjs        (config from ./config.json, see config.example.json)
import { createServer } from 'node:http'
import { readFile, writeFile, mkdir, readdir, unlink } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { randomBytes, randomUUID, createHash, timingSafeEqual } from 'node:crypto'

const __dir = dirname(fileURLToPath(import.meta.url))
const CONFIG_PATH = process.env.EEACCESS_CONFIG || join(__dir, 'config.json')
const USERS_DIR = process.env.EEACCESS_USERS_DIR || join(__dir, 'users')
const SCHEDULES_PATH = process.env.EEACCESS_SCHEDULES || join(__dir, 'schedules.json')
const TOKEN_URL = 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token'
const AUTHORIZE_URL = 'https://auth.tesla.com/oauth2/v3/authorize'
const SCOPES = 'openid offline_access vehicle_device_data vehicle_cmds vehicle_charging_cmds'

// config: { clientId, clientSecret, regionBase, redirectUri, host, port }
let config = JSON.parse(await readFile(CONFIG_PATH, 'utf8'))
await mkdir(USERS_DIR, { recursive: true })

const log = (...a) => console.log(new Date().toISOString(), ...a)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const b64url = (buf) => buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const sha256hex = (s) => createHash('sha256').update(s).digest('hex')

function safeEqual(a, b) {
  const bufA = Buffer.from(a)
  const bufB = Buffer.from(b)
  return bufA.length === bufB.length && timingSafeEqual(bufA, bufB)
}

class UpstreamError extends Error {
  constructor(status, body) { super(`${status}: ${body}`); this.status = status }
}

// --- Per-user storage ----------------------------------------------------------
// One JSON file per user (userId = random UUID). apiKeyHash is SHA-256 of the
// random API key issued at registration — the plaintext key is returned to
// the app exactly once (at /oauth/complete) and never stored server-side.
const userPath = (id) => join(USERS_DIR, `${id}.json`)

async function loadUser(id) {
  try { return JSON.parse(await readFile(userPath(id), 'utf8')) } catch { return null }
}
async function saveUser(user) {
  await writeFile(userPath(user.id), JSON.stringify(user, null, 2))
}
async function deleteUser(user) {
  apiKeyIndex.delete(user.apiKeyHash)
  await unlink(userPath(user.id)).catch(() => {})
  for (const s of [...schedules.values()]) {
    if (s.userId === user.id) await cancelScheduleById(s.id)
  }
}

// apiKeyHash -> userId, rebuilt from disk at startup so auth lookups are a
// Map hit instead of hashing + scanning every user file per request.
let apiKeyIndex = new Map()
async function rebuildApiKeyIndex() {
  apiKeyIndex = new Map()
  const files = await readdir(USERS_DIR).catch(() => [])
  for (const f of files) {
    if (!f.endsWith('.json')) continue
    const user = JSON.parse(await readFile(join(USERS_DIR, f), 'utf8'))
    apiKeyIndex.set(user.apiKeyHash, user.id)
  }
  log(`loaded ${apiKeyIndex.size} user(s)`)
}
await rebuildApiKeyIndex()

async function userForApiKey(key) {
  if (!key) return null
  const id = apiKeyIndex.get(sha256hex(key))
  return id ? loadUser(id) : null
}

// --- Tesla token management (per user, shared app credentials) -----------------
async function getAccessToken(user) {
  if (user.accessToken && Date.now() < user.accessExpiry - 120_000) return user.accessToken
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: config.clientId,
    refresh_token: user.refreshToken,
  })
  if (config.clientSecret) body.set('client_secret', config.clientSecret)
  const res = await fetch(TOKEN_URL, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body })
  if (!res.ok) throw new UpstreamError(res.status, (await res.text()).slice(0, 200))
  const j = await res.json()
  user.accessToken = j.access_token
  user.accessExpiry = Date.now() + j.expires_in * 1000
  if (j.refresh_token && j.refresh_token !== user.refreshToken) user.refreshToken = j.refresh_token
  await saveUser(user)
  return user.accessToken
}

// Tesla routes user data to the account's home-region host — resolve it once
// per user and cache on their record (see EEAccess iOS/watch clients for the
// same pattern against the direct Fleet API).
async function resolveRegion(user) {
  try {
    const token = await getAccessToken(user)
    const res = await fetch(config.regionBase + '/api/1/users/region', { headers: { Authorization: `Bearer ${token}` } })
    if (res.ok) {
      const j = await res.json()
      if (j.response?.fleet_api_base_url) {
        user.regionBase = j.response.fleet_api_base_url
        await saveUser(user)
      }
    }
  } catch (e) {
    log('region resolve failed for', user.id, e.message)
  }
}

async function tesla(user, method, path) {
  const token = await getAccessToken(user)
  const base = user.regionBase || config.regionBase
  const res = await fetch(base + path, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: method === 'POST' ? '{}' : undefined,
  })
  const text = await res.text()
  if (!res.ok) throw new UpstreamError(res.status, text.slice(0, 200))
  return text ? JSON.parse(text) : {}
}

// pre-2021 S/X accept these unsigned; 2021+ need the signing proxy (later phase).
const CMD = {
  unlock: 'door_unlock',
  lock: 'door_lock',
  drive: 'remote_start_drive',
  climate_on: 'auto_conditioning_start',
  climate_off: 'auto_conditioning_stop',
}
const sendCommand = (user, vin, cmd) => tesla(user, 'POST', `/api/1/vehicles/${vin}/command/${CMD[cmd]}`)

// Confirms `vin` actually belongs to `user`'s Tesla account before letting them
// command it — essential now that many users share one server: without this, a
// user who learns/guesses another VIN in transit could steer commands at a car
// that isn't theirs.
async function assertOwnsVehicle(user, vin) {
  const stale = Date.now() - (user.vehiclesCachedAt || 0) > 10 * 60 * 1000
  if (!user.vehicles?.includes(vin) || stale) {
    const d = await tesla(user, 'GET', '/api/1/vehicles')
    user.vehicles = (d.response || []).map((v) => v.vin)
    user.vehiclesCachedAt = Date.now()
    await saveUser(user)
  }
  if (!user.vehicles.includes(vin)) throw new UpstreamError(403, 'vehicle not on this account')
}

// --- Rate limiting (per user) ---------------------------------------------------
// Protects the shared Tesla app's standing — a runaway/buggy client hammering
// Tesla under the one shared Client ID risks Tesla throttling everyone, not
// just the offender.
const RATE_LIMIT = 30 // requests per window per user
const RATE_WINDOW_MS = 60_000
const rateState = new Map() // userId -> { windowStart, count }
function rateLimited(userId) {
  const now = Date.now()
  const s = rateState.get(userId)
  if (!s || now - s.windowStart > RATE_WINDOW_MS) {
    rateState.set(userId, { windowStart: now, count: 1 })
    return false
  }
  s.count++
  return s.count > RATE_LIMIT
}

// --- Server-mediated OAuth ------------------------------------------------------
// The app never sees the shared Client Secret. It opens the Tesla login the
// server hands back, Tesla redirects to THIS server (not the app), a tiny
// bounce page hands the code to the app's custom URL scheme, and the app posts
// that code back here for the actual token exchange.
const pendingAuth = new Map() // state -> { verifier, createdAt }
const AUTH_TTL_MS = 10 * 60 * 1000

function pruneExpiredAuth() {
  const now = Date.now()
  for (const [state, v] of pendingAuth) if (now - v.createdAt > AUTH_TTL_MS) pendingAuth.delete(state)
}

function startOAuth() {
  pruneExpiredAuth()
  const verifier = b64url(randomBytes(32))
  const challenge = b64url(createHash('sha256').update(verifier).digest())
  const state = b64url(randomBytes(16))
  pendingAuth.set(state, { verifier, createdAt: Date.now() })
  const url = new URL(AUTHORIZE_URL)
  url.search = new URLSearchParams({
    response_type: 'code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: SCOPES,
    state,
    code_challenge: challenge,
    code_challenge_method: 'S256',
  }).toString()
  return { authorizeUrl: url.toString(), state }
}

async function completeOAuth(code, state) {
  const pending = pendingAuth.get(state)
  if (!pending) throw new UpstreamError(400, 'unknown or expired sign-in attempt — try again')
  pendingAuth.delete(state)

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: config.clientId,
    code,
    code_verifier: pending.verifier,
    redirect_uri: config.redirectUri,
    audience: config.regionBase,
  })
  if (config.clientSecret) body.set('client_secret', config.clientSecret)
  const res = await fetch(TOKEN_URL, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body })
  if (!res.ok) throw new UpstreamError(res.status, (await res.text()).slice(0, 200))
  const j = await res.json()

  const id = randomUUID()
  const apiKey = b64url(randomBytes(32))
  const user = {
    id,
    apiKeyHash: sha256hex(apiKey),
    refreshToken: j.refresh_token,
    accessToken: j.access_token,
    accessExpiry: Date.now() + j.expires_in * 1000,
    regionBase: config.regionBase,
    createdAt: new Date().toISOString(),
  }
  await saveUser(user)
  apiKeyIndex.set(user.apiKeyHash, id)
  resolveRegion(user) // fire-and-forget refine; doesn't block the response
  return { apiKey, userId: id }
}

// --- Server-side scheduling (persisted; survives a restart) --------------------
let seq = 1
const schedules = new Map() // id -> {id, userId, vin, action, fireAt, timer}
const GRACE_MS = 15 * 60 * 1000 // fire late (within 15 min) rather than drop silently

async function persistSchedules() {
  const plain = [...schedules.values()].map(({ id, userId, vin, action, fireAt }) => ({ id, userId, vin, action, fireAt }))
  try {
    await writeFile(SCHEDULES_PATH, JSON.stringify({ seq, schedules: plain }, null, 2))
  } catch (e) {
    log('persistSchedules failed:', e.message)
  }
}

function armTimer(id, userId, vin, fireAt) {
  const timer = setTimeout(() => fireSchedule(id), Math.max(0, fireAt - Date.now()))
  const entry = { id, userId, vin, action: 'unlock_drive', fireAt, timer }
  schedules.set(id, entry)
  return entry
}

async function fireSchedule(id) {
  const s = schedules.get(id)
  if (!s) return
  schedules.delete(id)
  await persistSchedules()
  const user = await loadUser(s.userId)
  if (!user) { log(`schedule ${id} FAILED — user ${s.userId} no longer exists`); return }
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await sendCommand(user, s.vin, 'unlock')
      await sendCommand(user, s.vin, 'drive')
      log(`schedule ${id} fired OK for ${s.vin}`)
      return
    } catch (e) {
      log(`schedule ${id} attempt ${attempt + 1} failed: ${e.message}`)
      if (attempt < 2) await sleep(5000)
    }
  }
  log(`schedule ${id} FAILED all attempts for ${s.vin}`)
}

async function scheduleUnlockDrive(userId, vin, delay) {
  const id = seq++
  const entry = armTimer(id, userId, vin, Date.now() + delay * 1000)
  await persistSchedules()
  return { id, vin, action: entry.action, fireAt: entry.fireAt }
}

async function cancelScheduleById(id) {
  const s = schedules.get(id)
  if (!s) return false
  clearTimeout(s.timer)
  schedules.delete(id)
  await persistSchedules()
  return true
}

async function restoreSchedules() {
  let raw
  try {
    raw = JSON.parse(await readFile(SCHEDULES_PATH, 'utf8'))
  } catch (e) {
    if (e.code !== 'ENOENT') log('restoreSchedules read failed:', e.message)
    return
  }
  seq = Math.max(seq, raw.seq || 1)
  for (const s of raw.schedules || []) {
    const overdueMs = Date.now() - s.fireAt
    if (overdueMs > GRACE_MS) {
      log(`schedule ${s.id} for ${s.vin} dropped — ${Math.round(overdueMs / 1000)}s overdue (service was down)`)
      continue
    }
    if (overdueMs > 0) log(`schedule ${s.id} for ${s.vin} is overdue by ${Math.round(overdueMs / 1000)}s — firing now`)
    else log(`schedule ${s.id} for ${s.vin} re-armed, fires in ${Math.round(-overdueMs / 1000)}s`)
    armTimer(s.id, s.userId, s.vin, s.fireAt)
  }
  await persistSchedules()
}

// --- HTTP ------------------------------------------------------------------------
const json = (res, code, obj) => {
  res.writeHead(code, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(obj))
}
const html = (res, code, body) => {
  res.writeHead(code, { 'Content-Type': 'text/html; charset=utf-8' })
  res.end(body)
}
async function readBody(req) {
  const chunks = []
  for await (const c of req) chunks.push(c)
  const s = Buffer.concat(chunks).toString('utf8')
  return s ? JSON.parse(s) : {}
}

// Bounce page: Tesla redirects the in-app browser HERE after login (this
// server's own domain, matching the registered Allowed Redirect URI), and this
// page's only job is to hand the code+state to the app's custom URL scheme so
// ASWebAuthenticationSession can intercept it — the same pattern already
// proven for the single-tenant personal relay's manual login flow.
function callbackHTML(code, state, error) {
  if (error) {
    return `<!doctype html><meta charset="utf-8"><title>EEAccess</title>
      <p style="font-family:system-ui">Sign-in failed: ${error}. Return to the app and try again.</p>`
  }
  const target = `eeaccess://tesla/relay-callback?code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`
  return `<!doctype html><meta charset="utf-8"><title>EEAccess</title>
    <script>location.replace(${JSON.stringify(target)})</script>
    <p style="font-family:system-ui">Returning to EEAccess…</p>`
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x')
    const p = url.pathname.split('/').filter(Boolean)

    if (url.pathname === '/health') return json(res, 200, { ok: true, users: apiKeyIndex.size })

    if (req.method === 'GET' && url.pathname === '/oauth/start') {
      return json(res, 200, startOAuth())
    }
    if (req.method === 'GET' && url.pathname === '/oauth/callback') {
      return html(res, 200, callbackHTML(url.searchParams.get('code'), url.searchParams.get('state'), url.searchParams.get('error')))
    }
    if (req.method === 'POST' && url.pathname === '/oauth/complete') {
      const body = await readBody(req)
      return json(res, 200, await completeOAuth(body.code, body.state))
    }

    // Everything below requires a valid per-user API key.
    const authHeader = req.headers.authorization || ''
    const key = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null
    const user = await userForApiKey(key)
    if (!user) return json(res, 401, { error: 'unauthorized' })

    // Disconnect must work even if this user is rate-limited — a stuck/buggy
    // client is exactly the situation where they need an escape hatch, and
    // this endpoint makes no Tesla API call, so it can't itself be abused to
    // burn the shared app's quota.
    if (req.method === 'DELETE' && url.pathname === '/account') {
      await deleteUser(user)
      return json(res, 200, { deleted: true })
    }

    if (rateLimited(user.id)) return json(res, 429, { error: 'rate limit exceeded — slow down' })

    if (req.method === 'GET' && url.pathname === '/vehicles')
      return json(res, 200, await tesla(user, 'GET', '/api/1/vehicles'))

    if (req.method === 'GET' && url.pathname === '/schedules') {
      return json(res, 200, [...schedules.values()]
        .filter((s) => s.userId === user.id)
        .map(({ id, vin, action, fireAt }) => ({ id, vin, action, fireAt })))
    }

    if (req.method === 'DELETE' && p[0] === 'schedules' && p[1]) {
      const id = Number(p[1])
      const s = schedules.get(id)
      if (s && s.userId !== user.id) return json(res, 403, { error: 'not your schedule' })
      return json(res, 200, { cancelled: (await cancelScheduleById(id)) ? id : null })
    }

    if (p[0] === 'vehicles' && p[1]) {
      const vin = p[1], sub = p[2]
      await assertOwnsVehicle(user, vin)
      if (req.method === 'GET' && sub === 'state') return json(res, 200, await tesla(user, 'GET', `/api/1/vehicles/${vin}/vehicle_data`))
      if (req.method === 'POST' && sub === 'wake') return json(res, 200, await tesla(user, 'POST', `/api/1/vehicles/${vin}/wake_up`))
      if (req.method === 'POST' && sub === 'schedule') {
        const body = await readBody(req)
        return json(res, 200, await scheduleUnlockDrive(user.id, vin, Number(body.delay ?? 60)))
      }
      if (req.method === 'POST' && CMD[sub]) return json(res, 200, await sendCommand(user, vin, sub))
    }

    json(res, 404, { error: 'not found' })
  } catch (e) {
    log('error:', e.message)
    const status = e instanceof UpstreamError && e.status >= 400 && e.status < 600 ? e.status : 502
    json(res, status, { error: e.message })
  }
})

await restoreSchedules()

server.listen(config.port || 8737, config.host || '0.0.0.0', () => {
  log(`EEAccess Tesla relay (multi-tenant) listening on ${config.host || '0.0.0.0'}:${config.port || 8737}`)
})
