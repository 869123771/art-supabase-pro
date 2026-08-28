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
// These versions already exist in the linked production migration history. They
// repeat the immediately preceding migration byte-for-byte, so keep them for a
// faithful history checkout while continuing to reject any new duplicates.
const remoteDuplicateMigrationAllowlist = new Set([
  '20260823113536_expand_talent_aging_route_and_due_soon.sql',
  '20260823122825_expand_vms_workflow_smis_decision_workspaces.sql',
  '20260823123745_optimize_organization_route_first_load.sql'
])
type ManagedModule = 'tms' | 'vms' | 'fms' | 'hr' | 'smis' | 'system' | 'workflow'

const managedViewRoots = new Map<ManagedModule, string>([
  ['tms', join(projectRoot, 'modules/art-supabase-tms/src/views')],
  ['system', join(projectRoot, 'src/views/system')],
  ['workflow', join(projectRoot, 'src/views/workflow')],
  ['fms', join(projectRoot, 'modules/art-supabase-fms/src/views')],
  ['vms', join(projectRoot, 'modules/art-supabase-vms/src/views')],
  ['hr', join(projectRoot, 'modules/art-supabase-hr/src/views')],
  ['smis', join(projectRoot, 'modules/art-supabase-smis/src/views')]
])
const businessModules = new Set<ManagedModule>(['tms', 'vms', 'fms', 'hr', 'smis'])
const sourceExtensions = new Set(['.ts', '.tsx', '.vue'])
const permissionPattern =
  /['"`]((?:System|Workflow|Tms|Finance|Hr|Smis|Vehicle|Insurance|Parts|PartsCategory|Supplier)[A-Za-z0-9]*(?::[A-Za-z][A-Za-z0-9]*)+)['"`]/g
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
  ],
  [
    'modules/art-supabase-hr/src/views/operations/absence/index.vue',
    'cross-tenant absence workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/absence/modules/absence-dialog.vue',
    'cross-tenant absence assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/attendance/index.vue',
    'cross-tenant attendance context and controlled period reopen'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/attendance/modules/attendance-dialog.vue',
    'cross-tenant attendance assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/benefits/index.vue',
    'cross-tenant benefits workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/benefits/modules/benefit-record-dialog.vue',
    'cross-tenant benefit assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/compensation-review/modules/compensation-review-dialog.vue',
    'cross-tenant compensation-review assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/compensation/index.vue',
    'cross-tenant compensation context and sensitive columns'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/compensation/modules/compensation-dialog.vue',
    'cross-tenant compensation assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/contingent-workforce/modules/contingent-workforce-dialog.vue',
    'cross-tenant contingent-workforce assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/employee-experience/index.vue',
    'cross-tenant employee-experience context'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/employee-experience/modules/experience-action-dialog.vue',
    'cross-tenant experience-action assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/employee-experience/modules/experience-survey-dialog.vue',
    'cross-tenant experience-survey assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/employee-relations/index.vue',
    'cross-tenant employee-relations context'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/employee-relations/modules/employee-relation-record-dialog.vue',
    'cross-tenant employee-relation assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/headcount/index.vue',
    'cross-tenant workforce-planning context'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/headcount/modules/workforce-planning-dialog.vue',
    'cross-tenant workforce-plan assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/policy-acknowledgement/modules/policy-document-dialog.vue',
    'cross-tenant policy-document assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/self-service/index.vue',
    'cross-tenant service-delivery context'
  ],
  [
    'modules/art-supabase-hr/src/views/operations/self-service/modules/service-delivery-dialog.vue',
    'cross-tenant service-delivery assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/compliance/index.vue',
    'cross-tenant compliance workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/compliance/modules/compliance-record-dialog.vue',
    'cross-tenant compliance-record assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/job-architecture/index.vue',
    'cross-tenant job-architecture context and tenant columns'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/job-architecture/modules/job-architecture-dialog.vue',
    'cross-tenant job-architecture assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/lifecycle/index.vue',
    'cross-tenant lifecycle workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/lifecycle/modules/lifecycle-dialog.vue',
    'cross-tenant lifecycle assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/personnel/organization-design/modules/organization-design-dialog.vue',
    'cross-tenant organization-design assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/recruitment/workbench/index.vue',
    'cross-tenant recruitment workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/recruitment/workbench/modules/recruitment-dialog.vue',
    'cross-tenant recruitment assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/development/index.vue',
    'cross-tenant learning workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/development/modules/learning-dialog.vue',
    'cross-tenant learning assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/internal-mobility/index.vue',
    'cross-tenant internal-mobility context'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/internal-mobility/modules/internal-mobility-dialog.vue',
    'cross-tenant internal-opportunity assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/performance/index.vue',
    'cross-tenant performance workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/performance/modules/performance-dialog.vue',
    'cross-tenant performance assignment'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/succession/index.vue',
    'cross-tenant succession workspace context'
  ],
  [
    'modules/art-supabase-hr/src/views/talent/succession/modules/succession-dialog.vue',
    'cross-tenant succession assignment'
  ],
  [
    'modules/art-supabase-smis/src/views/basic-data/inspection-category/index.vue',
    'cross-tenant inspection-category context and tenant columns'
  ],
  [
    'modules/art-supabase-smis/src/views/basic-data/inspection-category/modules/inspection-category-dialog.vue',
    'cross-tenant inspection-category assignment'
  ]
])

const sourceReferenceExemptions = new Map<string, string>([
  ...[
    'SmisStatutoryHoliday:View',
    'SmisSite:View',
    'SmisInspectionCategory:View',
    'SmisEquipmentCategory:View',
    'SmisStorageLocation:View',
    'SmisEquipmentLedger:View',
    'SmisEquipmentDepreciation:View',
    'SmisInspectionDeclaration:View',
    'SmisSpecialEquipmentAnalysis:View',
    'SmisSpecialEquipmentLedger:View',
    'SmisEquipmentReminder:View',
    'SmisSupplier:View',
    'Hr:JobFamily:View',
    'Hr:Grade:View'
  ].map((code) => [code, 'page-route read boundary'] as const),
  ...[
    'Hr:EmployeeRelations:Sensitive:View',
    'Hr:Benefits:Amount:View',
    'Hr:Benefits:Payroll:Export',
    'Hr:Benefits:Evidence:View',
    'Hr:Experience:Comments:View',
    'Hr:Compensation:Amount:View',
    'Hr:Compensation:Amount:Edit',
    'Hr:CompensationReview:Amount:View',
    'Hr:ContingentWorkforce:PII:View',
    'Hr:ContingentWorkforce:Cost:View',
    'Hr:PolicyAcknowledgement:Evidence:View',
    'Hr:Absence:Reason:View'
  ].map((code) => [code, 'server or field-level authorization boundary'] as const),
  ...[
    'Hr:Lifecycle:Add',
    'Hr:Lifecycle:Edit',
    'Hr:Lifecycle:Delete',
    'Hr:Succession:Plan:Add',
    'Hr:Succession:Plan:Edit',
    'Hr:Succession:Plan:Delete',
    'Hr:Succession:Candidate:Add',
    'Hr:Succession:Candidate:Edit',
    'Hr:Succession:Candidate:Delete',
    'Hr:Succession:Action:Add',
    'Hr:Succession:Action:Edit',
    'Hr:Succession:Action:Delete',
    'Hr:Performance:Edit',
    'Hr:Performance:Delete'
  ].map((code) => [code, 'deterministic entity-action permission resolver'] as const),
  [
    'SmisEquipmentLedger:Inspection',
    'inspection declaration is authorized at its workflow boundary'
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
  if (menuName.startsWith('Smis')) return 'smis'
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

for (const code of sourceReferenceExemptions.keys()) {
  assert.ok(catalogCodes.has(code), `页面权限引用例外未登记在目录中：${code}`)
}

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
  .filter(
    (migration, index, migrations) =>
      !remoteDuplicateMigrationAllowlist.has(migration.fileName) &&
      migrations.some(
        (candidate, candidateIndex) =>
          candidateIndex < index && candidate.contentHash === migration.contentHash
      )
  )
  .map((migration) => migration.fileName)
assert.deepEqual(duplicateContents, [], `存在内容完全重复的迁移：${duplicateContents.join(', ')}`)

for (const fileName of remoteDuplicateMigrationAllowlist) {
  const duplicateIndex = migrationFiles.findIndex((migration) => migration.fileName === fileName)
  assert.notEqual(duplicateIndex, -1, `远端重复迁移兼容项不存在：${fileName}`)
  assert.ok(
    migrationFiles.some(
      (candidate, candidateIndex) =>
        candidateIndex < duplicateIndex &&
        candidate.contentHash === migrationFiles[duplicateIndex]!.contentHash
    ),
    `远端重复迁移兼容项不再重复，请移除白名单：${fileName}`
  )
}

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
    !sourceReferenceExemptions.has(code) &&
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
