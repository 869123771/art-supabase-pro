import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { fetchGetTenantList } from '@/api/system-manage'
import {
  readTenantScopeId,
  writePlatformTenantScopeActive,
  writeTenantScopeId
} from '@/utils/tenant-scope-context'
import { useUserStore } from './user'

type TenantScopeOption = Api.SystemManage.TenantListItem & { id: string }

export const useTenantScopeStore = defineStore(
  'tenantScopeStore',
  () => {
    const selectedTenantId = ref<string | null>(readTenantScopeId())
    const scopeOwnerUserId = ref<string | null>(null)
    const tenantOptions = ref<TenantScopeOption[]>([])
    const loading = ref(false)
    const loadError = ref<string | null>(null)
    const revision = ref(0)

    const userStore = useUserStore()
    const isPlatformScope = computed(() => userStore.isPlatformSuper)
    const isAllTenants = computed(() => isPlatformScope.value && selectedTenantId.value === null)
    const effectiveTenantId = computed(() =>
      isPlatformScope.value ? selectedTenantId.value : (userStore.getUserInfo.tenantId ?? null)
    )
    const selectedTenant = computed(() =>
      tenantOptions.value.find((tenant) => tenant.id === selectedTenantId.value)
    )
    const scopeLabel = computed(() =>
      isAllTenants.value ? '全部租户' : (selectedTenant.value?.tenantName ?? '当前租户')
    )

    const resetForCurrentUser = (): void => {
      const currentUserId = userStore.getUserInfo.userId ?? null
      if (scopeOwnerUserId.value === currentUserId) return

      const hadSelectedTenant = selectedTenantId.value !== null
      scopeOwnerUserId.value = currentUserId
      selectedTenantId.value = null
      writeTenantScopeId(null)
      writePlatformTenantScopeActive(isPlatformScope.value)
      tenantOptions.value = []
      if (hadSelectedTenant) revision.value += 1
    }

    const loadTenantOptions = async (force = false): Promise<void> => {
      resetForCurrentUser()
      if (!isPlatformScope.value) {
        tenantOptions.value = []
        selectedTenantId.value = userStore.getUserInfo.tenantId ?? null
        writeTenantScopeId(null)
        writePlatformTenantScopeActive(false)
        loadError.value = null
        return
      }
      writePlatformTenantScopeActive(true)
      writeTenantScopeId(selectedTenantId.value)
      if (tenantOptions.value.length && !force) return

      loading.value = true
      loadError.value = null
      try {
        const { data, error } = await fetchGetTenantList({ status: '1', from: 0, to: 999 })
        if (error) throw error

        tenantOptions.value = (data ?? []).filter(
          (tenant): tenant is TenantScopeOption =>
            typeof tenant.id === 'string' && tenant.builtinType !== 'platform'
        )
        if (
          selectedTenantId.value &&
          !tenantOptions.value.some((tenant) => tenant.id === selectedTenantId.value)
        ) {
          selectedTenantId.value = null
          writeTenantScopeId(null)
          revision.value += 1
        }
      } catch (error) {
        loadError.value = error instanceof Error ? error.message : '租户列表加载失败'
      } finally {
        loading.value = false
      }
    }

    const setTenantScope = (tenantId: string | null): void => {
      if (!isPlatformScope.value) return
      if (tenantId && !tenantOptions.value.some((tenant) => tenant.id === tenantId)) {
        return
      }
      if (selectedTenantId.value === tenantId) return

      selectedTenantId.value = tenantId
      writePlatformTenantScopeActive(true)
      writeTenantScopeId(tenantId)
      revision.value += 1
    }

    return {
      selectedTenantId,
      scopeOwnerUserId,
      tenantOptions,
      loading,
      loadError,
      revision,
      isPlatformScope,
      isAllTenants,
      effectiveTenantId,
      selectedTenant,
      scopeLabel,
      loadTenantOptions,
      setTenantScope
    }
  },
  {
    persist: {
      key: 'tenant-scope',
      storage: sessionStorage,
      pick: ['selectedTenantId', 'scopeOwnerUserId']
    }
  }
)
