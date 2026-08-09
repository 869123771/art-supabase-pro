<!-- 菜单管理页面 -->
<template>
  <div class="menu-page art-full-height">
    <MasterDeleteProcessingNotice
      action-hint="当前菜单已自动定位；可先解除角色授权或处理编号场景后返回。"
    />
    <section class="menu-page__overview art-card-xs">
      <header class="menu-page__hero">
        <div class="menu-page__identity">
          <div class="menu-page__brand" aria-hidden="true">
            <ArtSvgIcon icon="ri:route-line" />
          </div>
          <div>
            <span>NAVIGATION GOVERNANCE</span>
            <h1>菜单管理</h1>
            <p>统一维护导航层级、页面入口与按钮权限，确保路由结构和角色授权边界清晰一致。</p>
          </div>
        </div>
        <div class="menu-page__hero-status">
          <ElTag :type="canSortMenu ? 'success' : 'info'" effect="light" round>
            {{ canSortMenu ? '专业树形排序' : '排序只读' }}
          </ElTag>
          <ElTag type="primary" effect="plain" round>树形权限结构</ElTag>
        </div>
      </header>

      <div class="menu-page__metrics" aria-label="菜单结构概览">
        <article v-for="item in overviewCards" :key="item.label">
          <div :class="['menu-page__metric-icon', `is-${item.tone}`]">
            <ArtSvgIcon :icon="item.icon" />
          </div>
          <div>
            <span>{{ item.label }}</span>
            <strong>{{ item.value }}</strong>
            <small>{{ item.hint }}</small>
          </div>
        </article>
      </div>
    </section>

    <ArtTableQuery
      ref="tableQueryRef"
      focusable
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
    />

    <!-- 菜单弹窗 -->
    <MenuDialog ref="menuDialogRef" @submit="handleSubmit" />
    <MenuSortDialog ref="menuSortDialogRef" @submit="handleSubmit" />
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleSubmit" />
  </div>
</template>

<script setup lang="ts">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { formatMenuTitle } from '@/utils/router'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import type { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import type { AppRouteRecord } from '@/types/router'
  import MenuDialog from './modules/menu-dialog.vue'
  import MenuSortDialog from './modules/menu-sort-dialog.vue'
  import TreeUtils from '@/utils/tree'
  import { ElMessage, ElTag } from 'element-plus'
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
  import { deleteMenu, fetchGetMenuList } from '@/api/system-manage'
  import { useAuth } from '@/hooks/core/useAuth'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'

  defineOptions({ name: 'Menus' })

  const { confirmAction } = useArtFeedback()
  const route = useRoute()

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

  interface MenuSortDialogExpose {
    handleOpen: (menuTree: AppRouteRecord[]) => Promise<void>
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  interface MenuOverviewCard {
    label: string
    value: number
    hint: string
    icon: string
    tone: 'primary' | 'success' | 'warning' | 'info'
  }

  const { hasAuth } = useAuth()
  const canSortMenu = computed(() => hasAuth('System:Menu:Edit'))

  const isExpanded = ref(false)
  const expandRowKeys = ref<string[]>([])

  const showSearchBar = ref(false)
  // 弹窗相关
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const menuDialogRef = ref<MenuDialogExpose>()
  const menuSortDialogRef = ref<MenuSortDialogExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()

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
      props: { clearable: true, placeholder: '请输入菜单名称或权限标识' }
    },
    {
      label: '路由地址',
      key: 'path',
      type: 'input',
      props: { clearable: true, placeholder: '请输入路由、组件或外链地址' }
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
    rowClassName: () => 'menu-tree-row',
    defaultExpandAll: false,
    expandRowKeys: expandRowKeys.value,
    emptyText: '暂无符合条件的菜单',
    emptyDescription: '可调整筛选条件，或新增菜单后再配置页面与按钮权限。',
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
      key: 'tree-sort',
      label: '树形排序',
      icon: 'ri:drag-move-2-line',
      permission: 'System:Menu:Edit',
      buttonProps: { plain: true },
      onClick: () => void menuSortDialogRef.value?.handleOpen(tableData.value)
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
    if (row.meta?.link) return '外链'
    if (row.path) return '菜单'
    return '未知'
  }

  const getMenuTypeIcon = (row: AppRouteRecord): string => {
    if (row.type === 'button') return 'ri:cursor-line'
    if (row.meta?.link && row.meta?.isIframe) return 'ri:window-line'
    if (row.meta?.link) return 'ri:external-link-line'
    if (row.type === 'folder') return row.meta?.icon || 'ri:folder-3-line'
    return row.meta?.icon || 'ri:file-list-3-line'
  }

  const getDirectPermissionCount = (row: AppRouteRecord): number =>
    row.children?.filter((item) => item.type === 'button' || item.meta?.menuType === 'button')
      .length ?? 0

  const getAccessPrimaryText = (row: AppRouteRecord): string => {
    if (row.type === 'button') return row.name || '未配置权限标识'
    return row.meta?.link || row.path || '未配置访问地址'
  }

  const getAccessSecondaryText = (row: AppRouteRecord): string => {
    if (row.type === 'button') return '操作权限'
    if (row.meta?.link && row.meta?.isIframe) return '站内嵌入页面'
    if (row.meta?.link) return '外部链接'
    return typeof row.component === 'string' && row.component ? row.component : '目录容器'
  }

  const columnsFactory = (): ColumnOption<AppRouteRecord>[] => [
    {
      prop: 'meta.title',
      label: '菜单信息',
      minWidth: 230,
      formatter: (row: AppRouteRecord) => {
        const permissionCount = getDirectPermissionCount(row)
        return h('div', { class: 'menu-identity-cell' }, [
          h(
            'span',
            {
              class: ['menu-identity-cell__icon', `is-${row.type || 'menu'}`],
              'aria-hidden': 'true'
            },
            [h(ArtSvgIcon, { icon: getMenuTypeIcon(row) })]
          ),
          h('div', { class: 'menu-identity-cell__copy' }, [
            h('div', { class: 'menu-identity-cell__heading' }, [
              h(
                'strong',
                { title: formatMenuTitle(row.meta?.title) },
                formatMenuTitle(row.meta?.title)
              ),
              permissionCount
                ? h(
                    'span',
                    { class: 'menu-identity-cell__permission-count' },
                    `${permissionCount}项权限`
                  )
                : null
            ]),
            h('small', { title: row.name, translate: 'no' }, row.name || '未配置权限标识')
          ])
        ])
      }
    },
    {
      prop: 'type',
      label: '菜单类型',
      width: 96,
      formatter: (row: AppRouteRecord) => {
        return h(ElTag, { type: getMenuTypeTag(row), effect: 'light' }, () => getMenuTypeText(row))
      }
    },
    {
      prop: 'accessConfig',
      label: '访问配置',
      minWidth: 220,
      formatter: (row: AppRouteRecord) => {
        const primary = getAccessPrimaryText(row)
        const secondary = getAccessSecondaryText(row)
        return h('div', { class: 'menu-access-cell' }, [
          h('span', { title: primary, translate: 'no' }, primary),
          h('small', { title: secondary, translate: 'no' }, secondary)
        ])
      }
    },
    {
      prop: 'sort',
      label: '排序',
      width: 72,
      align: 'center'
    },
    {
      prop: 'updateTime',
      label: '最后编辑',
      width: 164,
      formatter: (row: AppRouteRecord) =>
        h('span', { class: 'menu-update-cell' }, formatWithDayjs(row?.updateTime) || '--')
    },
    {
      prop: 'status',
      label: '状态',
      width: 88,
      formatter: (row: AppRouteRecord) => {
        const enabled = row.meta?.isEnable !== false
        return h(ElTag, { type: enabled ? 'success' : 'info', effect: 'light' }, () =>
          enabled ? '启用' : '停用'
        )
      }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 96,
      align: 'right',
      formatter: (row: AppRouteRecord) =>
        h(ArtButtonMore, {
          list: getMenuActions(row),
          onClick: (item: ButtonMoreItem) => handleMenuAction(item, row)
        })
    }
  ]

  // 数据相关
  const tableData = ref<AppRouteRecord[]>([])
  const flatMenuRows = computed(() => treeUtils.treeToList(tableData.value))
  const overviewCards = computed<MenuOverviewCard[]>(() => {
    const rows = flatMenuRows.value
    const navigationRows = rows.filter((row) => row.type !== 'button')
    const permissionRows = rows.filter(
      (row) => row.type === 'button' || row.meta?.menuType === 'button'
    )
    const enabledRows = rows.filter((row) => row.meta?.isEnable !== false)

    return [
      {
        label: '全部节点',
        value: rows.length,
        hint: `${tableData.value.length} 个一级入口`,
        icon: 'ri:node-tree',
        tone: 'primary'
      },
      {
        label: '导航菜单',
        value: navigationRows.length,
        hint: '目录、页面与外部入口',
        icon: 'ri:menu-2-line',
        tone: 'info'
      },
      {
        label: '按钮权限',
        value: permissionRows.length,
        hint: '用于角色精细化授权',
        icon: 'ri:shield-keyhole-line',
        tone: 'warning'
      },
      {
        label: '启用节点',
        value: enabledRows.length,
        hint: rows.length
          ? `占全部节点 ${Math.round((enabledRows.length / rows.length) * 100)}%`
          : '暂无节点',
        icon: 'ri:checkbox-circle-line',
        tone: 'success'
      }
    ]
  })

  const getMenuActions = (row: AppRouteRecord): ButtonMoreItem[] =>
    [
      {
        key: 'add',
        label: row.type === 'folder' ? '新增子菜单' : '新增按钮权限',
        icon: row.type === 'folder' ? 'ri:file-add-line' : 'ri:add-circle-line',
        auth: 'System:Menu:Add',
        hidden: row.type === 'button'
      },
      {
        key: 'edit',
        label: `编辑${getMenuActionSubject(row)}`,
        icon: 'ri:edit-2-line',
        auth: 'System:Menu:Edit'
      },
      {
        key: 'delete',
        label: `删除${getMenuActionSubject(row)}`,
        icon: 'ri:delete-bin-4-line',
        color: 'var(--el-color-danger)',
        auth: 'System:Menu:Delete'
      }
    ].filter((item) => !item.hidden)

  const getMenuActionSubject = (row: AppRouteRecord): string => {
    if (row.type === 'button') return '权限'
    if (row.type === 'folder') return '目录'
    return '菜单'
  }

  const handleMenuAction = (item: ButtonMoreItem, row: AppRouteRecord): void => {
    switch (item.key) {
      case 'add':
        handleAdd(row.type === 'folder' ? 'menu' : 'button', row)
        break
      case 'edit':
        handleEdit(row)
        break
      case 'delete':
        void handleDelete(row)
        break
    }
  }

  const fetchTableData = (params: AppRouteRecord) => {
    return fetchGetMenuList({
      ...params,
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : undefined
    })
  }

  const responseAdapter = (response: { data: AppRouteRecord[] }): ApiResponse<AppRouteRecord> => {
    const treeData = treeUtils.listToTree(response.data, (a, b) => (a.sort ?? 0) - (b.sort ?? 0))
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

  /**
   * 删除菜单
   */
  const handleDelete = async (row: AppRouteRecord): Promise<void> => {
    try {
      const ids = treeUtils
        .getDescendants(tableData.value, row.id as string, true)
        ?.map((item) => String(item.id))
      const descendants = treeUtils.getDescendants(tableData.value, row.id as string, true)
      const blocked = await deleteGuardRef.value?.inspect({
        resourceType: 'menu',
        resourceLabel: '菜单',
        resources: descendants.map((item) => ({
          id: String(item.id),
          label: formatMenuTitle(item.meta?.title)
        }))
      })
      if (blocked) return

      await confirmAction(
        `删除「${formatMenuTitle(row.meta?.title)}」后，其下级菜单与按钮权限会一并移除，关联角色也将失去对应访问权限。确认继续吗？`,
        '删除菜单',
        {
          confirmButtonText: '确认删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteMenu({ ids })
      ElMessage.success('菜单删除成功')
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
    return treeUtils
      .treeToList(rows)
      .map((row) => row.id)
      .filter((id): id is string => id != null)
  }

  watch(
    () => route.query.recordId,
    () => {
      void tableQueryRef.value?.refreshData()
    }
  )
</script>

<style scoped lang="scss">
  .menu-page {
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
        transparent 34%
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
        text-wrap: balance;
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
          font-variant-numeric: tabular-nums;
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

      &.is-warning {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
      }

      &.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }
    }

    :deep(.menu-identity-cell) {
      display: flex;
      flex: 1;
      gap: 10px;
      align-items: center;
      min-width: 0;

      .menu-identity-cell__icon {
        display: grid;
        flex: 0 0 34px;
        place-items: center;
        width: 34px;
        height: 34px;
        font-size: 16px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border: 1px solid var(--el-color-primary-light-7);
        border-radius: var(--art-control-radius);

        &.is-folder {
          color: var(--el-color-warning-dark-2);
          background: var(--el-color-warning-light-9);
          border-color: var(--el-color-warning-light-7);
        }

        &.is-button {
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
          border-color: var(--el-color-danger-light-7);
        }
      }

      .menu-identity-cell__copy,
      .menu-identity-cell__heading {
        min-width: 0;
      }

      .menu-identity-cell__heading {
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

      small {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      .menu-identity-cell__permission-count {
        flex: none;
        padding: 1px 6px;
        font-size: 10px;
        line-height: 17px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 999px;
      }
    }

    :deep(.menu-tree-row > td:first-child .cell) {
      display: flex;
      align-items: center;
    }

    :deep(.menu-tree-row .el-table__expand-icon) {
      display: inline-flex;
      flex: none;
      align-items: center;
      align-self: center;
      justify-content: center;
      margin-right: 6px;
    }

    :deep(.menu-tree-row .el-table__placeholder) {
      flex: none;
    }

    :deep(.menu-access-cell) {
      display: grid;
      min-width: 0;
      line-height: 19px;

      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      span {
        color: var(--el-text-color-regular);
      }

      small {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.menu-update-cell) {
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-secondary);
    }

    @media (width <= 1080px) {
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

      &__metrics {
        grid-template-columns: 1fr;

        article {
          border-right: 0 !important;
          border-bottom: 1px solid var(--el-border-color-lighter);

          &:last-child {
            border-bottom: 0;
          }
        }
      }
    }
  }
</style>
