<template>
  <div class="role-page business-workspace-page art-full-height">
    <MasterDeleteProcessingNotice
      action-hint="当前角色已自动定位；可先解除用户或菜单授权后返回。"
    />
    <BusinessWorkspaceHeader
      class="role-page__overview"
      eyebrow="ACCESS GOVERNANCE"
      title="角色与权限"
      description="按租户维护职责角色与菜单访问边界，让权限配置清晰、可追踪、可审计。"
      icon="ri:shield-user-line"
      :tags="[
        { label: '权限按租户隔离', type: 'success', effect: 'light' },
        { label: '遵循最小权限原则', type: 'primary', effect: 'plain' }
      ]"
      :metrics="workspaceMetrics"
    />

    <div class="role-page__workspace">
      <aside v-if="isDesktopOrganizationLayout" class="role-page__organization-panel">
        <OrganizationScopeFilter
          scope-type="role"
          :data="organizationTree"
          :loading="organizationFilterLoading"
          :selected-key="selectedOrganizationKey"
          :include-descendants="includeDescendantOrganizations"
          :tenant-id="selectedTenantId"
          :tenant-options="tenantOptions"
          :show-tenant-select="isPlatformSuper"
          @select="handleOrganizationSelect"
          @refresh="handleOrganizationRefresh"
          @update:include-descendants="handleIncludeDescendantsChange"
          @update:tenant-id="handleTenantChange"
        />
      </aside>

      <div class="role-page__table-workspace">
        <section v-if="!isDesktopOrganizationLayout" class="role-page__mobile-scope art-card-xs">
          <span class="role-page__mobile-scope-icon" aria-hidden="true">
            <ArtSvgIcon icon="ri:node-tree" />
          </span>
          <div>
            <small>当前组织范围</small>
            <strong>{{ selectedOrganizationLabel }}</strong>
          </div>
          <ElButton type="primary" plain @click="openOrganizationDrawer">
            <ArtSvgIcon icon="ri:filter-3-line" />
            组织筛选
          </ElButton>
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
      </div>
    </div>

    <RoleEditDialog ref="roleEditDialogRef" @success="refreshData" />
    <RolePermissionDialog ref="rolePermissionDialogRef" @success="refreshData" />
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="refreshData" />
    <ArtDrawer ref="organizationDrawerRef">
      <OrganizationScopeFilter
        scope-type="role"
        class="role-page__drawer-filter"
        :data="organizationTree"
        :loading="organizationFilterLoading"
        :selected-key="selectedOrganizationKey"
        :include-descendants="includeDescendantOrganizations"
        :tenant-id="selectedTenantId"
        :tenant-options="tenantOptions"
        :show-tenant-select="isPlatformSuper"
        @select="handleOrganizationSelect"
        @refresh="handleOrganizationRefresh"
        @update:include-descendants="handleIncludeDescendantsChange"
        @update:tenant-id="handleTenantChange"
      />
    </ArtDrawer>
  </div>
</template>

<script setup lang="ts">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useMediaQuery } from '@vueuse/core'
  import { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import { useTable } from '@/hooks/core/useTable'
  import {
    deleteRole,
    fetchGetEnableTenantList,
    fetchGetRoleList,
    fetchGetRoleOrganizationTree
  } from '@/api/system-manage'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
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
  import { useUserStore } from '@/store/modules/user'
  import TreeUtils from '@/utils/tree'
  import OrganizationScopeFilter from '../shared/organization-scope-filter.vue'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'

  defineOptions({ name: 'Role' })

  const { confirmAction } = useArtFeedback()
  const route = useRoute()

  type RoleListItem = Api.SystemManage.RoleListItem
  type OrganizationFilterItem = Api.SystemManage.OrganizationScopeFilterItem
  type TenantListItem = Api.SystemManage.TenantListItem
  type RoleSearchParams = Api.SystemManage.RoleSearchParams & {
    daterange?: [string, string] | null
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  const searchForm = ref({
    roleName: undefined,
    roleCode: undefined,
    description: undefined,
    enabled: undefined,
    daterange: undefined
  })

  const showSearchBar = ref(false)
  const { getDictMap, getUserInfo, isPlatformSuper } = storeToRefs(useUserStore())
  const ALL_ORGANIZATIONS_KEY = '__all_organizations__'
  const UNASSIGNED_ORGANIZATION_KEY = '__unassigned_organization__'
  const organizationTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })
  const organizationDrawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()
  const isDesktopOrganizationLayout = useMediaQuery('(min-width: 1201px)')
  const organizationTree = ref<OrganizationFilterItem[]>([])
  const tenantOptions = ref<TenantListItem[]>([])
  const organizationFilterLoading = ref(false)
  const selectedTenantId = ref(getUserInfo.value.tenantId ?? '')
  const selectedOrganizationKey = ref(ALL_ORGANIZATIONS_KEY)
  const includeDescendantOrganizations = ref(true)
  const selectedOrganization = computed(() =>
    selectedOrganizationKey.value === ALL_ORGANIZATIONS_KEY ||
    selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY
      ? null
      : organizationTreeUtils.findNode(organizationTree.value, selectedOrganizationKey.value)
  )
  const selectedOrganizationLabel = computed(() => {
    if (selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY) return '待归属角色'
    if (selectedOrganizationKey.value === ALL_ORGANIZATIONS_KEY) return '全部角色'
    return selectedOrganization.value?.organizationName ?? '全部角色'
  })
  const selectedOrganizationIds = computed(() => {
    const organization = selectedOrganization.value
    if (!organization?.id) return []
    if (!includeDescendantOrganizations.value) return [organization.id]

    return organizationTreeUtils
      .getDescendants(organizationTree.value, organization.id, true)
      .map((item) => item.id)
      .filter((id): id is string => Boolean(id))
  })
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
      permission: 'System:Role:Add',
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
  const isDefaultRegisterRole = (row: RoleListItem): boolean =>
    row.builtinType === 'default_register'

  const isSuperRole = (row: RoleListItem): boolean => row.builtinType === 'platform_super'

  const getRoleMoreActions = (row: RoleListItem): ButtonMoreItem[] => {
    if (isSuperRole(row)) {
      return []
    }

    const actions: ButtonMoreItem[] = [
      {
        key: 'edit',
        label: '编辑角色',
        icon: 'ri:edit-2-line',
        auth: 'System:Role:Edit'
      },
      {
        key: 'delete',
        label: '删除角色',
        icon: 'ri:delete-bin-4-line',
        color: 'var(--el-color-danger)',
        auth: 'System:Role:Delete'
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
              !isDefaultRegisterRole(row) || isPlatformSuper.value
                ? h(ArtButtonTable, {
                    type: 'view',
                    icon: 'ri:shield-keyhole-line',
                    label: '配置菜单权限',
                    permission: 'System:Role:AssignPermission',
                    onClick: () => showPermissionDialog(row)
                  })
                : null,
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
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '当前结果',
      value: pagination.total,
      description: '随筛选条件实时更新',
      icon: 'ri:team-line'
    },
    {
      label: '本页启用',
      value: enabledRoleCount.value,
      description: '当前页可正常授权',
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    },
    {
      label: '受保护角色',
      value: protectedRoleCount.value,
      description: '内置角色限制关键操作',
      icon: 'ri:shield-keyhole-line',
      tone: 'warning'
    }
  ])

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
    if (!row.id || row.builtinType) return
    try {
      const blocked = await deleteGuardRef.value?.inspect({
        resourceType: 'role',
        resourceLabel: '角色',
        resources: [{ id: row.id, label: row.roleName }]
      })
      if (blocked) return

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
      tenantId: selectedTenantId.value || getUserInfo.value.tenantId,
      organizationIds: selectedOrganizationIds.value,
      organizationUnassigned: selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY,
      roleName,
      roleCode,
      description,
      enabled,
      startTime,
      endTime,
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : undefined,
      from,
      to
    })
  }

  const loadTenantOptions = async (): Promise<void> => {
    if (!isPlatformSuper.value) return
    const response = await fetchGetEnableTenantList()
    tenantOptions.value = response.data ?? []
    if (
      !selectedTenantId.value ||
      !tenantOptions.value.some((item) => item.id === selectedTenantId.value)
    ) {
      selectedTenantId.value = tenantOptions.value[0]?.id ?? ''
    }
  }

  const loadOrganizationTree = async (): Promise<void> => {
    organizationFilterLoading.value = true
    try {
      const response = await fetchGetRoleOrganizationTree({
        tenantId: selectedTenantId.value || getUserInfo.value.tenantId
      })
      organizationTree.value = response.data ?? []

      if (
        selectedOrganizationKey.value !== ALL_ORGANIZATIONS_KEY &&
        selectedOrganizationKey.value !== UNASSIGNED_ORGANIZATION_KEY &&
        !organizationTreeUtils.findNode(organizationTree.value, selectedOrganizationKey.value)
      ) {
        selectedOrganizationKey.value = ALL_ORGANIZATIONS_KEY
      }
    } finally {
      organizationFilterLoading.value = false
    }
  }

  const handleOrganizationSelect = async (key: string): Promise<void> => {
    if (selectedOrganizationKey.value === key) return
    selectedOrganizationKey.value = key
    await getData()
  }

  const handleIncludeDescendantsChange = async (value: boolean): Promise<void> => {
    includeDescendantOrganizations.value = value
    if (selectedOrganization.value) await getData()
  }

  const handleTenantChange = async (tenantId: string): Promise<void> => {
    if (!tenantId || selectedTenantId.value === tenantId) return
    selectedTenantId.value = tenantId
    selectedOrganizationKey.value = ALL_ORGANIZATIONS_KEY
    await loadOrganizationTree()
    await getData()
  }

  const handleOrganizationRefresh = async (): Promise<void> => {
    await loadOrganizationTree()
    await refreshData()
  }

  const openOrganizationDrawer = async (): Promise<void> => {
    await organizationDrawerRef.value?.handleOpen(
      {},
      {
        title: '筛选组织范围',
        subtitle: '按组织节点快速定位角色；可选择是否包含全部下级组织。',
        size: 'sm',
        contentHeight: 'calc(100vh - 118px)',
        showFooter: false,
        drawerProps: {
          appendToBody: true,
          bodyClass: 'role-organization-filter-drawer__body'
        }
      }
    )
  }

  onMounted(async () => {
    await loadTenantOptions()
    await loadOrganizationTree()
  })

  watch(
    () => route.query.recordId,
    () => {
      void refreshData()
    }
  )
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

    &__workspace {
      display: grid;
      flex: 1 1 auto;
      grid-template-columns: 264px minmax(0, 1fr);
      gap: 12px;
      min-width: 0;
      min-height: 0;
    }

    &__organization-panel,
    &__table-workspace {
      min-width: 0;
      min-height: 0;
    }

    &__organization-panel {
      overflow: hidden;
    }

    &__table-workspace {
      display: flex;
      flex-direction: column;
    }

    &__mobile-scope {
      display: flex;
      flex: none;
      gap: 11px;
      align-items: center;
      min-width: 0;
      padding: 12px 14px;
      margin-bottom: 12px;
      background: linear-gradient(145deg, var(--el-color-primary-light-9), var(--el-bg-color) 76%);

      > div {
        display: grid;
        flex: 1;
        min-width: 0;
      }

      small,
      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 14px;
        color: var(--el-text-color-primary);
      }
    }

    &__mobile-scope-icon {
      display: inline-flex;
      flex: 0 0 36px;
      align-items: center;
      justify-content: center;
      width: 36px;
      height: 36px;
      color: var(--el-color-primary);
      background: var(--el-bg-color);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--custom-radius);
    }

    &__drawer-filter {
      height: 100%;
      border: 0;
      border-radius: 0;
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
      gap: 20px;
      justify-content: space-between;
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
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__brand {
      flex: 0 0 50px;
      justify-content: center;
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
        gap: 12px;
        min-width: 0;
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
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
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
      flex: 0 0 38px;
      justify-content: center;
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
      gap: 10px;
      align-items: center;
      min-width: 0;

      .role-identity-cell__icon {
        display: grid;
        flex: 0 0 36px;
        place-items: center;
        width: 36px;
        height: 36px;
        font-size: 14px;
        font-weight: 700;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border: 1px solid var(--el-color-primary-light-7);
        border-radius: var(--art-control-radius);

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
        gap: 6px;
        align-items: center;

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 600;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }
      }

      .role-identity-cell__code {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--el-text-color-secondary);
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

    @media (width <= 900px) {
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

    @media (width <= 1200px) {
      &__workspace {
        grid-template-columns: minmax(0, 1fr);
      }
    }

    @media (width <= 640px) {
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

      &__mobile-scope {
        .el-button {
          flex: none;
          padding-inline: 10px;
        }
      }
    }
  }

  :global(.role-organization-filter-drawer__body) {
    --art-drawer-content-padding: 0;

    padding: 0 !important;
    overflow: hidden !important;
  }

  :global(.art-table-focus-page .role-page__workspace) {
    display: grid !important;
    grid-template-columns: 264px minmax(0, 1fr) !important;
    gap: 12px !important;
  }

  :global(.art-table-focus-page .role-page__organization-panel.art-table-focus-hidden) {
    display: block !important;
  }
</style>
