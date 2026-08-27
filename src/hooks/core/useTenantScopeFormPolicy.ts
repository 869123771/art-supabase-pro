import { storeToRefs } from 'pinia'
import { useTenantScopeStore } from '@/store/modules/tenantScope'

interface TenantScopedFormItem {
  key: string
}

/**
 * Keeps the platform header tenant scope as the single source of truth for forms.
 * A singular tenantId field is context, not a page-level business input.
 */
export function useTenantScopeFormPolicy() {
  const { effectiveTenantId } = storeToRefs(useTenantScopeStore())
  const isTenantScopeItem = (item: TenantScopedFormItem): boolean => item.key === 'tenantId'

  return {
    effectiveTenantId,
    isTenantScopeItem
  }
}
