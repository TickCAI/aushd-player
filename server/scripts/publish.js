#!/usr/bin/env node
'use strict'

/**
 * Register a built artifact with the AusHD distribution service.
 *
 * Used by GitHub Actions after a release build, or manually:
 *   DIST_URL=https://dist.example.com ADMIN_TOKEN=xxx \
 *     node scripts/publish.js --platform windows --tag v1.0.1 \
 *       --file build/installer/AusHD-Player-1.0.1-setup.exe
 *
 * If --url is omitted, a GitHub Releases download URL is derived from
 * GITHUB_REPOSITORY (set automatically by Actions) and the tag.
 */
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

const args = {}
for (let i = 2; i < process.argv.length; i += 1) {
  const a = process.argv[i]
  if (!a.startsWith('--')) continue
  const key = a.slice(2)
  const next = process.argv[i + 1]
  args[key] = next && !next.startsWith('--') ? (() => { i += 1; return next })() : 'true'
}

const base = String(process.env.DIST_URL || '').replace(/\/+$/, '')
const token = process.env.ADMIN_TOKEN || ''
const tag = String(args.tag || '').trim()
const platform = String(args.platform || '').trim()
const channel = String(args.channel || 'stable').trim()

if (!base || !token) {
  console.error('DIST_URL and ADMIN_TOKEN environment variables are required.')
  process.exit(1)
}
if (!tag || !platform) {
  console.error('--tag and --platform are required.')
  process.exit(1)
}

const file = args.file && args.file !== 'true' ? path.resolve(args.file) : null
const payload = {
  tag,
  platform,
  channel,
  name: args.name && args.name !== 'true' ? args.name : `AusHD Player ${tag.replace(/^v/, '')}`,
  version: args.version && args.version !== 'true' ? args.version : tag.replace(/^v/, ''),
  notes: args.notes && args.notes !== 'true' ? args.notes : '',
  mandatory: args.mandatory === 'true',
}

if (file) {
  if (!fs.existsSync(file)) {
    console.error('Artifact not found:', file)
    process.exit(1)
  }
  const buf = fs.readFileSync(file)
  payload.file = path.basename(file)
  payload.size = buf.length
  payload.sha256 = crypto.createHash('sha256').update(buf).digest('hex')
} else {
  if (args.size) payload.size = Number(args.size)
  if (args.sha256) payload.sha256 = String(args.sha256)
}

if (args.url && args.url !== 'true') {
  payload.url = args.url
} else if (process.env.GITHUB_REPOSITORY && payload.file) {
  payload.url = `https://github.com/${process.env.GITHUB_REPOSITORY}/releases/download/${encodeURIComponent(tag)}/${encodeURIComponent(payload.file)}`
} else if (args.url === undefined && payload.file) {
  payload.url = `${base}/download/${encodeURIComponent(payload.file)}`
}

;(async () => {
  const res = await fetch(`${base}/api/admin/releases`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(payload),
  })
  const text = await res.text()
  if (!res.ok) {
    console.error(`Publish failed (HTTP ${res.status}): ${text}`)
    process.exit(1)
  }
  console.log('Published', tag, platform, channel, 'sha256', payload.sha256 || '(none)')
  console.log(text)
})().catch((err) => {
  console.error('Publish failed:', err.message)
  process.exit(1)
})
