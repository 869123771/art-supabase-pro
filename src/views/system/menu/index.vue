<!-- 菜单管理页面 -->
<template>
  <div class="menu-page art-full-height">
    <!-- 搜索栏 -->
    <ArtSearchBar
      v-model="formFilters"
      :items="formItems"
      :showExpand="false"
      @reset="handleReset"
      @search="handleSearch"
    />

    <ElCard class="art-table-card" shadow="never">
      <!-- 表格头部 -->
      <ArtTableHeader
        :showZebra="false"
        :loading="loading"
        v-model:columns="columnChecks"
        @refresh="handleRefresh"
      >
        <template #left>
          <ElButton v-auth="'menu:add'" @click="handleAddMenu" v-ripple> 添加菜单 </ElButton>
          <ElButton @click="toggleExpand" v-ripple>
            {{ isExpanded ? '收起' : '展开' }}
          </ElButton>
        </template>
      </ArtTableHeader>

      <ArtTable
        ref="tableRef"
        rowKey="id"
        :loading="loading"
        :columns="columns"
        :data="filteredTableData"
        :stripe="false"
        :tree-props="{ children: 'children', hasChildren: 'hasChildren' }"
        :default-expand-all="false"
      />

      <!-- 菜单弹窗 -->
      <MenuDialog
        ref="menuDialogRef"
        v-model:visible="dialogVisible"
        :editData="editData"
        :lockType="lockMenuType"
        @submit="handleSubmit"
      />
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import { formatMenuTitle } from '@/utils/router'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { useTableColumns } from '@/hooks/core/useTableColumns'
  import type { AppRouteRecord } from '@/types/router'
  import MenuDialog from './modules/menu-dialog.vue'
  import TreeUtils from '@/utils/tree'
  import { ElMessageBox, ElTag } from 'element-plus'

  import { formatWithDayjs } from '@/utils/time'
  import { deleteMenu, fetchGetMenuList } from '@/api/system-manage'

  defineOptions({ name: 'Menus' })

  const treeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children',
    deepClone: true
  })

  // 状态管理
  const loading = ref(false)
  const isExpanded = ref(false)
  const tableRef = ref()

  // 弹窗相关
  const menuDialogRef = ref()
  const dialogVisible = ref(false)
  const editData = ref<AppRouteRecord | any>({})
  const lockMenuType = ref(false)

  // 搜索相关
  const initialSearchState = {
    name: '',
    path: ''
  }

  const formFilters = reactive({ ...initialSearchState })
  const appliedFilters = reactive({ ...initialSearchState })

  const formItems = computed(() => [
    {
      label: '菜单名称',
      key: 'name',
      type: 'input',
      props: { clearable: true }
    },
    {
      label: '路由地址',
      key: 'path',
      type: 'input',
      props: { clearable: true }
    }
  ])

  onMounted(() => {
    handleGetMenuList()
  })

  /**
   * 获取菜单类型标签颜色
   * @param row 菜单行数据
   * @returns 标签颜色类型
   */
  const getMenuTypeTag = (
    row: AppRouteRecord
  ): 'primary' | 'success' | 'warning' | 'info' | 'danger' => {
    if (row.type === 'button') return 'danger'
    if (row.type === 'menu') return 'primary'
    if (row.meta?.link && row.meta?.isIframe) return 'success'
    if (row.meta?.link) return 'warning'
    return 'info'
  }

  /**
   * 获取菜单类型文本
   * @param row 菜单行数据
   * @returns 菜单类型文本
   */
  const getMenuTypeText = (row: AppRouteRecord): string => {
    if (row.type === 'button') return '按钮'
    if (row.type === 'folder') return '目录'
    if (row.meta?.link && row.meta?.isIframe) return '内嵌'
    if (row.path) return '菜单'
    if (row.meta?.link) return '外链'
    return '未知'
  }

  // 表格列配置
  const { columnChecks, columns } = useTableColumns(() => [
    {
      prop: 'meta.title',
      label: '菜单名称',
      minWidth: 120,
      formatter: (row: AppRouteRecord) => formatMenuTitle(row.meta?.title)
    },
    {
      prop: 'type',
      label: '菜单类型',
      formatter: (row: AppRouteRecord) => {
        return h(ElTag, { type: getMenuTypeTag(row) }, () => getMenuTypeText(row))
      }
    },
    {
      prop: 'path',
      label: '路由',
      formatter: (row: AppRouteRecord) => {
        if (row.meta?.isAuthButton) return ''
        return row.meta?.link || row.path || ''
      }
    },
    {
      prop: 'name',
      label: '权限标识',
      formatter: (row: AppRouteRecord) => {
        if (row.children?.length) {
          if (row.children.some((item: any) => item.meta?.menuType === 'button')) {
            return `${row.children.length} 个权限标识`
          } else {
            return row.name
          }
        } else {
          return row.name
        }
      }
    },
    {
      prop: 'sort',
      label: '排序'
    },
    {
      prop: 'updateTime',
      label: '编辑时间',
      width: 180,
      formatter: (row: AppRouteRecord) => formatWithDayjs(row?.updateTime)
    },
    {
      prop: 'status',
      label: '状态',
      formatter: () => h(ElTag, { type: 'success' }, () => '启用')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 180,
      align: 'right',
      formatter: (row: AppRouteRecord) => {
        const buttonStyle = { style: 'text-align: right' }

        if (row.type === 'button') {
          return h('div', buttonStyle, [
            h(ArtButtonTable, {
              type: 'edit',
              permission: 'menu:edit',
              onClick: () => handleEditAuth(row)
            }),
            h(ArtButtonTable, {
              type: 'delete',
              permission: 'menu:delete',
              onClick: () => handleDeleteMenu(row)
            })
          ])
        }

        return h('div', buttonStyle, [
          h(ArtButtonTable, {
            type: 'add',
            permission: 'menu:add',
            onClick: () => handleAddAuth(row),
            title: '新增权限'
          }),
          h(ArtButtonTable, {
            type: 'edit',
            permission: 'menu:edit',
            onClick: () => handleEditMenu(row)
          }),
          h(ArtButtonTable, {
            type: 'delete',
            permission: 'menu:delete',
            onClick: () => handleDeleteMenu(row)
          })
        ])
      }
    }
  ])

  // 数据相关
  const tableData = ref<AppRouteRecord[]>([])

  /**
   * 重置搜索条件
   */
  const handleReset = (): void => {
    Object.assign(formFilters, { ...initialSearchState })
    Object.assign(appliedFilters, { ...initialSearchState })
    handleGetMenuList()
  }

  /**
   * 执行搜索
   */
  const handleSearch = (): void => {
    Object.assign(appliedFilters, { ...formFilters })
    handleGetMenuList()
  }

  /**
   * 刷新菜单列表
   */
  const handleRefresh = (): void => {
    handleGetMenuList()
  }

  // 过滤后的表格数据
  const filteredTableData = computed(() => {
    return tableData.value
  })

  /**
   * 添加菜单
   */
  const handleAddMenu = (): void => {
    editData.value = {}
    lockMenuType.value = false
    dialogVisible.value = true
    menuDialogRef.value.handleSetParent({
      menuTree: tableData.value
    })
  }

  /**
   * 添加权限按钮
   */
  const handleAddAuth = (row: AppRouteRecord): void => {
    editData.value = {}
    lockMenuType.value = false
    menuDialogRef.value.handleSetParent({
      ...row,
      menuTree: tableData.value
    })
    dialogVisible.value = true
  }

  /**
   * 编辑菜单
   * @param row 菜单行数据
   */
  const handleEditMenu = (row: AppRouteRecord): void => {
    editData.value = row
    lockMenuType.value = true
    dialogVisible.value = true
    menuDialogRef.value.handleSetParent({
      ...row,
      menuTree: tableData.value
    })
  }

  /**
   * 编辑权限按钮
   * @param row 权限行数据
   */
  const handleEditAuth = (row: AppRouteRecord): void => {
    editData.value = row
    lockMenuType.value = false
    dialogVisible.value = true
    menuDialogRef.value.handleSetParent({
      ...row,
      menuTree: tableData.value
    })
  }

  /**
   * 菜单表单数据类型
   */
  interface MenuFormData {
    name: string
    path: string
    component?: string
    icon?: string
    roles?: string[]
    sort?: number
    [key: string]: any
  }

  /**
   * 提交表单数据
   * @param formData 表单数据
   */
  const handleSubmit = (formData: MenuFormData): void => {
    console.log('提交数据:', formData)
    // TODO: 调用API保存数据
    handleGetMenuList()
  }

  /**
   * 删除菜单
   */
  const handleDeleteMenu = async (row: AppRouteRecord): Promise<void> => {
    try {
      await ElMessageBox.confirm('确定要删除该菜单吗？删除后无法恢复', '提示', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      })
      const ids = treeUtils
        .getDescendants(tableData.value, row.id as string, true)
        ?.map((item: any) => item.id)
      await deleteMenu({ ids })
      await handleGetMenuList()
    } catch (error) {
      if (error !== 'cancel') {
        ElMessage.error('删除失败')
      }
    }
  }

  /**
   * 切换展开/收起所有菜单
   */
  const toggleExpand = (): void => {
    isExpanded.value = !isExpanded.value
    nextTick(() => {
      if (tableRef.value?.elTableRef && filteredTableData.value) {
        const processRows = (rows: AppRouteRecord[]) => {
          rows.forEach((row) => {
            if (row.children?.length) {
              tableRef.value.elTableRef.toggleRowExpansion(row, isExpanded.value)
              processRows(row.children)
            }
          })
        }
        processRows(filteredTableData.value)
      }
    })
  }

  const handleGetMenuList = async () => {
    try {
      loading.value = true
      const { name, path } = formFilters
      const params = {
        name,
        path
      }
      const { data } = await fetchGetMenuList(params as AppRouteRecord)
      tableData.value = treeUtils.listToTree(data, (a, b) => a.sort - b.sort) as AppRouteRecord[]
    } finally {
      loading.value = false
    }
  }
</script>
