import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import test from 'node:test'

test('standalone module builds include the platform region data and document examples', () => {
  const projectRoot = fileURLToPath(new URL('../..', import.meta.url))
  const artifactRoot = resolve(projectRoot, '.artifacts')
  mkdirSync(artifactRoot, { recursive: true })
  const fixtureRoot = mkdtempSync(join(artifactRoot, 'module-public-assets-'))
  try {
    writeFileSync(
      join(fixtureRoot, 'index.html'),
      '<!doctype html><html><body>资源验收</body></html>'
    )
    const factoryUrl = pathToFileURL(join(projectRoot, 'scripts/module-vite-config.mjs')).href
    const result = spawnSync(
      process.execPath,
      [
        '--input-type=module',
        '-e',
        `
          import assert from 'node:assert/strict'
          import { readFile } from 'node:fs/promises'
          import path from 'node:path'
          import { build, createServer } from 'vite'
          const { createModuleViteConfig } = await import(${JSON.stringify(factoryUrl)})
          const root = ${JSON.stringify(fixtureRoot)}
          const platformRoot = ${JSON.stringify(projectRoot)}
          const config = await createModuleViteConfig({
            appCode: 'smis', applicationRoot: root, defaultPort: 0,
            mode: 'test', platformRoot
          })
          assert.equal(config.publicDir, path.join(platformRoot, 'public'))
          await build({
            ...config, root, configFile: false, logLevel: 'silent',
            build: { ...config.build, outDir: path.join(root, 'dist') }
          })
          for (const asset of [
            'data/pca-code.json',
            'data/equipment-accessory-demo/safety-valve-photo.png',
            'data/equipment-accessory-demo/pressure-gauge-use-registration-sample.pdf'
          ]) {
            assert.deepEqual(
              await readFile(path.join(root, 'dist', asset)),
              await readFile(path.join(platformRoot, 'public', asset))
            )
          }
          const server = await createServer({
            ...config, root, configFile: false, logLevel: 'silent',
            server: { ...config.server, host: '127.0.0.1', port: 0 }
          })
          try {
            await server.listen()
            const url = server.resolvedUrls?.local[0]
            assert.ok(url, '未启动模块资源服务器')
            const response = await fetch(new URL('data/pca-code.json', url))
            assert.equal(response.status, 200)
            assert.deepEqual(
              Buffer.from(await response.arrayBuffer()),
              await readFile(path.join(platformRoot, 'public/data/pca-code.json'))
            )
          } finally {
            await server.close()
          }
          console.info('Shared module public assets verified')
        `
      ],
      { cwd: projectRoot, encoding: 'utf8', timeout: 60_000 }
    )
    assert.equal(result.status, 0, result.stderr)
    assert.match(result.stdout, /Shared module public assets verified/)
  } finally {
    assert.equal(dirname(resolve(fixtureRoot)), artifactRoot)
    assert.ok(fixtureRoot.startsWith(join(artifactRoot, 'module-public-assets-')))
    rmSync(fixtureRoot, { recursive: true, force: true })
  }
})
