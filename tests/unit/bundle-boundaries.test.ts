import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  isLazyCapabilityAsset,
  isLazyCapabilityStyle,
  shouldPreloadHtmlDependency
} from '../../scripts/bundle-boundaries'

test('heavy capabilities remain outside ordinary application chunk budgets', () => {
  for (const asset of [
    'assets/3d-runtime.123.js',
    'assets/exceljs.123.js',
    'assets/file-viewer.123.js',
    'assets/monaco.123.js'
  ]) {
    assert.equal(isLazyCapabilityAsset(asset), true, asset)
    assert.equal(shouldPreloadHtmlDependency(asset), false, asset)
  }

  assert.equal(isLazyCapabilityAsset('assets/dashboard.123.js'), false)
  assert.equal(shouldPreloadHtmlDependency('assets/framework.123.js'), true)
})

test('only known lazy capability styles are excluded from application CSS totals', () => {
  assert.equal(isLazyCapabilityStyle('assets/art-file-viewer.123.css'), true)
  assert.equal(isLazyCapabilityStyle('assets/art-settings-panel.123.css'), true)
  assert.equal(isLazyCapabilityStyle('assets/art-global-search.123.css'), true)
  assert.equal(isLazyCapabilityStyle('assets/art-chat-window.123.css'), true)
  assert.equal(isLazyCapabilityStyle('assets/art-fireworks-effect.123.css'), true)
  assert.equal(isLazyCapabilityStyle('vendor/pdf/viewer.css'), true)
  assert.equal(isLazyCapabilityStyle('assets/dashboard.123.css'), false)
})

test('SQL console keeps Monaco limited to the workers it actually uses', () => {
  const sqlSetupSource = readFileSync(
    new URL('../../src/utils/monacoSqlSetup.ts', import.meta.url),
    'utf8'
  )

  assert.doesNotMatch(sqlSetupSource, /from ['"]monaco-editor['"]/)
  assert.doesNotMatch(sqlSetupSource, /pgsql\.worker\?worker/)
  assert.doesNotMatch(sqlSetupSource, /setupLanguageFeatures/)
  assert.match(sqlSetupSource, /registerCompletionItemProvider/)
})

test('application shell imports focused system APIs instead of the management barrel', () => {
  const shellSources = [
    '../../src/router/core/MenuProcessor.ts',
    '../../src/store/modules/tenantScope.ts',
    '../../src/hooks/core/useWebsiteConfig.ts',
    '../../src/hooks/core/system-param/read-system-param.ts',
    '../../src/utils/application-navigation.ts'
  ].map((path) => readFileSync(new URL(path, import.meta.url), 'utf8'))

  for (const source of shellSources) {
    assert.doesNotMatch(source, /from ['"]@\/api\/system-manage['"]/)
  }

  const combinedSource = shellSources.join('\n')
  assert.match(combinedSource, /system-manage\/application-access/)
  assert.match(combinedSource, /system-manage\/tenant/)
  assert.match(combinedSource, /system-manage\/system-param/)
  assert.match(combinedSource, /system-manage\/website-config/)
})

test('startup modules avoid the all-utils barrel and defer dictionary queries', () => {
  const shellPaths = [
    '../../src/store/modules/setting.ts',
    '../../src/store/modules/menu.ts',
    '../../src/store/modules/user.ts',
    '../../src/router/core/MenuProcessor.ts',
    '../../src/api/common.ts',
    '../../src/views/auth/login/index.vue'
  ]

  for (const path of shellPaths) {
    const source = readFileSync(new URL(path, import.meta.url), 'utf8')
    assert.doesNotMatch(source, /from ['"]@\/utils['"]/, path)
  }

  const userStoreSource = readFileSync(
    new URL('../../src/store/modules/user.ts', import.meta.url),
    'utf8'
  )
  assert.doesNotMatch(userStoreSource, /from ['"]@\/api\/data-center['"]/)
  assert.match(userStoreSource, /await import\(['"]@\/api\/data-center['"]\)/)
})

test('the public entry defers hosted application views until authenticated route registration', () => {
  const entrySource = readFileSync(new URL('../../src/main.ts', import.meta.url), 'utf8')
  const guardSource = readFileSync(
    new URL('../../src/router/guards/beforeEach.ts', import.meta.url),
    'utf8'
  )

  assert.doesNotMatch(entrySource, /import ['"]\.\/bootstrapHostedApplications['"]/)
  assert.match(
    entrySource,
    /loadHostedApplications: \(\) => import\(['"]\.\/bootstrapHostedApplications['"]\)/
  )
  assert.match(guardSource, /loadHostedApplications\?\.\(\)/)
  assert.match(guardSource, /routeRegistry \?\?= new RouteRegistry\(router\)/)
  assert.ok(
    guardSource.indexOf('loadHostedApplications?.()') <
      guardSource.indexOf('routeRegistry ??= new RouteRegistry(router)')
  )
})

test('upgrade changelog stays out of the startup dependency graph', () => {
  const upgradeSource = readFileSync(
    new URL('../../src/utils/sys/upgrade.ts', import.meta.url),
    'utf8'
  )

  assert.doesNotMatch(upgradeSource, /import \{ upgradeLogList \} from/)
  assert.match(upgradeSource, /await import\(['"]@\/mock\/upgrade\/changeLog['"]\)/)
})
