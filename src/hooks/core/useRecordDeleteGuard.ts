import { ref, toValue, type MaybeRefOrGetter } from 'vue'
import { useAuth } from './useAuth'
import { createRecordReferenceNavigation } from '@/components/business/master-data-delete-guard/record-navigation'
import { ElMessage } from 'element-plus'
import { fetchRecordDeleteDependencies } from '@/api/master-data-delete'
import { notifyFriendlyError, useArtFeedback } from './useArtFeedback'
import {
  getDeleteReferenceContext,
  type DeleteReferenceContext
} from '@/utils/supabase/delete-reference'
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
  resources: MasterDataDeleteResource[],
  referenceMeta: Record<string, Partial<MasterDataDeleteDependencyMeta>> = {}
): MasterDataDeleteGuardOpenOptions {
  const { hasAuth } = useAuth()
  const navigationMeta = { ...createRecordReferenceNavigation(hasAuth), ...referenceMeta }
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
          description: '请核对以下引用记录，处理关联后再重试删除。',
          ...navigationMeta[row.sourceTable]
        }
      }
      return rows.map((row) => ({
        ...row,
        createdAt: row.createdAt ?? '',
        dependencyCode: row.sourceTable,
        recordStatus: getRecordReferenceMeta(row.sourceTable).statusDictCode
          ? row.recordStatus
          : formatReferenceStatus(row.recordStatus) || '状态待核对',
        cleanupAllowed: false
      }))
    }
  }
}

export function useRecordDeleteGuard(
  table: MaybeRefOrGetter<string>,
  resourceLabel: MaybeRefOrGetter<string>,
  referenceMeta: Record<string, Partial<MasterDataDeleteDependencyMeta>> = {}
) {
  const { hasAuth } = useAuth()
  const { confirmDelete } = useArtFeedback()
  const deleteBusy = ref(false)
  const deleteGuardRef = ref<{
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }>()
  const inspectResolvedReferences = (
    resources: MasterDataDeleteResource[],
    tableName: string,
    label: string,
    constraint?: string
  ) => {
    if (!deleteGuardRef.value) {
      ElMessage.error('关联校验尚未就绪，请刷新页面后重试删除')
      return Promise.resolve(true)
    }
    return deleteGuardRef.value.inspect(
      recordDeleteGuardOptions(
        { table: tableName, ids: resources.map((row) => row.id), constraint },
        label,
        resources,
        referenceMeta
      )
    )
  }
  const inspectDeleteReferences = (resources: MasterDataDeleteResource[], constraint?: string) =>
    inspectResolvedReferences(resources, toValue(table), toValue(resourceLabel), constraint)
  const deleteRecord = async (options: {
    resource: MasterDataDeleteResource
    resourceLabel?: string
    permission: string | string[]
    remove: () => Promise<unknown>
    onDeleted?: () => Promise<unknown>
    confirmMessage?: string
    failureMessage?: string
  }): Promise<void> => {
    if (deleteBusy.value) return
    const permissions = Array.isArray(options.permission)
      ? [...options.permission]
      : [options.permission]
    const hasDeletePermission = () =>
      permissions.length > 0 &&
      permissions.every((permission) => permission.trim().length > 0 && hasAuth(permission))
    if (!options.resource.id || !hasDeletePermission()) {
      ElMessage.error('当前账号无权删除此记录，或记录已变化，请刷新后重试')
      return
    }
    deleteBusy.value = true
    const resources = [options.resource]
    const label = options.resourceLabel ?? toValue(resourceLabel)
    const tableName = toValue(table)
    try {
      if (await inspectResolvedReferences(resources, tableName, label)) return
      await confirmDelete(
        options.confirmMessage ?? `确认删除${label}“${options.resource.label}”？此操作不可恢复。`
      )
      if (!hasDeletePermission()) {
        ElMessage.error('删除权限已变化，请刷新页面后重试')
        return
      }
      try {
        await options.remove()
      } catch (error) {
        if (
          await inspectResolvedReferences(
            resources,
            tableName,
            label,
            getDeleteReferenceContext(error)?.constraint
          )
        )
          return
        throw error
      }
      await options.onDeleted?.()
    } catch (error) {
      if (error !== 'cancel' && error !== 'close')
        notifyFriendlyError(error, options.failureMessage ?? `${label}删除失败，请刷新列表后重试`)
    } finally {
      deleteBusy.value = false
    }
  }
  return { deleteGuardRef, inspectDeleteReferences, deleteRecord, deleteBusy }
}
