<template>
  <div class="hr-roster-page business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      class="hr-roster-page__overview"
      eyebrow="PEOPLE DIRECTORY"
      title="员工花名册"
      description="按组织维护员工身份、任职状态与完整人事履历，并衔接系统账号开通。"
      icon="ri:contacts-book-3-line"
      :tags="workspaceTags"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <div class="hr-roster-page__workspace">
      <aside v-if="isDesktopOrganizationLayout" class="hr-roster-page__organization-panel">
        <OrganizationScopeFilter
          scope-type="employee"
          :data="organizationTree"
          :loading="organizationFilterLoading"
          :selected-key="selectedOrganizationKey"
          :include-descendants="includeDescendantOrganizations"
          :tenant-id="selectedTenantId"
          :tenant-options="tenantOptions"
          :show-tenant-select="isPlatformSuper"
          @select="handleOrganizationSelect"
          @refresh="loadOrganizationTree"
          @update:include-descendants="handleIncludeDescendantsChange"
          @update:tenant-id="handleTenantChange"
        />
      </aside>
      <div class="hr-roster-page__table-workspace">
        <section
          v-if="!isDesktopOrganizationLayout"
          class="hr-roster-page__mobile-scope art-card-xs"
        >
          <span aria-hidden="true"><ArtSvgIcon icon="ri:node-tree" /></span
          ><div
            ><small>当前组织范围</small><strong>{{ selectedOrganizationLabel }}</strong></div
          >
          <ElButton type="primary" plain @click="openOrganizationDrawer"
            ><ArtSvgIcon icon="ri:filter-3-line" />组织筛选</ElButton
          >
        </section>
        <ArtTableQuery
          :key="tablePermissionKey"
          ref="tableQueryRef"
          v-model="searchForm"
          :search-items="searchItems"
          :api-fn="fetchTableData"
          :columns-factory="columnsFactory"
          :header-actions="headerActions"
          header-actions-placement="workspace"
          :search-bar-props="{ span: 6, labelWidth: 82 }"
          :table-props="{
            rowKey: 'id',
            tableLayout: 'fixed',
            emptyText: '暂无员工档案',
            emptyDescription: '可切换组织范围或新增员工档案。'
          }"
          :on-success="handleTableSuccess"
          focusable
        />
      </div>
    </div>
    <ArtDrawer ref="organizationDrawerRef">
      <OrganizationScopeFilter
        scope-type="employee"
        class="hr-roster-page__drawer-filter"
        :data="organizationTree"
        :loading="organizationFilterLoading"
        :selected-key="selectedOrganizationKey"
        :include-descendants="includeDescendantOrganizations"
        :tenant-id="selectedTenantId"
        :tenant-options="tenantOptions"
        :show-tenant-select="isPlatformSuper"
        @select="handleOrganizationSelect"
        @refresh="loadOrganizationTree"
        @update:include-descendants="handleIncludeDescendantsChange"
        @update:tenant-id="handleTenantChange"
      />
    </ArtDrawer>
  </div>
</template>

<script setup lang="tsx">
  import { ElAvatar } from 'element-plus'
  import { useMediaQuery } from '@vueuse/core'
  import type { ColumnOption } from '@/types'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric,
    type BusinessWorkspaceTag
  } from '@/components/business/business-workspace-header/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import OrganizationScopeFilter from '@/views/system/shared/organization-scope-filter.vue'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { formatWithDayjs } from '@/utils/time'
  import { canViewField, getFieldAccess } from '@/utils/field-permission'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import TreeUtils from '@/utils/tree'
  import { useUserStore } from '@/store/modules/user'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import { deleteEmployee, fetchEmployeeList, fetchEmployeeOrganizationTree } from '@/api/hr'

  defineOptions({ name: 'HrEmployeeRoster' })
  type Employee = Api.Hr.Employee
  type SearchParams = Api.Hr.EmployeeSearchParams
  type EmployeeFieldKey = Api.Hr.EmployeeFieldKey
  type EmployeeFieldAccessMap = Api.Hr.EmployeeFieldAccessMap
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type Organization = Api.SystemManage.OrganizationScopeFilterItem
  type Tenant = Api.SystemManage.TenantListItem
  interface OverviewRow {
    employmentStatus?: unknown
    account?: { id?: unknown } | null
  }

  const ALL_ORGANIZATIONS_KEY = '__all_organizations__'
  const UNASSIGNED_ORGANIZATION_KEY = '__unassigned_organization__'
  const router = useRouter()
  const route = useRoute()
  const userStore = useUserStore()
  const { getDictMap, getUserInfo, isPlatformSuper } = storeToRefs(userStore)
  const { confirmAction } = useArtFeedback()
  const organizationTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const organizationDrawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const isDesktopOrganizationLayout = useMediaQuery('(min-width: 1201px)')
  const organizationTree = ref<Organization[]>([])
  const tenantOptions = ref<Tenant[]>([])
  const organizationFilterLoading = ref(false)
  const selectedTenantId = ref(getUserInfo.value.tenantId ?? '')
  const selectedOrganizationKey = ref(ALL_ORGANIZATIONS_KEY)
  const includeDescendantOrganizations = ref(true)
  const listFieldAccess = ref<EmployeeFieldAccessMap>({})
  const currentRows = ref<Employee[]>([])
  const overview = reactive<{ total: number; rows: OverviewRow[] }>({ total: 0, rows: [] })
  const searchForm = ref<SearchParams>({
    recordId: typeof route.query.recordId === 'string' ? route.query.recordId : undefined,
    employmentStatus: undefined,
    employmentType: undefined,
    hireDateRange: [],
    keyword: ''
  })
  const activeCount = computed(
    () =>
      overview.rows.filter((row) => ['probation', 'active'].includes(String(row.employmentStatus)))
        .length
  )
  const linkedAccountCount = computed(() => overview.rows.filter((row) => row.account?.id).length)
  const workspaceTags: BusinessWorkspaceTag[] = [
    { label: '人事档案按租户隔离', type: 'success', effect: 'light' },
    { label: '支持账号联动', type: 'primary', effect: 'plain' }
  ]
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '当前结果',
      value: overview.total,
      description: '随筛选条件更新',
      icon: 'ri:group-line'
    },
    {
      label: '本页在岗',
      value: activeCount.value,
      description: '含试用期员工',
      icon: 'ri:user-follow-line',
      tone: 'success'
    },
    ...(['read', 'edit'].includes(getFieldAccess(listFieldAccess.value, 'maintenanceAudit'))
      ? [
          {
            label: '已开通账号',
            value: linkedAccountCount.value,
            description: '当前页账号关联',
            icon: 'ri:shield-user-line',
            tone: 'info' as const
          }
        ]
      : [])
  ])
  const selectedOrganization = computed(() =>
    [ALL_ORGANIZATIONS_KEY, UNASSIGNED_ORGANIZATION_KEY].includes(selectedOrganizationKey.value)
      ? null
      : organizationTreeUtils.findNode(organizationTree.value, selectedOrganizationKey.value)
  )
  const selectedOrganizationLabel = computed(() =>
    selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY
      ? '待归属员工'
      : selectedOrganizationKey.value === ALL_ORGANIZATIONS_KEY
        ? '全部员工'
        : (selectedOrganization.value?.organizationName ?? '全部员工')
  )
  const selectedOrganizationIds = computed(() => {
    const organization = selectedOrganization.value
    if (!organization?.id) return []
    if (!includeDescendantOrganizations.value) return [organization.id]
    return organizationTreeUtils
      .getDescendants(organizationTree.value, organization.id, true)
      .map((item) => item.id)
      .filter((id): id is string => Boolean(id))
  })
  const shouldDisplayField = (field: EmployeeFieldKey): boolean =>
    canViewField(listFieldAccess.value, field) ||
    currentRows.value.some((row) => canViewField(row.fieldAccess, field))

  const tablePermissionKey = computed(() =>
    (['contactDetails', 'maintenanceAudit'] as const)
      .map((field) => `${field}:${shouldDisplayField(field) ? 'visible' : 'hidden'}`)
      .join('|')
  )

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '任职状态',
      key: 'employmentStatus',
      type: 'select',
      props: { clearable: true, options: getDictMap.value.hrEmploymentStatus ?? [] }
    },
    {
      label: '用工类型',
      key: 'employmentType',
      type: 'select',
      props: { clearable: true, options: getDictMap.value.hrEmploymentType ?? [] }
    },
    {
      label: '入职日期',
      key: 'hireDateRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至',
        class: '!w-full'
      }
    },
    {
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: canViewField(listFieldAccess.value, 'contactDetails')
          ? '工号、姓名、手机、邮箱或岗位'
          : '工号、姓名或岗位'
      }
    }
  ])
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', label: '新增员工', permission: 'Hr:Employee:Add', onClick: () => openProfile() }
  ])
  const columnsFactory = (): ColumnOption<Employee>[] => [
    {
      prop: 'employeeIdentity',
      label: '员工身份',
      minWidth: 210,
      fixed: 'left',
      formatter: (row) =>
        h('div', { class: 'hr-roster-cell' }, [
          h(
            ElAvatar,
            { size: 38, src: row.avatarUrl || undefined, alt: `${row.employeeName}的头像` },
            () => row.employeeName.slice(0, 1)
          ),
          h('div', null, [
            h('strong', { title: row.employeeName }, row.employeeName),
            h('small', { title: row.employeeNo }, row.employeeNo)
          ])
        ])
    },
    {
      prop: 'employmentStatus',
      label: '任职状态',
      width: 108,
      dict: { code: 'hrEmploymentStatus', display: 'auto' }
    },
    {
      prop: 'organization',
      label: '所属组织',
      minWidth: 170,
      showOverflowTooltip: true,
      formatter: (row) => row.organization?.organizationName || '待归属'
    },
    {
      prop: 'jobTitle',
      label: '工作岗位',
      minWidth: 140,
      showOverflowTooltip: true,
      formatter: (row) => row.jobTitle || '--'
    },
    {
      prop: 'employmentType',
      label: '用工类型',
      width: 108,
      dict: { code: 'hrEmploymentType', display: 'text' }
    },
    { prop: 'hireDate', label: '入职日期', width: 116, formatter: (row) => row.hireDate || '--' },
    ...(shouldDisplayField('contactDetails')
      ? [
          {
            prop: 'contact',
            label: '联系方式',
            minWidth: 200,
            formatter: (row: Employee) =>
              canViewField(row.fieldAccess, 'contactDetails')
                ? h('div', { class: 'hr-roster-contact' }, [
                    h('span', null, row.phone || '未填写手机'),
                    h('small', { title: row.email || undefined }, row.email || '未填写邮箱')
                  ])
                : '--'
          }
        ]
      : []),
    ...(shouldDisplayField('maintenanceAudit')
      ? [
          {
            prop: 'account',
            label: '系统账号',
            width: 112,
            formatter: (row: Employee) => {
              const access = getFieldAccess(row.fieldAccess, 'maintenanceAudit')
              if (access === 'masked') return '***'
              return ['read', 'edit'].includes(access)
                ? h(
                    'span',
                    { class: ['hr-roster-account', row.account?.id ? 'is-linked' : ''] },
                    row.account?.id ? '已开通' : '未开通'
                  )
                : '--'
            }
          },
          {
            prop: 'updateTime',
            label: '最近维护',
            width: 160,
            formatter: (row: Employee) => {
              const access = getFieldAccess(row.fieldAccess, 'maintenanceAudit')
              if (access === 'masked') return '***'
              return ['read', 'edit'].includes(access)
                ? formatWithDayjs(row.updateTime, 'YYYY-MM-DD HH:mm') || '--'
                : '--'
            }
          }
        ]
      : []),
    {
      prop: 'operation',
      label: '操作',
      width: 196,
      fixed: 'right',
      formatter: (row) =>
        h('div', { class: 'hr-roster-actions' }, [
          h(ArtButtonTable, {
            type: 'view',
            label: '查看',
            permission: 'Hr:Employee:View',
            onClick: () => openEmployeeDetail(row)
          }),
          h(ArtButtonTable, {
            type: 'edit',
            permission: 'Hr:Employee:Edit',
            onClick: () => openProfile(row)
          }),
          h(ArtButtonTable, {
            type: 'delete',
            permission: 'Hr:Employee:Delete',
            onClick: () => handleDelete(row)
          })
        ])
    }
  ]
  const fetchTableData = async (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchEmployeeList({
      ...params,
      tenantId: selectedTenantId.value || getUserInfo.value.tenantId,
      organizationIds: selectedOrganizationIds.value,
      organizationUnassigned: selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY,
      from,
      to
    })
    listFieldAccess.value = result.fieldAccess
    currentRows.value = result.data
    return result
  }
  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows.map((row) => ({
      employmentStatus: row.employmentStatus,
      account:
        row.account && typeof row.account === 'object'
          ? { id: Reflect.get(row.account, 'id') }
          : null
    }))
    overview.total = response.total ?? rows.length
  }
  const loadOrganizationTree = async (): Promise<void> => {
    organizationFilterLoading.value = true
    try {
      const response = await fetchEmployeeOrganizationTree({ tenantId: selectedTenantId.value })
      organizationTree.value = response.data ?? []
    } finally {
      organizationFilterLoading.value = false
    }
  }
  const handleOrganizationSelect = (key: string): void => {
    selectedOrganizationKey.value = key
    organizationDrawerRef.value?.handleClose()
    void tableQueryRef.value?.refreshData()
  }
  const handleIncludeDescendantsChange = (value: boolean): void => {
    includeDescendantOrganizations.value = value
    void tableQueryRef.value?.refreshData()
  }
  const handleTenantChange = async (tenantId: string): Promise<void> => {
    selectedTenantId.value = tenantId
    selectedOrganizationKey.value = ALL_ORGANIZATIONS_KEY
    await loadOrganizationTree()
    void tableQueryRef.value?.refreshData()
  }
  const openOrganizationDrawer = (): void => {
    void organizationDrawerRef.value?.handleOpen(
      {},
      {
        title: '组织范围',
        subtitle: '按组织筛选员工花名册',
        size: 'sm',
        showFooter: false,
        contentHeight: 'calc(100vh - 118px)'
      }
    )
  }
  const openProfile = (row?: Employee): void => {
    void router.push(
      row?.id ? `/hr/personnel/employee-profile/${row.id}` : '/hr/personnel/employee-profile'
    )
  }
  const openEmployeeDetail = (row: Employee): void => {
    if (!row.id) return
    void router.push(`/hr/personnel/employee-detail/${row.id}`)
  }
  const handleDelete = async (row: Employee): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(
        `确定删除“${row.employeeName}（${row.employeeNo}）”吗？相关履历将一并删除。`,
        '删除员工档案',
        {
          confirmButtonText: '确认删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteEmployee(row.id)
      await loadOrganizationTree()
      void tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消时无需额外提示。
    }
  }
  onMounted(async () => {
    await Promise.all(
      ['hrEmploymentStatus', 'hrEmploymentType'].map((code) => userStore.ensureDictLoaded(code))
    )
    if (isPlatformSuper.value) {
      const response = await fetchGetEnableTenantList()
      tenantOptions.value = response.data ?? []
      if (
        !selectedTenantId.value ||
        !tenantOptions.value.some((item) => item.id === selectedTenantId.value)
      )
        selectedTenantId.value = tenantOptions.value[0]?.id ?? ''
    }
    await loadOrganizationTree()
  })
</script>

<style scoped lang="scss">
  .hr-roster-page {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;

    &__workspace {
      display: grid;
      flex: 1;
      grid-template-columns: 264px minmax(0, 1fr);
      gap: 12px;
      min-width: 0;
      min-height: 0;
    }

    &__organization-panel {
      min-height: 0;
    }

    &__table-workspace {
      display: flex;
      flex-direction: column;
      gap: 12px;
      min-width: 0;
      min-height: 0;
    }

    &__mobile-scope {
      display: flex;
      gap: 12px;
      align-items: center;
      padding: 12px 14px;
    }

    &__mobile-scope > span {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 36px;
      height: 36px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 10px;
    }

    &__mobile-scope > div {
      display: grid;
      flex: 1;
      min-width: 0;
    }

    &__mobile-scope small {
      color: var(--el-text-color-secondary);
    }

    &__mobile-scope strong {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__drawer-filter {
      height: 100%;
    }

    :deep(.hr-roster-cell),
    :deep(.hr-roster-contact) {
      display: flex;
      align-items: center;
      min-width: 0;
    }

    :deep(.hr-roster-cell) {
      gap: 10px;
    }

    :deep(.hr-roster-cell > div),
    :deep(.hr-roster-contact) {
      flex-direction: column;
      align-items: flex-start;
      min-width: 0;
    }

    :deep(.hr-roster-cell strong),
    :deep(.hr-roster-cell small),
    :deep(.hr-roster-contact small) {
      max-width: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    :deep(.hr-roster-cell small),
    :deep(.hr-roster-contact small) {
      color: var(--el-text-color-secondary);
    }

    :deep(.hr-roster-account) {
      color: var(--el-text-color-secondary);
    }

    :deep(.hr-roster-account.is-linked) {
      color: var(--el-color-success);
    }

    :deep(.hr-roster-actions) {
      display: flex;
      gap: 2px;
      align-items: center;
    }

    @media (width <= 1200px) {
      &__workspace {
        display: flex;
        flex-direction: column;
      }
    }
  }

  :global(.art-table-focus-page .hr-roster-page__workspace) {
    display: grid !important;
    grid-template-columns: 264px minmax(0, 1fr) !important;
    gap: 12px !important;
  }

  :global(.art-table-focus-page .hr-roster-page__organization-panel.art-table-focus-hidden) {
    display: block !important;
  }

  @media (width <= 1200px) {
    :global(.art-table-focus-page .hr-roster-page__workspace) {
      display: flex !important;
      flex-direction: column !important;
    }
  }
</style>
