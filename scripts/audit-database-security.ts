import assert from 'node:assert/strict'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { extname, join, resolve } from 'node:path'
import process from 'node:process'

const projectRoot = resolve(import.meta.dirname, '..')
const migrationDirectory = join(projectRoot, 'supabase/migrations')
const securityBoundaryVersion = '20260823110836'
const securityBoundaryName = 'harden_public_function_default_execution'
const internalHelperMigrationName = 'restrict_internal_security_definer_helpers'
const explicitExecutionBoundaryVersion = '20260823112749'
const explicitExecutionBoundaryName = 'make_public_function_execution_explicit'
const privilegedBatchBoundaryName = 'bound_privileged_batch_rpc_inputs'
const migrationPattern = /^(\d{14})_([a-z0-9_]+)\.sql$/
const publicFunctionPattern =
  /create\s+(?:or\s+replace\s+)?function\s+public\.([a-z_][a-z0-9_]*)\s*\(/gi
const sourceExtensions = new Set(['.js', '.mjs', '.ts', '.tsx', '.vue'])
const internalOnlyFunctions = new Map([
  ['get_app_user_display_name', ''],
  ['validate_tms_expense_reimbursement_submission_secure', 'uuid'],
  ['validate_tms_waybill_cost_submission_secure', 'uuid']
])
const boundedArrayRpcContracts = new Map([
  ['tms_delete_orders_secure', 'p_order_ids'],
  ['tms_cancel_waybill_orders_secure', 'p_order_ids'],
  ['tms_create_customer_statement_secure', 'p_waybill_ids'],
  ['tms_create_carrier_statement_secure', 'p_cost_ids']
])

function walkSourceFiles(directory: string): string[] {
  if (!existsSync(directory)) return []

  return readdirSync(directory).flatMap((entry) => {
    const absolutePath = join(directory, entry)
    const stats = statSync(absolutePath)
    if (stats.isDirectory()) return walkSourceFiles(absolutePath)
    return sourceExtensions.has(extname(entry)) ? [absolutePath] : []
  })
}

const migrations = readdirSync(migrationDirectory)
  .filter((fileName) => fileName.endsWith('.sql'))
  .sort()
  .map((fileName) => {
    const match = migrationPattern.exec(fileName)
    assert.ok(match, `迁移文件名格式错误：${fileName}`)
    return {
      fileName,
      version: match[1]!,
      name: match[2]!,
      sql: readFileSync(join(migrationDirectory, fileName), 'utf8')
    }
  })

if (migrations.length === 0) {
  console.log('Database security migration audit skipped: local SQL history is not stored in Git.')
  process.exit(0)
}

const boundaryMigrations = migrations.filter(
  ({ version, name }) => version === securityBoundaryVersion && name === securityBoundaryName
)
assert.equal(boundaryMigrations.length, 1, '数据库函数默认权限加固迁移必须且只能存在一份')

const boundarySql = boundaryMigrations[0]!.sql
assert.match(
  boundarySql,
  /alter\s+default\s+privileges\s+for\s+role\s+postgres\s+in\s+schema\s+public[\s\S]*?revoke\s+execute\s+on\s+functions\s+from\s+anon/i,
  'public schema 的新函数必须默认拒绝 anon 执行'
)

for (const triggerFunction of ['clean_role_menus_on_role_delete', 'trg_set_create_time_and_by']) {
  assert.match(
    boundarySql,
    new RegExp(
      `revoke\\s+execute\\s+on\\s+function\\s+public\\.${triggerFunction}\\s*\\(\\s*\\)[\\s\\S]*?from\\s+public\\s*,\\s*anon\\s*,\\s*authenticated`,
      'i'
    ),
    `触发器函数不得暴露为 authenticated RPC：${triggerFunction}`
  )
}

const internalHelperMigrations = migrations.filter(
  ({ name }) => name === internalHelperMigrationName
)
assert.equal(internalHelperMigrations.length, 1, '数据库内部 SECURITY DEFINER 撤权迁移必须存在')

const internalHelperSql = internalHelperMigrations[0]!.sql
for (const [functionName, argumentTypes] of internalOnlyFunctions) {
  const escapedArguments = argumentTypes ? argumentTypes.replaceAll(' ', '\\s*') : '\\s*'
  assert.match(
    internalHelperSql,
    new RegExp(
      `revoke\\s+execute\\s+on\\s+function\\s+public\\.${functionName}\\s*\\(\\s*${escapedArguments}\\s*\\)[\\s\\S]*?from\\s+public\\s*,\\s*anon\\s*,\\s*authenticated`,
      'i'
    ),
    `数据库内部函数不得向 authenticated 暴露：public.${functionName}`
  )
}

const moduleDirectories = readdirSync(join(projectRoot, 'modules')).map((entry) =>
  join(projectRoot, 'modules', entry)
)
const rpcSourceRoots = [
  join(projectRoot, 'src'),
  join(projectRoot, 'supabase/functions'),
  ...moduleDirectories.flatMap((moduleDirectory) => [
    join(moduleDirectory, 'src'),
    join(moduleDirectory, 'supabase/functions')
  ])
]
const rpcSource = rpcSourceRoots
  .flatMap((directory) => walkSourceFiles(directory))
  .map((filePath) => readFileSync(filePath, 'utf8'))
  .join('\n')

for (const functionName of internalOnlyFunctions.keys()) {
  assert.doesNotMatch(
    rpcSource,
    new RegExp(`\\.rpc\\s*\\(\\s*['"]${functionName}['"]`, 'i'),
    `数据库内部函数不得重新成为客户端 RPC：public.${functionName}`
  )
}

const explicitExecutionBoundaryMigrations = migrations.filter(
  ({ version, name }) =>
    version === explicitExecutionBoundaryVersion && name === explicitExecutionBoundaryName
)
assert.equal(
  explicitExecutionBoundaryMigrations.length,
  1,
  '公共函数 authenticated 默认权限加固迁移必须且只能存在一份'
)
assert.match(
  explicitExecutionBoundaryMigrations[0]!.sql,
  /alter\s+default\s+privileges\s+for\s+role\s+postgres\s+in\s+schema\s+public[\s\S]*?revoke\s+execute\s+on\s+functions\s+from\s+authenticated/i,
  '新建 public schema 函数必须默认拒绝 authenticated，业务 RPC 只能显式授权'
)

const privilegedBatchBoundaryMigrations = migrations.filter(
  ({ name }) => name === privilegedBatchBoundaryName
)
assert.equal(
  privilegedBatchBoundaryMigrations.length,
  1,
  '高权限批量 RPC 输入边界迁移必须存在且只能存在一份'
)

const privilegedBatchBoundarySql = privilegedBatchBoundaryMigrations[0]!.sql
assert.match(
  privilegedBatchBoundarySql,
  /create\s+or\s+replace\s+function\s+app_private\.assert_uuid_array_limit\s*\(/i,
  '批量 RPC 必须复用统一 UUID 数组上限守卫'
)
assert.match(
  privilegedBatchBoundarySql,
  /revoke\s+all\s+on\s+function\s+app_private\.assert_uuid_array_limit\s*\([\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated/i,
  '内部批量上限守卫不得向客户端角色暴露'
)

const extractFunctionBody = (sql: string, schema: string, functionName: string): string | null => {
  const escapedSchema = schema.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const escapedFunction = functionName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const match = sql.match(
    new RegExp(
      `create\\s+(?:or\\s+replace\\s+)?function\\s+${escapedSchema}\\.${escapedFunction}\\s*\\([\\s\\S]*?\\)\\s*returns[\\s\\S]*?as\\s*\\$\\$([\\s\\S]*?)\\$\\$\\s*;`,
      'i'
    )
  )
  return match?.[1] ?? null
}

for (const [functionName, parameterName] of boundedArrayRpcContracts) {
  const latestDefinition = migrations.findLast(({ sql }) =>
    new RegExp(
      `create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${functionName}\\s*\\(`,
      'i'
    ).test(sql)
  )
  assert.ok(latestDefinition, `缺少受治理批量 RPC：public.${functionName}`)
  const functionBody = extractFunctionBody(latestDefinition.sql, 'public', functionName)
  assert.ok(functionBody, `无法解析受治理批量 RPC：public.${functionName}`)
  assert.match(
    functionBody,
    new RegExp(
      `app_private\\.assert_uuid_array_limit\\s*\\(\\s*${parameterName}\\s*,[\\s\\S]*?500`,
      'i'
    ),
    `高权限批量 RPC 必须限制为最多 500 条：public.${functionName}`
  )
}

const latestCustomerDeleteScope = migrations.findLast(({ sql }) =>
  /create\s+(?:or\s+replace\s+)?function\s+app_private\.assert_customer_delete_scope\s*\(/i.test(
    sql
  )
)
assert.ok(latestCustomerDeleteScope, '缺少客户删除范围守卫')
const customerDeleteScopeBody = extractFunctionBody(
  latestCustomerDeleteScope.sql,
  'app_private',
  'assert_customer_delete_scope'
)
assert.ok(customerDeleteScopeBody, '无法解析客户删除范围守卫')
assert.match(
  customerDeleteScopeBody,
  /app_private\.assert_uuid_array_limit\s*\(\s*p_customer_ids\s*,[\s\S]*?500/i,
  '客户依赖分析与清理必须限制为最多 500 个客户'
)

const governedMigrations = migrations.filter(({ version }) => version > securityBoundaryVersion)
const explicitAclMigrations = migrations.filter(
  ({ version }) => version > explicitExecutionBoundaryVersion
)
const missingFunctionAcl: string[] = []
const missingExplicitFunctionAcl: string[] = []
const forbiddenAnonymousGrants: string[] = []

for (const migration of governedMigrations) {
  if (
    /grant\s+execute\s+on\s+(?:all\s+functions\s+in\s+schema\s+public|function[\s\S]*?)\s+to\s+(?:public|anon)\b/i.test(
      migration.sql
    )
  ) {
    forbiddenAnonymousGrants.push(migration.fileName)
  }

  if (!/security\s+definer/i.test(migration.sql)) continue

  const functionNames = [
    ...new Set([...migration.sql.matchAll(publicFunctionPattern)].map((match) => match[1]!))
  ]

  for (const functionName of functionNames) {
    const explicitRevokePattern = new RegExp(
      `revoke\\s+(?:all|execute)\\s+on\\s+function\\s+public\\.${functionName}\\s*\\(`,
      'i'
    )
    if (!explicitRevokePattern.test(migration.sql)) {
      missingFunctionAcl.push(`${migration.fileName}: public.${functionName}`)
    }
  }
}

for (const migration of explicitAclMigrations) {
  const functionNames = [
    ...new Set([...migration.sql.matchAll(publicFunctionPattern)].map((match) => match[1]!))
  ]

  for (const functionName of functionNames) {
    const explicitRevokePattern = new RegExp(
      `revoke\\s+(?:all|execute)\\s+on\\s+function\\s+public\\.${functionName}\\s*\\(`,
      'i'
    )
    if (!explicitRevokePattern.test(migration.sql)) {
      missingExplicitFunctionAcl.push(`${migration.fileName}: public.${functionName}`)
    }
  }
}

assert.deepEqual(
  forbiddenAnonymousGrants,
  [],
  `安全边界之后禁止向 public/anon 授予 public schema 函数执行权：\n${forbiddenAnonymousGrants.join('\n')}`
)
assert.deepEqual(
  missingFunctionAcl,
  [],
  `新增 SECURITY DEFINER 函数必须显式撤销默认 EXECUTE，再按需授权：\n${missingFunctionAcl.join('\n')}`
)
assert.deepEqual(
  missingExplicitFunctionAcl,
  [],
  `新增 public schema 函数必须显式声明 EXECUTE 权限边界：\n${missingExplicitFunctionAcl.join('\n')}`
)

console.log(
  `Database security audit passed: ${migrations.length} migrations, ${governedMigrations.length} SECURITY DEFINER changes and ${explicitAclMigrations.length} explicit-ACL changes governed after the fail-closed boundaries.`
)
