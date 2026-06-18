<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
    />

    <TenantDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessageBox, ElTag } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import type { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import { deleteTenant, deleteTenantBatch, fetchGetTenantList } from '@/api/system-manage'
  import TenantDialog from './modules/tenant-dialog.vue'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'Tenant' })

  type Tenant = Api.SystemManage.TenantListItem
  type SearchParams = Api.SystemManage.TenantSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Tenant) => Promise<void>
  }
  const userStore = useUserStore()
  const { getDictTagByValue } = userStore
  const { getDictMap, isSuper } = storeToRefs(userStore)

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const SYSTEM_TENANT_CODES = new Set(['platform', 'public-register'])
  const canManageTenant = computed(() => Boolean(isSuper.value))

  const searchQuery = ref<SearchParams>({
    tenantCode: '',
    tenantName: '',
    status: undefined
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '租户编码',
      key: 'tenantCode',
      type: 'input'
    },
    {
      label: '租户名称',
      key: 'tenantName',
      type: 'input'
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
      width: 80
    },
    {
      prop: 'tenantCode',
      label: '租户编码',
      minWidth: 140
    },
    {
      prop: 'tenantName',
      label: '租户名称',
      minWidth: 180
    },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      formatter: (row) => {
        const tag = getDictTagByValue('status', row.status)
        return (
          <ElTag type={tag.type}>
            <span>{tag.label}</span>
          </ElTag>
        )
      }
    },
    {
      prop: 'remark',
      label: '备注',
      minWidth: 180
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 180,
      formatter: (row) => formatWithDayjs(row.createTime)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 80,
      fixed: 'right',
      formatter: (row) =>
        canManageTenant.value ? (
          <ArtButtonMore
            list={getTenantActions(row)}
            onClick={(item: ButtonMoreItem) => handleTenantAction(item, row)}
          />
        ) : null
    }
  ]

  const openDialog = (row?: Tenant): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const isSystemTenant = (row: Pick<Tenant, 'tenantCode'>): boolean => {
    return SYSTEM_TENANT_CODES.has(String(row.tenantCode ?? '').toLowerCase())
  }

  const getTenantActions = (row: Tenant): ButtonMoreItem[] => {
    const actions: ButtonMoreItem[] = [
      {
        key: 'edit',
        label: '编辑',
        icon: 'ri:edit-2-line',
        auth: 'System:Tenant:Edit'
      },
      {
        key: 'delete',
        label: '删除',
        icon: 'ri:delete-bin-4-line',
        color: '#f56c6c',
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
      await ElMessageBox.confirm(
        `确定删除租户“${row.tenantName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
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
