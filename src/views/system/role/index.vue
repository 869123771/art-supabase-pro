<template>
  <div class="role-page art-full-height">
    <section class="role-page__overview art-card-xs">
      <header class="role-page__hero">
        <div class="role-page__identity">
          <div class="role-page__brand" aria-hidden="true">
            <ArtSvgIcon icon="ri:shield-user-line" />
          </div>
          <div>
            <span>ACCESS GOVERNANCE</span>
            <h1>角色与权限</h1>
            <p>按租户维护职责角色与菜单访问边界，让权限配置清晰、可追踪、可审计。</p>
          </div>
        </div>
        <div class="role-page__hero-status">
          <ElTag type="success" effect="light" round>权限按租户隔离</ElTag>
          <ElTag type="primary" effect="plain" round>遵循最小权限原则</ElTag>
        </div>
      </header>

      <div class="role-page__metrics" aria-label="角色治理概览">
        <article>
          <div class="role-page__metric-icon is-primary">
            <ArtSvgIcon icon="ri:team-line" />
          </div>
          <div>
            <span>当前结果</span>
            <strong>{{ pagination.total }}</strong>
            <small>随筛选条件实时更新</small>
          </div>
        </article>
        <article>
          <div class="role-page__metric-icon is-success">
            <ArtSvgIcon icon="ri:checkbox-circle-line" />
          </div>
          <div>
            <span>本页启用</span>
            <strong>{{ enabledRoleCount }}</strong>
            <small>当前页可正常授权</small>
          </div>
        </article>
        <article>
          <div class="role-page__metric-icon is-warning">
            <ArtSvgIcon icon="ri:shield-keyhole-line" />
          </div>
          <div>
            <span>受保护角色</span>
            <strong>{{ protectedRoleCount }}</strong>
            <small>内置角色限制关键操作</small>
          </div>
        </article>
      </div>
    </section>

    <ArtTableQuery
      focusable
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
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
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

  const getRoleMoreActions = (row: RoleListItem): ButtonMoreItem[] => {
    if (isSuperRole(row)) {
      return []
    }

    const actions: ButtonMoreItem[] = [
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
          prop: 'organization',
          label: '适用组织',
          minWidth: 180,
          formatter: (row: RoleListItem) =>
            row.organization
              ? h('div', { class: 'role-organization-cell' }, [
                  h(
                    'strong',
                    { title: row.organization.organizationName },
                    row.organization.organizationName
                  ),
                  h(
                    'small',
                    { title: row.organization.organizationCode },
                    row.organization.organizationCode
                  )
                ])
              : h('span', { class: 'role-organization-cell__empty' }, '待归入组织')
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
          width: 120,
          fixed: 'right',
          formatter: (row: RoleListItem) => {
            if (isSuperRole(row)) {
              return h('span', { class: 'role-operation-cell__protected' }, '受保护')
            }

            return h('div', { class: 'role-operation-cell' }, [
              h(ArtButtonTable, {
                type: 'view',
                icon: 'ri:shield-keyhole-line',
                label: '配置菜单权限',
                onClick: () => showPermissionDialog(row)
              }),
              h(ArtButtonMore, {
                list: getRoleMoreActions(row),
                onClick: (item: ButtonMoreItem) => buttonMoreClick(item, row)
              })
            ])
          }
        }
      ]
    }
  })

  const enabledRoleCount = computed(() => data.value.filter((row) => row.enabled).length)
  const protectedRoleCount = computed(
    () => data.value.filter((row) => isSuperRole(row) || isDefaultRegisterRole(row)).length
  )

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
    gap: 12px;
    min-width: 0;

    &__overview {
      flex: 0 0 auto;
      min-width: 0;
      overflow: hidden;
    }

    &__hero,
    &__identity,
    &__hero-status,
    &__metrics article,
    &__brand,
    &__metric-icon {
      display: flex;
      align-items: center;
    }

    &__hero {
      justify-content: space-between;
      gap: 20px;
      padding: 20px 24px 18px;
      background: radial-gradient(
        circle at 92% 0%,
        var(--el-color-primary-light-9),
        transparent 32%
      );
    }

    &__identity {
      min-width: 0;

      > div:last-child {
        min-width: 0;
      }

      span {
        display: block;
        margin-bottom: 3px;
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.14em;
      }

      h1 {
        margin: 0 0 3px;
        font-size: 22px;
        line-height: 1.35;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        overflow-wrap: anywhere;
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
      }
    }

    &__brand {
      justify-content: center;
      flex: 0 0 50px;
      width: 50px;
      height: 50px;
      margin-right: 16px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), var(--el-color-primary-dark-2));
      border-radius: var(--custom-radius);

      :deep(svg) {
        width: 23px;
        height: 23px;
      }
    }

    &__hero-status {
      flex: 0 0 auto;
      gap: 8px;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      border-top: 1px solid var(--el-border-color-lighter);

      article {
        min-width: 0;
        gap: 12px;
        padding: 14px 24px;

        &:not(:last-child) {
          border-right: 1px solid var(--el-border-color-lighter);
        }

        > div:last-child {
          display: grid;
          min-width: 0;
        }

        span,
        small {
          overflow: hidden;
          color: var(--el-text-color-secondary);
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        span {
          font-size: 12px;
        }

        strong {
          margin: 1px 0;
          font-size: 20px;
          line-height: 1.25;
          color: var(--el-text-color-primary);
        }

        small {
          font-size: 11px;
        }
      }
    }

    &__metric-icon {
      justify-content: center;
      flex: 0 0 38px;
      width: 38px;
      height: 38px;
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 18px;
        height: 18px;
      }

      &.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
      }
    }

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
    :deep(.role-organization-cell),
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

    :deep(.role-organization-cell__empty) {
      font-size: 12px;
      color: var(--el-text-color-placeholder);
    }

    :deep(.role-operation-cell) {
      display: flex;
      gap: 4px;
      align-items: center;

      .role-operation-cell__protected {
        font-size: 12px;
        color: var(--el-text-color-placeholder);
      }
    }

    @media (max-width: 900px) {
      &__hero {
        align-items: flex-start;
      }

      &__hero-status {
        flex-direction: column;
        align-items: flex-end;
      }

      &__metrics article {
        padding-inline: 16px;
      }
    }

    @media (max-width: 640px) {
      &__hero {
        flex-direction: column;
        padding: 18px;
      }

      &__hero-status {
        flex-direction: row;
        align-items: center;
        margin-left: 66px;
      }

      &__metrics {
        grid-template-columns: 1fr;

        article:not(:last-child) {
          border-right: 0;
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }
    }
  }
</style>
