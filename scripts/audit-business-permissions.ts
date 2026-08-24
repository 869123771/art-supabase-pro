import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { extname, join, relative, resolve } from 'node:path'
import {
  businessButtonPermissionCatalog,
  resolveCatalogPermissionCode,
  systemButtonPermissionCatalog
} from './business-button-permission-catalog'

const projectRoot = resolve(import.meta.dirname, '..')
const migrationDirectory = join(projectRoot, 'supabase/migrations')
const migrationFilePattern = /^(\d{14})_([a-z0-9_]+)\.sql$/
const requiredPermissionMigrations = [
  'business_button_permissions',
  'system_button_permissions',
  'tenant_notification_reminder',
  'backfill_new_button_permissions_for_existing_roles'
] as const
type ManagedModule = 'tms' | 'vms' | 'fms' | 'hr' | 'system' | 'workflow'

const managedViewRoots = new Map<ManagedModule, string>([
  ['tms', join(projectRoot, 'modules/art-supabase-tms/src/views')],
  ['system', join(projectRoot, 'src/views/system')],
  ['workflow', join(projectRoot, 'src/views/workflow')],
  ['fms', join(projectRoot, 'modules/art-supabase-fms/src/views')],
  ['vms', join(projectRoot, 'modules/art-supabase-vms/src/views')],
  ['hr', join(projectRoot, 'modules/art-supabase-hr/src/views')]
])
const businessModules = new Set<ManagedModule>(['tms', 'vms', 'fms', 'hr'])
const sourceExtensions = new Set(['.ts', '.tsx', '.vue'])
const permissionPattern =
  /['"`]((?:System|Workflow|Tms|Finance|Hr|Vehicle|Insurance|Parts|PartsCategory|Supplier)[A-Za-z0-9]*(?::[A-Za-z][A-Za-z0-9]*)+)['"`]/g
const platformSuperPattern = /isPlatformSuper|平台超级管理员|仅平台|platform super administrator/i

// These files use platform-super only for cross-tenant context or for controlled AI writes.
// Adding a file here requires an explicit security rationale; normal business maintenance is forbidden.
const platformSuperAllowlist = new Map<string, string>([
  [
    'modules/art-supabase-fms/src/views/account-set/index.vue',
    'cross-tenant account-set selector and tenant columns'
  ],
  [
    'modules/art-supabase-fms/src/views/expense-item/index.vue',
    'cross-tenant expense-item selector and tenant columns'
  ],
  [
    'modules/art-supabase-fms/src/views/cash-transaction/modules/cash-bank-batch-import-dialog.vue',
    'controlled AI batch write'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/employee-roster/index.vue',
    'cross-tenant employee selector'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/employee-profile/index.vue',
    'cross-tenant employee context'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/position/index.vue',
    'cross-tenant position selector and tenant columns'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/position/modules/position-dialog.vue',
    'cross-tenant position tenant assignment'
  ],
  [
    'modules/art-supabase-tms/src/views/basic-data/favorite-route/index.vue',
    'cross-tenant favorite-route context'
  ],
  [
    'modules/art-supabase-tms/src/views/basic-data/favorite-route/modules/favorite-route-dialog.vue',
    'cross-tenant favorite-route context'
  ],
  [
    'modules/art-supabase-tms/src/views/order-open/modules/ai-order-drawer.vue',
    'controlled AI master-data write'
  ],
  [
    'modules/art-supabase-tms/src/views/delivery-management/modules/receipt-exception-work-order-drawer.vue',
    'controlled AI workflow-state write'
  ],
  [
    'modules/art-supabase-tms/src/views/delivery-management/modules/waybill-receipt-ocr-panel.vue',
    'controlled AI workflow-state write'
  ]
])

function walkSourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const absolutePath = join(directory, entry)
    const stats = statSync(absolutePath)
    if (stats.isDirectory()) return walkSourceFiles(absolutePath)
    return sourceExtensions.has(extname(entry)) ? [absolutePath] : []
  })
}

function toProjectPath(filePath: string): string {
  return relative(projectRoot, filePath).replaceAll('\\', '/')
}

function resolveBusinessCatalogOwner(menuName: string): ManagedModule {
  if (menuName.startsWith('Tms')) return 'tms'
  if (menuName.startsWith('Finance')) return 'fms'
  if (menuName.startsWith('Hr')) return 'hr'
  return 'vms'
}

const catalogRows = [
  ...businessButtonPermissionCatalog.flatMap((entry) =>
    entry.buttons.map((definition) => ({
      owner: resolveBusinessCatalogOwner(entry.menuName),
      menuName: entry.menuName,
      action: definition.action,
      code: resolveCatalogPermissionCode(entry.menuName, definition)
    }))
  ),
  ...systemButtonPermissionCatalog.flatMap((entry) =>
    entry.buttons.map((definition) => ({
      owner: 'system' as const,
      menuName: entry.menuName,
      action: definition.action,
      code: resolveCatalogPermissionCode(entry.menuName, definition)
    }))
  )
]
const catalogCodes = new Set(catalogRows.map((row) => row.code))
assert.equal(catalogCodes.size, catalogRows.length, '业务按钮权限码存在重复，请保持全局唯一')

for (const row of catalogRows) {
  assert.match(
    row.code,
    /^[A-Za-z][A-Za-z0-9]*(?::[A-Za-z][A-Za-z0-9]*)+$/,
    `权限码格式不正确：${row.code}`
  )
}

const migrationFiles = readdirSync(migrationDirectory)
  .filter((fileName) => fileName.endsWith('.sql'))
  .sort()
  .map((fileName) => {
    const match = migrationFilePattern.exec(fileName)
    assert.ok(match, `迁移文件名必须使用 <14位版本>_<snake_case名称>.sql：${fileName}`)

    const sql = readFileSync(join(migrationDirectory, fileName), 'utf8')
    assert.ok(sql.trim(), `迁移文件不能为空：${fileName}`)

    return {
      fileName,
      version: match[1],
      name: match[2],
      sql,
      contentHash: createHash('sha256').update(sql.replace(/\r\n?/g, '\n').trimEnd()).digest('hex')
    }
  })

const duplicateVersions = migrationFiles
  .filter((migration, index, migrations) =>
    migrations.some(
      (candidate, candidateIndex) =>
        candidateIndex < index && candidate.version === migration.version
    )
  )
  .map((migration) => migration.version)
assert.deepEqual(duplicateVersions, [], `迁移版本号重复：${duplicateVersions.join(', ')}`)

const duplicateContents = migrationFiles
  .filter((migration, index, migrations) =>
    migrations.some(
      (candidate, candidateIndex) =>
        candidateIndex < index && candidate.contentHash === migration.contentHash
    )
  )
  .map((migration) => migration.fileName)
assert.deepEqual(duplicateContents, [], `存在内容完全重复的迁移：${duplicateContents.join(', ')}`)

if (migrationFiles.length > 0) {
  assert.ok(
    migrationFiles.some((migration) => migration.name === 'baseline'),
    '缺少真实数据库 baseline 迁移'
  )

  const requiredMigrationFiles = new Map(
    requiredPermissionMigrations.map((migrationName) => {
      const matches = migrationFiles.filter((migration) => migration.name === migrationName)
      assert.equal(matches.length, 1, `权限关键迁移必须且只能存在一份：${migrationName}`)
      return [migrationName, matches[0]!]
    })
  )
  const allMigrationSql = migrationFiles.map((migration) => migration.sql).join('\n')
  const missingFromMigration = catalogRows.filter(
    (row) =>
      !allMigrationSql.includes(JSON.stringify(row.code)) &&
      !allMigrationSql.includes(`'${row.code}'`)
  )
  assert.deepEqual(
    missingFromMigration,
    [],
    `权限目录尚未写入迁移：${missingFromMigration.map((row) => row.code).join(', ')}`
  )

  const compatibilityMigrationSql = requiredMigrationFiles.get(
    'backfill_new_button_permissions_for_existing_roles'
  )!.sql
  for (const migrationOwner of [
    'codex-business-permission-migration',
    'codex-system-permission-migration'
  ]) {
    assert.ok(
      compatibilityMigrationSql.includes(`'${migrationOwner}'`),
      `历史页面角色兼容迁移缺少按钮来源：${migrationOwner}`
    )
  }
  assert.match(
    compatibilityMigrationSql,
    /button\.parent_id\s*=\s*parent_grant\.menu_id/,
    '历史角色只能继承其已授权页面直属的新增按钮'
  )
}

const sourceFiles = [...managedViewRoots.entries()].flatMap(([moduleName, viewRoot]) =>
  existsSync(viewRoot)
    ? walkSourceFiles(viewRoot).map((filePath) => ({ filePath, moduleName }))
    : []
)
const availableSourceModules = new Set<ManagedModule>(
  [...managedViewRoots.entries()]
    .filter(([, viewRoot]) => existsSync(viewRoot))
    .map(([moduleName]) => moduleName)
)
const uncataloguedReferences: string[] = []
const forbiddenPlatformSuperReferences: string[] = []
const sourceText = new Map<string, string>()

for (const { filePath, moduleName } of sourceFiles) {
  const source = readFileSync(filePath, 'utf8')
  const projectPath = toProjectPath(filePath)
  sourceText.set(projectPath, source)

  for (const match of source.matchAll(permissionPattern)) {
    const code = match[1]
    if (code && !catalogCodes.has(code)) uncataloguedReferences.push(`${projectPath}: ${code}`)
  }

  if (
    businessModules.has(moduleName) &&
    platformSuperPattern.test(source) &&
    !platformSuperAllowlist.has(projectPath)
  ) {
    forbiddenPlatformSuperReferences.push(projectPath)
  }
}

const allManagedSource = [...sourceText.values()].join('\n')
const missingExplicitReferences = catalogRows.filter(
  ({ code, owner }) =>
    availableSourceModules.has(owner) &&
    !allManagedSource.includes(`'${code}'`) &&
    !allManagedSource.includes(`"${code}"`) &&
    !allManagedSource.includes(`\`${code}\``)
)

assert.deepEqual(
  [...new Set(uncataloguedReferences)].sort(),
  [],
  `页面引用了未登记的业务按钮权限：\n${[...new Set(uncataloguedReferences)].sort().join('\n')}`
)
assert.deepEqual(
  forbiddenPlatformSuperReferences.sort(),
  [],
  `业务页面存在未获安全例外的平台超管判断：\n${forbiddenPlatformSuperReferences.sort().join('\n')}`
)
assert.deepEqual(
  missingExplicitReferences,
  [],
  `Every catalogued action must declare its exact permission code in page source; inference is fallback only:\n${missingExplicitReferences
    .map((row) => row.code)
    .join('\n')}`
)

console.log(
  `Managed permission audit passed: ${businessButtonPermissionCatalog.length} business menus, ${catalogRows.length} button permissions, ${sourceFiles.length} source files, ${migrationFiles.length} migrations.`
)
