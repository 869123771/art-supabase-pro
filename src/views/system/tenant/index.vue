<template>
  <div class="tenant-page art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :table-props="tableProps"
    />

    <TenantDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import type { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import { deleteTenant, deleteTenantBatch, fetchGetTenantList } from '@/api/system-manage'
  import TenantDialog from './modules/tenant-dialog.vue'
  import { useUserStore } from '@/store/modules/user'
  import { useSystemParam } from '@/hooks'

  defineOptions({ name: 'Tenant' })

  const { confirmAction } = useArtFeedback()

  type Tenant = Api.SystemManage.TenantListItem
  type SearchParams = Api.SystemManage.TenantSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Tenant) => Promise<void>
  }
  const userStore = useUserStore()
  const { getDictMap, isSuper } = storeToRefs(userStore)
  const { defaultRegisterTenantCode, loadRoleBuiltinCodes } = useSystemParam()

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const systemTenantCodes = computed(
    () => new Set(['platform', defaultRegisterTenantCode.value.toLowerCase()])
  )
  const canManageTenant = computed(() => Boolean(isSuper.value))

  onMounted(() => {
    void loadRoleBuiltinCodes()
  })

  const searchQuery = ref<SearchParams>({
    tenantCode: '',
    tenantName: '',
    status: undefined
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '租户编码',
      key: 'tenantCode',
      type: 'input',
      props: { placeholder: '请输入租户编码', clearable: true }
    },
    {
      label: '租户名称',
      key: 'tenantName',
      type: 'input',
      props: { placeholder: '请输入租户名称', clearable: true }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.status ?? []
      }
    }
  ])

  const tableProps: ArtTableQueryTableProps = {
    rowKey: 'id',
    tableLayout: 'fixed',
    emptyText: '暂无符合条件的租户',
    emptyDescription: canManageTenant.value
      ? '可调整筛选条件，或新增租户后再查看。'
      : '当前账号仅能查看已授权的租户信息。'
  }

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    canManageTenant.value
      ? [
          {
            type: 'add',
            permission: 'System:Tenant:Add',
            onClick: () => openDialog()
          },
          {
            type: 'delete',
            permission: 'System:Tenant:Delete',
            content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
              `确定删除选中的 ${selectedCount} 个租户吗？删除后无法恢复。`,
            onClick: async ({ selectedRows }) => {
              const ids = selectedRows.map((row) => row.id).filter(Boolean)
              await deleteTenantBatch(ids)
              await tableQueryRef.value?.refreshRemove()
            }
          }
        ]
      : []
  )

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchGetTenantList({
      ...params,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<Tenant>[] => [
    {
      type: 'selection',
      width: 50,
      fixed: 'left',
      reserveSelection: true,
      selectable: (row: Tenant) => canManageTenant.value && !isSystemTenant(row)
    },
    {
      type: 'globalIndex',
      label: '序号',
      width: 72
    },
    {
      prop: 'tenantIdentity',
      label: '租户身份',
      minWidth: 260,
      formatter: (row) => (
        <div class="tenant-identity-cell">
          <span
            class={['tenant-identity-cell__icon', { 'is-system': isSystemTenant(row) }]}
            aria-hidden="true"
          >
            {(row.tenantName || '租').slice(0, 1)}
          </span>
          <div class="tenant-identity-cell__copy">
            <div class="tenant-identity-cell__heading">
              <strong title={row.tenantName}>{row.tenantName}</strong>
              {isSystemTenant(row) ? (
                <span class="tenant-identity-cell__system">系统租户</span>
              ) : null}
            </div>
            <span class="tenant-identity-cell__code" title={row.tenantCode}>
              {row.tenantCode}
            </span>
          </div>
        </div>
      )
    },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      dict: { code: 'status', display: 'auto' }
    },
    {
      prop: 'remark',
      label: '用途说明',
      minWidth: 260,
      showOverflowTooltip: true,
      formatter: (row) =>
        row.remark ? (
          <span class="tenant-remark-cell">{row.remark}</span>
        ) : (
          <span class="tenant-cell-placeholder">暂无说明</span>
        )
    },
    {
      prop: 'createTime',
      label: '创建信息',
      minWidth: 190,
      formatter: (row) => (
        <div class="tenant-created-cell">
          <span>{formatWithDayjs(row.createTime)}</span>
          <small>{row.createBy || '系统创建'}</small>
        </div>
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 104,
      fixed: 'right',
      formatter: (row) =>
        canManageTenant.value ? (
          <ArtButtonMore
            list={getTenantActions(row)}
            onClick={(item: ButtonMoreItem) => handleTenantAction(item, row)}
          />
        ) : (
          <span class="tenant-readonly-cell">只读</span>
        )
    }
  ]

  const openDialog = (row?: Tenant): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const isSystemTenant = (row: Pick<Tenant, 'tenantCode'>): boolean => {
    return systemTenantCodes.value.has(String(row.tenantCode ?? '').toLowerCase())
  }

  const getTenantActions = (row: Tenant): ButtonMoreItem[] => {
    const actions: ButtonMoreItem[] = [
      {
        key: 'edit',
        label: '编辑租户',
        icon: 'ri:edit-2-line',
        auth: 'System:Tenant:Edit'
      },
      {
        key: 'delete',
        label: '删除租户',
        icon: 'ri:delete-bin-4-line',
        color: 'var(--el-color-danger)',
        auth: 'System:Tenant:Delete'
      }
    ]

    return isSystemTenant(row) ? actions.filter((item) => item.key !== 'delete') : actions
  }

  const handleTenantAction = (item: ButtonMoreItem, row: Tenant): void => {
    switch (item.key) {
      case 'edit':
        openDialog(row)
        break
      case 'delete':
        void handleDelete(row)
        break
    }
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Tenant): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(
        `删除「${row.tenantName}」后，其账号、角色及业务数据关联可能受到影响。确认继续吗？`,
        '删除租户',
        {
          confirmButtonText: '确认删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteTenant(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需额外提示。
    }
  }
</script>

<style scoped lang="scss">
  .tenant-page {
    :deep(.tenant-identity-cell) {
      display: flex;
      min-width: 0;
      align-items: center;
      gap: 10px;

      .tenant-identity-cell__icon {
        display: grid;
        flex: 0 0 36px;
        width: 36px;
        height: 36px;
        font-size: 14px;
        font-weight: 700;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border: 1px solid var(--el-color-primary-light-7);
        border-radius: var(--art-control-radius);
        place-items: center;

        &.is-system {
          color: var(--el-color-warning-dark-2);
          background: var(--el-color-warning-light-9);
          border-color: var(--el-color-warning-light-7);
        }
      }

      .tenant-identity-cell__copy,
      .tenant-identity-cell__heading {
        min-width: 0;
      }

      .tenant-identity-cell__heading {
        display: flex;
        align-items: center;
        gap: 6px;

        strong {
          overflow: hidden;
          font-weight: 600;
          color: var(--el-text-color-primary);
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }

      .tenant-identity-cell__code {
        display: block;
        overflow: hidden;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .tenant-identity-cell__system {
        flex: none;
        padding: 1px 6px;
        font-size: 10px;
        line-height: 17px;
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-radius: 999px;
      }
    }

    :deep(.tenant-remark-cell) {
      color: var(--el-text-color-regular);
    }

    :deep(.tenant-cell-placeholder),
    :deep(.tenant-readonly-cell) {
      font-size: 12px;
      color: var(--el-text-color-placeholder);
    }

    :deep(.tenant-created-cell) {
      display: grid;
      min-width: 0;
      line-height: 20px;

      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      span {
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }
  }
</style>
