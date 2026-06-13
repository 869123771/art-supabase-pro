<!-- 基础表格 -->
<template>
  <div class="user-page art-full-height">
    <ElCard class="art-table-card" style="margin-top: 0">
      <!-- 表格 -->
      <ArtTable
        rowKey="id"
        :show-table-header="false"
        :loading="loading"
        :data="data"
        :columns="columns"
        :pagination="pagination"
        @pagination:size-change="handleSizeChange"
        @pagination:current-change="handleCurrentChange"
      >
      </ArtTable>
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import { useTable } from '@/hooks/core/useTable'
  import { fetchGetUserList } from '@/api/system-manage'

  defineOptions({ name: 'UserMixedUsageExample' })

  type ExampleUserSearchParams = Api.SystemManage.UserSearchParams & {
    current?: number
    size?: number
  }

  const fetchExampleUserList = (params: ExampleUserSearchParams) => {
    const { current = 1, size = 20, ...filters } = params
    return fetchGetUserList({
      ...filters,
      from: (current - 1) * size,
      to: current * size - 1
    })
  }

  const { data, columns, loading, pagination, handleSizeChange, handleCurrentChange } = useTable<
    Api.SystemManage.UserListItem,
    typeof fetchExampleUserList
  >({
    core: {
      apiFn: fetchExampleUserList,
      apiParams: {
        current: 1,
        size: 20,
        userName: '',
        userPhone: '',
        userEmail: ''
      },
      columnsFactory: () => [
        {
          prop: 'id',
          label: 'ID'
        },
        {
          prop: 'nickName',
          label: '昵称'
        },
        {
          prop: 'userGender',
          label: '性别',
          sortable: true,
          formatter: (row) => row.userGender || '未知'
        },
        {
          prop: 'userPhone',
          label: '手机号'
        },
        {
          prop: 'userEmail',
          label: '邮箱'
        }
      ]
    }
  })
</script>
