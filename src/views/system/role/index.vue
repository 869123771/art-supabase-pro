<template>
  <div class="role-page art-full-height">
    <ArtTableQuery
      v-model="searchForm"
      v-model:columns="columnChecks"
      v-model:show-search-bar="showSearchBar"
      :loading="loading"
      :data="data"
      :table-columns="columns"
      :pagination="pagination"
      :search-bar-props="searchBarProps"
      :header-actions="headerActions"
      :table-props="tableProps"
      @search="handleSearch"
      @reset="resetSearchParams"
      @refresh="refreshData"
      @pagination:size-change="handleSizeChange"
      @pagination:current-change="handleCurrentChange"
    />

    <RoleEditDialog ref="roleEditDialogRef" @success="refreshData" />
    <RolePermissionDialog ref="rolePermissionDialogRef" @success="refreshData" />
  </div>
</template>

<script setup lang="ts">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import { useTable } from '@/hooks/core/useTable'
  import { deleteRole, fetchGetRoleList } from '@/api/system-manage'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import RoleEditDialog from './modules/role-edit-dialog.vue'
  import RolePermissionDialog from './modules/role-permission-dialog.vue'
  import { formatWithDayjs } from '@/utils/time'
  import { pageInfoHandler } from '@utils/table/tableUtils'
  import { ColumnOption } from '@/types'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryHeaderAction,
    ArtTableQuerySearchBarProps,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import { useSystemParam } from '@/hooks'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'Role' })

  const { confirmAction } = useArtFeedback()

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
  const { getDictMap } = storeToRefs(useUserStore())
  const statusOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

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
      label: '是否启用',
      key: 'enabled',
      type: 'select',
      props: {
        placeholder: '请选择是否启用',
        options: statusOptions.value,
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

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '新增角色',
      onClick: () => showDialog('add')
    }
  ])

  const tableProps: ArtTableQueryTableProps = {
    rowKey: 'id',
    tableLayout: 'fixed',
    emptyText: '暂无符合条件的角色',
    emptyDescription: '可调整筛选条件，或新增角色后再配置菜单权限。'
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
        color: 'var(--el-color-danger)'
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
          prop: 'roleIdentity',
          label: '角色身份',
          minWidth: 230,
          formatter: (row: RoleListItem) =>
            h('div', { class: 'role-identity-cell' }, [
              h(
                'span',
                {
                  class: [
                    'role-identity-cell__icon',
                    { 'is-protected': isSuperRole(row) || isDefaultRegisterRole(row) }
                  ],
                  'aria-hidden': 'true'
                },
                (row.roleName || '角').slice(0, 1)
              ),
              h('div', { class: 'role-identity-cell__copy' }, [
                h('div', { class: 'role-identity-cell__heading' }, [
                  h('strong', { title: row.roleName }, row.roleName),
                  isSuperRole(row) || isDefaultRegisterRole(row)
                    ? h('span', { class: 'role-identity-cell__builtin' }, '系统内置')
                    : null
                ]),
                h('span', { class: 'role-identity-cell__code', title: row.roleCode }, row.roleCode)
              ])
            ])
        },
        {
          prop: 'tenant',
          label: '所属租户',
          minWidth: 180,
          formatter: (row: RoleListItem) =>
            h('div', { class: 'role-tenant-cell' }, [
              h('strong', { title: row.tenant?.tenantName }, row.tenant?.tenantName || '当前租户'),
              row.tenant?.tenantCode
                ? h('span', { title: row.tenant.tenantCode }, row.tenant.tenantCode)
                : null
            ])
        },
        {
          prop: 'description',
          label: '角色描述',
          minWidth: 220,
          showOverflowTooltip: true
        },
        {
          prop: 'enabled',
          label: '是否启用',
          width: 96,
          dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.enabled) }
        },
        {
          prop: 'createTime',
          label: '创建信息',
          minWidth: 190,
          sortable: true,
          formatter: (row: RoleListItem) =>
            h('div', { class: 'role-created-cell' }, [
              h('span', null, formatWithDayjs(row.createTime) || '--'),
              h('small', null, row.createBy || '系统创建')
            ])
        },
        {
          prop: 'operation',
          label: '操作',
          width: 104,
          fixed: 'right',
          formatter: (row: RoleListItem) =>
            h('div', { class: 'role-operation-cell' }, [
              getRoleActions(row).length
                ? h(ArtButtonMore, {
                    list: getRoleActions(row),
                    onClick: (item: ButtonMoreItem) => buttonMoreClick(item, row)
                  })
                : h('span', { class: 'role-operation-cell__protected' }, '受保护')
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

  const handleDeleteRole = async (row: RoleListItem): Promise<void> => {
    try {
      await confirmAction(
        `删除后，已关联该角色的用户将失去对应菜单权限。确认删除「${row.roleName}」吗？`,
        '删除角色',
        {
          confirmButtonText: '确认删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteRole(row)
      await refreshData()
    } catch {
      // 用户取消删除时无需额外提示。
    }
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

<style scoped lang="scss">
  .role-page {
    :deep(.role-identity-cell) {
      display: flex;
      min-width: 0;
      align-items: center;
      gap: 10px;

      .role-identity-cell__icon {
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

        &.is-protected {
          color: var(--el-color-warning-dark-2);
          background: var(--el-color-warning-light-9);
          border-color: var(--el-color-warning-light-7);
        }
      }

      .role-identity-cell__copy,
      .role-identity-cell__heading {
        min-width: 0;
      }

      .role-identity-cell__heading {
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

      .role-identity-cell__code {
        display: block;
        overflow: hidden;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .role-identity-cell__builtin {
        flex: none;
        padding: 1px 6px;
        font-size: 10px;
        line-height: 17px;
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-radius: 999px;
      }
    }

    :deep(.role-tenant-cell),
    :deep(.role-created-cell) {
      display: grid;
      min-width: 0;
      line-height: 20px;

      strong,
      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong,
      span {
        font-weight: 500;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.role-operation-cell) {
      display: flex;
      align-items: center;

      .role-operation-cell__protected {
        font-size: 12px;
        color: var(--el-text-color-placeholder);
      }
    }
  }
</style>
