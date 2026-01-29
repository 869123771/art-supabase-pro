<!-- 用户管理页面 -->
<!-- art-full-height 自动计算出页面剩余高度 -->
<!-- art-table-card 一个符合系统样式的 class，同时自动撑满剩余高度 -->
<!-- 更多 useTable 使用示例请移步至 功能示例 下面的高级表格示例或者查看官方文档 -->
<!-- useTable 文档：https://www.artd.pro/docs/zh/guide/hooks/use-table.html -->
<template>
  <div class="user-page art-full-height">
    <!-- 搜索栏 -->
    <UserSearch v-model="searchForm" @search="handleSearch" @reset="resetSearchParams"></UserSearch>

    <ElCard class="art-table-card" shadow="never">
      <!-- 表格头部 -->
      <ArtTableHeader v-model:columns="columnChecks" :loading="loading" @refresh="refreshData">
        <template #left>
          <ElSpace wrap>
            <ElButton @click="showDialog('add')" v-ripple>新增用户</ElButton>
          </ElSpace>
        </template>
      </ArtTableHeader>

      <!-- 表格 -->
      <ArtTable
        table-layout="fixed"
        :loading="loading"
        :data="data as any"
        :columns="columns"
        :pagination="pagination"
        @selection-change="handleSelectionChange"
        @pagination:size-change="handleSizeChange"
        @pagination:current-change="handleCurrentChange"
      >
      </ArtTable>

      <!-- 用户弹窗 -->
      <UserDialog
        v-model:visible="dialogVisible"
        :type="dialogType"
        :user-data="currentUserData"
        @submit="handleDialogSubmit"
      />

      <UserRoleDialog ref="userRoleRef" @success="getData" />
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { useTable } from '@/hooks/core/useTable'
  import UserSearch from './modules/user-search.vue'
  import UserDialog from './modules/user-dialog.vue'
  import { ElTag, ElMessageBox, ElImage, type TagProps } from 'element-plus'
  import { ColumnOption, DialogType } from '@/types'

  import { formatWithDayjs } from '@/utils/time'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import { deleteUser, fetchGetUserList, resetUser } from '@/api/system-manage'
  import ArtButtonMore, { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import UserRoleDialog from '@views/system/user/modules/user-role-dialog.vue'

  defineOptions({ name: 'User' })

  type UserListItem = Api.SystemManage.UserListItem

  const userStore = useUserStore()

  // 弹窗相关
  const dialogType = ref<DialogType>('add')
  const dialogVisible = ref(false)
  const currentUserData = ref<Partial<UserListItem>>({})

  const userRoleRef = ref()

  // 选中行
  const selectedRows = ref<UserListItem[]>([])

  // 搜索表单
  const searchForm = ref({
    userName: undefined,
    userGender: undefined,
    userPhone: undefined,
    userEmail: undefined,
    status: ''
  })

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
  } = useTable({
    // 核心配置
    core: {
      apiFn: () => handleGetUserList(),
      apiParams: {
        current: 1,
        size: 20,
        ...searchForm.value
      },
      // 自定义分页字段映射，未设置时将使用全局配置 tableConfig.ts 中的 paginationKey
      // paginationKey: {
      //   current: 'pageNum',
      //   size: 'pageSize'
      // },
      columnsFactory: (): ColumnOption[] => [
        { type: 'selection' }, // 勾选列
        { type: 'index', width: 60, label: '序号' }, // 序号
        {
          prop: 'userInfo',
          label: '用户名',
          width: 280,
          // visible: false, // 默认是否显示列
          formatter: (row: UserListItem) => {
            return h('div', { class: 'user flex-c' }, [
              h(ElImage, {
                class: 'size-9.5 rounded-md',
                src: row.avatar as string,
                previewSrcList: [row.avatar || ''],
                // 图片预览是否插入至 body 元素上，用于解决表格内部图片预览样式异常
                previewTeleported: true
              }),
              h('div', { class: 'ml-2' }, [
                h('p', { class: 'user-name' }, row.userName),
                h('p', { class: 'email' }, row.userEmail)
              ])
            ])
          }
        },
        {
          prop: 'userType',
          label: '用户类型',
          formatter: (row: UserListItem) => {
            const colorMap: Record<string, TagProps['type']> = {
              '1': 'primary',
              '2': 'info'
            }
            const tagType = colorMap[String(row.userType)] ?? 'info'
            return h(ElTag, { type: tagType }, () =>
              userStore.getDictLabelByValue('userType', row?.userType || '')
            )
          }
        },
        {
          prop: 'userGender',
          label: '性别',
          sortable: true,
          formatter: (row: UserListItem) => userStore.getDictLabelByValue('sex', row.userGender)
        },
        { prop: 'userPhone', label: '手机号' },
        {
          prop: 'status',
          label: '状态',
          formatter: (row: UserListItem) => {
            const colorMap: Record<string, TagProps['type']> = {
              '1': 'success',
              '2': 'danger'
            }
            const tagType = colorMap[String(row.status)] ?? 'info'
            return h(ElTag, { type: tagType }, () =>
              userStore.getDictLabelByValue('status', row?.status || '')
            )
          }
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
          fixed: 'right', // 固定列
          formatter: (row: UserListItem) =>
            h(
              'div',
              {
                class: 'flex '
              },
              [
                h(ArtButtonTable, {
                  type: 'edit',
                  onClick: () => showDialog('edit', row)
                }),
                h(ArtButtonMore, {
                  list: () => {
                    const { info } = userStore
                    const selfExcludeButtonKeys = ['assignRoles', 'delete']
                    let buttonList: ButtonMoreItem[] = [
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
                    if (info.email === row.userEmail) {
                      buttonList = buttonList.filter(
                        (item: ButtonMoreItem) =>
                          !selfExcludeButtonKeys.includes(item.key as string)
                      )
                    }
                    return buttonList
                  },
                  onClick: (item: ButtonMoreItem) => handleButtonMoreClick(item, row)
                })
              ]
            )
        }
      ]
    }
  })

  /**
   * 搜索处理
   * @param params 参数
   */
  const handleSearch = (params: Record<string, any>) => {
    console.log(params)
    // 搜索参数赋值
    Object.assign(searchParams, params)
    getData()
  }

  /**
   * 显示用户弹窗
   */
  const showDialog = (type: DialogType, row?: UserListItem): void => {
    console.log('打开弹窗:', { type, row })
    dialogType.value = type
    currentUserData.value = row || {}
    nextTick(() => {
      dialogVisible.value = true
    })
  }

  const handleButtonMoreClick = (item: ButtonMoreItem, row: UserListItem) => {
    switch (item.key) {
      case 'assignRoles':
        userRoleRef.value.handleOpen(row)
        break
      case 'reset':
        handleResetPassword(row)
        break
      case 'delete':
        handleDeleteUser(row)
        break
    }
  }

  /**
   * 删除用户
   */
  const handleResetPassword = (row: UserListItem): void => {
    ElMessageBox.confirm(`是否将用户密码重置为[123456]?`, '系统提示', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning',
      beforeClose: async (action, instance, done) => {
        if (action !== 'confirm') {
          done()
          return
        }

        instance.confirmButtonLoading = true
        instance.confirmButtonText = '处理中...'

        try {
          const params: Pick<UserListItem, 'userEmail' | 'password'> = {
            userEmail: row.userEmail,
            password: '123456'
          }

          await resetUser(params as UserListItem)

          done() // ✅ 成功才关闭
        } finally {
          instance.confirmButtonLoading = false
          instance.confirmButtonText = '确定'
        }
      }
    })
  }

  /**
   * 删除用户
   */
  const handleDeleteUser = (row: UserListItem): void => {
    console.log('删除用户:', row)
    ElMessageBox.confirm(`确定要注销该用户吗?`, '注销用户', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning'
    }).then(async () => {
      await deleteUser(row)
      await getData()
    })
  }

  /**
   * 处理弹窗提交事件
   */
  const handleDialogSubmit = async () => {
    try {
      dialogVisible.value = false
      currentUserData.value = {}
      await getData()
    } catch (error) {
      console.error('提交失败:', error)
    }
  }

  /**
   * 处理表格行选择变化
   */
  const handleSelectionChange = (selection: UserListItem[]): void => {
    selectedRows.value = selection
    console.log('选中行数据:', selectedRows.value)
  }

  const handleGetUserList = async () => {
    const { userName, userPhone, userEmail, userGender, status } = searchParams as UserListItem
    const { from, to } = pageInfoHandler(pagination)
    return await fetchGetUserList({
      userName,
      userPhone,
      userEmail,
      userGender,
      status,
      from,
      to
    })
  }
</script>
