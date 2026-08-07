<template>
  <div class="art-full-height workflow-definition">
    <section class="workflow-definition__hero art-card-xs">
      <div class="workflow-definition__hero-copy">
        <span class="workflow-definition__hero-icon"><ArtSvgIcon icon="ri:git-merge-line" /></span>
        <div>
          <span>WORKFLOW GOVERNANCE</span>
          <div class="workflow-definition__heading">
            <h1>审批流程设计</h1>
            <ElTag v-if="!isPlatformSuper" type="info" effect="plain" round>租户只读</ElTag>
          </div>
          <p>用版本化配置复用审批能力，发布中的版本保持不可变，所有流转动作完整留痕。</p>
        </div>
      </div>
      <div class="workflow-definition__principles">
        <article aria-label="版本治理：草稿、发布、停用边界清晰">
          <ArtSvgIcon icon="ri:stack-line" />
          <div><strong>版本治理</strong><small>草稿、发布、停用边界清晰</small></div>
        </article>
        <article aria-label="职责分离：角色审批与禁止自审">
          <ArtSvgIcon icon="ri:shield-user-line" />
          <div><strong>职责分离</strong><small>角色审批与禁止自审</small></div>
        </article>
        <article aria-label="全程审计：实例、任务、动作可追溯">
          <ArtSvgIcon icon="ri:file-history-line" />
          <div><strong>全程审计</strong><small>实例、任务、动作可追溯</small></div>
        </article>
      </div>
      <ElButton class="workflow-definition__catalog-button" plain @click="catalogRef?.handleOpen()">
        <ArtSvgIcon icon="ri:apps-2-line" />业务覆盖
      </ElButton>
    </section>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 8, labelWidth: 88 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无审批流程定义',
        emptyDescription: isPlatformSuper
          ? '可以新建流程，或调整筛选条件后重新查询。'
          : '当前租户还没有可查看的流程，请联系平台管理员配置。'
      }"
    />

    <WorkflowDesignerDrawer ref="designerRef" @success="handleSaveSuccess" />
    <WorkflowVersionHistoryDialog ref="versionHistoryRef" @success="handleSaveSuccess" />
    <WorkflowBusinessCatalogDialog ref="catalogRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElTag } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import {
    deleteWorkflowDefinition,
    fetchWorkflowDefinitionList,
    publishWorkflowDefinition,
    setWorkflowDefinitionEnabled
  } from '@/api/workflow'
  import WorkflowDesignerDrawer from './modules/workflow-designer-drawer.vue'
  import WorkflowVersionHistoryDialog from './modules/workflow-version-history-dialog.vue'
  import WorkflowBusinessCatalogDialog from './modules/workflow-business-catalog-dialog.vue'

  defineOptions({ name: 'WorkflowDefinition' })

  type Definition = Api.Workflow.WorkflowDefinitionRecord
  type SearchParams = Pick<
    Api.Workflow.WorkflowDefinitionSearchParams,
    'keyword' | 'businessType' | 'status' | 'tenantId'
  >
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DesignerExpose {
    handleOpen: (row?: Definition) => Promise<void>
  }
  interface VersionHistoryExpose {
    handleOpen: (row: Definition, options?: { canManage?: boolean }) => Promise<void>
  }
  interface CatalogExpose {
    handleOpen: () => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<Definition>[]
  }

  const userStore = useUserStore()
  const { getDictMap, isPlatformSuper } = storeToRefs(userStore)
  const { confirmAction, confirmDelete } = useArtFeedback()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const designerRef = ref<DesignerExpose>()
  const versionHistoryRef = ref<VersionHistoryExpose>()
  const catalogRef = ref<CatalogExpose>()

  const getCurrentVersion = (row: Definition) =>
    row.versions?.find((version) => version.id === row.currentVersionId) ||
    [...(row.versions || [])].sort((a, b) => b.versionNo - a.versionNo)[0]

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: { keyword: '', businessType: '', status: '', tenantId: '' },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { placeholder: '搜索流程名称或编码', clearable: true }
      },
      {
        label: '业务类型',
        key: 'businessType',
        type: 'select',
        props: {
          options: getDictMap.value.workflowBusinessType ?? [],
          placeholder: '全部业务类型',
          clearable: true
        }
      },
      {
        label: '流程状态',
        key: 'status',
        type: 'select',
        props: {
          options: getDictMap.value.workflowDefinitionStatus ?? [],
          placeholder: '全部状态',
          clearable: true
        }
      },
      {
        label: '所属租户',
        key: 'tenantId',
        type: 'select',
        hidden: !isPlatformSuper.value,
        api: fetchGetEnableTenantList,
        resultField: 'data',
        valueField: 'id',
        labelFn: (tenant) => `${tenant.tenantName}（${tenant.tenantCode}）`,
        props: {
          placeholder: '全部租户',
          filterable: true,
          clearable: true
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() =>
      isPlatformSuper.value
        ? [{ type: 'add', label: '新建流程', onClick: () => designerRef.value?.handleOpen() }]
        : []
    ),
    columnsFactory: () => [
      {
        prop: 'name',
        label: '流程定义',
        minWidth: 270,
        fixed: 'left',
        formatter: (row) => (
          <div class="workflow-definition__name-cell">
            <span>
              <ArtSvgIcon icon="ri:flow-chart" />
            </span>
            <div>
              <strong>{row.name}</strong>
              <div class="workflow-definition__name-meta">
                <small>{row.code}</small>
                <i>·</i>
                <span>{row.description || '暂无流程说明'}</span>
              </div>
            </div>
          </div>
        )
      },
      {
        prop: 'businessType',
        label: '业务类型',
        minWidth: 150,
        formatter: (row) => (
          <ArtDictDisplay value={row.businessType} dictCode="workflowBusinessType" display="text" />
        )
      },
      ...(isPlatformSuper.value
        ? [
            {
              prop: 'tenant',
              label: '所属租户',
              minWidth: 190,
              formatter: (row: Definition) => (
                <div class="workflow-definition__tenant-cell">
                  <strong>{row.tenant?.tenantName || '--'}</strong>
                  <small>{row.tenant?.tenantCode || row.tenantId}</small>
                </div>
              )
            } satisfies ColumnOption<Definition>
          ]
        : []),
      {
        prop: 'status',
        label: '状态',
        width: 110,
        dict: { code: 'workflowDefinitionStatus', display: 'tag' }
      },
      {
        prop: 'version',
        label: '版本与节点',
        width: 132,
        formatter: (row) => {
          const version = getCurrentVersion(row)
          return (
            <div class="workflow-definition__version-cell">
              {version ? <ElTag effect="plain">V{version.versionNo}</ElTag> : <span>--</span>}
              <small>{version?.config.nodes.length ?? 0} 个审批节点</small>
              <button
                type="button"
                onClick={() =>
                  versionHistoryRef.value?.handleOpen(row, { canManage: isPlatformSuper.value })
                }
              >
                查看版本
              </button>
            </div>
          )
        }
      },
      {
        prop: 'updateTime',
        label: '最近更新',
        width: 168,
        formatter: (row) => formatWithDayjs(row.updateTime)
      },
      ...(isPlatformSuper.value
        ? [
            {
              prop: 'operation',
              label: '操作',
              width: 106,
              fixed: 'right',
              formatter: (row: Definition) => (
                <div class="workflow-definition__actions">
                  <ArtButtonTable
                    type="edit"
                    label="编辑流程"
                    onClick={() => designerRef.value?.handleOpen(row)}
                  />
                  <ArtButtonMore
                    list={() => getRowMoreActions(row)}
                    onClick={(item: ButtonMoreItem) => handleRowMoreAction(item, row)}
                  />
                </div>
              )
            } satisfies ColumnOption<Definition>
          ]
        : [])
    ]
  })

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler(params)
    return fetchWorkflowDefinitionList({ ...params, from, to })
  }

  function getRowMoreActions(row: Definition): ButtonMoreItem[] {
    return [
      {
        key: 'publish',
        label: '发布流程',
        icon: 'ri:send-plane-line',
        disabled: !row.versions?.some((version) => version.status === 'draft')
      },
      {
        key: 'toggle',
        label: row.status === 'disabled' ? '启用流程' : '停用流程',
        icon: row.status === 'disabled' ? 'ri:play-circle-line' : 'ri:pause-circle-line',
        disabled: row.status === 'draft'
      },
      {
        key: 'delete',
        label: '删除流程',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)'
      }
    ]
  }

  function handleRowMoreAction(item: ButtonMoreItem, row: Definition): void {
    const actionMap: Record<string, () => Promise<void>> = {
      publish: () => handlePublish(row),
      toggle: () => handleToggle(row),
      delete: () => handleDelete(row)
    }
    const action = actionMap[String(item.key)]
    if (action) void action()
  }

  async function handlePublish(row: Definition): Promise<void> {
    await confirmAction(`发布“${row.name}”后，该版本将不可直接修改，新实例会立即使用新版本。`, {
      title: '发布流程',
      confirmButtonText: '确认发布',
      type: 'warning'
    })
    await publishWorkflowDefinition(row.id)
    await tableQueryRef.value?.getData()
  }

  async function handleToggle(row: Definition): Promise<void> {
    const enabled = row.status === 'disabled'
    await confirmAction(
      enabled
        ? `启用“${row.name}”后，业务可以再次发起审批。`
        : `停用“${row.name}”后，将阻止新实例发起，运行中实例不受影响。`,
      {
        title: enabled ? '启用流程' : '停用流程',
        confirmButtonText: enabled ? '确认启用' : '确认停用'
      }
    )
    await setWorkflowDefinitionEnabled(row.id, enabled)
    await tableQueryRef.value?.getData()
  }

  async function handleDelete(row: Definition): Promise<void> {
    const tenantLabel = row.tenant?.tenantName ? `（${row.tenant.tenantName}）` : ''
    await confirmDelete(
      `确定删除“${row.name}”${tenantLabel}吗？只有从未产生审批记录的流程可以删除；已有历史的流程必须停用。`
    )
    await deleteWorkflowDefinition(row.id)
    await tableQueryRef.value?.refreshRemove()
  }

  async function handleSaveSuccess(): Promise<void> {
    await tableQueryRef.value?.getData()
  }

  onMounted(() => void userStore.fetchDictList())
</script>

<style scoped lang="scss">
  .workflow-definition {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;

    &__hero {
      display: flex;
      gap: 24px;
      align-items: center;
      justify-content: space-between;
      padding: 22px 24px;
      overflow: hidden;
      background:
        radial-gradient(circle at 95% 15%, rgb(64 158 255 / 15%), transparent 34%),
        var(--default-box-color);
    }

    &__hero-copy {
      display: flex;
      gap: 15px;
      align-items: center;

      > div > span {
        font-size: 11px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.12em;
      }

      h1 {
        margin: 4px 0 5px;
        font-size: 24px;
        font-weight: 600;
        line-height: 1.25;
        color: var(--art-gray-900);
      }

      p {
        max-width: 620px;
        margin: 0;
        font-size: 13px;
        line-height: 1.6;
        color: var(--art-gray-500);
      }
    }

    &__heading {
      display: flex;
      gap: 10px;
      align-items: center;

      .el-tag {
        flex: none;
      }
    }

    &__hero-icon {
      display: grid;
      flex: 0 0 auto;
      place-items: center;
      width: 52px;
      height: 52px;
      font-size: 26px;
      color: #fff;
      background: linear-gradient(145deg, var(--el-color-primary), #7568f8);
      border-radius: calc(var(--el-border-radius-base) + 8px);
      box-shadow: 0 12px 25px rgb(64 120 255 / 24%);
    }

    &__principles {
      display: flex;
      flex: 0 0 auto;
      gap: 10px;

      article {
        display: flex;
        gap: 9px;
        align-items: center;
        min-width: 148px;
        padding: 11px 12px;
        background: rgb(255 255 255 / 55%);
        border: 1px solid var(--art-gray-200);
        border-radius: var(--el-border-radius-base);
      }

      article > svg {
        font-size: 19px;
        color: var(--el-color-primary);
      }

      article div {
        display: grid;
        gap: 2px;
      }

      strong {
        font-size: 13px;
        color: var(--art-gray-800);
      }

      small {
        font-size: 12px;
        line-height: 1.35;
        color: var(--art-gray-600);
      }
    }

    :deep(.art-table-query) {
      min-height: 0;
    }

    :deep(.workflow-definition__name-cell) {
      display: flex;
      gap: 10px;
      align-items: center;
    }

    :deep(.workflow-definition__name-cell > span) {
      display: grid;
      place-items: center;
      width: 34px;
      height: 34px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: calc(var(--el-border-radius-base) + 1px);
    }

    :deep(.workflow-definition__name-cell > div) {
      display: grid;
      gap: 2px;
      min-width: 0;
    }

    :deep(.workflow-definition__name-cell strong),
    :deep(.workflow-definition__name-meta small),
    :deep(.workflow-definition__name-meta span) {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    :deep(.workflow-definition__name-meta) {
      display: flex;
      gap: 5px;
      align-items: center;
      min-width: 0;
      font-size: 12px;
      color: var(--art-gray-500);

      small {
        flex: 0 1 auto;
        font-size: inherit;
        color: var(--art-gray-600);
      }

      i {
        flex: none;
        font-style: normal;
        color: var(--art-gray-400);
      }

      span {
        min-width: 0;
      }
    }

    :deep(.workflow-definition__version-cell) {
      display: grid;
      gap: 5px;
      justify-items: start;

      small {
        font-size: 12px;
        color: var(--art-gray-600);
      }
    }

    &__catalog-button {
      flex: 0 0 auto;
    }

    :deep(.workflow-definition__version-cell button) {
      width: fit-content;
      padding: 0;
      font-size: 11px;
      color: var(--el-color-primary);
      cursor: pointer;
      background: transparent;
      border: 0;
    }

    :deep(.workflow-definition__version-cell button:hover) {
      text-decoration: underline;
    }

    :deep(.workflow-definition__tenant-cell) {
      display: grid;
      gap: 2px;
      min-width: 0;
    }

    :deep(.workflow-definition__tenant-cell strong),
    :deep(.workflow-definition__tenant-cell small) {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    :deep(.workflow-definition__tenant-cell strong) {
      font-size: 13px;
      font-weight: 500;
      color: var(--art-gray-800);
    }

    :deep(.workflow-definition__tenant-cell small) {
      font-size: 12px;
      color: var(--art-gray-600);
    }

    :deep(.workflow-definition__actions) {
      display: flex;
      gap: 2px;
      align-items: center;
    }
  }

  @media (width <= 1360px) {
    .workflow-definition__principles article:nth-child(n + 2) {
      display: none;
    }
  }

  @media (width <= 720px) {
    .workflow-definition__hero {
      align-items: flex-start;
      padding: 18px;
    }

    .workflow-definition__catalog-button {
      width: 100%;
    }

    .workflow-definition__principles {
      display: none;
    }

    .workflow-definition__hero-copy {
      align-items: flex-start;
    }

    .workflow-definition__hero-copy h1 {
      font-size: 20px;
    }
  }
</style>
