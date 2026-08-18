<template>
  <div class="number-rule-page business-workspace-page art-full-height">
    <MasterDeleteProcessingNotice
      action-hint="已按关联菜单过滤编号场景；请调整或迁移规则后返回。"
    />
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="NUMBER GOVERNANCE"
      title="编号规则"
      description="统一维护运输单据、财务单据、基础资料和车辆业务的编码方式。系统取号由数据库事务完成，支持租户隔离、周期重置与并发防重。"
      icon="ri:hashtag"
      :tags="[
        {
          label: isPlatformSuper ? '平台维护视图' : '本租户只读视图',
          type: isPlatformSuper ? 'primary' : 'info'
        },
        { label: `覆盖租户：${overview.stats.tenantCount}` },
        { label: `最近更新：${overview.lastUpdateText}` }
      ]"
      :metrics="overview.cards"
    />

    <section class="number-rule-page__category art-card-xs">
      <ElSegmented
        :model-value="table.searchQuery.category ?? ''"
        :options="categorySegments"
        @change="handleCategoryChange"
      />
    </section>

    <div class="number-rule-page__workspace">
      <aside v-if="isDesktopMenuLayout" class="number-rule-page__menu-panel">
        <DocumentNumberMenuFilter
          :data="menuTree"
          :scenes="scenes"
          :selected-menu-id="selectedMenuId"
          :loading="menuFilterLoading"
          @select="handleMenuSelect"
          @refresh="handleMenuRefresh"
        />
      </aside>

      <div class="number-rule-page__table-workspace">
        <section v-if="!isDesktopMenuLayout" class="number-rule-page__mobile-menu art-card-xs">
          <span aria-hidden="true"><ArtSvgIcon icon="ri:node-tree" /></span>
          <div>
            <small>当前功能范围</small>
            <strong>{{ selectedMenuLabel }}</strong>
          </div>
          <ElButton type="primary" plain @click="openMenuDrawer">
            <ArtSvgIcon icon="ri:filter-3-line" />
            菜单筛选
          </ElButton>
        </section>

        <ArtTableQuery
          ref="tableQueryRef"
          focusable
          v-model="table.searchQuery"
          :search-items="table.searchItems"
          :header-actions="table.headerActions"
          :api-fn="fetchTableData"
          :columns-factory="columnsFactory"
          :table-header-props="{ layout: 'refresh,size,fullscreen,columns,settings' }"
          :table-props="tableProps"
        />
      </div>
    </div>

    <DocumentNumberDialog v-if="isPlatformSuper" ref="dialogRef" @success="handleSaveSuccess" />
    <DocumentNumberCreateDialog
      v-if="isPlatformSuper"
      ref="createDialogRef"
      @success="handleSaveSuccess"
    />
    <ArtDrawer ref="menuDrawerRef">
      <DocumentNumberMenuFilter
        class="number-rule-page__drawer-filter"
        :data="menuTree"
        :scenes="scenes"
        :selected-menu-id="selectedMenuId"
        :loading="menuFilterLoading"
        @select="handleDrawerMenuSelect"
        @refresh="handleMenuRefresh"
      />
    </ArtDrawer>
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { useMediaQuery } from '@vueuse/core'
  import { ElTag } from 'element-plus'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import type { AppRouteRecord } from '@/types/router'
  import {
    fetchDocumentNumberRuleList,
    fetchDocumentNumberRuleStats,
    fetchDocumentNumberSceneList
  } from '@/api/document-number'
  import { fetchGetEnableMenuList, fetchGetEnableTenantList } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import TreeUtils from '@/utils/tree'
  import DocumentNumberDialog from './modules/document-number-dialog.vue'
  import DocumentNumberCreateDialog from './modules/document-number-create-dialog.vue'
  import DocumentNumberMenuFilter from './modules/document-number-menu-filter.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'

  defineOptions({ name: 'DocumentNumberRule' })

  type NumberRule = Api.SystemManage.DocumentNumberRuleItem
  type SearchParams = Api.SystemManage.DocumentNumberRuleSearchParams
  type Category = Api.SystemManage.DocumentNumberCategory
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row: NumberRule) => Promise<void>
  }

  interface CreateDialogExpose {
    handleOpen: () => Promise<void>
  }

  interface OverviewGroup {
    stats: Api.SystemManage.DocumentNumberRuleStats
    lastUpdateText: ComputedRef<string>
    cards: ComputedRef<BusinessWorkspaceMetric[]>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const route = useRoute()
  const dialogRef = ref<DialogExpose>()
  const createDialogRef = ref<CreateDialogExpose>()
  const menuDrawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const tenantOptions = ref<Array<{ label: string; value: string }>>([])
  const menuTree = ref<AppRouteRecord[]>([])
  const scenes = ref<Api.SystemManage.DocumentNumberSceneItem[]>([])
  const selectedMenuId = ref(typeof route.query.menuId === 'string' ? route.query.menuId : '')
  const menuFilterLoading = ref(false)
  const isDesktopMenuLayout = useMediaQuery('(min-width: 1201px)')
  const treeUtils = new TreeUtils({ idKey: 'id', parentKey: 'parentId', childrenKey: 'children' })
  const userStore = useUserStore()
  const { getDictMap, isPlatformSuper } = storeToRefs(userStore)

  const overview: UnwrapNestedRefs<OverviewGroup> = reactive<OverviewGroup>({
    stats: {
      total: 0,
      automatic: 0,
      manual: 0,
      tenantCount: 0,
      categoryCounts: { business_document: 0, master_data: 0, vehicle: 0 }
    },
    lastUpdateText: computed(() => formatWithDayjs(overview.stats.lastUpdateTime) || '-'),
    cards: computed(() => [
      {
        label: '规则总量',
        value: overview.stats.total,
        description: '已接入数据库编号引擎的业务字段',
        icon: 'ri:file-list-3-line',
        tone: 'primary'
      },
      {
        label: '自动编码',
        value: overview.stats.automatic,
        description: '保存时由系统生成正式唯一编号',
        icon: 'ri:magic-line',
        tone: 'success'
      },
      {
        label: '手工填写',
        value: overview.stats.manual,
        description: '由业务人员填写并接受唯一性校验',
        icon: 'ri:edit-box-line',
        tone: 'warning'
      },
      {
        label: '业务单据',
        value: overview.stats.categoryCounts.business_document,
        description: '运输、合同、财务及异常工单编号',
        icon: 'ri:bill-line',
        tone: 'info'
      }
    ])
  })

  const categoryOptions = computed(() => getDictMap.value.documentNumberCategory ?? [])
  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: String(item.value) === 'true'
    }))
  )
  const categorySegments = computed(() => [
    { label: `全部 (${overview.stats.total})`, value: '' },
    ...categoryOptions.value.map((item) => {
      const value = String(item.value) as Category
      return {
        label: `${item.label} (${overview.stats.categoryCounts[value] ?? 0})`,
        value
      }
    })
  ])
  const selectedMenu = computed(() =>
    selectedMenuId.value ? treeUtils.findNode(menuTree.value, selectedMenuId.value) : null
  )
  const selectedMenuLabel = computed(() =>
    selectedMenu.value
      ? String(selectedMenu.value.meta?.title || selectedMenu.value.name || '未命名菜单')
      : '全部功能'
  )
  const selectedRuleKeys = computed(() => {
    if (!selectedMenuId.value) return []
    const menuIds = new Set(
      treeUtils
        .getDescendants(menuTree.value, selectedMenuId.value, true)
        .map((menu) => menu.id)
        .filter((id): id is string => Boolean(id))
    )
    return scenes.value.filter((scene) => menuIds.has(scene.menuId)).map((scene) => scene.ruleKey)
  })

  const table = reactive({
    searchQuery: {
      keyword: '',
      tenantId: undefined,
      category: undefined,
      autoEnabled: undefined
    } as SearchParams,
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '关键字',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '搜索名称、规则键或目标表' }
      },
      ...(isPlatformSuper.value
        ? [
            {
              label: '生效租户',
              key: 'tenantId',
              type: 'select' as const,
              props: {
                clearable: true,
                filterable: true,
                options: tenantOptions.value,
                placeholder: '全部租户'
              }
            }
          ]
        : []),
      {
        label: '生成方式',
        key: 'autoEnabled',
        type: 'select',
        props: { clearable: true, options: booleanOptions.value, placeholder: '全部方式' }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() =>
      isPlatformSuper.value
        ? [
            {
              type: 'add',
              label: '新增规则',
              onClick: () => void createDialogRef.value?.handleOpen()
            }
          ]
        : []
    )
  })

  const tableProps: ArtTableQueryTableProps = {
    rowKey: 'id',
    tableLayout: 'fixed',
    height: '100%',
    showOverflowTooltip: true,
    emptyText: '暂无符合条件的编号规则',
    emptyDescription: '可调整租户、业务分类或生成方式后重试。'
  }

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchDocumentNumberRuleList({
      ...params,
      ruleKeys: selectedMenuId.value ? selectedRuleKeys.value : undefined,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<NumberRule>[] => [
    {
      prop: 'ruleName',
      label: '规则定义',
      minWidth: 240,
      fixed: 'left',
      formatter: (row) => (
        <div class="number-rule-identity">
          <span class="number-rule-identity__icon" aria-hidden="true">
            <ArtSvgIcon icon="ri:hashtag" />
          </span>
          <div>
            <strong title={row.ruleName}>{row.ruleName}</strong>
            <code title={row.ruleKey} translate="no">
              {row.ruleKey}
            </code>
          </div>
        </div>
      )
    },
    {
      prop: 'scene',
      label: '功能菜单',
      minWidth: 230,
      formatter: (row) => (
        <div class="number-rule-menu">
          <strong title={resolveMenuPath(row.scene?.menuId)}>
            {resolveMenuPath(row.scene?.menuId) || '--'}
          </strong>
          <small>
            {row.scene?.fieldLabel || row.targetColumn} · {row.scene?.menu?.component || '--'}
          </small>
        </div>
      )
    },
    ...(isPlatformSuper.value
      ? [
          {
            prop: 'tenant',
            label: '生效租户',
            minWidth: 150,
            formatter: (row: NumberRule) => (
              <div class="number-rule-tenant">
                <strong>{row.tenant?.tenantName || '--'}</strong>
                <small>{row.tenant?.tenantCode || '--'}</small>
              </div>
            )
          } satisfies ColumnOption<NumberRule>
        ]
      : []),
    {
      prop: 'category',
      label: '业务分类',
      width: 110,
      formatter: (row) => (
        <ArtDictDisplay dictCode="documentNumberCategory" value={row.category} display="tag" />
      )
    },
    {
      prop: 'template',
      label: '模板与预览',
      minWidth: 235,
      formatter: (row) => (
        <div class="number-rule-template">
          <code title={row.template} translate="no">
            {row.template}
          </code>
          <span title={row.preview} translate="no">
            {row.preview || '--'}
          </span>
        </div>
      )
    },
    {
      prop: 'autoEnabled',
      label: '生成方式',
      width: 110,
      formatter: (row) => (
        <ElTag type={row.autoEnabled ? 'success' : 'warning'} effect="light">
          {row.autoEnabled ? '自动编码' : '手工填写'}
        </ElTag>
      )
    },
    {
      prop: 'counter',
      label: '当前计数',
      minWidth: 132,
      formatter: (row) => (
        <div class="number-rule-counter">
          <strong>{row.currentValue ?? 0}</strong>
          <small>
            {row.currentPeriodKey || '永久累计'} · V{row.ruleVersion}
          </small>
        </div>
      )
    },
    {
      prop: 'resetCycle',
      label: '重置周期',
      width: 108,
      formatter: (row) => (
        <ArtDictDisplay dictCode="documentNumberResetCycle" value={row.resetCycle} display="text" />
      )
    },
    {
      prop: 'updateTime',
      label: '更新信息',
      minWidth: 168,
      formatter: (row) => (
        <div class="number-rule-update">
          <span>{formatWithDayjs(row.updateTime) || '--'}</span>
          <small>{row.updateBy || '系统维护'}</small>
        </div>
      )
    },
    ...(isPlatformSuper.value
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 88,
            fixed: 'right',
            formatter: (row: NumberRule) => (
              <ArtButtonTable type="edit" onClick={() => void dialogRef.value?.handleOpen(row)} />
            )
          } satisfies ColumnOption<NumberRule>
        ]
      : [])
  ]

  const loadStats = async (): Promise<void> => {
    const { data } = await fetchDocumentNumberRuleStats()
    Object.assign(overview.stats, data)
  }

  const loadTenantOptions = async (): Promise<void> => {
    if (!isPlatformSuper.value) return
    const { data } = await fetchGetEnableTenantList()
    tenantOptions.value = (data ?? []).map((tenant) => ({
      label: `${tenant.tenantName}（${tenant.tenantCode}）`,
      value: String(tenant.id)
    }))
  }

  const loadMenuTree = async (): Promise<void> => {
    const { data } = await fetchGetEnableMenuList()
    menuTree.value = treeUtils.listToTree((data ?? []).filter((menu) => menu.type !== 'button'))
  }

  const loadScenes = async (): Promise<void> => {
    const { data } = await fetchDocumentNumberSceneList()
    scenes.value = data ?? []
  }

  const resolveMenuPath = (menuId?: string): string => {
    if (!menuId) return ''
    return treeUtils
      .getAncestors(menuTree.value, menuId)
      .map((menu) => String(menu.meta?.title || menu.name || '未命名菜单'))
      .join(' / ')
  }

  const handleCategoryChange = async (value: string | number): Promise<void> => {
    table.searchQuery.category = (String(value) || undefined) as Category | undefined
    await tableQueryRef.value?.getData()
  }

  const handleMenuSelect = async (menuId: string): Promise<void> => {
    if (selectedMenuId.value === menuId) return
    selectedMenuId.value = menuId
    await tableQueryRef.value?.getData()
  }

  const handleDrawerMenuSelect = async (menuId: string): Promise<void> => {
    await handleMenuSelect(menuId)
    await menuDrawerRef.value?.handleClose()
  }

  const handleMenuRefresh = async (): Promise<void> => {
    menuFilterLoading.value = true
    try {
      await Promise.all([loadMenuTree(), loadScenes()])
      if (selectedMenuId.value && !treeUtils.findNode(menuTree.value, selectedMenuId.value)) {
        selectedMenuId.value = ''
      }
      await tableQueryRef.value?.getData()
    } finally {
      menuFilterLoading.value = false
    }
  }

  const openMenuDrawer = async (): Promise<void> => {
    await menuDrawerRef.value?.handleOpen(
      {},
      {
        title: '筛选功能菜单',
        subtitle: '按业务菜单树定位编号规则，选择目录时自动包含全部下级菜单。',
        size: 'sm',
        contentHeight: 'calc(100vh - 118px)',
        showFooter: false,
        drawerProps: {
          appendToBody: true,
          bodyClass: 'document-number-menu-filter-drawer__body'
        }
      }
    )
  }

  const handleSaveSuccess = (): void => {
    void Promise.all([tableQueryRef.value?.refreshUpdate(), loadStats()])
  }

  onMounted(async () => {
    menuFilterLoading.value = true
    try {
      await Promise.all([
        userStore.ensureDictLoaded('documentNumberCategory'),
        userStore.ensureDictLoaded('documentNumberResetCycle'),
        loadStats(),
        loadTenantOptions(),
        loadMenuTree(),
        loadScenes()
      ])
      await tableQueryRef.value?.getData()
    } finally {
      menuFilterLoading.value = false
    }
  })

  watch(
    () => route.query.menuId,
    async (menuId) => {
      selectedMenuId.value = typeof menuId === 'string' ? menuId : ''
      await tableQueryRef.value?.getData()
    }
  )
</script>

<style scoped lang="scss">
  .number-rule-page {
    gap: 12px;
    min-width: 0;
    overflow: hidden;

    &__hero {
      display: flex;
      gap: 18px;
      align-items: flex-start;
      justify-content: space-between;
      padding: 16px 20px;

      h1 {
        margin: 0 0 6px;
        font-size: 22px;
        line-height: 1.2;
        color: var(--art-text-gray-900);
      }

      p {
        max-width: 800px;
        margin: 0;
        font-size: 14px;
        line-height: 1.55;
        color: var(--art-text-gray-600);
      }
    }

    &__hero-identity {
      display: flex;
      gap: 16px;
      min-width: 0;
    }

    &__hero-icon {
      display: grid;
      flex: 0 0 46px;
      place-items: center;
      width: 46px;
      height: 46px;
      font-size: 22px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--art-surface-radius);
    }

    &__eyebrow {
      display: block;
      margin-bottom: 6px;
      font-size: 11px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.12em;
    }

    &__hero-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
      min-width: 340px;
    }

    &__stats {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
    }

    &__stat {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      min-height: 88px;
      padding: 14px 16px;

      span {
        font-size: 13px;
        color: var(--art-text-gray-600);
      }

      strong {
        display: block;
        margin-top: 5px;
        font-size: 24px;
        line-height: 1;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 7px 0 0;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }
    }

    &__stat-icon {
      display: grid;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 19px !important;
      border-radius: var(--art-surface-radius);
    }

    &__category {
      flex: none;
      padding: 8px 12px;
      overflow-x: auto;
    }

    &__workspace {
      display: grid;
      flex: 1 1 auto;
      grid-template-rows: minmax(0, 1fr);
      grid-template-columns: 264px minmax(0, 1fr);
      gap: 12px;
      min-width: 0;
      min-height: 0;
      overflow: hidden;
    }

    &__menu-panel,
    &__table-workspace {
      min-width: 0;
      height: 100%;
      min-height: 0;
      overflow: hidden;
    }

    &__table-workspace {
      display: flex;
      flex-direction: column;
    }

    &__mobile-menu {
      display: flex;
      flex: none;
      gap: 11px;
      align-items: center;
      min-width: 0;
      padding: 12px 14px;
      margin-bottom: 12px;
      background: linear-gradient(145deg, var(--el-color-primary-light-9), var(--el-bg-color) 76%);

      > span {
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

    &__drawer-filter {
      height: 100%;
      border: 0;
      border-radius: 0;
    }

    :deep(.art-table-query) {
      flex: 1 1 auto;
      height: 100%;
      min-height: 0;
      overflow: hidden;
    }
  }

  :deep(.number-rule-identity) {
    display: flex;
    gap: 10px;
    align-items: center;
    min-width: 0;

    div {
      min-width: 0;
    }

    strong,
    code {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      color: var(--art-text-gray-900);
    }

    code {
      margin-top: 3px;
      font-size: 11px;
      color: var(--art-text-gray-500);
    }
  }

  :deep(.number-rule-identity__icon) {
    display: grid;
    flex: 0 0 34px;
    place-items: center;
    width: 34px;
    height: 34px;
    color: var(--el-color-primary);
    background: var(--el-color-primary-light-9);
    border-radius: var(--art-control-radius);
  }

  :deep(.number-rule-tenant),
  :deep(.number-rule-menu),
  :deep(.number-rule-template),
  :deep(.number-rule-counter),
  :deep(.number-rule-update) {
    strong,
    span,
    code,
    small {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      margin-top: 3px;
      color: var(--art-text-gray-500);
    }
  }

  :deep(.number-rule-template) {
    code {
      color: var(--art-text-gray-800);
    }

    span {
      margin-top: 4px;
      font-size: 12px;
      color: var(--el-color-primary);
    }
  }

  :deep(.number-rule-menu) {
    strong {
      color: var(--art-text-gray-900);
    }

    small {
      max-width: 100%;
    }
  }

  :deep(.number-rule-counter strong) {
    font-size: 16px;
    font-variant-numeric: tabular-nums;
  }

  @media (width <= 1100px) {
    .number-rule-page {
      &__stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__hero {
        flex-direction: column;
      }

      &__hero-tags {
        justify-content: flex-start;
        min-width: 0;
      }
    }
  }

  @media (width <= 640px) {
    .number-rule-page__stats {
      grid-template-columns: 1fr;
    }
  }

  :global(.document-number-menu-filter-drawer__body) {
    --art-drawer-content-padding: 0;

    padding: 0 !important;
    overflow: hidden !important;
  }

  :global(.art-table-focus-page .number-rule-page__workspace) {
    display: grid !important;
    grid-template-columns: 264px minmax(0, 1fr) !important;
    gap: 12px !important;
  }

  :global(.art-table-focus-page .number-rule-page__menu-panel.art-table-focus-hidden) {
    display: block !important;
  }
</style>
