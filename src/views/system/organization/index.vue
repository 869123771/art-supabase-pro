<template>
  <div class="organization-page art-full-height">
    <section class="organization-page__overview art-card-xs">
      <header class="organization-page__hero">
        <div class="organization-page__identity">
          <div class="organization-page__brand" aria-hidden="true">
            <ArtSvgIcon icon="ri:organization-chart" />
          </div>
          <div>
            <span>ORGANIZATION GOVERNANCE</span>
            <h1>组织管理</h1>
            <p>用统一组织树串联成员归属、职责角色与菜单权限，清晰呈现每个组织的访问边界。</p>
          </div>
        </div>
        <div class="organization-page__hero-status">
          <ElTag :type="canManageOrganization ? 'success' : 'info'" effect="light" round>
            {{ canManageOrganization ? '组织管理员模式' : '租户内只读模式' }}
          </ElTag>
          <ElTag type="primary" effect="plain" round>用户 · 角色 · 菜单联动</ElTag>
        </div>
      </header>

      <div class="organization-page__metrics" aria-label="组织治理概览">
        <article>
          <span class="organization-page__metric-icon is-primary">
            <ArtSvgIcon icon="ri:node-tree" />
          </span>
          <div>
            <span>组织节点</span>
            <strong>{{ overview.organizations }}</strong>
            <small>当前筛选范围</small>
          </div>
        </article>
        <article>
          <span class="organization-page__metric-icon is-success">
            <ArtSvgIcon icon="ri:group-line" />
          </span>
          <div>
            <span>归属成员</span>
            <strong>{{ overview.members }}</strong>
            <small>已纳入组织管理</small>
          </div>
        </article>
        <article>
          <span class="organization-page__metric-icon is-warning">
            <ArtSvgIcon icon="ri:shield-user-line" />
          </span>
          <div>
            <span>组织角色</span>
            <strong>{{ overview.roles }}</strong>
            <small>承载职责授权</small>
          </div>
        </article>
        <article>
          <span class="organization-page__metric-icon is-info">
            <ArtSvgIcon icon="ri:menu-line" />
          </span>
          <div>
            <span>菜单覆盖</span>
            <strong>{{ overview.menus }}</strong>
            <small>去重后的访问项</small>
          </div>
        </article>
      </div>
    </section>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchForm"
      :api-fn="fetchTableData"
      :api-params="tableApiParams"
      :search-items="searchItems"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :table-props="tableProps"
      :on-success="handleTableSuccess"
      focusable
    />

    <OrganizationDialog ref="organizationDialogRef" @success="handleSaveSuccess" />
    <OrganizationDetailDrawer ref="organizationDetailDrawerRef" />
  </div>
</template>

<script setup lang="ts">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ColumnOption } from '@/types'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryProps,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import { deleteOrganization, fetchGetOrganizationTree } from '@/api/system-manage'
  import { formatWithDayjs } from '@/utils/time'
  import TreeUtils from '@/utils/tree'
  import OrganizationDialog from './modules/organization-dialog.vue'
  import OrganizationDetailDrawer from './modules/organization-detail-drawer.vue'

  defineOptions({ name: 'Organization' })

  type Organization = Api.SystemManage.OrganizationListItem
  type OrganizationSearchParams = Api.SystemManage.OrganizationSearchParams

  interface OrganizationDialogExpose {
    handleOpen: (data: {
      type: 'add' | 'edit'
      row?: Organization
      parent?: Organization
    }) => Promise<void>
  }

  interface OrganizationDetailDrawerExpose {
    handleOpen: (row: Organization) => Promise<void>
  }

  interface OverviewState {
    organizations: number
    members: number
    roles: number
    menus: number
  }

  const { confirmAction } = useArtFeedback()
  const userStore = useUserStore()
  const { getDictMap, getUserInfo, isPlatformSuper } = storeToRefs(userStore)
  const treeUtils = new TreeUtils({ idKey: 'id', parentKey: 'parentId', childrenKey: 'children' })
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const organizationDialogRef = ref<OrganizationDialogExpose>()
  const organizationDetailDrawerRef = ref<OrganizationDetailDrawerExpose>()
  const overview = reactive<OverviewState>({
    organizations: 0,
    members: 0,
    roles: 0,
    menus: 0
  })

  const canManageOrganization = computed(
    () =>
      Boolean(isPlatformSuper.value) || Boolean(getUserInfo.value.userRoles?.includes('R_ADMIN'))
  )

  const searchForm = ref<OrganizationSearchParams>({
    keyword: '',
    organizationType: undefined,
    status: undefined
  })

  const tableApiParams = { current: 1, size: 1000 }

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '组织关键字',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '搜索组织名称、编码或职责说明'
      }
    },
    {
      label: '组织类型',
      key: 'organizationType',
      type: 'select',
      props: {
        clearable: true,
        placeholder: '全部类型',
        options: getDictMap.value.organizationType ?? []
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        clearable: true,
        placeholder: '全部状态',
        options: getDictMap.value.status ?? []
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    canManageOrganization.value
      ? [
          {
            type: 'add',
            label: '新增组织',
            permission: 'System:Organization:Add',
            onClick: () => openOrganizationDialog('add')
          }
        ]
      : []
  )

  const tableProps: ArtTableQueryTableProps = {
    rowKey: 'id',
    tableLayout: 'fixed',
    treeProps: { children: 'children', hasChildren: 'hasChildren' },
    defaultExpandAll: true,
    emptyText: '暂无符合条件的组织',
    emptyDescription: '可调整筛选条件；组织管理员也可以新增组织节点。',
    paginationOptions: {
      hideOnSinglePage: true
    }
  }

  const getOrganizationIcon = (type: Api.SystemManage.OrganizationType): string => {
    const iconMap: Record<Api.SystemManage.OrganizationType, string> = {
      company: 'ri:building-4-line',
      division: 'ri:git-branch-line',
      department: 'ri:team-line',
      team: 'ri:group-2-line'
    }
    return iconMap[type]
  }

  const getMenuCoverage = (row: Organization): number => {
    const menuIds = new Set(
      (row.roles ?? []).flatMap((role) =>
        (role.roleMenus ?? []).map((roleMenu) => roleMenu.menuId).filter(Boolean)
      )
    )
    return menuIds.size
  }

  const columnsFactory = (): ColumnOption<Organization>[] => [
    {
      prop: 'organizationIdentity',
      label: '组织信息',
      minWidth: 250,
      formatter: (row) =>
        h('div', { class: 'organization-identity-cell' }, [
          h(
            'span',
            {
              class: ['organization-identity-cell__icon', `is-${row.organizationType}`],
              'aria-hidden': 'true'
            },
            [h(ArtSvgIcon, { icon: getOrganizationIcon(row.organizationType) })]
          ),
          h('div', { class: 'organization-identity-cell__copy' }, [
            h('div', { class: 'organization-identity-cell__heading' }, [
              h('strong', { title: row.organizationName }, row.organizationName),
              row.isSystem
                ? h('span', { class: 'organization-identity-cell__system' }, '根组织')
                : null
            ]),
            h('small', { title: row.organizationCode, translate: 'no' }, row.organizationCode)
          ])
        ])
    },
    {
      prop: 'organizationType',
      label: '组织类型',
      width: 104,
      dict: { code: 'organizationType', display: 'auto' }
    },
    {
      prop: 'tenant',
      label: '所属租户',
      minWidth: 168,
      formatter: (row) =>
        h('div', { class: 'organization-tenant-cell' }, [
          h('span', { title: row.tenant?.tenantName }, row.tenant?.tenantName || '当前租户'),
          row.tenant?.tenantCode
            ? h('small', { title: row.tenant.tenantCode }, row.tenant.tenantCode)
            : null
        ])
    },
    {
      prop: 'leader',
      label: '负责人',
      minWidth: 160,
      formatter: (row) =>
        row.leader
          ? h('div', { class: 'organization-leader-cell' }, [
              h('strong', null, row.leader.nickName || row.leader.userName),
              h('small', { title: row.leader.userEmail }, row.leader.userEmail)
            ])
          : h('span', { class: 'organization-empty-cell' }, '待指定')
    },
    {
      prop: 'accessChain',
      label: '用户 / 角色 / 菜单',
      minWidth: 190,
      formatter: (row) =>
        h('div', { class: 'organization-access-cell' }, [
          h('span', null, [h('strong', null, String(row.members?.length ?? 0)), ' 名成员']),
          h('span', null, [h('strong', null, String(row.roles?.length ?? 0)), ' 个角色']),
          h('span', null, [h('strong', null, String(getMenuCoverage(row))), ' 项菜单'])
        ])
    },
    {
      prop: 'status',
      label: '状态',
      width: 88,
      dict: { code: 'status', display: 'auto' }
    },
    {
      prop: 'updateTime',
      label: '最后更新',
      width: 166,
      formatter: (row) => formatWithDayjs(row.updateTime) || '--'
    },
    {
      prop: 'operation',
      label: '操作',
      width: canManageOrganization.value ? 186 : 88,
      fixed: 'right',
      formatter: (row) =>
        h('div', { class: 'organization-operation-cell' }, [
          h(ArtButtonTable, {
            type: 'view',
            label: '治理详情',
            onClick: () => organizationDetailDrawerRef.value?.handleOpen(row)
          }),
          canManageOrganization.value
            ? h(ArtButtonMore, {
                list: getOrganizationActions(row),
                onClick: (item: ButtonMoreItem) => handleOrganizationAction(item, row)
              })
            : null
        ])
    }
  ]

  const fetchTableData = (params: OrganizationSearchParams) => fetchGetOrganizationTree(params)

  const getOrganizationActions = (row: Organization): ButtonMoreItem[] => {
    const hasDependencies = Boolean(
      row.children?.length || row.members?.length || row.roles?.length
    )
    return [
      {
        key: 'addChild',
        label: '新增下级组织',
        icon: 'ri:node-tree',
        auth: 'System:Organization:Add'
      },
      {
        key: 'edit',
        label: '编辑组织',
        icon: 'ri:edit-2-line',
        auth: 'System:Organization:Edit'
      },
      {
        key: 'delete',
        label: hasDependencies ? '存在关联，不能删除' : '删除组织',
        icon: hasDependencies ? 'ri:lock-line' : 'ri:delete-bin-4-line',
        color: hasDependencies ? 'var(--el-text-color-disabled)' : 'var(--el-color-danger)',
        auth: 'System:Organization:Delete',
        disabled: row.isSystem || hasDependencies
      }
    ]
  }

  const handleOrganizationAction = (item: ButtonMoreItem, row: Organization): void => {
    if (item.disabled) return
    if (item.key === 'addChild') {
      openOrganizationDialog('add', undefined, row)
    } else if (item.key === 'edit') {
      openOrganizationDialog('edit', row)
    } else if (item.key === 'delete') {
      void handleDelete(row)
    }
  }

  const openOrganizationDialog = (
    type: 'add' | 'edit',
    row?: Organization,
    parent?: Organization
  ): void => {
    void organizationDialogRef.value?.handleOpen({ type, row, parent })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows) => {
    const organizations = treeUtils.treeToList(rows as Organization[])
    const menuIds = new Set<string>()
    let members = 0
    let roles = 0

    organizations.forEach((organization) => {
      members += organization.members?.length ?? 0
      roles += organization.roles?.length ?? 0
      organization.roles?.forEach((role) => {
        role.roleMenus?.forEach((roleMenu) => {
          if (roleMenu.menuId) menuIds.add(roleMenu.menuId)
        })
      })
    })

    Object.assign(overview, {
      organizations: organizations.length,
      members,
      roles,
      menus: menuIds.size
    })
  }

  const handleSaveSuccess = (type: 'add' | 'edit'): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Organization): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(
        `删除「${row.organizationName}」后无法恢复。仅无下级组织、无成员且无角色的节点可以删除。`,
        '删除组织',
        {
          confirmButtonText: '确认删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteOrganization(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消或数据库阻止删除时，反馈由统一请求层处理。
    }
  }
</script>

<style scoped lang="scss">
  .organization-page {
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
      grid-template-columns: repeat(4, minmax(0, 1fr));
      border-top: 1px solid var(--el-border-color-lighter);

      article {
        gap: 12px;
        min-width: 0;
        padding: 14px 20px;

        &:not(:last-child) {
          border-right: 1px solid var(--el-border-color-lighter);
        }

        > div {
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

      &.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }
    }

    :deep(.organization-identity-cell) {
      display: flex;
      gap: 10px;
      align-items: center;
      min-width: 0;
    }

    :deep(.organization-identity-cell__icon) {
      display: grid;
      flex: 0 0 36px;
      place-items: center;
      width: 36px;
      height: 36px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--el-border-radius-base);

      &.is-division {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-color: var(--el-color-warning-light-7);
      }

      &.is-department,
      &.is-team {
        color: var(--el-color-success-dark-2);
        background: var(--el-color-success-light-9);
        border-color: var(--el-color-success-light-7);
      }
    }

    :deep(.organization-identity-cell__copy),
    :deep(.organization-identity-cell__heading) {
      min-width: 0;
    }

    :deep(.organization-identity-cell__heading) {
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

    :deep(.organization-identity-cell__copy small),
    :deep(.organization-tenant-cell small),
    :deep(.organization-leader-cell small) {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      white-space: nowrap;
    }

    :deep(.organization-identity-cell__system) {
      flex: none;
      padding: 1px 6px;
      font-size: 10px;
      line-height: 17px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 999px;
    }

    :deep(.organization-tenant-cell),
    :deep(.organization-leader-cell) {
      display: grid;
      min-width: 0;
      line-height: 20px;

      span,
      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    :deep(.organization-access-cell) {
      display: flex;
      flex-wrap: wrap;
      gap: 5px;

      span {
        padding: 2px 7px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color-light);
        border-radius: 999px;
      }

      strong {
        color: var(--el-text-color-primary);
      }
    }

    :deep(.organization-empty-cell) {
      font-size: 12px;
      color: var(--el-text-color-placeholder);
    }

    :deep(.organization-operation-cell) {
      display: flex;
      gap: 8px;
      align-items: center;

      .art-button-table {
        margin-right: 0;
      }
    }

    @media (width <= 1100px) {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));

        article:nth-child(2) {
          border-right: 0;
        }

        article:nth-child(-n + 2) {
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }
    }

    @media (width <= 720px) {
      &__hero {
        flex-direction: column;
        align-items: flex-start;
        padding: 18px;
      }

      &__hero-status {
        flex-wrap: wrap;
        margin-left: 66px;
      }
    }

    @media (width <= 560px) {
      &__metrics {
        grid-template-columns: 1fr;

        article {
          border-right: 0 !important;

          &:not(:last-child) {
            border-bottom: 1px solid var(--el-border-color-lighter);
          }
        }
      }
    }
  }
</style>
