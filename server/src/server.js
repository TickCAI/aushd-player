'use strict'

/**
 * AusHD Player distribution service.
 *
 * Endpoints:
 *   GET  /healthz
 *   GET  /api/releases                 list releases (platform / channel filters)
 *   GET  /api/releases/latest          newest release for a platform+channel
 *   GET  /download/:file               artifact hosting (Range supported)
 *   POST /api/admin/releases           register / update a release (Bearer token)
 *   DELETE /api/admin/releases         remove a release (Bearer token)
 *   GET  /api/admin/codes              list link codes (Bearer token)
 *   POST /api/admin/codes              upsert a link code (Bearer token)
 *   POST /api/app/link                 upstream-compatible hub link protocol
 *   POST /api/app/logs                 client diagnostic log upload
 *   GET  /api/admin/logs               list uploaded log ids (Bearer token)
 *
 * Zero runtime dependencies. Data lives in DATA_DIR as JSON files.
 */
const http = require('http')
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const { URL } = require('url')
const { Store } = require('./store')

const cfg = {
  port: Number(process.env.PORT || 8787),
  dataDir: path.resolve(process.env.DATA_DIR || path.join(__dirname, '..', 'data')),
  artifactsDir: path.resolve(process.env.ARTIFACTS_DIR || path.join(__dirname, '..', 'artifacts')),
  adminToken: process.env.ADMIN_TOKEN || '',
  publicBaseUrl: (process.env.PUBLIC_BASE_URL || `http://localhost:${process.env.PORT || 8787}`).replace(/\/+$/, ''),
  maxBody: Number(process.env.MAX_BODY_BYTES || 2 * 1024 * 1024),
}

fs.mkdirSync(cfg.artifactsDir, { recursive: true })
const store = new Store(cfg.dataDir)
const startedAt = Date.now()
const hits = new Map()

const PLATFORMS = ['windows', 'linux', 'androidtv']
const CHANNELS = ['stable', 'beta']
const DEFAULT_FEATURES = { requests: false, together: false, profiles: false, redownload: false }

function json(res, status, obj, extra = {}) {
  const body = Buffer.from(JSON.stringify(obj))
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': body.length,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...extra,
  })
  res.end(body)
}

function fail(res, status, code, message) {
  json(res, status, { code, message })
}

function noContent(res) {
  res.writeHead(204, { 'cache-control': 'no-store' })
  res.end()
}

function log(...parts) {
  console.log(new Date().toISOString(), ...parts)
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let size = 0
    let done = false
    req.on('data', (c) => {
      size += c.length
      if (size > limit) {
        done = true
        reject(Object.assign(new Error('body too large'), { status: 413 }))
        req.destroy()
        return
      }
      chunks.push(c)
    })
    req.on('end', () => {
      if (done) return
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {})
      } catch {
        reject(Object.assign(new Error('invalid JSON'), { status: 400 }))
      }
    })
    req.on('error', reject)
  })
}

function safeEqual(a, b) {
  const aa = Buffer.from(String(a))
  const bb = Buffer.from(String(b))
  return aa.length === bb.length && crypto.timingSafeEqual(aa, bb)
}

function isAdmin(req) {
  if (!cfg.adminToken) return false
  const h = String(req.headers.authorization || '')
  return h.startsWith('Bearer ') && safeEqual(h.slice(7), cfg.adminToken)
}

function rateOk(key, max = 30, windowMs = 60_000) {
  const now = Date.now()
  const arr = (hits.get(key) || []).filter((t) => now - t < windowMs)
  arr.push(now)
  hits.set(key, arr)
  return arr.length <= max
}

function clientIp(req) {
  return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown').split(',')[0].trim()
}

function contentType(name) {
  const ext = path.extname(name).toLowerCase()
  return {
    '.exe': 'application/vnd.microsoft.portable-executable',
    '.apk': 'application/vnd.android.package-archive',
    '.gz': 'application/gzip',
    '.zip': 'application/zip',
    '.json': 'application/json',
    '.txt': 'text/plain; charset=utf-8',
  }[ext] || 'application/octet-stream'
}

function releases() {
  const list = store.read('releases.json', [])
  return Array.isArray(list) ? list : []
}

function pickLatest(list, platform, channel) {
  return list
    .filter((r) => r.platform === platform && (r.channel || 'stable') === channel && r.enabled !== false)
    .sort((a, b) => String(b.publishedAt || '').localeCompare(String(a.publishedAt || '')))[0]
}

function artifactPath(name) {
  if (!name || name.includes('/') || name.includes('\\') || name.includes('..') || name.includes('\0')) return null
  const resolved = path.resolve(cfg.artifactsDir, name)
  if (!resolved.startsWith(cfg.artifactsDir + path.sep)) return null
  return resolved
}

function serveArtifact(req, res, url) {
  let name
  try {
    name = decodeURIComponent(url.pathname.slice('/download/'.length))
  } catch {
    return fail(res, 400, 'bad-path', 'Invalid file name.')
  }
  const file = artifactPath(name)
  if (!file) return fail(res, 400, 'bad-path', 'Invalid file name.')
  let stat
  try {
    stat = fs.statSync(file)
  } catch {
    return fail(res, 404, 'not-found', 'Artifact not found.')
  }
  if (!stat.isFile()) return fail(res, 404, 'not-found', 'Artifact not found.')
  const type = contentType(name)
  const range = String(req.headers.range || '')
  const base = {
    'content-type': type,
    'accept-ranges': 'bytes',
    'content-disposition': `attachment; filename="${path.basename(name).replace(/["\r\n]/g, '')}"`,
    'x-content-type-options': 'nosniff',
  }
  if (range.startsWith('bytes=')) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim())
    if (!m) return fail(res, 416, 'bad-range', 'Invalid Range header.')
    const start = m[1] ? Number(m[1]) : 0
    const end = m[2] ? Math.min(Number(m[2]), stat.size - 1) : stat.size - 1
    if (!Number.isFinite(start) || !Number.isFinite(end) || start > end || start >= stat.size) {
      return fail(res, 416, 'bad-range', 'Range not satisfiable.')
    }
    res.writeHead(206, {
      ...base,
      'content-range': `bytes ${start}-${end}/${stat.size}`,
      'content-length': end - start + 1,
    })
    if (req.method === 'HEAD') return res.end()
    fs.createReadStream(file, { start, end }).pipe(res)
    return
  }
  res.writeHead(200, { ...base, 'content-length': stat.size })
  if (req.method === 'HEAD') return res.end()
  fs.createReadStream(file).pipe(res)
}

function linkResponse(entry) {
  return {
    server: {
      name: (entry.server && entry.server.name) || 'Media server',
      url: (entry.server && entry.server.url) || 'https://emby.example.com',
      kind: (entry.server && entry.server.kind) || 'emby',
    },
    hub: cfg.publicBaseUrl,
    features: { ...DEFAULT_FEATURES, ...(entry.features || {}) },
    refreshHours: Number(entry.refreshHours || 6),
    tmdbApiKey: entry.tmdbApiKey || '',
    mdblistApiKey: entry.mdblistApiKey || '',
    metadataLanguage: entry.metadataLanguage || 'zh-CN',
    seerr: entry.seerr || { enabled: false, url: '' },
    liveTv: {
      xtreamUrl: (entry.liveTv && entry.liveTv.xtreamUrl) || '',
      xtreamAccounts: (entry.liveTv && entry.liveTv.xtreamAccounts) || [],
      playlistUrl: (entry.liveTv && entry.liveTv.playlistUrl) || '',
      playlistGuideUrl: (entry.liveTv && entry.liveTv.playlistGuideUrl) || '',
    },
  }
}

async function handle(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
  const p = url.pathname.replace(/\/+$/, '') || '/'
  const method = req.method
  const ip = clientIp(req)

  if (p === '/healthz' && method === 'GET') {
    return json(res, 200, {
      ok: true,
      service: 'aushd-distribution',
      version: '1.0.0',
      uptimeSec: Math.floor((Date.now() - startedAt) / 1000),
      releases: releases().length,
      adminEnabled: Boolean(cfg.adminToken),
    })
  }

  if (p === '/' && method === 'GET') {
    const body = `<!doctype html><meta charset="utf-8"><title>AusHD distribution</title>
      <body style="font:14px/1.6 system-ui;max-width:720px;margin:48px auto;color:#212228">
      <h1>AusHD Player 分发服务</h1>
      <p>状态正常 · 版本记录 ${releases().length} 条 · 管理接口 ${cfg.adminToken ? '已启用' : '未启用'}</p>
      <ul>
        <li><code>GET /healthz</code> 健康检查</li>
        <li><code>GET /api/releases/latest?platform=windows&amp;channel=stable</code> 最新版本</li>
        <li><code>GET /api/releases</code> 版本列表</li>
        <li><code>GET /download/:file</code> 安装包下载</li>
        <li><code>POST /api/app/link</code> 兑换码配置下发</li>
      </ul></body>`
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' })
    return res.end(body)
  }

  if (p === '/api/releases' && method === 'GET') {
    const platform = url.searchParams.get('platform')
    const channel = url.searchParams.get('channel')
    const list = releases().filter(
      (r) => (!platform || r.platform === platform) && (!channel || (r.channel || 'stable') === channel),
    )
    return json(res, 200, { releases: list })
  }

  if (p === '/api/releases/latest' && method === 'GET') {
    const platform = (url.searchParams.get('platform') || '').trim()
    const channel = (url.searchParams.get('channel') || 'stable').trim()
    if (!PLATFORMS.includes(platform)) {
      return fail(res, 400, 'bad-platform', `platform must be one of ${PLATFORMS.join(', ')}`)
    }
    if (!CHANNELS.includes(channel)) {
      return fail(res, 400, 'bad-channel', `channel must be one of ${CHANNELS.join(', ')}`)
    }
    const latest = pickLatest(releases(), platform, channel)
    if (!latest) return noContent(res)
    const current = url.searchParams.get('current') || ''
    if (current && current === latest.tag) return noContent(res)
    const download = latest.url || (latest.file ? `${cfg.publicBaseUrl}/download/${encodeURIComponent(latest.file)}` : '')
    if (!download) return fail(res, 500, 'no-download', 'Release has no download URL.')
    return json(res, 200, {
      available: true,
      tag: latest.tag,
      name: latest.name || latest.tag,
      version: latest.version || '',
      platform: latest.platform,
      channel: latest.channel || 'stable',
      download,
      size: Number(latest.size || 0),
      sha256: latest.sha256 || '',
      notes: latest.notes || '',
      mandatory: Boolean(latest.mandatory),
      publishedAt: latest.publishedAt || '',
    })
  }

  if (p.startsWith('/download/') && (method === 'GET' || method === 'HEAD')) {
    return serveArtifact(req, res, url)
  }

  if (p === '/api/admin/releases' && method === 'POST') {
    if (!isAdmin(req)) return fail(res, 401, 'unauthorized', 'A valid admin token is required.')
    let body
    try {
      body = await readBody(req, cfg.maxBody)
    } catch (err) {
      return fail(res, err.status || 400, 'bad-body', err.message)
    }
    const tag = String(body.tag || '').trim()
    const platform = String(body.platform || '').trim()
    const channel = String(body.channel || 'stable').trim()
    if (!/^[A-Za-z0-9._-]{1,64}$/.test(tag)) return fail(res, 400, 'bad-tag', 'Invalid tag.')
    if (!PLATFORMS.includes(platform)) return fail(res, 400, 'bad-platform', 'Invalid platform.')
    if (!CHANNELS.includes(channel)) return fail(res, 400, 'bad-channel', 'Invalid channel.')
    if (body.sha256 && !/^[a-f0-9]{64}$/i.test(String(body.sha256))) {
      return fail(res, 400, 'bad-sha256', 'sha256 must be a 64 character hex digest.')
    }
    if (!body.url && !body.file) return fail(res, 400, 'missing-artifact', 'Provide url or file.')
    const list = releases()
    const idx = list.findIndex((r) => r.tag === tag && r.platform === platform && (r.channel || 'stable') === channel)
    const record = {
      tag,
      platform,
      channel,
      name: String(body.name || tag),
      version: String(body.version || tag.replace(/^v/, '')),
      url: body.url ? String(body.url) : undefined,
      file: body.file ? String(body.file) : undefined,
      size: Number(body.size || 0),
      sha256: body.sha256 ? String(body.sha256).toLowerCase() : '',
      notes: String(body.notes || ''),
      mandatory: Boolean(body.mandatory),
      enabled: body.enabled !== false,
      publishedAt: idx >= 0 && list[idx].publishedAt ? list[idx].publishedAt : new Date().toISOString(),
    }
    Object.keys(record).forEach((k) => record[k] === undefined && delete record[k])
    if (idx >= 0) list[idx] = record
    else list.push(record)
    store.write('releases.json', list)
    log('[admin] release saved', tag, platform, channel)
    return json(res, 200, { ok: true, release: record })
  }

  if (p === '/api/admin/releases' && method === 'DELETE') {
    if (!isAdmin(req)) return fail(res, 401, 'unauthorized', 'A valid admin token is required.')
    const tag = String(url.searchParams.get('tag') || '')
    const platform = String(url.searchParams.get('platform') || '')
    const channel = String(url.searchParams.get('channel') || 'stable')
    const before = releases().length
    const list = releases().filter(
      (r) => !(r.tag === tag && r.platform === platform && (r.channel || 'stable') === channel),
    )
    store.write('releases.json', list)
    return json(res, 200, { ok: true, removed: before - list.length })
  }

  if (p === '/api/admin/codes' && method === 'GET') {
    if (!isAdmin(req)) return fail(res, 401, 'unauthorized', 'A valid admin token is required.')
    const codes = store.read('codes.json', {})
    return json(res, 200, {
      codes: Object.entries(codes).map(([code, v]) => ({ code, active: v.active !== false, expiresAt: v.expiresAt || null })),
    })
  }

  if (p === '/api/admin/codes' && method === 'POST') {
    if (!isAdmin(req)) return fail(res, 401, 'unauthorized', 'A valid admin token is required.')
    let body
    try {
      body = await readBody(req, cfg.maxBody)
    } catch (err) {
      return fail(res, err.status || 400, 'bad-body', err.message)
    }
    const code = String(body.code || '').trim().toUpperCase()
    if (!/^[A-Z0-9-]{4,64}$/.test(code)) return fail(res, 400, 'bad-code', 'Invalid code.')
    const codes = store.read('codes.json', {})
    if (body.delete) delete codes[code]
    else codes[code] = { ...(body.config || body || {}), active: body.active !== false }
    store.write('codes.json', codes)
    log('[admin] code saved', code)
    return json(res, 200, { ok: true, code })
  }

  if (p === '/api/app/link' && method === 'POST') {
    if (!rateOk(`link:${ip}`, 20)) return fail(res, 429, 'rate-limited', 'Too many attempts, try again later.')
    let body
    try {
      body = await readBody(req, 64 * 1024)
    } catch (err) {
      return fail(res, err.status || 400, 'bad-body', err.message)
    }
    const code = String(body.code || '').trim().toUpperCase()
    const codes = store.read('codes.json', {})
    const entry = codes[code]
    if (!entry) return fail(res, 400, 'unknown-code', 'This code is not valid.')
    if (entry.revoked) return fail(res, 400, 'revoked', 'This code has been revoked.')
    if (entry.active === false) return fail(res, 400, 'inactive', 'This code is inactive.')
    if (entry.expiresAt && Date.parse(entry.expiresAt) < Date.now()) {
      return fail(res, 400, 'unknown-code', 'This code has expired.')
    }
    const usage = store.read('link_usage.json', [])
    usage.push({ code, at: new Date().toISOString(), device: (body.device && body.device.id) || '' })
    store.write('link_usage.json', usage.slice(-500))
    log('[link] redeemed', code, 'device', (body.device && body.device.platform) || 'unknown')
    return json(res, 200, linkResponse(entry))
  }

  if (p === '/api/app/logs' && method === 'POST') {
    if (!rateOk(`logs:${ip}`, 10)) return fail(res, 429, 'rate-limited', 'Too many uploads, try again later.')
    let body
    try {
      body = await readBody(req, cfg.maxBody)
    } catch (err) {
      return fail(res, err.status || 400, 'bad-body', err.message)
    }
    const id = crypto.randomUUID()
    const dir = path.join(cfg.dataDir, 'logs')
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(
      path.join(dir, `${id}.json`),
      JSON.stringify({
        id,
        at: new Date().toISOString(),
        device: body.device || {},
        note: String(body.note || '').slice(0, 2000),
        text: String(body.text || '').slice(0, cfg.maxBody),
      }, null, 2),
      'utf8',
    )
    log('[logs] stored', id)
    return json(res, 200, { id })
  }

  if (p === '/api/admin/logs' && method === 'GET') {
    if (!isAdmin(req)) return fail(res, 401, 'unauthorized', 'A valid admin token is required.')
    const dir = path.join(cfg.dataDir, 'logs')
    let ids = []
    try {
      ids = fs.readdirSync(dir).filter((f) => f.endsWith('.json')).map((f) => f.replace(/\.json$/, ''))
    } catch {}
    return json(res, 200, { logs: ids.slice(-100) })
  }

  return fail(res, 404, 'not-found', 'No such endpoint.')
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((err) => {
    log('[error]', err.message)
    if (!res.headersSent) fail(res, 500, 'internal', 'Internal server error.')
    else res.end()
  })
})

server.listen(cfg.port, () => {
  log(`[boot] AusHD distribution listening on :${cfg.port}`)
  log(`[boot] data=${cfg.dataDir} artifacts=${cfg.artifactsDir} publicBaseUrl=${cfg.publicBaseUrl}`)
  log(`[boot] admin API ${cfg.adminToken ? 'enabled' : 'DISABLED (set ADMIN_TOKEN)'}`)
})
