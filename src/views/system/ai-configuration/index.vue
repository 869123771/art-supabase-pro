<template>
  <div class="ai-configuration business-workspace-page">
    <BusinessWorkspaceHeader
      eyebrow="AI CONTROL PLANE"
      title="AI 配置中心"
      description="集中管理能力开关、模型路由、生成参数、超时策略与调用配额，修改后新请求即时生效。"
      icon="ri:equalizer-2-line"
      :tags="[
        {
          label: canManage ? '可维护' : '只读模式',
          type: canManage ? 'success' : 'info',
          effect: 'light'
        }
      ]"
      :metrics="metricCards"
    >
      <template #actions>
        <ElTooltip content="刷新配置" placement="bottom">
          <ArtIconButton
            icon="ri:refresh-line"
            circle
            :class="{ 'ai-configuration__refreshing': overview.loading }"
            @click="refreshAll"
          />
        </ElTooltip>
      </template>
    </BusinessWorkspaceHeader>

    <section class="ai-configuration__governance art-card-xs">
      <div>
        <ArtSvgIcon icon="ri:shield-keyhole-line" />
        <div>
          <strong>密钥与策略分离</strong>
          <span
            >数据库只保存非敏感运行参数；API Key 与服务地址由 Supabase Edge Function Secrets
            托管。</span
          >
        </div>
      </div>
      <ElTag type="warning" effect="plain" round>不存储任何 API Key</ElTag>
    </section>

    <ArtTableQuery
      ref="tableQueryRef"
      focusable
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :table-header-props="{ layout: 'refresh,size,fullscreen,columns,settings' }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无匹配的 AI 运行配置',
        emptyDescription: '可调整能力场景、启用状态或模型名称后重新查询。'
      }"
    />

    <AiFeatureConfigDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { ElMessage, ElTag } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import type { ColumnOption } from '@/types'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchAiFeatureConfigList,
    type AiFeatureConfig,
    type AiFeatureConfigSearchParams
  } from '@/api/ai-configuration'
  import AiFeatureConfigDialog from './modules/ai-feature-config-dialog.vue'

  defineOptions({ name: 'AiConfiguration' })

  interface DialogExpose {
    handleOpen: (data: { editData: AiFeatureConfig }) => Promise<void>
  }

  interface TableGroup {
    searchQuery: Partial<AiFeatureConfigSearchParams>
    searchItems: ComputedRef<SearchFormItem[]>
  }

  const userStore = useUserStore()
  const { getDictMap, isPlatformSuper } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const overview = reactive<{ loading: boolean; rows: AiFeatureConfig[] }>({
    loading: false,
    rows: []
  })

  const canManage = computed(() => isPlatformSuper.value)

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      feature: '',
      enabled: '',
      keyword: ''
    },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '能力场景',
        key: 'feature',
        type: 'select',
        props: {
          options: getDictMap.value.aiRunFeature ?? [],
          placeholder: '请选择能力场景',
          clearable: true
        }
      },
      {
        label: '启用状态',
        key: 'enabled',
        type: 'select',
        props: {
          options: (getDictMap.value.commonBoolean ?? []).map((item) => ({
            ...item,
            value: item.value === 'true'
          })),
          placeholder: '请选择启用状态',
          clearable: true
        }
      },
      {
        label: '模型名称',
        key: 'keyword',
        type: 'input',
        props: { placeholder: '搜索主模型、视觉模型或备用模型', clearable: true }
      }
    ])
  })

  const metricCards = computed<BusinessWorkspaceMetric[]>(() => {
    const enabled = overview.rows.filter((item) => item.enabled).length
    const averageTimeout = overview.rows.length
      ? Math.round(
          overview.rows.reduce((total, item) => total + Number(item.timeoutMs), 0) /
            overview.rows.length /
            1000
        )
      : 0
    const dailyQuota = overview.rows.reduce(
      (total, item) => total + Number(item.rateLimitPerDay),
      0
    )
    const inherited = overview.rows.filter((item) => item.inherited).length
    return [
      {
        label: '能力场景',
        value: `${overview.rows.length} 项`,
        description: inherited ? `${inherited} 项继承平台默认配置` : '统一纳入运行策略管理',
        icon: 'ri:apps-2-line',
        tone: 'primary'
      },
      {
        label: '已启用能力',
        value: `${enabled} 项`,
        description: `${Math.max(overview.rows.length - enabled, 0)} 项当前停用`,
        icon: 'ri:checkbox-circle-line',
        tone: 'success'
      },
      {
        label: '平均超时',
        value: `${averageTimeout} 秒`,
        description: `租户总日配额 ${dailyQuota.toLocaleString('zh-CN')} 次`,
        icon: 'ri:timer-flash-line',
        tone: 'warning'
      }
    ]
  })

  async function fetchTableData(params: AiFeatureConfigSearchParams) {
    return await fetchAiFeatureConfigList(params)
  }

  async function loadOverview(): Promise<void> {
    overview.loading = true
    try {
      const result = await fetchAiFeatureConfigList({
        current: 1,
        size: 100
      })
      overview.rows = result.data ?? []
    } finally {
      overview.loading = false
    }
  }

  async function refreshAll(): Promise<void> {
    if (overview.loading) return
    await Promise.all([loadOverview(), tableQueryRef.value?.refreshData()])
    ElMessage.success('AI 配置已刷新')
  }

  function openEdit(row: AiFeatureConfig): void {
    void dialogRef.value?.handleOpen({ editData: row })
  }

  async function handleSaveSuccess(): Promise<void> {
    await Promise.all([loadOverview(), tableQueryRef.value?.refreshUpdate()])
  }

  function formatSeconds(value: number): string {
    return `${(Number(value) / 1000).toFixed(Number(value) % 1000 === 0 ? 0 : 1)} 秒`
  }

  function getSecondaryRouteSummary(row: AiFeatureConfig): string {
    const routes = [
      row.visionModel ? `视觉：${row.visionModel}` : '',
      row.fallbackModel ? `备用：${row.fallbackModel}` : ''
    ].filter(Boolean)
    return routes.length ? routes.join(' · ') : '单模型路由'
  }

  const columnsFactory = (): ColumnOption<AiFeatureConfig>[] =>
    [
      { type: 'globalIndex', label: '序号', width: 76 },
      {
        prop: 'feature',
        label: '能力场景',
        minWidth: 135,
        dict: { code: 'aiRunFeature', display: 'text' }
      },
      {
        prop: 'inherited',
        label: '配置来源',
        width: 108,
        formatter: (row: AiFeatureConfig) => (
          <ElTag type={row.inherited ? 'info' : 'primary'} effect="plain" round>
            {row.inherited ? '平台默认' : canManage.value ? '平台配置' : '租户配置'}
          </ElTag>
        )
      },
      {
        prop: 'enabled',
        label: '状态',
        width: 90,
        formatter: (row: AiFeatureConfig) => (
          <span class={row.enabled ? 'text-success' : 'text-g-500'}>
            {row.enabled ? '● 已启用' : '○ 已停用'}
          </span>
        )
      },
      {
        prop: 'provider',
        label: '服务协议',
        minWidth: 145,
        dict: { code: 'aiProvider', display: 'auto' }
      },
      {
        prop: 'model',
        label: '模型路由',
        minWidth: 235,
        formatter: (row: AiFeatureConfig) => (
          <div class="ai-configuration__model-cell">
            <strong title={row.model}>{row.model}</strong>
            <span title={getSecondaryRouteSummary(row)}>{getSecondaryRouteSummary(row)}</span>
          </div>
        )
      },
      {
        prop: 'timeoutMs',
        label: '超时 / 重试',
        width: 120,
        formatter: (row: AiFeatureConfig) => (
          <span>
            {formatSeconds(row.timeoutMs)} / {row.maxRetries} 次
          </span>
        )
      },
      {
        prop: 'generation',
        label: '生成参数',
        width: 145,
        formatter: (row: AiFeatureConfig) => (
          <span>
            T {Number(row.temperature).toFixed(2)} · {row.maxTokens} Token
          </span>
        )
      },
      {
        prop: 'quota',
        label: '调用配额',
        width: 145,
        formatter: (row: AiFeatureConfig) => (
          <span>
            {row.rateLimitPerMinute}/分钟 · {row.rateLimitPerDay}/天
          </span>
        )
      },
      {
        prop: 'updateTime',
        label: '最近更新',
        width: 170,
        formatter: (row: AiFeatureConfig) => (
          <span>{dayjs(row.updateTime).format('YYYY-MM-DD HH:mm:ss')}</span>
        )
      },
      {
        prop: 'operation',
        label: '操作',
        width: 78,
        fixed: 'right',
        formatter: (row: AiFeatureConfig) => (
          <ArtButtonTable type="edit" onClick={() => openEdit(row)} />
        )
      }
    ].filter(
      (column) => canManage.value || column.prop !== 'operation'
    ) as ColumnOption<AiFeatureConfig>[]

  onMounted(async () => {
    await Promise.all([userStore.fetchDictList(), loadOverview()])
  })
</script>

<style scoped lang="scss">
  .ai-configuration {
    display: grid;
    gap: 16px;
    width: 100%;
    min-width: 0;
    max-width: 100%;
    padding-bottom: 20px;
    overflow: hidden;

    > * {
      min-width: 0;
      max-width: 100%;
    }

    :deep(.art-table-query),
    :deep(.art-search-bar),
    :deep(.art-table-card) {
      width: 100%;
      min-width: 0;
      max-width: 100%;
    }

    &__hero,
    &__hero-main,
    &__hero-actions,
    &__metrics article,
    &__governance,
    &__governance > div {
      display: flex;
      align-items: center;
    }

    &__control-plane {
      display: grid;
      overflow: hidden;
      background:
        linear-gradient(
          115deg,
          color-mix(in srgb, var(--theme-color) 5%, transparent),
          transparent 42%
        ),
        var(--art-main-bg-color);
    }

    &__hero {
      position: relative;
      justify-content: space-between;
      min-height: 108px;
      padding: 22px 26px;
      overflow: hidden;
      border-bottom: 1px solid var(--el-border-color-lighter);

      &::after {
        position: absolute;
        top: -110px;
        right: 7%;
        width: 280px;
        height: 280px;
        pointer-events: none;
        content: '';
        background: radial-gradient(circle, rgb(91 143 249 / 16%), transparent 68%);
      }
    }

    &__hero-main {
      flex: 1;
      gap: 17px;
      min-width: 0;

      > div:last-child {
        min-width: 0;
      }

      span {
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.16em;
      }

      h1 {
        margin: 3px 0 5px;
        font-size: 23px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.7;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__brand {
      display: grid;
      flex: 0 0 56px;
      place-items: center;
      width: 56px;
      height: 56px;
      font-size: 26px;
      color: #fff;
      background: linear-gradient(145deg, var(--el-color-primary), #7157de);
      border-radius: var(--custom-radius);
      box-shadow: 0 14px 30px rgb(64 116 255 / 24%);
    }

    &__hero-actions {
      z-index: 1;
      flex-shrink: 0;
      gap: 10px;
    }

    &__refreshing :deep(svg) {
      animation: ai-configuration-spin 0.8s linear infinite;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      min-width: 0;

      article {
        gap: 14px;
        min-width: 0;
        padding: 17px 18px;
        border-right: 1px solid var(--el-border-color-lighter);

        > div:last-child {
          display: grid;
          gap: 3px;
          min-width: 0;
        }

        span,
        small {
          color: var(--el-text-color-secondary);
        }

        span {
          font-size: 12px;
        }

        strong {
          font-size: 22px;
          color: var(--el-text-color-primary);
        }

        small {
          font-size: 11px;
        }
      }
    }

    &__control-body {
      display: grid;
      grid-template-columns: minmax(0, 1.45fr) minmax(320px, 0.55fr);
      min-width: 0;
    }

    &__metric-icon {
      display: grid;
      flex: 0 0 42px;
      place-items: center;
      width: 42px;
      height: 42px;
      font-size: 20px;
      border-radius: var(--el-border-radius-base);

      &.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }
    }

    &__governance {
      justify-content: space-between;
      min-width: 0;
      height: 100%;
      padding: 16px 18px;
      background: color-mix(in srgb, var(--art-main-bg-color) 96%, var(--el-color-warning));

      > div {
        gap: 12px;
        min-width: 0;

        > svg {
          font-size: 22px;
          color: var(--el-color-primary);
        }

        > div {
          display: grid;
          gap: 3px;
          min-width: 0;

          strong {
            font-size: 13px;
            color: var(--el-text-color-primary);
          }

          span {
            font-size: 12px;
            color: var(--el-text-color-secondary);
            overflow-wrap: anywhere;
          }
        }
      }
    }

    :deep(.ai-configuration__model-cell) {
      display: grid;
      gap: 4px;

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-weight: 600;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }

      span {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    @media (width <= 900px) {
      &__hero {
        flex-direction: column;
        gap: 14px;
        align-items: flex-start;
      }

      &__hero-actions {
        align-self: flex-end;
      }

      &__metrics {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      &__control-body {
        grid-template-columns: 1fr;
      }

      &__governance {
        border-top: 1px solid var(--el-border-color-lighter);
      }
    }

    @media (width <= 680px) {
      &__metrics {
        grid-template-columns: 1fr;

        article {
          border-right: 0;
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }

      &__governance {
        flex-direction: column;
        gap: 12px;
        align-items: flex-start;
      }
    }
  }

  @keyframes ai-configuration-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
