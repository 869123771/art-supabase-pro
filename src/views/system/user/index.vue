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
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import UserDialog from './modules/user-dialog.vue'
  import { ElMessageBox, ElImage } from 'element-plus'
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
      props: { placeholder: '请输入邮箱' }
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
    tableLayout: 'fixed'
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
      label: '用户名',
      minWidth: 260,
      formatter: (row: UserListItem) => {
        return h('div', { class: 'user-info-cell' }, [
          h(ElImage, {
            class: 'user-info-cell__avatar',
            src: row.avatar as string,
            previewSrcList: [row.avatar || ''],
            fit: 'cover',
            previewTeleported: true
          }),
          h('div', { class: 'user-info-cell__content' }, [
            h('p', { class: 'user-info-cell__name' }, row.userName),
            h('p', { class: 'user-info-cell__email', title: row.userEmail }, row.userEmail)
          ])
        ])
      }
    },
    {
      prop: 'userType',
      label: '用户类型',
      dict: { code: 'userType', display: 'auto' }
    },
    {
      prop: 'userGender',
      label: '性别',
      sortable: true,
      dict: { code: 'sex', display: 'text' }
    },
    { prop: 'userPhone', label: '手机号' },
    {
      prop: 'status',
      label: '状态',
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
        h('div', { class: 'flex ' }, [
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
        color: '#f56c6c'
      }
    ]

    if (getUserInfo.value.email !== row.userEmail) return buttonList
    return buttonList.filter((item) => !selfExcludeButtonKeys.includes(item.key as string))
  }

  const openDialog = (row?: UserListItem): void => {
    void userDialogRef.value?.handleOpen(row)
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
      await ElMessageBox.confirm(`是否将用户密码重置为[${password}]?`, '系统提示', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      })
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
      await ElMessageBox.confirm('确定要注销该用户吗?', '注销用户', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      })
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
      width: 38px;
      height: 38px;
      overflow: hidden;
      border-radius: 6px;

      .el-image__inner {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
    }

    :deep(.user-info-cell__content) {
      min-width: 0;
      margin-left: 10px;
      line-height: 20px;
    }

    :deep(.user-info-cell__name),
    :deep(.user-info-cell__email) {
      max-width: 100%;
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    :deep(.user-info-cell__name) {
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    :deep(.user-info-cell__email) {
      color: var(--el-text-color-regular);
    }
  }
</style>
