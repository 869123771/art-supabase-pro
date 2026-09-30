import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import type { ResolvedConfig } from 'vite'
import { createNoJekyllPlugin } from '../../src/plugins/nojekyll'

test('writes .nojekyll to Vite resolved output directory', async (context) => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'nojekyll-output-'))
  context.after(() => rm(root, { recursive: true, force: true }))

  const plugin = createNoJekyllPlugin('fallback-output')
  const configure = plugin.configResolved as (config: ResolvedConfig) => void
  const closeBundle = plugin.closeBundle as () => void

  configure({ root, build: { outDir: 'isolated-output' } } as ResolvedConfig)
  closeBundle()

  assert.equal(await readFile(path.join(root, 'isolated-output', '.nojekyll'), 'utf8'), '')
})
