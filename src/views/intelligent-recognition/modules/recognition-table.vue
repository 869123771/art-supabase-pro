<template>
  <ArtTableQuery
    ref="tableRef"
    focusable
    v-model="searchQuery"
    :search-items="searchItems"
    :api-fn="fetchTableData"
    :columns-factory="columnsFactory"
    :search-bar-props="{ span: 8, labelWidth: 82 }"
    :table-props="{
      rowKey: 'id',
      tableLayout: 'fixed',
      emptyText: mode === 'review' ? '当前没有待复核的识别任务' : '暂无识别记录',
      emptyDescription:
        mode === 'review'
          ? '新识别结果会在这里等待业务人员确认。'
          : '可前往识别工作台上传单据，或调整筛选条件。'
    }"
  >
    <template v-if="mode === 'review'" #header-left>
      <div class="recognition-table__queue-context">
        <strong>复核优先级</strong>
        <span>低可信度与风险任务优先</span>
      </div>
    </template>

    <template v-if="mode === 'review'" #header-right>
      <ElSegmented
        class="recognition-table__quick-filters"
        :model-value="searchQuery.confidenceLevel"
        :options="quickFilters"
        size="small"
        aria-label="可信度快捷筛选"
        @change="applyQuickFilter"
      />
    </template>
  </ArtTableQuery>
</template>

<script setup lang="tsx">
  import { ElButton, ElProgress, ElTag } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import RecognitionSourceGallery from './recognition-source-gallery.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { fetchRecognitionArtifactList } from '@/api/intelligent-recognition'
  import { useUserStore } from '@/store/modules/user'
  import {
    confidencePercent,
    getArtifactImageUrls,
    getArtifactTitle,
    getRecognitionRiskLevel
  } from './recognition-config'

  defineOptions({ name: 'RecognitionTable' })

  type Artifact = Api.IntelligentRecognition.RecognitionArtifact
  type Search = Pick<
    Api.IntelligentRecognition.ArtifactSearchParams,
    'creator' | 'feature' | 'status' | 'confidenceLevel' | 'createTimeRange'
  >

  const props = withDefaults(defineProps<{ mode: 'review' | 'records'; artifactId?: string }>(), {
    artifactId: ''
  })
  const emit = defineEmits<{ open: [row: Artifact]; business: [row: Artifact] }>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const tableRef = ref<ArtTableQueryExpose>()
  const searchQuery = reactive<Search>({
    creator: '',
    feature: '',
    status: props.mode === 'review' ? 'pending' : '',
    confidenceLevel: '',
    createTimeRange: []
  })
  const quickFilters: Array<{ label: string; value: Search['confidenceLevel'] }> = [
    { label: '全部待办', value: '' },
    { label: '低可信度', value: 'low' },
    { label: '中可信度', value: 'medium' }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '发起人',
      key: 'creator',
      type: 'input',
      props: { placeholder: '姓名或邮箱', clearable: true }
    },
    {
      label: '识别类型',
      key: 'feature',
      type: 'select',
      props: {
        options: getDictMap.value.aiOcrFeature ?? [],
        placeholder: '全部类型',
        clearable: true
      }
    },
    {
      label: '复核状态',
      key: 'status',
      type: 'select',
      hidden: props.mode === 'review',
      props: {
        options: getDictMap.value.aiArtifactStatus ?? [],
        placeholder: '全部状态',
        clearable: true
      }
    },
    {
      label: '可信度',
      key: 'confidenceLevel',
      type: 'select',
      props: {
        options: [
          { label: '高（≥85%）', value: 'high' },
          { label: '中（65%–84%）', value: 'medium' },
          { label: '低（<65%）', value: 'low' }
        ],
        placeholder: '全部区间',
        clearable: true
      }
    },
    {
      label: '发起时间',
      key: 'createTimeRange',
      type: 'daterange',
      props: { startPlaceholder: '开始日期', endPlaceholder: '结束日期' }
    }
  ])

  const columnsFactory = (): ColumnOption<Artifact>[] => [
    {
      prop: 'title',
      label: '识别任务',
      minWidth: 245,
      fixed: 'left',
      formatter: (row) => (
        <button class="recognition-table__document" type="button" onClick={() => emit('open', row)}>
          <span>
            <ArtSvgIcon icon="ri:file-search-line" />
          </span>
          <div>
            <strong>{getArtifactTitle(row)}</strong>
            <small>{row.id}</small>
          </div>
        </button>
      )
    },
    {
      prop: 'sourceImages',
      label: '原始票据',
      width: 126,
      formatter: (row) => (
        <RecognitionSourceGallery
          compact
          urls={getArtifactImageUrls(row)}
          expectedCount={Number(row.metadata?.imageCount ?? 0)}
        />
      )
    },
    {
      prop: 'feature',
      label: '识别类型',
      width: 135,
      formatter: (row) => (
        <ArtDictDisplay value={row.feature} dictCode="aiOcrFeature" display="tag" />
      )
    },
    {
      prop: 'confidence',
      label: '可信度',
      width: 155,
      formatter: (row) => {
        const percent = confidencePercent(row.confidence)
        return (
          <div class="recognition-table__confidence">
            <strong>{percent}%</strong>
            <ElProgress
              percentage={percent}
              strokeWidth={5}
              showText={false}
              status={percent >= 85 ? 'success' : percent < 65 ? 'exception' : undefined}
            />
          </div>
        )
      }
    },
    {
      prop: 'risk',
      label: '复核优先级',
      minWidth: 160,
      formatter: (row) => {
        const risk = getRecognitionRiskLevel(row)
        const config = {
          high: { label: '优先处理', type: 'danger' as const, icon: 'ri:alarm-warning-line' },
          medium: { label: '建议核对', type: 'warning' as const, icon: 'ri:error-warning-line' },
          normal: { label: '常规复核', type: 'success' as const, icon: 'ri:shield-check-line' }
        }[risk]
        return (
          <div class="recognition-table__risk">
            <ElTag type={config.type} effect="light">
              <ArtSvgIcon icon={config.icon} />
              {config.label}
            </ElTag>
            <small>
              {row.warnings?.length ? `${row.warnings.length} 项风险提示` : '未发现明显异常'}
            </small>
          </div>
        )
      }
    },
    ...(props.mode === 'records'
      ? [
          {
            prop: 'status',
            label: '状态',
            width: 118,
            formatter: (row: Artifact) => (
              <ArtDictDisplay value={row.status} dictCode="aiArtifactStatus" display="tag" />
            )
          } satisfies ColumnOption<Artifact>
        ]
      : []),
    ...(props.mode === 'records'
      ? [
          {
            prop: 'run',
            label: '模型 / 耗时',
            width: 170,
            formatter: (row: Artifact) => (
              <div class="recognition-table__run">
                <strong>{row.run?.model || '-'}</strong>
                <small>{row.run?.latencyMs ? `${row.run.latencyMs} ms` : '未记录耗时'}</small>
              </div>
            )
          } satisfies ColumnOption<Artifact>
        ]
      : []),
    {
      prop: 'createTime',
      label: '发起信息',
      width: 185,
      formatter: (row) => (
        <div class="recognition-table__run">
          <strong>{row.createBy || '-'}</strong>
          <small>{formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')}</small>
        </div>
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: props.mode === 'review' ? 170 : 90,
      fixed: 'right',
      formatter: (row) => (
        <div class="recognition-table__actions">
          <ElButton link type="primary" onClick={() => emit('open', row)}>
            详情
          </ElButton>
          {props.mode === 'review' ? (
            <ElButton link type="primary" onClick={() => emit('business', row)}>
              去业务复核
            </ElButton>
          ) : null}
        </div>
      )
    }
  ]

  function fetchTableData(params: Search & Api.Common.PaginationParams) {
    const { from, to } = pageInfoHandler(params)
    return fetchRecognitionArtifactList({
      ...params,
      status: props.mode === 'review' ? 'pending' : params.status,
      artifactId: props.artifactId || undefined,
      sort: props.mode === 'review' ? 'risk' : 'recent',
      from,
      to
    })
  }

  function refresh(): Promise<unknown> | undefined {
    return tableRef.value?.getData()
  }

  function applyQuickFilter(value: Search['confidenceLevel']): void {
    searchQuery.confidenceLevel = value
    void tableRef.value?.getData()
  }

  defineExpose({ refresh })
</script>

<style scoped lang="scss">
  .recognition-table__queue-context {
    min-width: 0;

    strong,
    span {
      display: block;
    }

    strong {
      font-size: 13px;
      line-height: 16px;
      color: var(--art-text-gray-800);
    }

    span {
      margin-top: 1px;
      font-size: 11px;
      line-height: 15px;
      color: var(--art-text-gray-500);
    }
  }

  .recognition-table__quick-filters {
    flex: 0 0 auto;
    height: 32px;
    margin-right: 10px;

    :deep(.el-segmented__item) {
      min-width: 68px;
    }
  }

  :deep(.recognition-table__document) {
    display: flex;
    gap: 9px;
    align-items: center;
    width: 100%;
    padding: 0;
    text-align: left;
    cursor: pointer;
    background: transparent;
    border: 0;

    > span {
      display: grid;
      flex: 0 0 34px;
      place-items: center;
      width: 34px;
      height: 34px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 8%, transparent);
      border-radius: var(--custom-radius);
    }

    > div {
      min-width: 0;
    }

    strong,
    small {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      color: var(--art-text-gray-900);
    }

    small {
      max-width: 176px;
      margin-top: 2px;
      font-size: 10px;
      color: var(--art-text-gray-400);
    }
  }

  :deep(.recognition-table__confidence) {
    strong {
      display: block;
      margin-bottom: 5px;
      font-size: 12px;
      color: var(--art-text-gray-800);
    }
  }

  :deep(.recognition-table__safe) {
    display: inline-flex;
    gap: 5px;
    align-items: center;
    font-size: 12px;
    color: var(--el-color-success);
  }

  :deep(.recognition-table__risk) {
    small {
      display: block;
      margin-top: 4px;
      font-size: 10px;
      color: var(--art-text-gray-500);
    }

    .el-tag {
      gap: 4px;
    }
  }

  :deep(.recognition-table__run) {
    min-width: 0;

    strong,
    small {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      font-size: 12px;
      color: var(--art-text-gray-800);
    }

    small {
      margin-top: 3px;
      font-size: 10px;
      color: var(--art-text-gray-500);
    }
  }

  :deep(.recognition-table__actions) {
    white-space: nowrap;
  }

  @media (width <= 720px) {
    .recognition-table__queue-context {
      span {
        display: none;
      }
    }
  }
</style>
