// EEAccess Tesla relay — a tiny zero-dependency Node service that holds your
// Tesla Fleet credentials, keeps the access token fresh, relays commands, and
// (the point) can schedule Unlock+Drive server-side so it fires even when your
// phone/watch has no signal in a garage. Reachable only over your tailnet.
//
// Run:  node server.mjs        (config from ./config.json, see config.example.json)
import { createServer } from 'node:http'
import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { timingSafeEqual } from 'node:crypto'

const __dir = dirname(fileURLToPath(import.meta.url))
const CONFIG_PATH = process.env.EEACCESS_CONFIG || join(__dir, 'config.json')
const SCHEDULES_PATH = process.env.EEACCESS_SCHEDULES || join(__dir, 'schedules.json')
const TOKEN_URL = 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token'

let config = JSON.parse(await readFile(CONFIG_PATH, 'utf8'))
const log = (...a) => console.log(new Date().toISOString(), ...a)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// --- Token management ---------------------------------------------------------
let accessToken = null
let accessExpiry = 0
let effectiveBase = config.regionBase

async function getAccessToken() {
  if (accessToken && Date.now() < accessExpiry - 120_000) return accessToken
  if (!config.refreshToken) throw new Error('no refresh token — run: node login.mjs')
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: config.clientId,
    refresh_token: config.refreshToken,
  })
  if (config.clientSecret) body.set('client_secret', config.clientSecret)
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) throw new Error(`token refresh ${res.status}: ${(await res.text()).slice(0, 200)}`)
  const j = await res.json()
  accessToken = j.access_token
  accessExpiry = Date.now() + j.expires_in * 1000
  // Tesla may rotate the refresh token — persist a new one so we don't lose it.
  if (j.refresh_token && j.refresh_token !== config.refreshToken) {
    config.refreshToken = j.refresh_token
    await writeFile(CONFIG_PATH, JSON.stringify(config, null, 2))
    log('rotated refresh token persisted')
  }
  return accessToken
}

// Tesla routes user data to the account's home-region host — resolve it once.
async function resolveRegion() {
  try {
    const token = await getAccessToken()
    const res = await fetch(config.regionBase + '/api/1/users/region', {
      headers: { Authorization: `Bearer ${token}` },
    })
    if (res.ok) {
      const j = await res.json()
      if (j.response?.fleet_api_base_url) {
        effectiveBase = j.response.fleet_api_base_url
        log('region base:', effectiveBase)
      }
    }
  } catch (e) {
    log('region resolve failed:', e.message)
  }
}

// Carries Tesla's actual HTTP status (e.g. 408 = vehicle asleep) so the HTTP
// handler can forward it instead of flattening every upstream failure to a
// generic 502 — the app needs the real code to show the right message.
class UpstreamError extends Error {
  constructor(status, body) {
    super(`${status}: ${body}`)
    this.status = status
  }
}

async function tesla(method, path) {
  const token = await getAccessToken()
  const res = await fetch(effectiveBase + path, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: method === 'POST' ? '{}' : undefined,
  })
  const text = await res.text()
  if (!res.ok) throw new UpstreamError(res.status, text.slice(0, 200))
  return text ? JSON.parse(text) : {}
}

// pre-2021 S/X accept these unsigned; 2021+ need the signing proxy (phase 2).
const CMD = {
  unlock: 'door_unlock',
  lock: 'door_lock',
  drive: 'remote_start_drive',
  climate_on: 'auto_conditioning_start',
  climate_off: 'auto_conditioning_stop',
}
const sendCommand = (vin, cmd) => tesla('POST', `/api/1/vehicles/${vin}/command/${CMD[cmd]}`)

// --- Server-side scheduling ---------------------------------------------------
// Persisted to disk so a pending "Unlock & Drive" survives a service restart
// (crash, `systemctl restart`, box reboot) — the whole point of scheduling
// server-side is that it fires even when nothing else is around to retry it.
let seq = 1
const schedules = new Map() // id -> {id, vin, action, fireAt, timer}
const GRACE_MS = 15 * 60 * 1000 // fire late (within 15 min) rather than drop silently

async function persistSchedules() {
  const plain = [...schedules.values()].map(({ id, vin, action, fireAt }) => ({ id, vin, action, fireAt }))
  try {
    await writeFile(SCHEDULES_PATH, JSON.stringify({ seq, schedules: plain }, null, 2))
  } catch (e) {
    log('persistSchedules failed:', e.message)
  }
}

function armTimer(id, vin, fireAt) {
  const timer = setTimeout(() => fireSchedule(id), Math.max(0, fireAt - Date.now()))
  const entry = { id, vin, action: 'unlock_drive', fireAt, timer }
  schedules.set(id, entry)
  return entry
}

async function fireSchedule(id) {
  const s = schedules.get(id)
  if (!s) return
  schedules.delete(id)
  await persistSchedules()
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await sendCommand(s.vin, 'unlock')
      await sendCommand(s.vin, 'drive')
      log(`schedule ${id} fired OK for ${s.vin}`)
      return
    } catch (e) {
      log(`schedule ${id} attempt ${attempt + 1} failed: ${e.message}`)
      if (attempt < 2) await sleep(5000)
    }
  }
  log(`schedule ${id} FAILED all attempts for ${s.vin}`)
}

async function scheduleUnlockDrive(vin, delay) {
  const id = seq++
  const entry = armTimer(id, vin, Date.now() + delay * 1000)
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

// Re-arms whatever was still pending when the process last stopped. An
// overdue schedule (service was down past its fire time) fires immediately if
// within the grace window, else is dropped (logged, not silently lost).
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
    armTimer(s.id, s.vin, s.fireAt)
  }
  await persistSchedules()
}

// --- HTTP ---------------------------------------------------------------------
// Accept either a bearer token (apps) or HTTP Basic username/password (humans/
// browser). Always run behind HTTPS (nginx TLS) — the credential is only as
// private as the transport. Comparisons are constant-time so response timing
// can't leak how much of the token/password was correct.
function safeEqual(a, b) {
  const bufA = Buffer.from(a)
  const bufB = Buffer.from(b)
  // timingSafeEqual requires equal-length buffers; a length mismatch already
  // means "not equal" and doesn't need to be constant-time to say so.
  return bufA.length === bufB.length && timingSafeEqual(bufA, bufB)
}
function authed(req) {
  const h = req.headers.authorization || ''
  if (config.serverToken && h.startsWith('Bearer ') && safeEqual(h.slice(7), config.serverToken)) return true
  if (h.startsWith('Basic ') && config.username) {
    const [u, p] = Buffer.from(h.slice(6), 'base64').toString('utf8').split(':')
    return u === config.username && safeEqual(p || '', config.password)
  }
  return false
}
const json = (res, code, obj) => {
  res.writeHead(code, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(obj))
}
async function readBody(req) {
  const chunks = []
  for await (const c of req) chunks.push(c)
  const s = Buffer.concat(chunks).toString('utf8')
  return s ? JSON.parse(s) : {}
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x')
    const p = url.pathname.split('/').filter(Boolean)

    if (url.pathname === '/health') return json(res, 200, { ok: true, base: effectiveBase })
    if (!authed(req)) return json(res, 401, { error: 'unauthorized' })

    if (req.method === 'GET' && url.pathname === '/vehicles')
      return json(res, 200, await tesla('GET', '/api/1/vehicles'))

    if (req.method === 'GET' && url.pathname === '/schedules')
      return json(res, 200, [...schedules.values()].map(({ id, vin, action, fireAt }) => ({ id, vin, action, fireAt })))

    if (req.method === 'DELETE' && p[0] === 'schedules' && p[1]) {
      return json(res, 200, { cancelled: await cancelScheduleById(Number(p[1])) ? Number(p[1]) : null })
    }

    if (p[0] === 'vehicles' && p[1]) {
      const vin = p[1], sub = p[2]
      if (req.method === 'GET' && sub === 'state') return json(res, 200, await tesla('GET', `/api/1/vehicles/${vin}/vehicle_data`))
      if (req.method === 'POST' && sub === 'wake') return json(res, 200, await tesla('POST', `/api/1/vehicles/${vin}/wake_up`))
      if (req.method === 'POST' && sub === 'schedule') {
        const body = await readBody(req)
        return json(res, 200, await scheduleUnlockDrive(vin, Number(body.delay ?? 60)))
      }
      if (req.method === 'POST' && CMD[sub]) return json(res, 200, await sendCommand(vin, sub))
    }

    json(res, 404, { error: 'not found' })
  } catch (e) {
    log('error:', e.message)
    // Forward Tesla's real status (e.g. 408 = asleep) when we have one;
    // anything else (our own bugs, network errors) is a genuine 502.
    const status = e instanceof UpstreamError && e.status >= 400 && e.status < 600 ? e.status : 502
    json(res, status, { error: e.message })
  }
})

await restoreSchedules()

server.listen(config.port || 8737, config.host || '0.0.0.0', () => {
  log(`EEAccess Tesla relay listening on ${config.host || '0.0.0.0'}:${config.port || 8737}`)
  if (config.refreshToken) resolveRegion()
})
