import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { hostedModuleSharedDependencies } from '../../scripts/hosted-module-dependencies'

interface PackageManifest {
  private?: boolean
  packageManager?: string
  engines?: Record<string, string>
  scripts?: Record<string, string>
}

interface TypeScriptConfig {
  compilerOptions?: {
    paths?: Record<string, string[]>
  }
}

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')

async function readManifest(relativePath: string): Promise<PackageManifest> {
  return JSON.parse(await readFile(path.join(projectRoot, relativePath, 'package.json'), 'utf8'))
}

async function readTypeScriptConfig(relativePath: string): Promise<TypeScriptConfig> {
  return JSON.parse(await readFile(path.join(projectRoot, relativePath, 'tsconfig.json'), 'utf8'))
}

async function readSubmodulePaths(): Promise<string[]> {
  const gitmodules = await readFile(path.join(projectRoot, '.gitmodules'), 'utf8')
  return [...gitmodules.matchAll(/^\s*path\s*=\s*(.+)$/gm)].map((match) => match[1].trim())
}

test('every hosted repository participates in the root module quality gate', async () => {
  const rootManifest = await readManifest('.')
  const modulePaths = await readSubmodulePaths()

  assert.equal(modulePaths.length, 6)
  assert.match(rootManifest.scripts?.['check:ci'] ?? '', /pnpm modules:check/)
  assert.match(rootManifest.scripts?.['check:ci'] ?? '', /pnpm modules:build/)

  for (const modulePath of modulePaths) {
    const manifest = await readManifest(modulePath)
    assert.equal(manifest.private, true, `${modulePath} must remain private`)
    assert.equal(manifest.packageManager, 'pnpm@11.9.0', `${modulePath} pnpm version drifted`)
    assert.equal(manifest.engines?.node, '>=22.0.0', `${modulePath} Node baseline drifted`)
    assert.ok(manifest.scripts?.check, `${modulePath} must expose pnpm check`)
  }
})

test('every business repository runs the shared UI audit independently', async () => {
  const modulePaths = (await readSubmodulePaths()).filter(
    (modulePath) => modulePath !== 'modules/art-supabase-doc'
  )

  for (const modulePath of modulePaths) {
    const manifest = await readManifest(modulePath)
    assert.equal(
      manifest.scripts?.['ui:audit'],
      'tsx node_modules/art-supabase-pro/scripts/ui-audit.ts',
      `${modulePath} must reuse the platform UI audit`
    )
    assert.match(manifest.scripts?.check ?? '', /pnpm ui:audit/)
  }
})

test('standalone module checks resolve one pinned platform snapshot', async () => {
  const modulePaths = (await readSubmodulePaths()).filter(
    (modulePath) => modulePath !== 'modules/art-supabase-doc'
  )
  const expectedPinnedAliases = new Map([
    ['@/*', 'node_modules/art-supabase-pro/src/*'],
    ['@views/*', 'node_modules/art-supabase-pro/src/views/*'],
    ['@styles/*', 'node_modules/art-supabase-pro/src/assets/styles/*'],
    ['@utils/*', 'node_modules/art-supabase-pro/src/utils/*'],
    ['@stores/*', 'node_modules/art-supabase-pro/src/store/*']
  ])

  for (const modulePath of modulePaths) {
    const config = await readTypeScriptConfig(modulePath)
    for (const [alias, pinnedPath] of expectedPinnedAliases) {
      assert.equal(
        config.compilerOptions?.paths?.[alias]?.[0],
        pinnedPath,
        `${modulePath} ${alias} must resolve from the same pinned platform package as global types`
      )
    }
  }
})

test('the host deduplicates stateful framework and transport dependencies', () => {
  const dependencies = new Set<string>(hostedModuleSharedDependencies)
  const requiredSingletons = [
    '@supabase/supabase-js',
    '@vueuse/core',
    'element-plus',
    'pinia',
    'vue',
    'vue-i18n',
    'vue-router'
  ]

  requiredSingletons.forEach((dependency) => {
    assert.ok(dependencies.has(dependency), `${dependency} must resolve from the platform host`)
  })
})
