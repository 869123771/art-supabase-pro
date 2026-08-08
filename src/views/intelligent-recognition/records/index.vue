<template>
  <div class="art-full-height recognition-records">
    <RecognitionPageHero
      title="识别记录"
      subtitle="集中查询识别结果、模型运行信息与业务采用状态，便于追溯每一次 AI 建议。"
      :metrics="heroMetrics"
    >
      <template #action>
        <ElButton plain @click="router.push('/intelligent-recognition/review')">
          <ArtSvgIcon icon="ri:shield-check-line" />查看待复核
        </ElButton>
      </template>
    </RecognitionPageHero>
    <RecognitionTable mode="records" @open="handleOpen" @business="goBusiness" />
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

  defineOptions({ name: 'RecognitionRecords' })

  type Artifact = Api.IntelligentRecognition.RecognitionArtifact
  interface DetailExpose {
    handleOpen: (row: Artifact | string) => Promise<void>
  }

  const router = useRouter()
  const detailRef = ref<DetailExpose>()
  const overview = reactive({ total: 0, applied: 0, avgConfidence: 0 })
  const heroMetrics = computed(() => [
    { label: '累计识别', value: overview.total, note: '当前可见范围' },
    { label: '已业务采用', value: overview.applied, note: '完成原业务确认' },
    {
      label: '平均可信度',
      value: `${confidencePercent(overview.avgConfidence)}%`,
      note: '历史综合表现'
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
  })
</script>
