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
        <article>
          <ArtSvgIcon icon="ri:stack-line" />
          <div><strong>版本治理</strong><small>草稿、发布、停用边界清晰</small></div>
        </article>
        <article>
          <ArtSvgIcon icon="ri:shield-user-line" />
          <div><strong>职责分离</strong><small>角色审批与禁止自审</small></div>
        </article>
        <article>
          <ArtSvgIcon icon="ri:file-history-line" />
          <div><strong>全程审计</strong><small>实例、任务、动作可追溯</small></div>
        </article>
      </div>
    </section>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 8, labelWidth: 88 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <WorkflowDesignerDrawer ref="designerRef" @success="handleSaveSuccess" />
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

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<Definition>[]
  }

  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const { confirmAction, confirmDelete } = useArtFeedback()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const designerRef = ref<DesignerExpose>()

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
        label: '流程名称',
        minWidth: 210,
        fixed: 'left',
        formatter: (row) => (
          <div class="workflow-definition__name-cell">
            <span>
              <ArtSvgIcon icon="ri:flow-chart" />
            </span>
            <div>
              <strong>{row.name}</strong>
              <small>{row.code}</small>
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
        label: '当前版本',
        width: 105,
        formatter: (row) => {
          const version = getCurrentVersion(row)
          return version ? <ElTag effect="plain">V{version.versionNo}</ElTag> : <span>--</span>
        }
      },
      {
        prop: 'nodes',
        label: '审批节点',
        width: 105,
        formatter: (row) => `${getCurrentVersion(row)?.config.nodes.length ?? 0} 个`
      },
      {
        prop: 'description',
        label: '说明',
        minWidth: 180,
        showOverflowTooltip: true,
        formatter: (row) => row.description || '--'
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
              width: 205,
              fixed: 'right',
              formatter: (row: Definition) => (
                <div class="workflow-definition__actions">
                  <ArtButtonTable
                    type="edit"
                    label="编辑流程"
                    onClick={() => designerRef.value?.handleOpen(row)}
                  />
                  <ArtButtonTable
                    type="sign"
                    icon="ri:send-plane-line"
                    label="发布流程"
                    disabled={!row.versions?.some((version) => version.status === 'draft')}
                    onClick={() => handlePublish(row)}
                  />
                  <ArtButtonTable
                    type="more"
                    icon={
                      row.status === 'disabled' ? 'ri:play-circle-line' : 'ri:pause-circle-line'
                    }
                    label={row.status === 'disabled' ? '启用流程' : '停用流程'}
                    disabled={row.status === 'draft'}
                    onClick={() => handleToggle(row)}
                  />
                  <ArtButtonTable
                    type="delete"
                    label="删除流程"
                    onClick={() => handleDelete(row)}
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
        color: var(--el-color-primary);
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.12em;
      }
      h1 {
        margin: 4px 0 5px;
        color: var(--art-gray-900);
        font-size: 24px;
        line-height: 1.25;
      }
      p {
        max-width: 620px;
        margin: 0;
        color: var(--art-gray-500);
        font-size: 13px;
        line-height: 1.6;
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
      width: 52px;
      height: 52px;
      color: #fff;
      background: linear-gradient(145deg, var(--el-color-primary), #7568f8);
      border-radius: calc(var(--el-border-radius-base) + 8px);
      box-shadow: 0 12px 25px rgb(64 120 255 / 24%);
      place-items: center;
      font-size: 26px;
    }

    &__principles {
      display: flex;
      flex: 0 0 auto;
      gap: 10px;

      article {
        display: flex;
        gap: 9px;
        align-items: center;
        min-width: 130px;
        padding: 10px 12px;
        background: rgb(255 255 255 / 55%);
        border: 1px solid var(--art-gray-200);
        border-radius: var(--el-border-radius-base);
      }
      article > svg {
        color: var(--el-color-primary);
        font-size: 19px;
      }
      article div {
        display: grid;
        gap: 2px;
      }
      strong {
        color: var(--art-gray-800);
        font-size: 13px;
      }
      small {
        color: var(--art-gray-500);
        font-size: 10px;
        white-space: nowrap;
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
      width: 34px;
      height: 34px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: calc(var(--el-border-radius-base) + 1px);
      place-items: center;
    }
    :deep(.workflow-definition__name-cell > div) {
      display: grid;
      min-width: 0;
      gap: 2px;
    }
    :deep(.workflow-definition__name-cell strong),
    :deep(.workflow-definition__name-cell small) {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    :deep(.workflow-definition__name-cell small) {
      color: var(--art-gray-500);
      font-size: 11px;
    }
    :deep(.workflow-definition__tenant-cell) {
      display: grid;
      min-width: 0;
      gap: 2px;
    }
    :deep(.workflow-definition__tenant-cell strong),
    :deep(.workflow-definition__tenant-cell small) {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    :deep(.workflow-definition__tenant-cell strong) {
      color: var(--art-gray-800);
      font-size: 13px;
      font-weight: 500;
    }
    :deep(.workflow-definition__tenant-cell small) {
      color: var(--art-gray-500);
      font-size: 11px;
    }
    :deep(.workflow-definition__actions) {
      display: flex;
      align-items: center;
    }
  }

  @media (width <= 1100px) {
    .workflow-definition__principles article:nth-child(n + 2) {
      display: none;
    }
  }

  @media (width <= 720px) {
    .workflow-definition__hero {
      align-items: flex-start;
      padding: 18px;
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
