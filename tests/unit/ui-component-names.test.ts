import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, unlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

test('UI audit rejects duplicate component identities across repositories and ignores comments', () => {
  const temporaryRoot = resolve(tmpdir())
  const fixtureRoot = mkdtempSync(join(temporaryRoot, 'art-component-names-'))
  const script = fileURLToPath(new URL('../../scripts/ui-audit.ts', import.meta.url))
  try {
    mkdirSync(join(fixtureRoot, 'src'), { recursive: true })
    mkdirSync(join(fixtureRoot, 'modules', 'demo', 'src'), { recursive: true })
    writeFileSync(
      join(fixtureRoot, 'src', 'page.vue'),
      `<template><p>测试页面</p></template>
<script setup lang="ts">
// defineOptions({ name: 'CommentOnly' })
defineOptions({ inheritAttrs: false, name: 'BusinessWorkspace' })
</script>`
    )
    const moduleFile = join(fixtureRoot, 'modules', 'demo', 'src', 'page.vue')
    writeFileSync(
      moduleFile,
      `<template><p>测试页面</p></template>
<script setup lang="ts">
defineOptions({ 'name': 'BusinessWorkspace' })
</script>`
    )
    const runAudit = () =>
      spawnSync(process.execPath, ['--import', import.meta.resolve('tsx'), script], {
        cwd: fixtureRoot,
        encoding: 'utf8',
        timeout: 30_000
      })
    const rejected = runAudit()
    assert.equal(rejected.status, 1, rejected.stderr)
    assert.match(rejected.stderr, /naming\/unique-component-name/)
    assert.match(rejected.stderr, /BusinessWorkspace/)
    writeFileSync(
      moduleFile,
      `<template><p>测试页面</p></template>
<script setup lang="ts">
// defineOptions({ name: 'BusinessWorkspace' })
defineOptions({ name: 'DistinctWorkspace' })
</script>`
    )
    const accepted = runAudit()
    assert.equal(accepted.status, 0, accepted.stderr)
    assert.match(accepted.stdout, /UI audit passed/)
    writeFileSync(
      moduleFile,
      `<template><p>测试页面</p></template>
<script setup lang="ts">
defineOptions({ name: 'business-workspace' })
</script>`
    )
    const invalidName = runAudit()
    assert.equal(invalidName.status, 1, invalidName.stderr)
    assert.match(invalidName.stderr, /naming\/pascal-case-component-name/)
    assert.match(invalidName.stderr, /business-workspace/)
    // A module without source is optional; an unreadable source must never count as audited.
    const brokenModule = join(fixtureRoot, 'modules', 'broken')
    mkdirSync(brokenModule)
    writeFileSync(moduleFile, '<template><p>测试页面</p></template>')
    writeFileSync(join(brokenModule, 'src'), 'not a source directory')
    const unreadableSource = runAudit()
    assert.notEqual(unreadableSource.status, 0)
    assert.doesNotMatch(unreadableSource.stdout, /UI audit passed/)
    const reuseScript = fileURLToPath(
      new URL('../../scripts/audit-shared-reuse.ts', import.meta.url)
    )
    const unreadableReuseSource = spawnSync(
      process.execPath,
      ['--import', import.meta.resolve('tsx'), reuseScript],
      { cwd: fixtureRoot, encoding: 'utf8', timeout: 30_000 }
    )
    assert.notEqual(unreadableReuseSource.status, 0)
    assert.match(unreadableReuseSource.stderr, /ENOTDIR/)
    unlinkSync(join(brokenModule, 'src'))
    writeFileSync(join(brokenModule, 'tsconfig.json'), '{ invalid config')
    const malformedConfig = spawnSync(
      process.execPath,
      ['--import', import.meta.resolve('tsx'), reuseScript],
      { cwd: fixtureRoot, encoding: 'utf8', timeout: 30_000 }
    )
    assert.notEqual(malformedConfig.status, 0)
    assert.match(malformedConfig.stderr, /SyntaxError/)
  } finally {
    assert.equal(dirname(resolve(fixtureRoot)), temporaryRoot)
    assert.ok(fixtureRoot.startsWith(join(temporaryRoot, 'art-component-names-')))
    rmSync(fixtureRoot, { recursive: true, force: true })
  }
})
