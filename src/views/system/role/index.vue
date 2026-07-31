<template>
  <div class="art-full-height">
    <ArtTableQuery
      v-model="searchForm"
      v-model:columns="columnChecks"
      v-model:show-search-bar="showSearchBar"
      :loading="loading"
      :data="data"
      :table-columns="columns"
      :pagination="pagination"
      :search-bar-props="searchBarProps"
      :table-props="tableProps"
      @search="handleSearch"
      @reset="resetSearchParams"
      @refresh="refreshData"
      @pagination:size-change="handleSizeChange"
      @pagination:current-change="handleCurrentChange"
    >
      <template #header-left>
        <ElSpace wrap>
          <ElButton @click="showDialog('add')" v-ripple>新增角色</ElButton>
        </ElSpace>
      </template>
    </ArtTableQuery>

    <RoleEditDialog ref="roleEditDialogRef" @success="refreshData" />
    <RolePermissionDialog ref="rolePermissionDialogRef" @success="refreshData" />
  </div>
</template>

<script setup lang="ts">
  import { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import { useTable } from '@/hooks/core/useTable'
  import { deleteRole, fetchGetRoleList } from '@/api/system-manage'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import RoleEditDialog from './modules/role-edit-dialog.vue'
  import RolePermissionDialog from './modules/role-permission-dialog.vue'
  import { ElTag, ElMessageBox } from 'element-plus'
  import { formatWithDayjs } from '@/utils/time'
  import { pageInfoHandler } from '@utils/table/tableUtils'
  import { ColumnOption } from '@/types'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQuerySearchBarProps,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import { useSystemParam } from '@/hooks'

  defineOptions({ name: 'Role' })

  type RoleListItem = Api.SystemManage.RoleListItem
  type RoleSearchParams = Api.SystemManage.RoleSearchParams & {
    daterange?: [string, string] | null
  }

  const searchForm = ref({
    roleName: undefined,
    roleCode: undefined,
    description: undefined,
    enabled: undefined,
    daterange: undefined
  })

  const showSearchBar = ref(false)
  const statusOptions = [
    { label: '启用', value: true },
    { label: '禁用', value: false }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '角色名称',
      key: 'roleName',
      type: 'input',
      placeholder: '请输入角色名称',
      clearable: true
    },
    {
      label: '角色编码',
      key: 'roleCode',
      type: 'input',
      placeholder: '请输入角色编码',
      clearable: true
    },
    {
      label: '角色描述',
      key: 'description',
      type: 'input',
      placeholder: '请输入角色描述',
      clearable: true
    },
    {
      label: '角色状态',
      key: 'enabled',
      type: 'select',
      props: {
        placeholder: '请选择状态',
        options: statusOptions,
        clearable: true
      }
    },
    {
      label: '创建日期',
      key: 'daterange',
      type: 'date',
      props: {
        style: { width: '100%' },
        placeholder: '请选择日期范围',
        type: 'daterange',
        rangeSeparator: '至',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        valueFormat: 'YYYY-MM-DD',
        shortcuts: [
          { text: '今日', value: [new Date(), new Date()] },
          { text: '最近一周', value: [new Date(Date.now() - 604800000), new Date()] },
          { text: '最近一个月', value: [new Date(Date.now() - 2592000000), new Date()] }
        ]
      }
    }
  ])

  const searchBarProps = computed<ArtTableQuerySearchBarProps>(() => ({
    items: searchItems.value
  }))

  const tableProps: ArtTableQueryTableProps = {
    tableLayout: 'fixed'
  }

  interface RoleEditDialogExpose {
    handleOpen: (data: { type: 'add' | 'edit'; roleData?: RoleListItem }) => Promise<void>
  }

  interface RolePermissionDialogExpose {
    handleOpen: (data: RoleListItem) => Promise<void>
  }

  const roleEditDialogRef = ref<RoleEditDialogExpose>()
  const rolePermissionDialogRef = ref<RolePermissionDialogExpose>()
  const {
    defaultRegisterTenantCode,
    defaultRegisterRoleCode,
    superRoleCode,
    loadRoleBuiltinCodes
  } = useSystemParam()

  const normalizeRoleCode = (roleCode?: string): string => String(roleCode ?? '').toUpperCase()

  const isDefaultRegisterRole = (row: RoleListItem): boolean => {
    return (
      String(row.tenant?.tenantCode ?? '').toLowerCase() ===
        defaultRegisterTenantCode.value.toLowerCase() &&
      normalizeRoleCode(row.roleCode) === normalizeRoleCode(defaultRegisterRoleCode.value)
    )
  }

  const isSuperRole = (row: RoleListItem): boolean =>
    normalizeRoleCode(row.roleCode) === normalizeRoleCode(superRoleCode.value)

  onMounted(() => {
    void loadRoleBuiltinCodes()
  })

  const getRoleActions = (row: RoleListItem): ButtonMoreItem[] => {
    if (isSuperRole(row)) {
      return []
    }

    const actions: ButtonMoreItem[] = [
      {
        key: 'permission',
        label: '菜单权限',
        icon: 'ri:user-3-line'
      },
      {
        key: 'edit',
        label: '编辑角色',
        icon: 'ri:edit-2-line'
      },
      {
        key: 'delete',
        label: '删除角色',
        icon: 'ri:delete-bin-4-line',
        color: '#f56c6c'
      }
    ]

    return isDefaultRegisterRole(row) ? actions.filter((item) => item.key !== 'delete') : actions
  }

  const {
    columns,
    columnChecks,
    data,
    loading,
    pagination,
    getData,
    searchParams,
    resetSearchParams,
    handleSizeChange,
    handleCurrentChange,
    refreshData
  } = useTable<RoleListItem>({
    core: {
      apiFn: () => handleGetRoleList(),
      apiParams: {
        current: 1,
        size: 20
      },
      excludeParams: ['daterange'],
      columnsFactory: (): ColumnOption<RoleListItem>[] => [
        {
          prop: 'roleName',
          label: '角色名称',
          minWidth: 120
        },
        {
          prop: 'roleCode',
          label: '角色编码',
          minWidth: 120
        },
        {
          prop: 'description',
          label: '角色描述',
          minWidth: 150,
          showOverflowTooltip: true
        },
        {
          prop: 'enabled',
          label: '角色状态',
          width: 100,
          formatter: (row: RoleListItem) => {
            const statusConfig = row.enabled
              ? { type: 'success', text: '启用' }
              : { type: 'warning', text: '禁用' }
            return h(
              ElTag,
              { type: statusConfig.type as 'success' | 'warning' },
              () => statusConfig.text
            )
          }
        },
        {
          prop: 'createBy',
          label: '创建人',
          width: 180
        },
        {
          prop: 'createTime',
          label: '创建日期',
          width: 180,
          sortable: true,
          formatter: (row: RoleListItem) => formatWithDayjs(row.createTime)
        },
        {
          prop: 'operation',
          label: '操作',
          width: 80,
          fixed: 'right',
          formatter: (row: RoleListItem) =>
            h('div', [
              getRoleActions(row).length
                ? h(ArtButtonMore, {
                    list: getRoleActions(row),
                    onClick: (item: ButtonMoreItem) => buttonMoreClick(item, row)
                  })
                : null
            ])
        }
      ]
    }
  })

  const showDialog = (type: 'add' | 'edit', row?: RoleListItem) => {
    void roleEditDialogRef.value?.handleOpen({
      type,
      roleData: row
    })
  }

  const handleSearch = (params: Record<string, unknown>) => {
    const { daterange, ...filtersParams } = params
    const [startTime, endTime] = Array.isArray(daterange) ? daterange : [null, null]
    Object.assign(searchParams, { ...filtersParams, startTime, endTime })
    void getData()
  }

  const buttonMoreClick = (item: ButtonMoreItem, row: RoleListItem) => {
    switch (item.key) {
      case 'permission':
        showPermissionDialog(row)
        break
      case 'edit':
        showDialog('edit', row)
        break
      case 'delete':
        handleDeleteRole(row)
        break
    }
  }

  const showPermissionDialog = (row: RoleListItem) => {
    void rolePermissionDialogRef.value?.handleOpen(row)
  }

  const handleDeleteRole = (row: RoleListItem) => {
    ElMessageBox.confirm(`确定删除角色"${row.roleName}"吗？此操作不可恢复！`, '删除确认', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning'
    })
      .then(async () => {
        await deleteRole(row)
        await refreshData()
      })
      .catch(() => {
        ElMessage.info('已取消删除')
      })
  }

  const handleGetRoleList = async () => {
    const { roleName, roleCode, description, enabled, startTime, endTime } =
      searchParams as RoleSearchParams
    const { from, to } = pageInfoHandler(pagination)
    return await fetchGetRoleList({
      roleName,
      roleCode,
      description,
      enabled,
      startTime,
      endTime,
      from,
      to
    })
  }
</script>
