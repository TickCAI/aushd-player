#!/usr/bin/env node
'use strict'

/**
 * Pre-flight check for a deployed AusHD distribution service.
 * Zero dependencies, Node >= 18.
 *
 *   node scripts/check-deploy.js --url https://dist.your-domain.com
 *   DIST_URL=https://dist.your-domain.com npm run check:deploy
 *
 * Exits 0 when the service is usable by the client, 1 otherwise.
 */

function arg(name) {
  const i = process.argv.indexOf(name)
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null
}

const raw = arg('--url') || process.env.DIST_URL || 'http://127.0.0.1:8787'
const base = raw.replace(/\/+$/, '')
const results = []

function record(ok, label, detail) {
  results.push({ ok, label, detail })
  console.log(`${ok ? '  OK  ' : ' FAIL '} ${label}${detail ? ` — ${detail}` : ''}`)
}

async function call(path, init = {}) {
  const res = await fetch(base + path, {
    ...init,
    signal: AbortSignal.timeout(8000),
    headers: { accept: 'application/json', ...(init.headers || {}) },
  })
  const text = await res.text()
  let body = null
  try {
    body = text ? JSON.parse(text) : null
  } catch (_) {
    body = text
  }
  return { status: res.status, body }
}

async function main() {
  console.log(`AusHD 分发服务自检 → ${base}\n`)

  let health
  try {
    health = await call('/healthz')
  } catch (e) {
    record(false, '服务可达', e.message)
    return finish()
  }
  record(
    health.status === 200 && health.body && health.body.service === 'aushd-distribution',
    '健康检查 /healthz',
    `HTTP ${health.status}${health.body && health.body.version ? ` · v${health.body.version}` : ''}`,
  )

  for (const platform of ['windows', 'linux', 'androidtv']) {
    try {
      const r = await call(`/api/releases/latest?platform=${platform}&channel=stable`)
      if (r.status === 204 || r.status === 404) {
        record(true, `版本接口 ${platform}`, `HTTP ${r.status}（暂无版本，属正常）`)
        continue
      }
      if (r.status !== 200 || !r.body || typeof r.body !== 'object') {
        record(false, `版本接口 ${platform}`, `HTTP ${r.status}，响应不是 JSON 对象`)
        continue
      }
      const j = r.body
      const shape = typeof j.tag === 'string' && typeof j.download === 'string' &&
        typeof j.size === 'number'
      let host = '无效 URL'
      try {
        host = new URL(j.download).host
      } catch (_) {}
      record(shape, `版本接口 ${platform}`,
        shape ? `${j.tag} · ${host} · ${j.size} bytes` : '字段缺失或类型错误')
      if (shape && !/^https?:\/\//.test(j.download)) {
        record(false, `下载地址 ${platform}`, '不是 http(s) URL')
      }
      if (shape && !j.sha256) {
        console.log(`  WARN  版本 ${platform} 缺少 sha256，客户端将跳过完整性校验`)
      }
    } catch (e) {
      record(false, `版本接口 ${platform}`, e.message)
    }
  }

  try {
    const r = await call('/api/app/link', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code: '__preflight_invalid__', device: { id: 'preflight' } }),
    })
    record(r.status >= 400 && r.status < 500 && r.body && typeof r.body === 'object',
      '兑换码协议 /api/app/link',
      `无效码返回 HTTP ${r.status}${r.body && r.body.code ? ` · ${r.body.code}` : ''}`)
  } catch (e) {
    record(false, '兑换码协议 /api/app/link', e.message)
  }

  try {
    const r = await call('/api/admin/releases', { method: 'POST', body: '{}' })
    record(r.status === 401, '管理接口鉴权', `未带 token 返回 HTTP ${r.status}`)
  } catch (e) {
    record(false, '管理接口鉴权', e.message)
  }

  finish()
}

function finish() {
  const failed = results.filter((r) => !r.ok)
  console.log(`\n结果：${results.length - failed.length}/${results.length} 项通过`)
  if (failed.length) {
    console.log('服务尚不可用，请先修复以上失败项再配置 DIST_URL。')
    process.exit(1)
  }
  console.log('服务可用，可以把这个地址填入 GitHub Secret DIST_URL。')
}

main().catch((e) => {
  console.error('自检异常：', e)
  process.exit(1)
})
