import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

test('reuse audit rejects copied reference mapping but retains domain context and shared mapping', () => {
  const temporaryRoot = resolve(tmpdir())
  const root = mkdtempSync(join(temporaryRoot, 'art-reference-options-'))
  const script = fileURLToPath(new URL('../../scripts/audit-shared-reuse.ts', import.meta.url))
  try {
    const source = join(root, 'src', 'views')
    mkdirSync(source, { recursive: true })
    mkdirSync(join(root, 'modules'))
    cpSync(join(dirname(dirname(script)), 'src', 'utils'), join(root, 'src', 'utils'), {
      recursive: true
    })
    const file = join(source, 'options.ts')
    writeFileSync(
      file,
      "rows.map(item => ({label: [item.name, item.code].filter(Boolean).join(' · '), value: item.id}))"
    )
    const audit = () =>
      spawnSync(process.execPath, ['--import', import.meta.resolve('tsx'), script], {
        cwd: root,
        encoding: 'utf8',
        timeout: 60_000
      })
    const rejected = audit()
    assert.equal(rejected.status, 1, rejected.stderr)
    assert.match(rejected.stderr, /repeated-name-code-option-mapping/)
    writeFileSync(
      file,
      'rows.map(toNameCodeOption); rows.map(item => ({label: `${item.name} · ${item.workDate ?? item.code}`, value: item.id}))'
    )
    const accepted = audit()
    assert.equal(accepted.status, 0, accepted.stderr)
    assert.match(accepted.stdout, /Shared reuse audit passed/)
  } finally {
    assert.equal(dirname(resolve(root)), temporaryRoot)
    assert.ok(root.startsWith(join(temporaryRoot, 'art-reference-options-')))
    rmSync(root, { recursive: true, force: true })
  }
})
