// One-time OAuth to seed the server's Tesla refresh token.
// Run:  node login.mjs
// It prints an authorize URL — open it, log in, and paste back the code shown
// on the braapais.github.io/tesla/manual page.
import { readFile, writeFile } from 'node:fs/promises'
import { createInterface } from 'node:readline/promises'
import { randomBytes, createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const __dir = dirname(fileURLToPath(import.meta.url))
const CONFIG_PATH = process.env.EEACCESS_CONFIG || join(__dir, 'config.json')
const AUTHORIZE = 'https://auth.tesla.com/oauth2/v3/authorize'
const TOKEN = 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token'
const REDIRECT = 'https://braapais.github.io/tesla/manual/'
const SCOPES = 'openid offline_access vehicle_device_data vehicle_cmds vehicle_charging_cmds'

const config = JSON.parse(await readFile(CONFIG_PATH, 'utf8'))
const b64url = (b) => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const verifier = b64url(randomBytes(32))
const challenge = b64url(createHash('sha256').update(verifier).digest())

const url = new URL(AUTHORIZE)
url.search = new URLSearchParams({
  response_type: 'code',
  client_id: config.clientId,
  redirect_uri: REDIRECT,
  scope: SCOPES,
  state: b64url(randomBytes(16)),
  code_challenge: challenge,
  code_challenge_method: 'S256',
}).toString()

console.log('\n1) Open in a browser and log in with your Tesla account:\n')
console.log(url.toString())
console.log('\n2) You land on a page showing a code. Paste it here.\n')

const rl = createInterface({ input: process.stdin, output: process.stdout })
const code = (await rl.question('code: ')).trim()
rl.close()

const body = new URLSearchParams({
  grant_type: 'authorization_code',
  client_id: config.clientId,
  code,
  code_verifier: verifier,
  redirect_uri: REDIRECT,
  audience: config.regionBase,
})
if (config.clientSecret) body.set('client_secret', config.clientSecret)

const res = await fetch(TOKEN, {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body,
})
if (!res.ok) {
  console.error('token exchange failed:', res.status, await res.text())
  process.exit(1)
}
const j = await res.json()
config.refreshToken = j.refresh_token
await writeFile(CONFIG_PATH, JSON.stringify(config, null, 2))
console.log('\n✅ Refresh token saved. Start the server: node server.mjs (or the systemd service).')
