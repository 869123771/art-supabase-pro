<!-- 菜单管理页面 -->
<template>
  <div class="menu-page art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="formFilters"
      v-model:show-search-bar="showSearchBar"
      :search-items="formItems"
      :api-fn="fetchTableData"
      :api-params="tableApiParams"
      :columns-factory="columnsFactory"
      :response-adapter="responseAdapter"
      :header-actions="headerActions"
      :table-header-props="tableHeaderProps"
      :table-props="tableProps"
      @row-drag-end="handleMenuDragEnd"
    />

    <!-- 菜单弹窗 -->
    <MenuDialog ref="menuDialogRef" @submit="handleSubmit" />
  </div>
</template>

<script setup lang="ts">
  import { formatMenuTitle } from '@/utils/router'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { AppRouteRecord } from '@/types/router'
  import MenuDialog from './modules/menu-dialog.vue'
  import TreeUtils from '@/utils/tree'
  import { ElMessage, ElMessageBox, ElTag } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryTableHeaderProps,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import type { ApiResponse } from '@/utils/table/tableCache'

  import { formatWithDayjs } from '@/utils/time'
  import { deleteMenu, fetchGetMenuList, saveMenuDragSort } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'Menus' })

  const treeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children',
    deepClone: true
  })

  type MenuType = 'folder' | 'menu' | 'button'

  interface MenuDialogOpenData {
    row?: AppRouteRecord | Record<string, never>
    type?: MenuType
    parent?: AppRouteRecord
    menuTree: AppRouteRecord[]
  }

  interface MenuDialogExpose {
    handleOpen: (data: MenuDialogOpenData) => Promise<void>
  }

  interface MenuRowDragPayload {
    row?: AppRouteRecord
    targetRow?: AppRouteRecord
    oldIndex?: number
    newIndex?: number
  }

  interface MenuDragSortUpdate {
    id: string
    parentId: string | null
    sort: number
  }

  const { isSuper } = storeToRefs(useUserStore())

  const isExpanded = ref(false)
  const expandRowKeys = ref<string[]>([])

  const showSearchBar = ref(false)
  // 弹窗相关
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const menuDialogRef = ref<MenuDialogExpose>()

  const openMenuDialog = async (data: MenuDialogOpenData): Promise<void> => {
    await menuDialogRef.value?.handleOpen(data)
  }

  // 搜索相关
  const initialSearchState = {
    name: '',
    path: ''
  }

  const formFilters = ref({ ...initialSearchState })
  const tableApiParams = {
    current: 1,
    size: 9999
  }

  const formItems = computed<SearchFormItem[]>(() => [
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

  const tableHeaderProps: ArtTableQueryTableHeaderProps = {
    showZebra: false
  }

  const tableProps = computed<ArtTableQueryTableProps>(() => ({
    rowKey: 'id',
    tableLayout: 'fixed',
    stripe: false,
    treeProps: { children: 'children', hasChildren: 'hasChildren' },
    defaultExpandAll: false,
    expandRowKeys: expandRowKeys.value,
    paginationOptions: {
      hideOnSinglePage: true
    }
  }))

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '添加菜单',
      permission: 'System:Menu:Add',
      onClick: () => handleAdd('menu')
    },
    {
      key: 'toggle-expand',
      label: isExpanded.value ? '收起' : '展开',
      icon: isExpanded.value ? 'ri:collapse-diagonal-line' : 'ri:expand-diagonal-line',
      buttonProps: { plain: true },
      onClick: toggleExpand
    }
  ])

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

  const columnsFactory = (): ColumnOption<AppRouteRecord>[] => [
    {
      prop: 'meta.title',
      label: '菜单名称',
      minWidth: 120,
      draggable: true,
      dragDisabled: (row: AppRouteRecord) => !isSuper.value || row.type === 'button',
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
      formatter: (row: AppRouteRecord) => renderOperationButtons(row)
    }
  ]

  // 数据相关
  const tableData = ref<AppRouteRecord[]>([])

  const renderOperationButtons = (row: AppRouteRecord) => {
    const actions = [
      {
        type: 'add' as const,
        permission: 'System:Menu:Add',
        hidden: row.type === 'button',
        onClick: () => handleAdd('button', row)
      },
      {
        type: 'edit' as const,
        permission: 'System:Menu:Edit',
        onClick: () => handleEdit(row)
      },
      {
        type: 'delete' as const,
        permission: 'System:Menu:Delete',
        onClick: () => handleDelete(row)
      }
    ]

    return h(
      'div',
      { style: 'text-align: right' },
      actions
        .filter((action) => !action.hidden)
        .map(({ type, permission, onClick }) =>
          h(ArtButtonTable, {
            type,
            permission,
            onClick
          })
        )
    )
  }

  const fetchTableData = (params: AppRouteRecord) => {
    return fetchGetMenuList(params)
  }

  const responseAdapter = (response: { data: AppRouteRecord[] }): ApiResponse<AppRouteRecord> => {
    const treeData = treeUtils.listToTree(
      response.data,
      (a, b) => a.sort - b.sort
    ) as AppRouteRecord[]
    tableData.value = treeData
    if (isExpanded.value) {
      expandRowKeys.value = getExpandableRowKeys(treeData)
    }

    return {
      records: treeData,
      total: treeData.length,
      current: tableApiParams.current,
      size: tableApiParams.size
    }
  }

  /**
   * 添加菜单/权限
   */
  const handleAdd = (type: MenuType, row?: AppRouteRecord): void => {
    void openMenuDialog({
      row: {},
      type,
      parent: row,
      menuTree: tableData.value
    })
  }

  /**
   * 编辑菜单/权限
   * @param row 菜单行数据
   */
  const handleEdit = (row: AppRouteRecord): void => {
    void openMenuDialog({
      row,
      parent: row,
      menuTree: tableData.value
    })
  }

  /**
   * 提交表单数据
   */
  const handleSubmit = (): void => {
    void tableQueryRef.value?.refreshData()
  }

  const normalizeParentId = (parentId: AppRouteRecord['parentId']): string | null => {
    return parentId || null
  }

  const getSiblingMenus = (parentId: string | null): AppRouteRecord[] => {
    if (parentId == null) return tableData.value
    const parent = treeUtils.findNode(tableData.value, parentId) as AppRouteRecord | null
    return parent?.children ?? []
  }

  const hasDescendant = (row: AppRouteRecord, targetId: string | null): boolean => {
    if (!targetId || !row.id) return false
    return treeUtils
      .getDescendants(tableData.value, row.id, false)
      .some((item) => item.id === targetId)
  }

  const reindexSiblingMenus = (
    parentId: string | null,
    rows: AppRouteRecord[]
  ): MenuDragSortUpdate[] => {
    return rows
      .filter((item): item is AppRouteRecord & { id: string } => !!item.id)
      .map((item, index) => ({
        id: item.id,
        parentId,
        sort: index + 1
      }))
  }

  const buildMenuDragUpdates = (
    row: AppRouteRecord,
    targetRow: AppRouteRecord,
    targetParentId: string | null,
    oldIndex = 0,
    newIndex = 0
  ): MenuDragSortUpdate[] => {
    const sourceParentId = normalizeParentId(row.parentId)
    const sourceSiblings = getSiblingMenus(sourceParentId).filter((item) => item.id !== row.id)
    const targetSiblings = getSiblingMenus(targetParentId).filter((item) => item.id !== row.id)
    const targetIndex = targetSiblings.findIndex((item) => item.id === targetRow.id)
    if (targetIndex < 0) {
      targetSiblings.push(row)
    } else {
      const insertIndex = oldIndex < newIndex ? targetIndex + 1 : targetIndex
      targetSiblings.splice(insertIndex, 0, row)
    }

    const updates = new Map<string, MenuDragSortUpdate>()
    if (sourceParentId !== targetParentId) {
      reindexSiblingMenus(sourceParentId, sourceSiblings).forEach((item) =>
        updates.set(item.id, item)
      )
    }
    reindexSiblingMenus(targetParentId, targetSiblings).forEach((item) =>
      updates.set(item.id, item)
    )
    return Array.from(updates.values())
  }

  const handleMenuDragEnd = async (payload: MenuRowDragPayload): Promise<void> => {
    const { row, targetRow, oldIndex, newIndex } = payload
    if (!row?.id || !targetRow?.id || oldIndex === newIndex) return

    const targetParentId = normalizeParentId(targetRow.parentId)
    if (row.id === targetRow.id || hasDescendant(row, targetParentId)) {
      ElMessage.warning('不能拖拽到自身或子级菜单下')
      await tableQueryRef.value?.refreshData()
      return
    }

    try {
      const updates = buildMenuDragUpdates(row, targetRow, targetParentId, oldIndex, newIndex)
      if (!updates.length) return

      await saveMenuDragSort(updates)
      ElMessage.success('菜单排序已保存')
      await tableQueryRef.value?.refreshData()
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '菜单拖拽保存失败')
      await tableQueryRef.value?.refreshData()
    }
  }

  /**
   * 删除菜单
   */
  const handleDelete = async (row: AppRouteRecord): Promise<void> => {
    try {
      await ElMessageBox.confirm('确定要删除该菜单吗？删除后无法恢复', '提示', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      })
      const ids = treeUtils
        .getDescendants(tableData.value, row.id as string, true)
        ?.map((item: any) => item.id)
      await deleteMenu({ ids } as Record<any, any>)
      await tableQueryRef.value?.refreshRemove()
    } catch (error) {
      if (error !== 'cancel') {
        ElMessage.error(error instanceof Error ? error.message : '删除失败')
      }
    }
  }

  /**
   * 切换展开/收起所有菜单
   */
  const toggleExpand = (): void => {
    isExpanded.value = !isExpanded.value
    expandRowKeys.value = isExpanded.value ? getExpandableRowKeys(tableData.value) : []
  }

  const getExpandableRowKeys = (rows: AppRouteRecord[]): string[] => {
    const keys: string[] = []
    rows.forEach((row) => {
      if (row.children?.length && row.id != null) {
        keys.push(String(row.id))
        keys.push(...getExpandableRowKeys(row.children))
      }
    })
    return keys
  }
</script>
