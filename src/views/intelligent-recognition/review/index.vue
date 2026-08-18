<template>
  <div class="art-full-height business-workspace-page recognition-review">
    <RecognitionPageHero
      title="待复核"
      subtitle="队列已按风险优先排序。打开任务查看识别依据，确认后可携带当前结果进入原业务表单继续处理。"
      :metrics="heroMetrics"
    >
      <template #action>
        <ElButton type="primary" @click="router.push('/intelligent-recognition/workbench')">
          <ArtSvgIcon icon="ri:add-line" />发起识别
        </ElButton>
      </template>
    </RecognitionPageHero>
    <RecognitionTable
      ref="tableRef"
      mode="review"
      :artifact-id="artifactId"
      @open="handleOpen"
      @business="goBusiness"
    />
    <RecognitionDetailDrawer ref="detailRef" />
  </div>
</template>

<script setup lang="ts">
  import { fetchRecognitionOverview } from '@/api/intelligent-recognition'
  import RecognitionPageHero from '../modules/recognition-page-hero.vue'
  import RecognitionTable from '../modules/recognition-table.vue'
  import RecognitionDetailDrawer from '../modules/recognition-detail-drawer.vue'
  import { buildRecognitionBusinessRoute } from '@/utils/intelligent-recognition'
  import { confidencePercent } from '../modules/recognition-config'

  defineOptions({ name: 'RecognitionReview' })

  type Artifact = Api.IntelligentRecognition.RecognitionArtifact
  interface DetailExpose {
    handleOpen: (row: Artifact | string) => Promise<void>
  }

  const route = useRoute()
  const router = useRouter()
  const detailRef = ref<DetailExpose>()
  const artifactId = computed(() => String(route.query.artifactId || ''))
  const overview = reactive({ pending: 0, lowConfidence: 0, avgConfidence: 0 })
  const heroMetrics = computed(() => [
    { label: '待复核', value: overview.pending, note: '当前可见任务' },
    { label: '低可信任务', value: overview.lowConfidence, note: '建议优先处理' },
    {
      label: '平均可信度',
      value: `${confidencePercent(overview.avgConfidence)}%`,
      note: '辅助判断，不替代人工'
    }
  ])

  function handleOpen(row: Artifact): void {
    void detailRef.value?.handleOpen(row)
  }

  function goBusiness(row: Artifact): void {
    void router.push(buildRecognitionBusinessRoute(row))
  }

  onMounted(async () => {
    const { data } = await fetchRecognitionOverview()
    if (data) Object.assign(overview, data)
    if (artifactId.value) void detailRef.value?.handleOpen(artifactId.value)
  })
</script>
