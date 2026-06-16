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
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
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
  const { getDictMap, getDictTagByValue } = useUserStore()

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()

  const searchQuery = ref<SearchParams>({
    tenantCode: '',
    tenantName: '',
    status: undefined,
    contactName: ''
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
      label: '联系人',
      key: 'contactName',
      type: 'input'
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap?.status ?? []
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
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
  ])

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
      reserveSelection: true
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
      prop: 'contactName',
      label: '联系人',
      width: 120
    },
    {
      prop: 'contactPhone',
      label: '联系电话',
      width: 150
    },
    {
      prop: 'contactEmail',
      label: '联系邮箱',
      minWidth: 180
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
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable
            type="edit"
            permission="System:Tenant:Edit"
            onClick={() => openDialog(row)}
          />
          <ArtButtonTable
            type="delete"
            permission="System:Tenant:Delete"
            onClick={() => handleDelete(row)}
          />
        </div>
      )
    }
  ]

  const openDialog = (row?: Tenant): void => {
    void dialogRef.value?.handleOpen(row)
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
