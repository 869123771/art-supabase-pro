import assert from 'node:assert/strict'
import test from 'node:test'
import {
  readTenantScopeId,
  readPlatformTenantScopeActive,
  readMutationTenantScopeId,
  normalizePlatformTenantReadUrl,
  resolveTenantScopeId,
  resolveTenantWorkspaceId,
  resolveTenantWriteTargetId,
  shouldAttachTenantScopeHeader,
  TENANT_SCOPE_MODE_STORAGE_KEY,
  TENANT_SCOPE_STORAGE_KEY,
  writePlatformTenantScopeActive,
  writeTenantScopeId
} from '../../src/utils/tenant-scope-context'

test('tenant-bound workspaces prefer the selected tenant and fall back to the home tenant', () => {
  assert.equal(
    resolveTenantWorkspaceId(
      '7529f951-938e-4e2c-ac0d-316c136ae1f9',
      '028e6a68-a9db-4055-974c-1e05bfe94b0f'
    ),
    '7529f951-938e-4e2c-ac0d-316c136ae1f9'
  )
  assert.equal(
    resolveTenantWorkspaceId(null, '028e6a68-a9db-4055-974c-1e05bfe94b0f'),
    '028e6a68-a9db-4055-974c-1e05bfe94b0f'
  )
  assert.equal(resolveTenantWorkspaceId(null, null), '')
})

test('tenant-owned writes prefer an explicit target and default to the actor tenant', () => {
  const ownTenantId = '028e6a68-a9db-4055-974c-1e05bfe94b0f'
  const otherTenantId = '7529f951-938e-4e2c-ac0d-316c136ae1f9'

  assert.equal(
    resolveTenantWriteTargetId({
      explicitTenantId: otherTenantId,
      effectiveTenantId: null,
      actorTenantId: ownTenantId,
      canWriteToOtherTenant: true
    }),
    otherTenantId
  )
  assert.equal(
    resolveTenantWriteTargetId({
      effectiveTenantId: otherTenantId,
      actorTenantId: ownTenantId,
      canWriteToOtherTenant: true
    }),
    otherTenantId
  )
  assert.equal(
    resolveTenantWriteTargetId({
      effectiveTenantId: ownTenantId,
      actorTenantId: ownTenantId,
      canWriteToOtherTenant: false
    }),
    ownTenantId
  )
  assert.equal(
    resolveTenantWriteTargetId({ actorTenantId: ownTenantId, canWriteToOtherTenant: true }),
    ownTenantId
  )
  assert.throws(
    () => resolveTenantWriteTargetId({ canWriteToOtherTenant: true }),
    /请先选择目标租户/
  )
  assert.throws(
    () =>
      resolveTenantWriteTargetId({
        explicitTenantId: otherTenantId,
        effectiveTenantId: ownTenantId,
        actorTenantId: ownTenantId,
        canWriteToOtherTenant: false
      }),
    /目标租户与当前选择不一致/
  )
  assert.throws(
    () =>
      resolveTenantWriteTargetId({
        explicitTenantId: otherTenantId,
        effectiveTenantId: ownTenantId,
        actorTenantId: ownTenantId,
        canWriteToOtherTenant: true
      }),
    /目标租户与当前选择不一致/
  )
  assert.throws(
    () =>
      resolveTenantWriteTargetId({
        explicitTenantId: otherTenantId,
        actorTenantId: ownTenantId,
        canWriteToOtherTenant: false
      }),
    /只能操作当前账号所属租户/
  )
  assert.throws(
    () => resolveTenantWriteTargetId({ explicitTenantId: '../other', canWriteToOtherTenant: true }),
    /目标租户无效/
  )
})

class MemoryStorage implements Storage {
  private readonly values = new Map<string, string>()

  get length(): number {
    return this.values.size
  }

  clear(): void {
    this.values.clear()
  }

  getItem(key: string): string | null {
    return this.values.get(key) ?? null
  }

  key(index: number): string | null {
    return [...this.values.keys()][index] ?? null
  }

  removeItem(key: string): void {
    this.values.delete(key)
  }

  setItem(key: string, value: string): void {
    this.values.set(key, value)
  }
}

test('tenant scope context persists only valid concrete tenant UUIDs', () => {
  const originalDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'sessionStorage')
  const storage = new MemoryStorage()
  Object.defineProperty(globalThis, 'sessionStorage', { configurable: true, value: storage })

  try {
    const tenantId = '7529f951-938e-4e2c-ac0d-316c136ae1f9'
    writeTenantScopeId(tenantId)
    assert.equal(readTenantScopeId(), tenantId)
    assert.equal(resolveTenantScopeId(), tenantId)
    assert.equal(
      resolveTenantScopeId('a6f21b7d-bca8-4698-a72a-b6df251bf07c'),
      'a6f21b7d-bca8-4698-a72a-b6df251bf07c'
    )

    storage.setItem(TENANT_SCOPE_STORAGE_KEY, 'not-a-tenant-id')
    assert.equal(readTenantScopeId(), null)
    assert.equal(resolveTenantScopeId(), undefined)

    writeTenantScopeId(null)
    assert.equal(storage.getItem(TENANT_SCOPE_STORAGE_KEY), null)
  } finally {
    if (originalDescriptor) {
      Object.defineProperty(globalThis, 'sessionStorage', originalDescriptor)
    } else {
      Reflect.deleteProperty(globalThis, 'sessionStorage')
    }
  }
})

test('platform scope state is explicit even when all tenants is selected', () => {
  const originalDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'sessionStorage')
  const storage = new MemoryStorage()
  Object.defineProperty(globalThis, 'sessionStorage', { configurable: true, value: storage })

  try {
    writePlatformTenantScopeActive(true)
    assert.equal(readPlatformTenantScopeActive(), true)
    assert.equal(storage.getItem(TENANT_SCOPE_MODE_STORAGE_KEY), '1')

    writePlatformTenantScopeActive(false)
    assert.equal(readPlatformTenantScopeActive(), false)
  } finally {
    if (originalDescriptor) {
      Object.defineProperty(globalThis, 'sessionStorage', originalDescriptor)
    } else {
      Reflect.deleteProperty(globalThis, 'sessionStorage')
    }
  }
})

test('platform table reads discard legacy tenant filters but preserve explicit filters and RPCs', () => {
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/mdm_production_department?select=*&tenant_id=eq.platform&enabled=eq.true'
    ),
    'https://example.supabase.co/rest/v1/mdm_production_department?select=*&tenant_id=eq.platform&enabled=eq.true'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/mdm_production_personnel?tenant_id=eq.selected&enabled=eq.true'
    ),
    'https://example.supabase.co/rest/v1/mdm_production_personnel?tenant_id=eq.selected&enabled=eq.true'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/mdm_work_center?tenant_id=eq.selected&code=ilike.%25A%25'
    ),
    'https://example.supabase.co/rest/v1/mdm_work_center?tenant_id=eq.selected&code=ilike.%25A%25'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/mdm_work_center_defaults?tenant_id=eq.selected&select=policy'
    ),
    'https://example.supabase.co/rest/v1/mdm_work_center_defaults?tenant_id=eq.selected&select=policy'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/mdm_employee?organization.tenant_id=eq.platform&name=ilike.%25A%25'
    ),
    'https://example.supabase.co/rest/v1/mdm_employee?name=ilike.%25A%25'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/rpc/list_people?tenant_id=platform'
    ),
    'https://example.supabase.co/rest/v1/rpc/list_people?tenant_id=platform'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/sys_document_number_rule?tenant_id=eq.selected&enabled=eq.true'
    ),
    'https://example.supabase.co/rest/v1/sys_document_number_rule?tenant_id=eq.selected&enabled=eq.true'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/sys_attachment?tenant_id=eq.target&hash=eq.filehash'
    ),
    'https://example.supabase.co/rest/v1/sys_attachment?tenant_id=eq.target&hash=eq.filehash'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/sys_role?tenant_id=eq.target&enabled=eq.true'
    ),
    'https://example.supabase.co/rest/v1/sys_role?tenant_id=eq.target&enabled=eq.true'
  )
  for (const table of [
    'hr_candidate',
    'hr_competency',
    'hr_employee_competency',
    'hr_employee_contract',
    'hr_employee_qualification',
    'hr_personnel_change',
    'hr_position_competency',
    'hr_position_headcount',
    'hr_recruitment_requisition',
    'hr_training_enrollment',
    'hr_training_plan',
    'sys_user',
    'mdm_master_group',
    'mdm_equipment',
    'pmis_department_setting',
    'pmis_plan',
    'pmis_repair_task',
    'pmis_task',
    'scm_order_target_document',
    'wms_purchase_document_list'
  ]) {
    const url = `https://example.supabase.co/rest/v1/${table}?tenant_id=eq.target&status=eq.active`
    assert.equal(normalizePlatformTenantReadUrl(url), url)
  }
})

test('tenant scope header is attached only to Supabase Data API requests', () => {
  assert.equal(
    shouldAttachTenantScopeHeader('https://example.supabase.co/rest/v1/sys_user?select=*'),
    true
  )
  assert.equal(
    shouldAttachTenantScopeHeader(
      'https://example.supabase.co/rest/v1/rpc/get_platform_tenant_options'
    ),
    true
  )
  assert.equal(shouldAttachTenantScopeHeader('/rest/v1/sys_tenant'), true)

  assert.equal(
    shouldAttachTenantScopeHeader('https://example.supabase.co/functions/v1/check_user_status'),
    false
  )
  assert.equal(
    shouldAttachTenantScopeHeader('https://example.supabase.co/auth/v1/token?grant_type=password'),
    false
  )
  assert.equal(
    shouldAttachTenantScopeHeader(
      'https://example.supabase.co/storage/v1/object/public/avatar/demo.png'
    ),
    false
  )
  assert.equal(shouldAttachTenantScopeHeader('not a Supabase request'), false)
})

test('mutation tenant scope is read only from explicit table and supported RPC payloads', () => {
  const tenantId = '7529f951-938e-4e2c-ac0d-316c136ae1f9'
  assert.equal(readMutationTenantScopeId(JSON.stringify({ tenant_id: tenantId })), tenantId)
  assert.equal(
    readMutationTenantScopeId(JSON.stringify({ p_header: { tenant_id: tenantId } })),
    tenantId
  )
  assert.equal(
    readMutationTenantScopeId(JSON.stringify({ p_document: { tenant_id: tenantId } })),
    tenantId
  )
  assert.equal(readMutationTenantScopeId(JSON.stringify({ tenant_id: 'invalid' })), null)
  assert.equal(readMutationTenantScopeId('not-json'), null)
})
