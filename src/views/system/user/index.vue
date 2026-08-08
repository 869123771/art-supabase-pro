<template>
  <div class="user-page art-full-height">
    <section class="user-page__overview art-card-xs">
      <header class="user-page__hero">
        <div class="user-page__identity">
          <div class="user-page__brand" aria-hidden="true">
            <ArtSvgIcon icon="ri:user-settings-line" />
          </div>
          <div>
            <span>ACCOUNT GOVERNANCE</span>
            <h1>用户管理</h1>
            <p>统一维护登录身份、联系方式、租户归属与角色授权，及时识别异常或停用账号。</p>
          </div>
        </div>
        <div class="user-page__hero-status">
          <ElTag type="success" effect="light" round>账号按租户隔离</ElTag>
          <ElTag type="primary" effect="plain" round>角色独立授权</ElTag>
        </div>
      </header>

      <div class="user-page__metrics" aria-label="账号治理概览">
        <article>
          <div class="user-page__metric-icon is-primary">
            <ArtSvgIcon icon="ri:group-line" />
          </div>
          <div>
            <span>当前结果</span>
            <strong>{{ overview.total }}</strong>
            <small>随筛选条件实时更新</small>
          </div>
        </article>
        <article>
          <div class="user-page__metric-icon is-success">
            <ArtSvgIcon icon="ri:user-follow-line" />
          </div>
          <div>
            <span>本页启用</span>
            <strong>{{ enabledUserCount }}</strong>
            <small>当前页可正常登录</small>
          </div>
        </article>
        <article>
          <div class="user-page__metric-icon is-info">
            <ArtSvgIcon icon="ri:contacts-book-2-line" />
          </div>
          <div>
            <span>联系信息完整</span>
            <strong>{{ completeContactCount }}</strong>
            <small>本页已填写手机和邮箱</small>
          </div>
        </article>
      </div>
    </section>

    <div class="user-page__workspace">
      <aside v-if="isDesktopOrganizationLayout" class="user-page__organization-panel">
        <OrganizationScopeFilter
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

      <div class="user-page__table-workspace">
        <section v-if="!isDesktopOrganizationLayout" class="user-page__mobile-scope art-card-xs">
          <span class="user-page__mobile-scope-icon" aria-hidden="true">
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
          ref="tableQueryRef"
          v-model="searchForm"
          :search-items="searchItems"
          :api-fn="fetchTableData"
          :columns-factory="columnsFactory"
          :header-actions="headerActions"
          :table-props="tableProps"
          :on-success="handleTableSuccess"
          focusable
        />
      </div>
    </div>

    <UserDialog ref="userDialogRef" @success="handleSaveSuccess" />
    <UserRoleDialog ref="userRoleRef" @success="tableQueryRef?.refreshUpdate()" />
    <ArtDrawer ref="organizationDrawerRef">
      <OrganizationScopeFilter
        class="user-page__drawer-filter"
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
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import UserDialog from './modules/user-dialog.vue'
  import OrganizationScopeFilter from '../shared/organization-scope-filter.vue'
  import { ElAvatar } from 'element-plus'
  import type { ColumnOption } from '@/types'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryProps,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import { formatWithDayjs } from '@/utils/time'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteUser,
    fetchGetEnableTenantList,
    fetchGetUserList,
    fetchGetUserOrganizationTree,
    resetUser
  } from '@/api/system-manage'
  import ArtButtonMore, { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import UserRoleDialog from '@views/system/user/modules/user-role-dialog.vue'
  import { useSystemParam } from '@/hooks'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import TreeUtils from '@/utils/tree'

  defineOptions({ name: 'User' })

  const { confirmAction } = useArtFeedback()

  type UserListItem = Api.SystemManage.UserListItem
  type OrganizationFilterItem = Api.SystemManage.OrganizationScopeFilterItem
  type TenantListItem = Api.SystemManage.TenantListItem

  const ALL_ORGANIZATIONS_KEY = '__all_organizations__'
  const UNASSIGNED_ORGANIZATION_KEY = '__unassigned_organization__'

  const userStore = useUserStore()
  const { getDictMap, getUserInfo, isPlatformSuper } = storeToRefs(userStore)
  const { loadPasswordPolicy, createTemporaryPassword } = useSystemParam()
  const organizationTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  interface UserDialogExpose {
    handleOpen: (row?: Partial<UserListItem>) => Promise<void>
  }

  interface UserRoleDialogExpose {
    handleOpen: (data: UserListItem) => Promise<void>
  }

  interface UserOverviewRow {
    status?: unknown
    userPhone?: unknown
    userEmail?: unknown
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const userDialogRef = ref<UserDialogExpose>()
  const userRoleRef = ref<UserRoleDialogExpose>()
  const organizationDrawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const isDesktopOrganizationLayout = useMediaQuery('(min-width: 1201px)')
  const organizationTree = ref<OrganizationFilterItem[]>([])
  const tenantOptions = ref<TenantListItem[]>([])
  const organizationFilterLoading = ref(false)
  const selectedTenantId = ref(getUserInfo.value.tenantId ?? '')
  const selectedOrganizationKey = ref(ALL_ORGANIZATIONS_KEY)
  const includeDescendantOrganizations = ref(true)
  const overview = reactive<{ total: number; rows: UserOverviewRow[] }>({
    total: 0,
    rows: []
  })
  const enabledUserCount = computed(
    () => overview.rows.filter((row) => String(row.status) === '1').length
  )
  const completeContactCount = computed(
    () =>
      overview.rows.filter(
        (row) => String(row.userPhone ?? '').trim() && String(row.userEmail ?? '').trim()
      ).length
  )
  const selectedOrganization = computed(() =>
    selectedOrganizationKey.value === ALL_ORGANIZATIONS_KEY ||
    selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY
      ? null
      : organizationTreeUtils.findNode(organizationTree.value, selectedOrganizationKey.value)
  )
  const selectedOrganizationLabel = computed(() => {
    if (selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY) return '待归属用户'
    if (selectedOrganizationKey.value === ALL_ORGANIZATIONS_KEY) return '全部用户'
    return selectedOrganization.value?.organizationName ?? '全部用户'
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

  type SearchParams = Api.SystemManage.UserSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  const searchForm = ref<SearchParams>({
    userName: undefined,
    userGender: undefined,
    userPhone: undefined,
    userEmail: undefined,
    status: ''
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '用户名',
      key: 'userName',
      type: 'input',
      placeholder: '请输入用户名',
      clearable: true
    },
    {
      label: '手机号',
      key: 'userPhone',
      type: 'input',
      props: { placeholder: '请输入手机号', maxlength: '11' }
    },
    {
      label: '邮箱',
      key: 'userEmail',
      type: 'input',
      props: { placeholder: '支持输入完整或部分邮箱', clearable: true }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        placeholder: '请选择状态',
        options: getDictMap.value.status ?? []
      }
    },
    {
      label: '性别',
      key: 'userGender',
      type: 'radioGroup',
      props: {
        options: getDictMap.value.sex ?? []
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '新增用户',
      permission: 'System:User:Add',
      onClick: () => openDialog()
    }
  ])

  const tableProps: ArtTableQueryTableProps = {
    rowKey: 'id',
    tableLayout: 'fixed',
    emptyText: '暂无符合条件的用户',
    emptyDescription: '可调整筛选条件，或新增用户后再查看。'
  }

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchGetUserList({
      ...params,
      tenantId: selectedTenantId.value || getUserInfo.value.tenantId,
      organizationIds: selectedOrganizationIds.value,
      organizationUnassigned: selectedOrganizationKey.value === UNASSIGNED_ORGANIZATION_KEY,
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
      const response = await fetchGetUserOrganizationTree({
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

  const refreshUsersFromOrganization = async (): Promise<void> => {
    await tableQueryRef.value?.getData()
  }

  const handleOrganizationSelect = async (key: string): Promise<void> => {
    if (selectedOrganizationKey.value === key) return
    selectedOrganizationKey.value = key
    await refreshUsersFromOrganization()
  }

  const handleIncludeDescendantsChange = async (value: boolean): Promise<void> => {
    includeDescendantOrganizations.value = value
    if (selectedOrganization.value) await refreshUsersFromOrganization()
  }

  const handleTenantChange = async (tenantId: string): Promise<void> => {
    if (!tenantId || selectedTenantId.value === tenantId) return
    selectedTenantId.value = tenantId
    selectedOrganizationKey.value = ALL_ORGANIZATIONS_KEY
    await loadOrganizationTree()
    await refreshUsersFromOrganization()
  }

  const handleOrganizationRefresh = async (): Promise<void> => {
    await loadOrganizationTree()
    await refreshUsersFromOrganization()
  }

  const openOrganizationDrawer = async (): Promise<void> => {
    await organizationDrawerRef.value?.handleOpen(
      {},
      {
        title: '筛选组织范围',
        subtitle: '按组织节点快速定位用户；可选择是否包含全部下级组织。',
        size: 'sm',
        contentHeight: 'calc(100vh - 118px)',
        showFooter: false,
        drawerProps: {
          appendToBody: true,
          bodyClass: 'user-organization-filter-drawer__body'
        }
      }
    )
  }

  const columnsFactory = (): ColumnOption<UserListItem>[] => [
    { type: 'index', width: 60, label: '序号' },
    {
      prop: 'userInfo',
      label: '用户身份',
      minWidth: 240,
      formatter: (row: UserListItem) => {
        return h('div', { class: 'user-info-cell' }, [
          h(
            ElAvatar,
            {
              class: 'user-info-cell__avatar',
              size: 38,
              src: row.avatar || undefined,
              alt: `${row.nickName || row.userName}的头像`
            },
            () => getAvatarFallback(row)
          ),
          h('div', { class: 'user-info-cell__content' }, [
            h('div', { class: 'user-info-cell__heading' }, [
              h('p', { class: 'user-info-cell__name' }, row.nickName || row.userName),
              getUserInfo.value.email === row.userEmail
                ? h('span', { class: 'user-info-cell__self' }, '当前账号')
                : null
            ]),
            h('p', { class: 'user-info-cell__username', title: row.userName }, `@${row.userName}`)
          ])
        ])
      }
    },
    {
      prop: 'userType',
      label: '用户类型',
      minWidth: 110,
      dict: { code: 'userType', display: 'auto' }
    },
    {
      prop: 'organization',
      label: '所属组织',
      minWidth: 180,
      formatter: (row: UserListItem) =>
        row.organization
          ? h('div', { class: 'user-organization-cell' }, [
              h(
                'p',
                { title: row.organization.organizationName },
                row.organization.organizationName
              ),
              h(
                'small',
                { title: row.organization.organizationCode },
                row.organization.organizationCode
              )
            ])
          : h('span', { class: 'user-organization-cell__empty' }, '待归入组织')
    },
    {
      prop: 'userRoles',
      label: '角色授权',
      minWidth: 170,
      formatter: (row: UserListItem) => {
        const roles = row.userRoles ?? []
        return roles.length
          ? h('div', { class: 'user-role-cell', title: roles.join('、') }, [
              h('p', null, `${roles.length} 个角色`),
              h('small', null, roles.slice(0, 2).join('、'))
            ])
          : h('span', { class: 'user-role-cell__empty' }, '尚未分配')
      }
    },
    {
      prop: 'userGender',
      label: '性别',
      width: 80,
      sortable: true,
      dict: { code: 'sex', display: 'text' }
    },
    {
      prop: 'contact',
      label: '联系方式',
      minWidth: 220,
      formatter: (row: UserListItem) =>
        h('div', { class: 'user-contact-cell' }, [
          h('p', { class: 'user-contact-cell__phone' }, row.userPhone || '未填写手机号'),
          h(
            'p',
            {
              class: ['user-contact-cell__email', { 'is-empty': !row.userEmail }],
              title: row.userEmail || undefined
            },
            row.userEmail || '未填写邮箱'
          )
        ])
    },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      dict: { code: 'status', display: 'auto' }
    },
    {
      prop: 'createTime',
      label: '创建信息',
      sortable: true,
      minWidth: 190,
      formatter: (row: UserListItem) =>
        h('div', { class: 'user-created-cell' }, [
          h('p', null, formatWithDayjs(row.createTime) || '--'),
          h('small', null, row.createBy || '系统创建')
        ])
    },
    {
      prop: 'operation',
      label: '操作',
      width: 186,
      fixed: 'right',
      formatter: (row: UserListItem) =>
        h('div', { class: 'user-operation-cell' }, [
          h(ArtButtonTable, {
            type: 'edit',
            permission: 'System:User:Edit',
            onClick: () => openDialog(row)
          }),
          !isCurrentUser(row) && !isProtectedUser(row)
            ? h(ArtButtonTable, {
                type: 'view',
                icon: 'ri:user-add-line',
                label: '分配角色',
                permission: 'System:User:AssignRole',
                onClick: () => userRoleRef.value?.handleOpen(row)
              })
            : null,
          h(ArtButtonMore, {
            list: () => getMoreActions(row),
            onClick: (item: ButtonMoreItem) => handleButtonMoreClick(item, row)
          })
        ])
    }
  ]

  const getMoreActions = (row: UserListItem): ButtonMoreItem[] => {
    const selfExcludeButtonKeys = ['delete']
    const buttonList: ButtonMoreItem[] = [
      {
        key: 'reset',
        label: '初始化密码',
        icon: 'ri-user-received-line',
        auth: 'System:User:ResetPassword'
      },
      {
        key: 'delete',
        label: '删除用户',
        icon: 'ri:delete-bin-4-line',
        color: 'var(--el-color-danger)',
        auth: 'System:User:Delete'
      }
    ]

    if (!isCurrentUser(row) && !isProtectedUser(row)) return buttonList
    return buttonList.filter((item) => !selfExcludeButtonKeys.includes(item.key as string))
  }

  const openDialog = (row?: UserListItem): void => {
    void userDialogRef.value?.handleOpen(row)
  }

  const getAvatarFallback = (row: UserListItem): string => {
    const displayName = (row.nickName || row.userName || '').trim()
    return displayName.slice(0, 1).toUpperCase() || 'U'
  }

  const isCurrentUser = (row: Pick<UserListItem, 'authUserId' | 'userEmail'>): boolean => {
    if (getUserInfo.value.userId && row.authUserId) {
      return getUserInfo.value.userId === row.authUserId
    }
    return Boolean(getUserInfo.value.email && getUserInfo.value.email === row.userEmail)
  }

  const isProtectedUser = (row: Pick<UserListItem, 'userEmail' | 'userRoles'>): boolean => {
    return (
      String(row.userEmail ?? '').toLowerCase() === '869123771@qq.com' ||
      Boolean(row.userRoles?.includes('R_SUPER'))
    )
  }

  const handleSaveSuccess = (type: 'add' | 'edit'): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows.map((row) => ({
      status: row.status,
      userPhone: row.userPhone,
      userEmail: row.userEmail
    }))
    overview.total = response.total ?? rows.length
  }

  const handleButtonMoreClick = (item: ButtonMoreItem, row: UserListItem) => {
    switch (item.key) {
      case 'reset':
        void handleResetPassword(row)
        break
      case 'delete':
        void handleDeleteUser(row)
        break
    }
  }

  const handleResetPassword = async (row: UserListItem): Promise<void> => {
    try {
      await loadPasswordPolicy()
      const password = createTemporaryPassword()
      await confirmAction(
        `即将为「${row.nickName || row.userName}」生成临时密码：${password}。请在安全渠道告知用户。`,
        '初始化登录密码',
        {
          confirmButtonText: '确认重置',
          cancelButtonText: '取消',
          type: 'warning'
        }
      )
      const params: Pick<UserListItem, 'userEmail' | 'password'> = {
        userEmail: row.userEmail,
        password
      }
      await resetUser(params as UserListItem)
    } catch {
      // 用户取消时无需额外提示。
    }
  }

  const handleDeleteUser = async (row: UserListItem): Promise<void> => {
    try {
      await confirmAction(
        `注销后「${row.nickName || row.userName}」将无法继续登录，历史业务记录不会被删除。`,
        '注销用户',
        {
          confirmButtonText: '确认注销',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteUser(row)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消时无需额外提示。
    }
  }

  onMounted(async () => {
    await loadTenantOptions()
    await loadOrganizationTree()
  })
</script>

<style scoped lang="scss">
  .user-page {
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

      &.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }
    }

    :deep(.user-info-cell) {
      display: flex;
      align-items: center;
      min-width: 0;
    }

    :deep(.user-info-cell__avatar) {
      flex: 0 0 38px;
      font-size: 14px;
      font-weight: 700;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
    }

    :deep(.user-info-cell__content) {
      min-width: 0;
      margin-left: 10px;
      line-height: 20px;
    }

    :deep(.user-info-cell__heading) {
      display: flex;
      gap: 6px;
      align-items: center;
      min-width: 0;
    }

    :deep(.user-info-cell__name),
    :deep(.user-info-cell__username),
    :deep(.user-contact-cell p) {
      max-width: 100%;
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    :deep(.user-info-cell__name) {
      min-width: 0;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    :deep(.user-info-cell__username),
    :deep(.user-contact-cell__email) {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    :deep(.user-info-cell__self) {
      flex: none;
      padding: 1px 6px;
      font-size: 11px;
      line-height: 18px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 999px;
    }

    :deep(.user-contact-cell) {
      min-width: 0;
      line-height: 20px;
    }

    :deep(.user-contact-cell__phone) {
      color: var(--el-text-color-primary);
    }

    :deep(.user-contact-cell .is-empty) {
      color: var(--el-text-color-placeholder);
    }

    :deep(.user-role-cell),
    :deep(.user-organization-cell),
    :deep(.user-created-cell) {
      display: grid;
      min-width: 0;
      line-height: 20px;

      p,
      small {
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      p {
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.user-role-cell__empty) {
      font-size: 12px;
      color: var(--el-color-warning-dark-2);
    }

    :deep(.user-organization-cell__empty) {
      font-size: 12px;
      color: var(--el-text-color-placeholder);
    }

    :deep(.user-operation-cell) {
      display: flex;
      gap: 8px;
      align-items: center;
    }

    :deep(.user-operation-cell .art-button-table) {
      margin-right: 0;
    }

    @media (width <= 1200px) {
      &__workspace {
        grid-template-columns: minmax(0, 1fr);
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

  :global(.user-organization-filter-drawer__body) {
    padding: 0 !important;
    overflow: hidden !important;
  }

  :global(.art-table-focus-page .user-page__workspace) {
    display: grid !important;
    grid-template-columns: 264px minmax(0, 1fr) !important;
    gap: 12px !important;
  }

  :global(.art-table-focus-page .user-page__organization-panel.art-table-focus-hidden) {
    display: block !important;
  }
</style>
