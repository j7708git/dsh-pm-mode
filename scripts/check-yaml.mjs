// 用 profile 內建的 `yaml` 套件解析 patch 檔，做結構檢查。
//
// `!!js` 是 harness loader 的自訂標籤；這裡先剝除再解析，只驗證 YAML 結構
// （縮排、list、map 是否成立），不求值運算式。
//
// 用法： node check-yaml.mjs <patch檔> <profile目錄>

import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'

const [patchPath, profileDir] = process.argv.slice(2)
if (!patchPath || !profileDir) {
  console.error('用法： node check-yaml.mjs <patch檔> <profile目錄>')
  process.exit(2)
}

let YAML
try {
  const require = createRequire(join(profileDir, 'package.json'))
  YAML = require('yaml')
} catch (error) {
  console.log(`SKIP：在 ${profileDir} 找不到 yaml 套件（${error.message}）`)
  process.exit(0)
}

const raw = readFileSync(patchPath, 'utf8')
const stripped = raw.replace(/!!js\s+/g, '')
const doc = YAML.parseDocument(stripped)

if (doc.errors.length > 0) {
  console.error('FAIL：YAML 解析失敗')
  for (const error of doc.errors) console.error('  - ' + error.message)
  process.exit(1)
}

const entries = doc.toJS() ?? []
const inserts = entries.filter((entry) => entry && typeof entry === 'object' && entry.insert)
const ids = entries.map((entry) => entry && entry.id).filter(Boolean)
const jsTags = (raw.match(/!!js\s+/g) ?? []).length

console.log(`OK：YAML 可解析，共 ${entries.length} 個 patch entry、${inserts.length} 個 insert、${jsTags} 處 !!js`)
console.log(`     entry ids = [${ids.join(', ')}]`)
process.exit(0)
