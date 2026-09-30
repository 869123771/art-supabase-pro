import { ref } from 'vue'
import { fetchRecordDeleteDependencies } from '@/api/master-data-delete'
import type { DeleteReferenceContext } from '@/utils/supabase/delete-reference'
import type {
  MasterDataDeleteGuardOpenOptions,
  MasterDataDeleteResource,
  MasterDataDeleteDependencyMeta
} from '@/components/business/master-data-delete-guard/index.vue'
import {
  formatReferenceStatus,
  getRecordReferenceMeta
} from '@/components/business/master-data-delete-guard/record-meta'

export function recordDeleteGuardOptions(
  context: DeleteReferenceContext,
  resourceLabel: string,
  resources: MasterDataDeleteResource[]
): MasterDataDeleteGuardOpenOptions {
  const dependencyMeta: Record<string, MasterDataDeleteDependencyMeta> = {}
  return {
    resourceLabel,
    resources,
    dependencyMeta,
    navigationResource: { type: context.table, queryKey: 'referencedRecordId' },
    fetchDependencies: async () => {
      const rows = await fetchRecordDeleteDependencies(context)
      for (const row of rows) {
        const meta = getRecordReferenceMeta(row.sourceTable)
        dependencyMeta[row.sourceTable] = {
          ...meta,
          unit: '条',
          order: 1,
          actionLabel: '查看关联',
          description: '请核对以下引用记录，处理关联后再重试删除。'
        }
      }
      return rows.map((row) => ({
        ...row,
        createdAt: row.createdAt ?? '',
        dependencyCode: row.sourceTable,
        recordStatus: formatReferenceStatus(row.recordStatus),
        cleanupAllowed: false
      }))
    }
  }
}

export function useRecordDeleteGuard(table: string, resourceLabel: string) {
  const deleteGuardRef = ref<{
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }>()
  const inspectDeleteReferences = (resources: MasterDataDeleteResource[]) =>
    deleteGuardRef.value?.inspect(
      recordDeleteGuardOptions(
        { table, ids: resources.map((row) => row.id) },
        resourceLabel,
        resources
      )
    ) ?? Promise.resolve(true)
  return { deleteGuardRef, inspectDeleteReferences }
}
