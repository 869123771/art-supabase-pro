import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

test('UI audit rejects whole-overlay body masks and permits shared owners and local regions', () => {
  const temporaryRoot = resolve(tmpdir())
  const fixtureRoot = mkdtempSync(join(temporaryRoot, 'art-overlay-loading-'))
  const script = fileURLToPath(new URL('../../scripts/ui-audit.ts', import.meta.url))
  const directory = join(fixtureRoot, 'src', 'views')
  try {
    mkdirSync(directory, { recursive: true })
    const file = join(directory, 'loading-owner.vue')
    writeFileSync(
      file,
      `<template>
        <ArtDrawer><template #header><strong>标题</strong></template><div><ArtAsyncState :loading="busy" /></div></ArtDrawer>
        <ArtDialog><template #default><ArtOverlayLoading :loading="busy" /></template></ArtDialog>
      </template>`
    )
    const audit = () =>
      spawnSync(process.execPath, ['--import', import.meta.resolve('tsx'), script], {
        cwd: fixtureRoot,
        encoding: 'utf8',
        timeout: 60_000
      })
    const rejected = audit()
    assert.equal(rejected.status, 1, rejected.stderr)
    assert.equal((rejected.stderr.match(/feedback\/whole-overlay-loading-owner/g) ?? []).length, 2)
    writeFileSync(
      file,
      `<template>
        <ArtDrawer :loading="busy"><ArtAsyncState :error="error" /></ArtDrawer>
        <ArtDialog :loading="busy"><ArtAsyncState :empty="empty" empty-description="请重新选择记录后重试。" /></ArtDialog>
        <ArtDrawer><div><p>独立区域</p><ArtSectionCard :loading="rowsLoading" /></div></ArtDrawer>
        <ArtDrawer><div><p>筛选</p><ArtAsyncState :loading="rowsLoading" /></div></ArtDrawer>
      </template>`
    )
    const accepted = audit()
    assert.equal(accepted.status, 0, accepted.stderr)
    assert.match(accepted.stdout, /UI audit passed/)
  } finally {
    assert.equal(dirname(resolve(fixtureRoot)), temporaryRoot)
    assert.ok(fixtureRoot.startsWith(join(temporaryRoot, 'art-overlay-loading-')))
    rmSync(fixtureRoot, { recursive: true, force: true })
  }
})
