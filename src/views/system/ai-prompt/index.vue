<template>
  <div class="ai-prompt">
    <section class="ai-prompt__hero art-card-xs">
      <div class="ai-prompt__hero-main">
        <div class="ai-prompt__brand"><ArtSvgIcon icon="ri:quill-pen-line" /></div>
        <div>
          <span>PROMPT GOVERNANCE</span>
          <h1>AI Prompt 中心</h1>
          <p>集中管理系统指令的草稿、发布与回滚，让每次调整可审计、可验证、可恢复。</p>
        </div>
      </div>
      <div class="ai-prompt__hero-actions">
        <ElTag :type="canManage ? 'success' : 'info'" effect="light" round>
          {{ canManage ? '可维护' : '只读模式' }}
        </ElTag>
        <ElTooltip content="刷新 Prompt" placement="bottom">
          <ArtIconButton
            icon="ri:refresh-line"
            circle
            :class="{ 'ai-prompt__refreshing': overview.loading }"
            @click="refreshAll"
          />
        </ElTooltip>
      </div>
    </section>

    <section class="ai-prompt__metrics">
      <article v-for="item in metricCards" :key="item.label" class="art-card-xs">
        <div :class="['ai-prompt__metric-icon', `is-${item.tone}`]">
          <ArtSvgIcon :icon="item.icon" />
        </div>
        <div>
          <span>{{ item.label }}</span>
          <strong>{{ item.value }}</strong>
          <small>{{ item.hint }}</small>
        </div>
      </article>
    </section>

    <section class="ai-prompt__governance art-card-xs">
      <div>
        <ArtSvgIcon icon="ri:shield-check-line" />
        <div>
          <strong>发布即生效，运行时安全边界不会被覆盖</strong>
          <span
            >Prompt 只定义静态系统指令；权限校验、页面上下文、工具结果和结构化协议由 Edge Function
            追加。</span
          >
        </div>
      </div>
      <ElTag type="primary" effect="plain" round>一项能力仅一个生效版本</ElTag>
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
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <AiPromptDialog ref="dialogRef" @success="handleDraftSaved" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import dayjs from 'dayjs'
  import { ElMessage, ElTooltip } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import {
    type ArtTableQueryExpose,
    type ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type { ColumnOption } from '@/types'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteAiPromptDraft,
    fetchAiPromptList,
    publishAiPrompt,
    type AiPromptSearchParams,
    type AiPromptTemplate
  } from '@/api/ai-prompt'
  import AiPromptDialog, { type AiPromptDialogOpenData } from './modules/ai-prompt-dialog.vue'

  defineOptions({ name: 'AiPrompt' })

  const { confirmAction } = useArtFeedback()

  interface DialogExpose {
    handleOpen: (data: AiPromptDialogOpenData) => Promise<void>
  }

  interface TableGroup {
    searchQuery: Partial<Omit<AiPromptSearchParams, 'tenantId'>>
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
  }

  interface MetricCard {
    label: string
    value: string
    hint: string
    icon: string
    tone: 'primary' | 'success' | 'warning' | 'info'
  }

  const userStore = useUserStore()
  const { getDictMap, getUserInfo, isPlatformSuper } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const overview = reactive<{ loading: boolean; rows: AiPromptTemplate[] }>({
    loading: false,
    rows: []
  })

  const tenantId = computed(() => getUserInfo.value.tenantId ?? '')
  const canManage = computed(() => isPlatformSuper.value)

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: { feature: '', status: '', keyword: '' },
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
        label: '版本状态',
        key: 'status',
        type: 'select',
        props: {
          options: getDictMap.value.aiPromptStatus ?? [],
          placeholder: '请选择版本状态',
          clearable: true
        }
      },
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { placeholder: '搜索版本号、名称或说明', clearable: true }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() =>
      canManage.value
        ? [
            {
              type: 'add',
              label: '新建版本',
              onClick: () => openDialog({ mode: 'create' })
            }
          ]
        : []
    )
  })

  const metricCards = computed<MetricCard[]>(() => {
    const published = overview.rows.filter((row) => row.status === 'published').length
    const drafts = overview.rows.filter((row) => row.status === 'draft').length
    const archived = overview.rows.filter((row) => row.status === 'archived').length
    return [
      {
        label: '全部版本',
        value: `${overview.rows.length} 个`,
        hint: '租户内全部 Prompt 资产',
        icon: 'ri:file-list-3-line',
        tone: 'primary'
      },
      {
        label: '生效版本',
        value: `${published} 个`,
        hint: '新 AI 请求即时读取',
        icon: 'ri:rocket-2-line',
        tone: 'success'
      },
      {
        label: '待发布草稿',
        value: `${drafts} 个`,
        hint: drafts ? '建议验证后再发布' : '当前没有待处理草稿',
        icon: 'ri:draft-line',
        tone: 'warning'
      },
      {
        label: '历史版本',
        value: `${archived} 个`,
        hint: '保留审计与回滚能力',
        icon: 'ri:history-line',
        tone: 'info'
      }
    ]
  })

  async function fetchTableData(params: Omit<AiPromptSearchParams, 'tenantId'>) {
    return await fetchAiPromptList({ ...params, tenantId: tenantId.value })
  }

  async function loadOverview(): Promise<void> {
    if (!tenantId.value) return
    overview.loading = true
    try {
      const result = await fetchAiPromptList({ current: 1, size: 100, tenantId: tenantId.value })
      overview.rows = result.data ?? []
    } finally {
      overview.loading = false
    }
  }

  async function refreshAll(): Promise<void> {
    if (overview.loading) return
    await Promise.all([loadOverview(), tableQueryRef.value?.refreshData()])
    ElMessage.success('Prompt 版本已刷新')
  }

  function openDialog(data: AiPromptDialogOpenData): void {
    void dialogRef.value?.handleOpen(data)
  }

  async function handleDraftSaved(): Promise<void> {
    await Promise.all([loadOverview(), tableQueryRef.value?.refreshCreate()])
  }

  async function handlePublish(row: AiPromptTemplate): Promise<void> {
    const isRollback = row.status === 'archived'
    await confirmAction(
      isRollback
        ? `确认回滚到 ${row.version}？当前生效版本会自动归档，新请求将立即使用该版本。`
        : `确认发布 ${row.version}？当前生效版本会自动归档，新请求将立即使用此 Prompt。`,
      isRollback ? '回滚 Prompt 版本' : '发布 Prompt 版本',
      {
        type: 'warning',
        confirmButtonText: isRollback ? '确认回滚' : '确认发布',
        cancelButtonText: '取消'
      }
    )
    await publishAiPrompt(row.id)
    ElMessage.success(isRollback ? 'Prompt 已回滚并生效' : 'Prompt 已发布并生效')
    await Promise.all([loadOverview(), tableQueryRef.value?.refreshUpdate()])
  }

  async function handleDelete(row: AiPromptTemplate): Promise<void> {
    await confirmAction(`确认删除草稿 ${row.version}？此操作不可恢复。`, '删除 Prompt 草稿', {
      type: 'warning',
      confirmButtonText: '确认删除',
      cancelButtonText: '取消'
    })
    await deleteAiPromptDraft(row.id)
    await Promise.all([loadOverview(), tableQueryRef.value?.refreshRemove()])
  }

  function getMoreActions(row: AiPromptTemplate): ButtonMoreItem[] {
    const actions: ButtonMoreItem[] = [
      {
        key: 'clone',
        label: row.status === 'draft' ? '复制为新版本' : '基于此版本新建草稿',
        icon: 'ri:file-copy-2-line'
      }
    ]
    if (row.status === 'draft') {
      actions.push({
        key: 'delete',
        label: '删除草稿',
        icon: 'ri:delete-bin-5-line',
        color: 'var(--el-color-danger)'
      })
    }
    return actions
  }

  function handleMoreAction(item: ButtonMoreItem, row: AiPromptTemplate): void {
    if (item.key === 'clone') {
      openDialog({ mode: 'clone', row })
      return
    }
    if (item.key === 'delete') void handleDelete(row)
  }

  const columnsFactory = (): ColumnOption<AiPromptTemplate>[] =>
    [
      { type: 'globalIndex', label: '序号', width: 72 },
      {
        prop: 'feature',
        label: '能力场景',
        minWidth: 130,
        dict: { code: 'aiRunFeature', display: 'text' }
      },
      {
        prop: 'versionInfo',
        label: '版本',
        minWidth: 240,
        showOverflowTooltip: false,
        formatter: (row: AiPromptTemplate) => (
          <div class="ai-prompt__version-cell">
            <div>
              <strong class="ai-prompt__version-code">{row.version}</strong>
              <span>{row.name}</span>
            </div>
            {row.description ? <small>{row.description}</small> : null}
          </div>
        )
      },
      {
        prop: 'status',
        label: '状态',
        width: 105,
        dict: { code: 'aiPromptStatus', display: 'auto' }
      },
      {
        prop: 'systemPrompt',
        label: '系统指令摘要',
        minWidth: 320,
        showOverflowTooltip: false,
        formatter: (row: AiPromptTemplate) => (
          <ElTooltip
            content={row.systemPrompt}
            placement="top"
            showAfter={350}
            hideAfter={100}
            popperClass="ai-prompt-prompt-tooltip"
          >
            <div class="ai-prompt__prompt-preview">{row.systemPrompt}</div>
          </ElTooltip>
        )
      },
      {
        prop: 'publishedAt',
        label: '发布信息',
        width: 190,
        showOverflowTooltip: false,
        formatter: (row: AiPromptTemplate) =>
          row.publishedAt ? (
            <div class="ai-prompt__publish-cell">
              <strong>{dayjs(row.publishedAt).format('YYYY-MM-DD HH:mm')}</strong>
              <small>{row.publishedBy || '--'}</small>
            </div>
          ) : (
            <span class="text-g-400">尚未发布</span>
          )
      },
      {
        prop: 'updateTime',
        label: '最近更新',
        width: 160,
        showOverflowTooltip: false,
        formatter: (row: AiPromptTemplate) => dayjs(row.updateTime).format('YYYY-MM-DD HH:mm')
      },
      {
        prop: 'operation',
        label: '操作',
        width: 142,
        fixed: 'right',
        showOverflowTooltip: false,
        formatter: (row: AiPromptTemplate) => (
          <div class="ai-prompt__actions">
            {row.status === 'draft' ? (
              <ElTooltip content="编辑草稿（发布前可反复修改）" placement="top">
                <ArtButtonTable type="edit" onClick={() => openDialog({ mode: 'edit', row })} />
              </ElTooltip>
            ) : null}
            {row.status !== 'published' ? (
              <ElTooltip
                content={row.status === 'archived' ? '回滚到此版本' : '发布版本'}
                placement="top"
              >
                <ArtButtonTable
                  type="sign"
                  icon={row.status === 'archived' ? 'ri:history-line' : 'ri:rocket-2-line'}
                  onClick={() => void handlePublish(row)}
                />
              </ElTooltip>
            ) : null}
            <ArtButtonMore
              list={() => getMoreActions(row)}
              onClick={(item) => handleMoreAction(item, row)}
            />
          </div>
        )
      }
    ].filter(
      (column) => canManage.value || column.prop !== 'operation'
    ) as ColumnOption<AiPromptTemplate>[]

  onMounted(async () => {
    await Promise.all([userStore.fetchDictList(), loadOverview()])
  })
</script>

<style scoped lang="scss">
  .ai-prompt {
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

    :deep(.el-tag) {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      line-height: 1;
    }

    :deep(.el-tag__content) {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      height: 100%;
      line-height: 1;
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
    &__brand,
    &__metrics article,
    &__metric-icon,
    &__governance,
    &__governance > div {
      display: flex;
      align-items: center;
    }

    &__hero {
      justify-content: space-between;
      padding: 26px 28px;
      background:
        radial-gradient(circle at 88% 15%, rgb(99 102 241 / 12%), transparent 28%),
        var(--art-main-bg-color);
    }

    &__hero-main {
      min-width: 0;

      > div:last-child {
        min-width: 0;
      }

      span {
        display: block;
        margin-bottom: 5px;
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.14em;
      }

      h1 {
        margin: 0 0 5px;
        font-size: 24px;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.7;
        color: var(--art-text-gray-500);
        overflow-wrap: anywhere;
      }
    }

    &__brand {
      flex: 0 0 58px;
      justify-content: center;
      width: 58px;
      height: 58px;
      margin-right: 18px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
      border-radius: var(--custom-radius);

      :deep(svg) {
        display: block;
        width: 25px;
        height: 25px;
      }
    }

    &__hero-actions {
      flex: 0 0 auto;
      gap: 10px;
      margin-left: 18px;
    }

    &__refreshing {
      :deep(svg) {
        animation: ai-prompt-spin 0.9s linear infinite;
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;

      article {
        min-width: 0;
        padding: 20px 22px;

        > div:last-child {
          display: grid;
          min-width: 0;
        }

        span,
        small {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--art-text-gray-500);
          white-space: nowrap;
        }

        span {
          font-size: 12px;
        }

        strong {
          margin: 3px 0 1px;
          font-size: 22px;
          color: var(--art-text-gray-900);
        }

        small {
          font-size: 11px;
        }
      }
    }

    &__metric-icon {
      flex: 0 0 42px;
      justify-content: center;
      width: 42px;
      height: 42px;
      margin-right: 14px;
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        display: block;
        width: 20px;
        height: 20px;
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
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }

      &.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }
    }

    &__governance {
      gap: 20px;
      justify-content: space-between;
      padding: 17px 22px;

      > div {
        min-width: 0;

        > :deep(svg) {
          display: block;
          flex: 0 0 auto;
          width: 22px;
          height: 22px;
          margin-right: 13px;
          color: var(--el-color-primary);
        }
      }

      strong,
      span {
        display: block;
      }

      strong {
        margin-bottom: 3px;
        font-size: 13px;
        color: var(--art-text-gray-900);
      }

      span {
        font-size: 12px;
        line-height: 1.6;
        color: var(--art-text-gray-500);
        overflow-wrap: anywhere;
      }

      > :deep(.el-tag) {
        flex: 0 0 auto;
      }
    }

    :deep(.ai-prompt__version-cell),
    :deep(.ai-prompt__publish-cell) {
      display: grid;
      min-width: 0;

      strong,
      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    :deep(.ai-prompt__version-cell) {
      gap: 4px;

      > div {
        display: flex;
        gap: 8px;
        align-items: center;
        min-width: 0;
      }

      strong {
        flex: 0 0 auto;
      }

      span {
        color: var(--art-text-gray-800);
      }

      small {
        color: var(--art-text-gray-500);
      }
    }

    :deep(.ai-prompt__version-code) {
      padding: 2px 6px;
      font-size: 11px;
      font-weight: 600;
      line-height: 1.4;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-small);
    }

    :deep(.ai-prompt__prompt-preview) {
      display: -webkit-box;
      width: 100%;
      min-width: 0;
      overflow: hidden;
      -webkit-line-clamp: 2;
      line-height: 1.65;
      color: var(--art-text-gray-600);
      overflow-wrap: anywhere;
      white-space: normal;
      -webkit-box-orient: vertical;
    }

    :deep(.ai-prompt__publish-cell) {
      gap: 3px;

      strong {
        font-size: 12px;
        font-weight: 500;
        color: var(--art-text-gray-800);
      }

      small {
        display: block;
        color: var(--art-text-gray-500);
      }
    }

    :deep(.ai-prompt__actions) {
      display: flex;
      align-items: center;

      .el-tooltip__trigger {
        display: inline-flex;
      }
    }
  }

  :global(.el-popper.ai-prompt-prompt-tooltip) {
    max-width: 460px;
    max-height: 240px;
    overflow: hidden;
    line-height: 1.65;
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }

  @keyframes ai-prompt-spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (width <= 1200px) {
    .ai-prompt {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }

  @media (width <= 768px) {
    .ai-prompt {
      &__hero,
      &__governance {
        flex-direction: column;
        align-items: flex-start;
      }

      &__hero-actions {
        margin-left: 0;
      }

      &__metrics {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
