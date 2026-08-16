import assert from 'node:assert/strict'
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { syncFileViewerAssets } from '../../scripts/file-viewer-asset-sync'

async function createFixture(): Promise<{
  root: string
  sourceRoot: string
  targetRoot: string
}> {
  const root = await mkdtemp(path.join(os.tmpdir(), 'file-viewer-assets-'))
  const sourceRoot = path.join(root, 'stage')
  const targetRoot = path.join(root, 'output')
  const sourceFont = path.join(sourceRoot, 'vendor/pdf/fonts/files/font.woff2')
  const targetFont = path.join(targetRoot, 'vendor/pdf/fonts/files/font.woff2')

  await mkdir(path.dirname(sourceFont), { recursive: true })
  await mkdir(path.dirname(targetFont), { recursive: true })
  await writeFile(sourceFont, 'stable-font-content')
  await writeFile(targetFont, 'stable-font-content')
  await writeFile(
    path.join(sourceRoot, 'flyfish-viewer-assets.json'),
    `${JSON.stringify(
      {
        schemaVersion: 1,
        assets: [{ id: 'pdf-cjk-font-fallback', to: path.join(sourceRoot, 'vendor/pdf/fonts') }]
      },
      null,
      2
    )}\n`
  )

  return { root, sourceRoot, targetRoot }
}

test('skips byte-identical file-viewer assets instead of replacing them', async (context) => {
  const fixture = await createFixture()
  context.after(() => rm(fixture.root, { recursive: true, force: true }))

  const targetFont = path.join(fixture.targetRoot, 'vendor/pdf/fonts/files/font.woff2')
  const before = await stat(targetFont)
  const firstResult = await syncFileViewerAssets(fixture.sourceRoot, fixture.targetRoot)
  const after = await stat(targetFont)

  assert.equal(firstResult.copied, 1)
  assert.equal(firstResult.unchanged, 1)
  assert.equal(after.mtimeMs, before.mtimeMs)

  const manifest = JSON.parse(
    await readFile(path.join(fixture.targetRoot, 'flyfish-viewer-assets.json'), 'utf8')
  ) as { assets: Array<{ to: string }> }
  assert.equal(manifest.assets[0]?.to, path.join(fixture.targetRoot, 'vendor/pdf/fonts'))

  const secondResult = await syncFileViewerAssets(fixture.sourceRoot, fixture.targetRoot)
  assert.deepEqual(secondResult, { copied: 0, unchanged: 2, total: 2 })
})

test('copies missing and changed file-viewer assets', async (context) => {
  const fixture = await createFixture()
  context.after(() => rm(fixture.root, { recursive: true, force: true }))

  const sourceWorker = path.join(fixture.sourceRoot, 'vendor/pdf/pdf.worker.mjs')
  const targetFont = path.join(fixture.targetRoot, 'vendor/pdf/fonts/files/font.woff2')
  await mkdir(path.dirname(sourceWorker), { recursive: true })
  await writeFile(sourceWorker, 'worker-content')
  await writeFile(targetFont, 'outdated-font-content')

  const result = await syncFileViewerAssets(fixture.sourceRoot, fixture.targetRoot)

  assert.equal(await readFile(targetFont, 'utf8'), 'stable-font-content')
  assert.equal(
    await readFile(path.join(fixture.targetRoot, 'vendor/pdf/pdf.worker.mjs'), 'utf8'),
    'worker-content'
  )
  assert.deepEqual(result, { copied: 3, unchanged: 0, total: 3 })
})
