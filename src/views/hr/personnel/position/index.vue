<template>
  <div class="business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="POSITION CATALOG"
      title="岗位管理"
      description="统一维护员工岗位与业务属性；系统司机岗位会联动创建司机运营档案。"
      icon="ri:briefcase-4-line"
      :tags="[
        { label: 'HR 主数据', type: 'primary' },
        { label: '司机联动', type: 'success' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 80, showExpand: false }"
      :table-props="{
        emptyText: '暂无岗位',
        emptyDescription: '可新增普通岗位；系统司机岗位已自动为每个租户建立。'
      }"
      focusable
    />

    <PositionDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElTag } from 'element-plus'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import { deletePosition, fetchPositionList } from '@/api/hr'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import PositionDialog from './modules/position-dialog.vue'

  defineOptions({ name: 'HrPosition' })

  type Position = Api.Hr.Position
  type SearchParams = Api.Hr.PositionSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface PositionDialogExpose {
    handleOpen: (row?: Position) => Promise<void>
  }

  const { confirmAction } = useArtFeedback()
  const { isPlatformSuper } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<PositionDialogExpose>()
  const tenantOptions = ref<Array<{ label: string; value: string }>>([])
  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: { tenantId: '', enabled: undefined, keyword: '' }
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '所属租户',
      key: 'tenantId',
      type: 'select',
      hidden: !isPlatformSuper.value,
      props: { options: tenantOptions.value, clearable: true, filterable: true }
    },
    {
      label: '状态',
      key: 'enabled',
      type: 'select',
      props: {
        options: [
          { label: '启用', value: true },
          { label: '停用', value: false }
        ],
        clearable: true
      }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '岗位编码、名称或说明' }
    }
  ])

  const columnsFactory = (): ColumnOption<Position>[] => [
    ...(isPlatformSuper.value
      ? [
          {
            prop: 'tenant.tenantName',
            label: '所属租户',
            minWidth: 170,
            showOverflowTooltip: true
          } as ColumnOption<Position>
        ]
      : []),
    { prop: 'positionCode', label: '岗位编码', minWidth: 140, showOverflowTooltip: true },
    { prop: 'positionName', label: '岗位名称', minWidth: 150, showOverflowTooltip: true },
    {
      prop: 'positionKind',
      label: '业务属性',
      width: 110,
      formatter: (row) => (
        <ElTag type={row.positionKind === 'driver' ? 'success' : 'info'} effect="plain">
          {row.positionKind === 'driver' ? '司机岗位' : '普通岗位'}
        </ElTag>
      )
    },
    { prop: 'employeeCount', label: '在岗人数', width: 100, align: 'right' },
    {
      prop: 'enabled',
      label: '状态',
      width: 90,
      formatter: (row) => (
        <ElTag type={row.enabled ? 'success' : 'info'} effect="plain">
          {row.enabled ? '启用' : '停用'}
        </ElTag>
      )
    },
    { prop: 'sort', label: '排序', width: 80, align: 'right' },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
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
            permission="Hr:Position:Edit"
            onClick={() => openDialog(row)}
          />
          {!row.systemCode && (
            <ArtButtonTable
              type="delete"
              permission="Hr:Position:Delete"
              onClick={() => handleDelete(row)}
            />
          )}
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '新增岗位',
      permission: 'Hr:Position:Add',
      onClick: () => openDialog()
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchPositionList({ ...params, from, to })
  }

  const openDialog = (row?: Position): void => void dialogRef.value?.handleOpen(row)
  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Position): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除岗位“${row.positionName}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deletePosition(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消或服务端依赖校验失败时不追加重复提示。
    }
  }

  onMounted(async () => {
    if (!isPlatformSuper.value) return
    const response = await fetchGetEnableTenantList()
    tenantOptions.value = (response.data ?? []).map((tenant) => ({
      label: `${tenant.tenantName}（${tenant.tenantCode}）`,
      value: tenant.id!
    }))
  })
</script>
