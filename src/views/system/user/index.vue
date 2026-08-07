<template>
  <div class="user-page art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchForm"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :table-props="tableProps"
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
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import { formatWithDayjs } from '@/utils/time'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import { deleteUser, fetchGetUserList, resetUser } from '@/api/system-manage'
  import ArtButtonMore, { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import UserRoleDialog from '@views/system/user/modules/user-role-dialog.vue'
  import { useSystemParam } from '@/hooks'

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

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const userDialogRef = ref<UserDialogExpose>()
  const userRoleRef = ref<UserRoleDialogExpose>()

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
    { type: 'selection' },
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
      label: '创建日期',
      sortable: true,
      width: 180,
      formatter: (row: UserListItem) => formatWithDayjs(row.createTime)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row: UserListItem) =>
        h('div', { class: 'flex items-center' }, [
          h(ArtButtonTable, {
            type: 'edit',
            onClick: () => openDialog(row)
          }),
          h(ArtButtonMore, {
            list: () => getMoreActions(row),
            onClick: (item: ButtonMoreItem) => handleButtonMoreClick(item, row)
          })
        ])
    }
  ]

  const getMoreActions = (row: UserListItem): ButtonMoreItem[] => {
    const selfExcludeButtonKeys = ['assignRoles', 'delete']
    const buttonList: ButtonMoreItem[] = [
      {
        key: 'assignRoles',
        label: '赋予角色',
        icon: 'ri-user-add-line'
      },
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

    if (getUserInfo.value.email !== row.userEmail) return buttonList
    return buttonList.filter((item) => !selfExcludeButtonKeys.includes(item.key as string))
  }

  const openDialog = (row?: UserListItem): void => {
    void userDialogRef.value?.handleOpen(row)
  }

  const getAvatarFallback = (row: UserListItem): string => {
    const displayName = (row.nickName || row.userName || '').trim()
    return displayName.slice(0, 1).toUpperCase() || 'U'
  }

  const handleSaveSuccess = (type: 'add' | 'edit'): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleButtonMoreClick = (item: ButtonMoreItem, row: UserListItem) => {
    switch (item.key) {
      case 'assignRoles':
        void userRoleRef.value?.handleOpen(row)
        break
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
  }
</style>
