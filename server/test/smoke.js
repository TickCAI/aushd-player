'use strict'

/** End-to-end smoke test: boots a temporary server instance and exercises every API. */
const { spawn } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const crypto = require('crypto')

const PORT = 8799
const BASE = `http://127.0.0.1:${PORT}`
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'aushd-dist-test-'))
const artifacts = path.join(tmp, 'artifacts')
fs.mkdirSync(artifacts, { recursive: true })
const sample = Buffer.from('AUSHD-PLAYER-TEST-ARTIFACT-0123456789')
fs.writeFileSync(path.join(artifacts, 'AusHD-Player-1.0.1-setup.exe'), sample)
const sha256 = crypto.createHash('sha256').update(sample).digest('hex')
fs.writeFileSync(
  path.join(tmp, 'codes.json'),
  JSON.stringify({
    'DEMO-1234': {
      active: true,
      server: { name: 'Demo Emby', url: 'https://emby.example.com', kind: 'emby' },
      features: { requests: true, together: false, profiles: true, redownload: true },
      metadataLanguage: 'zh-CN',
    },
  }),
)
const admin = { authorization: 'Bearer test-token', 'content-type': 'application/json' }
let passed = 0

function check(name, cond, extra = '') {
  if (!cond) throw new Error(`FAIL: ${name} ${extra}`)
  passed += 1
  console.log('  ok', name)
}

async function waitForServer() {
  for (let i = 0; i < 40; i += 1) {
    try {
      const r = await fetch(`${BASE}/healthz`)
      if (r.ok) return
    } catch {}
    await new Promise((r) => setTimeout(r, 150))
  }
  throw new Error('server did not start')
}

const child = spawn(process.execPath, [path.join(__dirname, '..', 'src', 'server.js')], {
  env: {
    ...process.env,
    PORT: String(PORT),
    DATA_DIR: tmp,
    ARTIFACTS_DIR: artifacts,
    ADMIN_TOKEN: 'test-token',
    PUBLIC_BASE_URL: BASE,
  },
  stdio: ['ignore', 'pipe', 'pipe'],
})
child.stdout.on('data', () => {})
child.stderr.on('data', (d) => process.stderr.write(d))

;(async () => {
  await waitForServer()

  let r = await fetch(`${BASE}/healthz`)
  check('healthz', r.status === 200 && (await r.json()).ok === true)

  r = await fetch(`${BASE}/api/admin/releases`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ tag: 'v1.0.1', platform: 'windows' }),
  })
  check('admin endpoint rejects missing token', r.status === 401)

  r = await fetch(`${BASE}/api/admin/releases`, {
    method: 'POST',
    headers: admin,
    body: JSON.stringify({
      tag: 'v1.0.1',
      platform: 'windows',
      channel: 'stable',
      name: 'AusHD Player 1.0.1',
      file: 'AusHD-Player-1.0.1-setup.exe',
      size: sample.length,
      sha256,
      notes: 'Smoke test release',
    }),
  })
  check('register release', r.status === 200)

  r = await fetch(`${BASE}/api/releases/latest?platform=windows&channel=stable`)
  const latest = await r.json()
  check('latest returns release', r.status === 200 && latest.tag === 'v1.0.1')
  check('latest carries checksum', latest.sha256 === sha256)
  check('latest carries download URL', latest.download.includes('/download/'))

  r = await fetch(`${BASE}/api/releases/latest?platform=windows&channel=stable&current=v1.0.1`)
  check('current version returns 204', r.status === 204)

  r = await fetch(`${BASE}/api/releases/latest?platform=linux`)
  check('unknown platform returns 204', r.status === 204)

  r = await fetch(`${BASE}/download/AusHD-Player-1.0.1-setup.exe`)
  check('artifact download', r.status === 200 && Buffer.from(await r.arrayBuffer()).equals(sample))

  r = await fetch(`${BASE}/download/AusHD-Player-1.0.1-setup.exe`, { headers: { range: 'bytes=0-3' } })
  check('range request', r.status === 206 && r.headers.get('content-range').startsWith('bytes 0-3/'))

  r = await fetch(`${BASE}/download/..%2F..%2Fetc%2Fpasswd`)
  check('path traversal blocked', r.status === 400 || r.status === 404)

  r = await fetch(`${BASE}/api/app/link`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code: 'DEMO-1234', device: { id: 'dev1', platform: 'windows' } }),
  })
  const link = await r.json()
  check('hub link protocol', r.status === 200 && link.hub === BASE && link.server.url.length > 0)
  check('hub link sets Chinese metadata', link.metadataLanguage === 'zh-CN')
  check('hub link features', link.features.requests === true && link.features.together === false)

  r = await fetch(`${BASE}/api/app/link`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code: 'NOPE' }),
  })
  check('bad link code rejected', r.status === 400 && (await r.json()).code === 'unknown-code')

  r = await fetch(`${BASE}/api/app/logs`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ device: { platform: 'windows' }, note: 'smoke', text: 'hello log' }),
  })
  check('log upload', r.status === 200 && typeof (await r.json()).id === 'string')

  r = await fetch(`${BASE}/api/releases`)
  check('release list', (await r.json()).releases.length === 1)

  r = await fetch(`${BASE}/api/admin/codes`, { headers: admin })
  check('admin codes list', r.status === 200 && (await r.json()).codes.length === 1)

  console.log(`\nPASS: ${passed} checks`)
})()
  .catch((err) => {
    console.error(err.message)
    process.exitCode = 1
  })
  .finally(() => {
    child.kill()
    try { fs.rmSync(tmp, { recursive: true, force: true }) } catch {}
  })
