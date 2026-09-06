import { storeToRefs } from 'pinia'
import { computed } from 'vue'
import { useTenantScopeStore } from '@/store/modules/tenantScope'

interface TenantScopedFormItem {
  key: string
}

/**
 * Resolves the tenant used by create forms.
 * A concrete shell scope supplies the tenant automatically. In the all-tenant scope, platform
 * administrators keep mutation access but must preserve/select the operation target tenant.
 */
export function useTenantScopeFormPolicy() {
  const { isAllTenants, effectiveTenantId: selectedTenantId } = storeToRefs(useTenantScopeStore())
  const effectiveTenantId = computed(() => selectedTenantId.value ?? null)
  const shouldExposeTenantField = computed(() => isAllTenants.value)
  const isTenantScopeItem = (item: TenantScopedFormItem): boolean => item.key === 'tenantId'

  return {
    effectiveTenantId,
    shouldExposeTenantField,
    isTenantScopeItem
  }
}
