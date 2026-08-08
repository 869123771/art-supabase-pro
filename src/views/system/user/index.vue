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

    <UserDialog ref="userDialogRef" @success="handleSaveSuccess" />
    <UserRoleDialog ref="userRoleRef" @success="tableQueryRef?.refreshUpdate()" />
  </div>
</template>

<script setup lang="ts">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import UserDialog from './modules/user-dialog.vue'
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
  import { deleteUser, fetchGetUserList, resetUser } from '@/api/system-manage'
  import ArtButtonMore, { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import UserRoleDialog from '@views/system/user/modules/user-role-dialog.vue'
  import { useSystemParam } from '@/hooks'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'User' })

  const { confirmAction } = useArtFeedback()

  type UserListItem = Api.SystemManage.UserListItem

  const userStore = useUserStore()
  const { getDictMap, getUserInfo } = storeToRefs(userStore)
  const { loadPasswordPolicy, createTemporaryPassword } = useSystemParam()

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
      from,
      to
    })
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
            onClick: () => openDialog(row)
          }),
          !isCurrentUser(row)
            ? h(ArtButtonTable, {
                type: 'view',
                icon: 'ri:user-add-line',
                label: '分配角色',
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
        icon: 'ri-user-received-line'
      },
      {
        key: 'delete',
        label: '删除用户',
        icon: 'ri:delete-bin-4-line',
        color: 'var(--el-color-danger)'
      }
    ]

    if (!isCurrentUser(row)) return buttonList
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

      &.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }
    }

    :deep(.user-info-cell) {
      display: flex;
      min-width: 0;
      align-items: center;
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
      min-width: 0;
      align-items: center;
      gap: 6px;
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
      align-items: center;
      gap: 8px;
    }

    :deep(.user-operation-cell .art-button-table) {
      margin-right: 0;
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
