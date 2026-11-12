'use strict'

const fs = require('fs')
const path = require('path')

/** Tiny JSON file store with atomic writes. No database dependency. */
class Store {
  constructor(dir) {
    this.dir = path.resolve(dir)
    fs.mkdirSync(this.dir, { recursive: true })
  }

  file(name) {
    return path.join(this.dir, name)
  }

  read(name, fallback) {
    try {
      return JSON.parse(fs.readFileSync(this.file(name), 'utf8'))
    } catch (err) {
      if (err.code !== 'ENOENT') console.error('[store] unreadable', name, err.message)
      return fallback
    }
  }

  write(name, value) {
    const target = this.file(name)
    const tmp = `${target}.${process.pid}.tmp`
    fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, 'utf8')
    fs.renameSync(tmp, target)
  }
}

module.exports = { Store }
