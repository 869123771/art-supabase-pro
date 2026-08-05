<template>
  <div class="system-param-page">
    <section class="system-param-page__hero">
      <div>
        <h2>参数设置</h2>
        <p>
          统一管理系统运行参数、登录体验、安全策略与审计策略。支持分组维护、内置保护、缓存刷新与按键名读取，便于后续业务模块复用。
        </p>
      </div>
      <div class="system-param-page__hero-tags">
        <ElTag round>缓存项：{{ overview.stats.total }}</ElTag>
        <ElTag round>分组数：{{ overview.stats.groups }}</ElTag>
        <ElTag round>最近刷新：{{ overview.lastRefreshText }}</ElTag>
      </div>
    </section>

    <section class="system-param-page__stats">
      <div
        v-for="item in overview.statCards"
        :key="item.label"
        class="system-param-page__stat-card"
      >
        <div>
          <span>{{ item.label }}</span>
          <strong>{{ item.value }}</strong>
          <p>{{ item.description }}</p>
        </div>
        <span
          class="system-param-page__stat-icon"
          :style="{ color: item.color, backgroundColor: item.backgroundColor }"
        >
          <ArtSvgIcon :icon="item.icon" />
        </span>
      </div>
    </section>

    <div class="system-param-page__groups">
      <ElSegmented
        :model-value="table.searchQuery.groupCode"
        :options="groupSegmentOptions"
        @change="handleGroupFilter"
      />
    </div>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="table.headerActions"
      :table-header-props="{ layout: 'refresh,size,fullscreen,columns,settings' }"
      :table-props="{ height: '100%', showOverflowTooltip: true }"
    />

    <SystemParamDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ElMessage, ElTag } from 'element-plus'
  import { omit } from 'lodash-es'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import {
    deleteSystemParam,
    deleteSystemParamBatch,
    fetchGetSystemParamList,
    fetchSystemParamStats
  } from '@/api/system-manage'
  import { clearSystemParamCache } from '@/hooks/core/system-param/read-system-param'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import SystemParamDialog from './modules/system-param-dialog.vue'

  defineOptions({ name: 'SystemParam' })

  const { confirmAction } = useArtFeedback()

  type SystemParam = Api.SystemManage.SystemParamItem
  type SearchParams = Api.SystemManage.SystemParamSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: SystemParam) => Promise<void>
  }

  interface OverviewGroup {
    stats: Api.SystemManage.SystemParamStats
    lastRefreshText: ComputedRef<string>
    statCards: ComputedRef<
      Array<{
        label: string
        value: number
        description: string
        icon: string
        color: string
        backgroundColor: string
      }>
    >
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const userStore = useUserStore()
  const { getDictMap, isPlatformSuper } = storeToRefs(userStore)
  const groupOptions = computed(() => getDictMap.value.systemParamGroup ?? [])
  const typeOptions = computed(() => getDictMap.value.systemParamType ?? [])

  const overview: UnwrapNestedRefs<OverviewGroup> = reactive<OverviewGroup>({
    stats: {
      total: 0,
      enabled: 0,
      builtin: 0,
      groups: 0,
      groupCounts: {},
      lastRefreshTime: undefined
    },
    lastRefreshText: computed(() =>
      overview.stats.lastRefreshTime ? formatWithDayjs(overview.stats.lastRefreshTime) || '-' : '-'
    ),
    statCards: computed(() => [
      {
        label: '参数总量',
        value: overview.stats.total,
        description: '包括内置参数与业务扩展参数',
        icon: 'ri:database-2-line',
        color: '#3b82f6',
        backgroundColor: 'var(--el-color-primary-light-9)'
      },
      {
        label: '启用参数',
        value: overview.stats.enabled,
        description: '当前会参与读取和缓存的有效参数',
        icon: 'ri:checkbox-circle-line',
        color: '#14b8a6',
        backgroundColor: 'var(--el-color-success-light-9)'
      },
      {
        label: '内置参数',
        value: overview.stats.builtin,
        description: '平台基础参数，建议谨慎修改',
        icon: 'ri:shield-keyhole-line',
        color: '#f59e0b',
        backgroundColor: 'var(--el-color-warning-light-9)'
      },
      {
        label: '参数分组',
        value: overview.stats.groups,
        description: '可按业务域划分不同配置命名空间',
        icon: 'ri:folder-settings-line',
        color: '#64748b',
        backgroundColor: 'var(--default-bg-color)'
      }
    ])
  })

  const groupSegmentOptions = computed(() => [
    {
      label: `全部分组 (${overview.stats.total})`,
      value: ''
    },
    ...groupOptions.value.map((group) => {
      const value = String(group.value)
      return {
        label: `${group.label} (${overview.stats.groupCounts[value] ?? 0})`,
        value
      }
    })
  ])

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      keyword: '',
      groupCode: '',
      paramType: undefined
    },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '关键字',
        key: 'keyword',
        type: 'input',
        props: {
          placeholder: '请输入参数名称、键名或备注'
        }
      },
      {
        label: '分组',
        key: 'groupCode',
        type: 'select',
        props: {
          clearable: true,
          placeholder: '请选择分组',
          options: groupOptions.value
        }
      },
      {
        label: '参数类型',
        key: 'paramType',
        type: 'select',
        props: {
          clearable: true,
          placeholder: '请选择参数类型',
          options: typeOptions.value
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() =>
      (
        [
          {
            type: 'add',
            label: '新增参数',
            // permission: 'System:SystemParam:Add',
            onClick: () => openDialog()
          },
          {
            type: 'delete',
            permission: 'System:SystemParam:Delete',
            disabled: ({ selectedRows }) => selectedRows.every((row) => Boolean(row.builtin)),
            content: ({ selectedRows }: ArtTableQueryHeaderActionContext) => {
              const removableCount = selectedRows.filter((row) => !row.builtin).length
              return `确定删除选中的 ${removableCount} 个非内置参数吗？内置参数会被自动跳过。`
            },
            onClick: async ({ selectedRows }) => {
              const ids = selectedRows
                .filter((row) => !row.builtin)
                .map((row) => String(row.id))
                .filter(Boolean)
              if (!ids.length) {
                ElMessage.warning('请选择非内置参数')
                return
              }
              await deleteSystemParamBatch(ids)
              await refreshAfterRemove()
            }
          },
          {
            key: 'refresh-cache',
            label: '刷新缓存',
            icon: 'ri:refresh-line',
            buttonProps: { plain: true },
            onClick: async () => {
              await userStore.fetchDictList()
              clearSystemParamCache()
              await refreshPage()
              ElMessage.success('缓存已刷新')
            }
          }
        ] as ArtTableQueryHeaderAction[]
      ).filter((action) => isPlatformSuper.value || action.key === 'refresh-cache')
    )
  })

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchGetSystemParamList({
      ...params,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<SystemParam>[] =>
    (
      [
        {
          type: 'selection',
          width: 50,
          fixed: 'left',
          reserveSelection: true,
          selectable: (row: SystemParam) => isPlatformSuper.value && !row.builtin
        },
        {
          type: 'globalIndex',
          label: '序号',
          width: 80
        },
        {
          prop: 'paramName',
          label: '参数名称',
          minWidth: 180
        },
        {
          prop: 'paramKey',
          label: '参数键名',
          minWidth: 240
        },
        {
          prop: 'groupCode',
          label: '分组',
          width: 120,
          dict: { code: 'systemParamGroup', display: 'text' }
        },
        {
          prop: 'paramType',
          label: '类型',
          width: 120,
          dict: { code: 'systemParamType', display: 'auto' }
        },
        {
          prop: 'paramValue',
          label: '当前值',
          minWidth: 160
        },
        {
          prop: 'enabled',
          label: '状态',
          width: 100,
          formatter: (row) => (
            <ElTag type={row.enabled ? 'success' : 'info'} effect="light">
              {row.enabled ? '启用' : '停用'}
            </ElTag>
          )
        },
        {
          prop: 'builtin',
          label: '属性',
          width: 100,
          formatter: (row) => (
            <ElTag type={row.builtin ? 'warning' : 'info'} effect="light">
              {row.builtin ? '内置' : '自定义'}
            </ElTag>
          )
        },
        {
          prop: 'updateTime',
          label: '最后更新',
          width: 180,
          formatter: (row) => formatWithDayjs(row.updateTime)
        },
        {
          prop: 'updateBy',
          label: '最后更新人',
          width: 180
        },
        {
          prop: 'operation',
          label: '操作',
          width: 120,
          fixed: 'right',
          formatter: (row) =>
            isPlatformSuper.value ? (
              <div class="system-param-page__operation">
                <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
                <ArtButtonTable
                  type="delete"
                  disabled={row.builtin}
                  onClick={() => void handleDelete(row)}
                />
              </div>
            ) : null
        }
      ] as ColumnOption<SystemParam>[]
    ).filter((column) => isPlatformSuper.value || column.prop !== 'operation')

  const openDialog = (row?: SystemParam): void => {
    void dialogRef.value?.handleOpen(row ? (omit(row, []) as SystemParam) : undefined)
  }

  const handleDelete = async (row: SystemParam): Promise<void> => {
    if (!row.id || row.builtin) {
      ElMessage.warning('内置参数不允许删除')
      return
    }

    try {
      await confirmAction(`确定删除参数“${row.paramName}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteSystemParam(row.id)
      await refreshAfterRemove()
    } catch {
      // 用户取消删除，无需提示。
    }
  }

  const handleGroupFilter = async (groupCode: string | number): Promise<void> => {
    table.searchQuery.groupCode = String(groupCode)
    await tableQueryRef.value?.getData()
  }

  const loadStats = async (): Promise<void> => {
    const { data } = await fetchSystemParamStats()
    Object.assign(overview.stats, data, {
      lastRefreshTime: data.lastRefreshTime || new Date().toISOString()
    })
  }

  const refreshPage = async (): Promise<void> => {
    await Promise.all([tableQueryRef.value?.refreshData(), loadStats()])
  }

  const refreshAfterRemove = async (): Promise<void> => {
    clearSystemParamCache()
    await Promise.all([tableQueryRef.value?.refreshRemove(), loadStats()])
  }

  const handleSaveSuccess = (type: DialogType): void => {
    clearSystemParamCache()
    void Promise.all([
      type === 'add' ? tableQueryRef.value?.refreshCreate() : tableQueryRef.value?.refreshUpdate(),
      loadStats()
    ])
  }

  onMounted(() => {
    void userStore.ensureDictLoaded('systemParamGroup')
    void userStore.ensureDictLoaded('systemParamType')
    void loadStats()
  })
</script>

<style scoped lang="scss">
  .system-param-page {
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-height: 100%;

    &__hero {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      padding: 24px 28px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--art-surface-radius);

      h2 {
        margin: 0 0 12px;
        font-size: 24px;
        font-weight: 700;
        line-height: 1.2;
        color: var(--art-text-gray-900);
      }

      p {
        max-width: 780px;
        margin: 0;
        font-size: 14px;
        line-height: 1.9;
        color: var(--art-text-gray-600);
      }
    }

    &__hero-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      justify-content: flex-end;
      min-width: 360px;
    }

    &__stats {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;
    }

    &__stat-card {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      min-height: 112px;
      padding: 22px 24px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--art-surface-radius);

      span {
        font-size: 14px;
        color: var(--art-text-gray-600);
      }

      strong {
        display: block;
        margin-top: 10px;
        font-size: 30px;
        line-height: 1;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 14px 0 0;
        font-size: 13px;
        color: var(--art-text-gray-500);
      }
    }

    &__stat-icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 44px;
      height: 44px;
      font-size: 22px !important;
      background: var(--el-fill-color-lighter);
      border-radius: var(--art-surface-radius);
    }

    &__groups {
      padding: 12px 16px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--art-surface-radius);
    }

    &__operation {
      display: inline-flex;
      gap: 8px;
      align-items: center;
    }

    :deep(.art-table-query) {
      flex: 1;
      min-height: 0;
    }

    &__groups :deep(.el-segmented) {
      --el-segmented-item-selected-color: var(--el-color-white);
      --el-segmented-item-selected-bg-color: var(--el-color-primary);

      max-width: 100%;

      .el-segmented__group {
        flex-wrap: wrap;
      }

      .el-segmented__item {
        color: var(--el-color-primary);

        &.is-selected {
          color: var(--el-color-white);
        }
      }
    }
  }

  @media (width <= 1200px) {
    .system-param-page {
      &__stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }

  @media (width <= 768px) {
    .system-param-page {
      &__hero {
        flex-direction: column;
      }

      &__hero-tags {
        justify-content: flex-start;
        min-width: 0;
      }

      &__stats {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
