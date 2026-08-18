<template>
  <ArtPageShell
    :loading="loading"
    :error="loadError"
    class="recognition-workbench"
    @retry="loadData"
  >
    <RecognitionPageHero
      title="智能识别工作台"
      subtitle="统一处理发票、运输回单和收付款凭证。AI 负责提取与风险提示，业务人员保留最终确认权。"
      :metrics="heroMetrics"
    >
      <template #action>
        <ElButton type="primary" @click="runnerRef?.handleOpen()">
          <ArtSvgIcon icon="ri:add-line" />发起识别
        </ElButton>
      </template>
    </RecognitionPageHero>

    <section class="recognition-workbench__attention" aria-label="待办概况">
      <div>
        <span class="recognition-workbench__attention-icon">
          <ArtSvgIcon icon="ri:shield-check-line" />
        </span>
        <div>
          <strong>{{ attentionTitle }}</strong>
          <p>{{ attentionDescription }}</p>
        </div>
      </div>
      <ElButton plain @click="router.push('/intelligent-recognition/review')">
        进入复核队列
        <ArtSvgIcon icon="ri:arrow-right-line" />
      </ElButton>
    </section>

    <ArtPageSection title="识别能力" subtitle="选择业务场景，系统会自动进入对应的识别与复核流程">
      <div class="recognition-workbench__capabilities">
        <article v-for="item in recognitionCapabilities" :key="item.feature">
          <header>
            <div class="recognition-workbench__capability-icon">
              <ArtSvgIcon :icon="item.icon" />
            </div>
            <div>
              <ElTag size="small" effect="plain">已启用</ElTag>
              <span>{{ overview.byFeature[item.feature] ?? 0 }} 次识别</span>
            </div>
          </header>
          <h3>{{ item.title }}</h3>
          <p>{{ item.description }}</p>
          <ul>
            <li><ArtSvgIcon icon="ri:check-line" />结构化字段提取</li>
            <li><ArtSvgIcon icon="ri:check-line" />低置信度风险提示</li>
          </ul>
          <footer>
            <span>{{ item.businessLabel }}</span>
            <ElButton link type="primary" @click="runnerRef?.handleOpen(item.feature)">
              {{ item.feature === 'waybill_receipt_ocr' ? '进入业务' : '开始识别' }}
              <ArtSvgIcon icon="ri:arrow-right-line" />
            </ElButton>
          </footer>
        </article>
      </div>
    </ArtPageSection>

    <div class="recognition-workbench__lower">
      <ArtPageSection title="标准处理路径" subtitle="识别建议不直接写入正式业务数据">
        <div class="recognition-workbench__flow">
          <template v-for="(item, index) in flowItems" :key="item.title">
            <article>
              <span>{{ index + 1 }}</span>
              <div
                ><strong>{{ item.title }}</strong
                ><small>{{ item.description }}</small></div
              >
            </article>
            <ArtSvgIcon v-if="index < flowItems.length - 1" icon="ri:arrow-right-line" />
          </template>
        </div>
      </ArtPageSection>

      <ArtPageSection title="最近识别" subtitle="仅展示当前账号有权访问的记录">
        <ArtTable
          :data="recentArtifacts"
          :columns="recentColumns"
          :pagination="false"
          table-layout="fixed"
          empty-text="还没有识别记录"
          empty-description="点击“发起识别”上传第一张单据。"
        >
          <template #operation="{ row }">
            <ElButton link type="primary" @click="detailRef?.handleOpen(row)">查看</ElButton>
          </template>
        </ArtTable>
      </ArtPageSection>
    </div>

    <RecognitionWorkbenchDrawer ref="runnerRef" @created="handleCreated" />
    <RecognitionDetailDrawer ref="detailRef" />
  </ArtPageShell>
</template>

<script setup lang="ts">
  import type { ColumnOption } from '@/types'
  import {
    fetchRecognitionArtifactList,
    fetchRecognitionOverview
  } from '@/api/intelligent-recognition'
  import { formatWithDayjs } from '@/utils/time'
  import RecognitionPageHero from '../modules/recognition-page-hero.vue'
  import RecognitionWorkbenchDrawer from '../modules/recognition-workbench-drawer.vue'
  import RecognitionDetailDrawer from '../modules/recognition-detail-drawer.vue'
  import {
    confidencePercent,
    featureLabels,
    getArtifactTitle,
    recognitionCapabilities,
    type RecognitionFeature
  } from '../modules/recognition-config'

  defineOptions({ name: 'RecognitionWorkbench' })

  type Artifact = Api.IntelligentRecognition.RecognitionArtifact
  interface RunnerExpose {
    handleOpen: (feature?: RecognitionFeature) => Promise<void>
  }
  interface DetailExpose {
    handleOpen: (row: Artifact | string) => Promise<void>
  }

  const router = useRouter()
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)
  const runnerRef = ref<RunnerExpose>()
  const detailRef = ref<DetailExpose>()
  const recentArtifacts = ref<Artifact[]>([])
  const overview = reactive<Api.IntelligentRecognition.RecognitionOverview>({
    total: 0,
    pending: 0,
    applied: 0,
    rejected: 0,
    lowConfidence: 0,
    today: 0,
    avgConfidence: 0,
    byFeature: {}
  })

  const heroMetrics = computed(() => [
    { label: '今日识别', value: overview.today, note: '当前可见范围' },
    { label: '待业务复核', value: overview.pending, note: '需要人工确认' },
    {
      label: '平均可信度',
      value: `${confidencePercent(overview.avgConfidence)}%`,
      note: '结构化字段综合'
    }
  ])
  const attentionTitle = computed(() =>
    overview.pending ? `有 ${overview.pending} 个识别任务等待业务复核` : '当前没有积压的复核任务'
  )
  const attentionDescription = computed(() => {
    if (!overview.pending) return '新的识别结果会自动进入复核队列，并保留完整审计记录。'
    if (overview.lowConfidence) {
      return `其中 ${overview.lowConfidence} 个任务可信度偏低，建议优先核对金额、单号和往来单位。`
    }
    return '队列状态健康，可按发起时间依次完成业务确认。'
  })
  const flowItems = [
    { title: '上传单据', description: '图片仅用于本次业务识别' },
    { title: 'AI 提取', description: '输出字段可信度与风险提示' },
    { title: '业务复核', description: '回到原页面核对和修正' },
    { title: '审计留痕', description: '记录采用、修正与关联单据' }
  ]
  const recentColumns: ColumnOption<Artifact>[] = [
    { prop: 'title', label: '任务', minWidth: 190, formatter: (row) => getArtifactTitle(row) },
    { prop: 'feature', label: '类型', width: 120, formatter: (row) => featureLabels[row.feature] },
    {
      prop: 'confidence',
      label: '可信度',
      width: 90,
      formatter: (row) => `${confidencePercent(row.confidence)}%`
    },
    {
      prop: 'createTime',
      label: '发起时间',
      width: 150,
      formatter: (row) => formatWithDayjs(row.createTime, 'MM-DD HH:mm')
    },
    { prop: 'operation', label: '操作', width: 70, fixed: 'right', useSlot: true }
  ]

  async function loadData(): Promise<void> {
    loading.value = true
    loadError.value = null
    try {
      const [overviewResponse, recentResponse] = await Promise.all([
        fetchRecognitionOverview(),
        fetchRecognitionArtifactList({ from: 0, to: 5 })
      ])
      if (overviewResponse.error) throw overviewResponse.error
      if (overviewResponse.data) Object.assign(overview, overviewResponse.data)
      recentArtifacts.value = recentResponse.data ?? []
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('智能识别工作台加载失败')
    } finally {
      loading.value = false
    }
  }

  function handleCreated(artifactId: string): void {
    void router.push({ path: '/intelligent-recognition/review', query: { artifactId } })
  }

  onMounted(loadData)
</script>

<style scoped lang="scss">
  .recognition-workbench {
    :deep(.art-async-state) {
      display: flex;
      flex-direction: column;
      gap: 14px;
    }

    &__attention {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      padding: 13px 16px;
      margin-bottom: 0;
      background: color-mix(in srgb, var(--theme-color) 5%, var(--art-main-bg-color));
      border: 1px solid color-mix(in srgb, var(--theme-color) 18%, var(--art-card-border));
      border-radius: var(--custom-radius);

      > div {
        display: flex;
        gap: 11px;
        align-items: center;
        min-width: 0;
      }

      strong {
        color: var(--art-text-gray-900);
      }

      p {
        margin: 3px 0 0;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }
    }

    &__attention-icon {
      display: grid;
      flex: 0 0 36px;
      place-items: center;
      width: 36px;
      height: 36px;
      font-size: 18px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, transparent);
      border-radius: 50%;
    }

    &__capabilities {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;

      article {
        position: relative;
        min-width: 0;
        padding: 17px;
        overflow: hidden;
        background: var(--art-main-bg-color);
        border: 1px solid var(--art-card-border);
        border-radius: var(--custom-radius);
        transition:
          border-color 0.18s ease,
          box-shadow 0.18s ease,
          transform 0.18s ease;

        > header {
          display: flex;
          align-items: center;
          justify-content: space-between;

          > div:last-child {
            display: flex;
            gap: 8px;
            align-items: center;
            font-size: 11px;
            color: var(--art-text-gray-400);
          }
        }

        h3 {
          margin: 14px 0 6px;
          color: var(--art-text-gray-900);
        }

        p {
          min-height: 44px;
          margin: 0;
          font-size: 12px;
          line-height: 1.7;
          color: var(--art-text-gray-500);
        }

        ul {
          display: flex;
          gap: 12px;
          padding: 0;
          margin: 12px 0 0;
          list-style: none;

          li {
            display: inline-flex;
            gap: 4px;
            align-items: center;
            font-size: 11px;
            color: var(--art-text-gray-500);
          }

          svg {
            color: var(--el-color-success);
          }
        }

        > footer {
          display: flex;
          gap: 8px;
          align-items: center;
          justify-content: space-between;
          padding-top: 12px;
          margin-top: 14px;
          border-top: 1px solid var(--art-border-dashed-color);
        }

        > footer > span {
          display: inline-flex;
          font-size: 11px;
          color: var(--art-text-gray-500);
        }
      }
    }

    &__capability-icon {
      display: grid;
      place-items: center;
      width: 42px;
      height: 42px;
      font-size: 21px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 9%, transparent);
      border-radius: var(--custom-radius);
    }

    &__lower {
      display: grid;
      grid-template-columns: minmax(0, 1.35fr) minmax(400px, 0.9fr);
      gap: 14px;
    }

    &__flow {
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 150px;

      > svg {
        flex: 0 0 auto;
        color: var(--art-text-gray-300);
      }

      article {
        display: flex;
        gap: 9px;
        align-items: center;
        min-width: 0;
      }

      article > span {
        display: grid;
        flex: 0 0 30px;
        place-items: center;
        width: 30px;
        height: 30px;
        font-weight: 700;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 9%, transparent);
        border-radius: 50%;
      }

      strong,
      small {
        display: block;
      }

      strong {
        font-size: 12px;
        color: var(--art-text-gray-800);
      }

      small {
        max-width: 108px;
        margin-top: 3px;
        font-size: 10px;
        line-height: 1.5;
        color: var(--art-text-gray-500);
      }
    }
  }

  :global([data-box-mode='border-mode']) .recognition-workbench__capabilities article:hover,
  :global([data-box-mode='border-mode']) .recognition-workbench__capabilities article:focus-within {
    border-color: color-mix(in srgb, var(--theme-color) 42%, var(--art-card-border));
  }

  :global([data-box-mode='shadow-mode']) .recognition-workbench__capabilities article:hover,
  :global([data-box-mode='shadow-mode']) .recognition-workbench__capabilities article:focus-within {
    box-shadow: 0 8px 24px color-mix(in srgb, var(--theme-color) 10%, transparent);
    transform: translateY(-1px);
  }

  @media (width <= 1100px) {
    .recognition-workbench {
      &__capabilities,
      &__lower {
        grid-template-columns: 1fr;
      }

      &__flow {
        flex-wrap: wrap;
        gap: 14px;
      }
    }
  }

  @media (width <= 640px) {
    .recognition-workbench {
      &__attention {
        align-items: stretch;
      }

      &__attention,
      &__capabilities article > footer {
        flex-direction: column;
        align-items: flex-start;
      }

      &__attention > .el-button {
        width: 100%;
      }

      &__capabilities article ul {
        flex-direction: column;
        gap: 5px;
      }

      &__flow {
        flex-direction: column;
        align-items: stretch;
      }

      &__flow > svg {
        align-self: center;
        transform: rotate(90deg);
      }
    }
  }
</style>
