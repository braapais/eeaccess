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

const __dir = dirname(fileURLToPath(import.meta.url))
const CONFIG_PATH = process.env.EEACCESS_CONFIG || join(__dir, 'config.json')
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

async function tesla(method, path) {
  const token = await getAccessToken()
  const res = await fetch(effectiveBase + path, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: method === 'POST' ? '{}' : undefined,
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`${res.status}: ${text.slice(0, 200)}`)
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
let seq = 1
const schedules = new Map() // id -> {id, vin, action, fireAt, timer}

function scheduleUnlockDrive(vin, delay) {
  const id = seq++
  const fireAt = Date.now() + delay * 1000
  const timer = setTimeout(async () => {
    const s = schedules.get(id)
    schedules.delete(id)
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        await sendCommand(vin, 'unlock')
        await sendCommand(vin, 'drive')
        log(`schedule ${id} fired OK for ${vin}`)
        return
      } catch (e) {
        log(`schedule ${id} attempt ${attempt + 1} failed: ${e.message}`)
        if (attempt < 2) await sleep(5000)
      }
    }
  }, delay * 1000)
  schedules.set(id, { id, vin, action: 'unlock_drive', fireAt, timer })
  return { id, vin, action: 'unlock_drive', fireAt }
}

// --- HTTP ---------------------------------------------------------------------
const authed = (req) => (req.headers.authorization || '') === `Bearer ${config.serverToken}`
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
      const id = Number(p[1]); const s = schedules.get(id)
      if (s) { clearTimeout(s.timer); schedules.delete(id) }
      return json(res, 200, { cancelled: id })
    }

    if (p[0] === 'vehicles' && p[1]) {
      const vin = p[1], sub = p[2]
      if (req.method === 'GET' && sub === 'state') return json(res, 200, await tesla('GET', `/api/1/vehicles/${vin}/vehicle_data`))
      if (req.method === 'POST' && sub === 'wake') return json(res, 200, await tesla('POST', `/api/1/vehicles/${vin}/wake_up`))
      if (req.method === 'POST' && sub === 'schedule') {
        const body = await readBody(req)
        return json(res, 200, scheduleUnlockDrive(vin, Number(body.delay ?? 60)))
      }
      if (req.method === 'POST' && CMD[sub]) return json(res, 200, await sendCommand(vin, sub))
    }

    json(res, 404, { error: 'not found' })
  } catch (e) {
    log('error:', e.message)
    json(res, 502, { error: e.message })
  }
})

server.listen(config.port || 8737, config.host || '0.0.0.0', () => {
  log(`EEAccess Tesla relay listening on ${config.host || '0.0.0.0'}:${config.port || 8737}`)
  if (config.refreshToken) resolveRegion()
})
