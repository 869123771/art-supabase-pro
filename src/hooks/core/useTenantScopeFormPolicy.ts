import { storeToRefs } from 'pinia'
import { computed } from 'vue'
import { useUserStore } from '@/store/modules/user'
import { useTenantScopeStore } from '@/store/modules/tenantScope'

interface TenantScopedFormItem {
  key: string
}

/**
 * Resolves the tenant used by create forms.
 * A platform super uses the explicitly selected tenant, while "all tenants" falls back to the
 * authenticated actor tenant. Ordinary users always use their own tenant.
 */
export function useTenantScopeFormPolicy() {
  const { getUserInfo } = storeToRefs(useUserStore())
  const { effectiveTenantId: selectedTenantId } = storeToRefs(useTenantScopeStore())
  const effectiveTenantId = computed(
    () => selectedTenantId.value ?? getUserInfo.value.tenantId ?? null
  )
  const isTenantScopeItem = (item: TenantScopedFormItem): boolean => item.key === 'tenantId'

  return {
    effectiveTenantId,
    isTenantScopeItem
  }
}
