import assert from 'node:assert/strict'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { extname, join, relative, resolve } from 'node:path'
import {
  businessButtonPermissionCatalog,
  managedButtonPermissionCatalog,
  resolveCatalogPermissionCode
} from './business-button-permission-catalog'

const projectRoot = resolve(import.meta.dirname, '..')
const migrationPath = join(
  projectRoot,
  'supabase/migrations/20260820005922_business_button_permissions.sql'
)
const systemMigrationPath = join(
  projectRoot,
  'supabase/migrations/20260820143000_system_button_permissions.sql'
)
const notificationReminderMigrationPath = join(
  projectRoot,
  'supabase/migrations/20260820044218_tenant_notification_reminder.sql'
)
const compatibilityMigrationPath = join(
  projectRoot,
  'supabase/migrations/20260820143100_backfill_new_button_permissions_for_existing_roles.sql'
)
const businessViewRoot = join(projectRoot, 'src/views')
const managedModules = new Set(['tms', 'vms', 'fms', 'hr', 'system'])
const businessModules = new Set(['tms', 'vms', 'fms', 'hr'])
const sourceExtensions = new Set(['.ts', '.tsx', '.vue'])
const permissionPattern =
  /['"`]((?:System|Tms|Finance|Hr|Vehicle|Insurance|Parts|PartsCategory|Supplier)[A-Za-z0-9]*(?::[A-Za-z][A-Za-z0-9]*)+)['"`]/g
const platformSuperPattern = /isPlatformSuper|平台超级管理员|仅平台|platform super administrator/i

// These files use platform-super only for cross-tenant context or for controlled AI writes.
// Adding a file here requires an explicit security rationale; normal business maintenance is forbidden.
const platformSuperAllowlist = new Map<string, string>([
  ['src/views/fms/account-set/index.vue', 'cross-tenant account-set selector and tenant columns'],
  ['src/views/fms/expense-item/index.vue', 'cross-tenant expense-item selector and tenant columns'],
  [
    'src/views/fms/cash-transaction/modules/cash-bank-batch-import-dialog.vue',
    'controlled AI batch write'
  ],
  ['src/views/hr/personnel/employee-roster/index.vue', 'cross-tenant employee selector'],
  ['src/views/hr/personnel/employee-profile/index.vue', 'cross-tenant employee context'],
  ['src/views/tms/basic-data/favorite-route/index.vue', 'cross-tenant favorite-route context'],
  [
    'src/views/tms/basic-data/favorite-route/modules/favorite-route-dialog.vue',
    'cross-tenant favorite-route context'
  ],
  ['src/views/tms/order-open/modules/ai-order-drawer.vue', 'controlled AI master-data write'],
  [
    'src/views/tms/delivery-management/modules/receipt-exception-work-order-drawer.vue',
    'controlled AI workflow-state write'
  ],
  [
    'src/views/tms/delivery-management/modules/waybill-receipt-ocr-panel.vue',
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

const catalogRows = managedButtonPermissionCatalog.flatMap((entry) =>
  entry.buttons.map((definition) => ({
    menuName: entry.menuName,
    action: definition.action,
    code: resolveCatalogPermissionCode(entry.menuName, definition)
  }))
)
const catalogCodes = new Set(catalogRows.map((row) => row.code))
assert.equal(catalogCodes.size, catalogRows.length, '业务按钮权限码存在重复，请保持全局唯一')

for (const row of catalogRows) {
  assert.match(
    row.code,
    /^[A-Za-z][A-Za-z0-9]*(?::[A-Za-z][A-Za-z0-9]*)+$/,
    `权限码格式不正确：${row.code}`
  )
}

const migrationSql = [migrationPath, systemMigrationPath, notificationReminderMigrationPath]
  .map((filePath) => readFileSync(filePath, 'utf8'))
  .join('\n')
const missingFromMigration = catalogRows.filter(
  (row) =>
    !migrationSql.includes(JSON.stringify(row.code)) && !migrationSql.includes(`'${row.code}'`)
)
assert.deepEqual(
  missingFromMigration,
  [],
  `权限目录尚未写入迁移：${missingFromMigration.map((row) => row.code).join(', ')}`
)

const compatibilityMigrationSql = readFileSync(compatibilityMigrationPath, 'utf8')
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

const sourceFiles = walkSourceFiles(businessViewRoot).filter((filePath) => {
  const moduleName = relative(businessViewRoot, filePath).split(/[\\/]/, 1)[0]
  return managedModules.has(moduleName)
})
const uncataloguedReferences: string[] = []
const forbiddenPlatformSuperReferences: string[] = []
const sourceText = new Map<string, string>()

for (const filePath of sourceFiles) {
  const source = readFileSync(filePath, 'utf8')
  const projectPath = toProjectPath(filePath)
  sourceText.set(projectPath, source)

  for (const match of source.matchAll(permissionPattern)) {
    const code = match[1]
    if (code && !catalogCodes.has(code)) uncataloguedReferences.push(`${projectPath}: ${code}`)
  }

  const moduleName = relative(businessViewRoot, filePath).split(/[\\/]/, 1)[0]
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
  ({ code }) =>
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
  `Managed permission audit passed: ${businessButtonPermissionCatalog.length} business menus, ${catalogRows.length} button permissions, ${sourceFiles.length} source files.`
)
