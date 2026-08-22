<template>
  <div class="recognition-page-hero">
    <BusinessWorkspaceHeader
      eyebrow="INTELLIGENT DOCUMENT HUB"
      :title="title"
      :description="subtitle"
      icon="ri:scan-2-line"
      :tags="[{ label: '人工复核闭环', type: 'success', effect: 'plain' }]"
      :metrics="workspaceMetrics"
    >
      <template v-if="$slots.action" #actions><slot name="action" /></template>
    </BusinessWorkspaceHeader>
    <ElAlert
      v-if="error"
      class="recognition-page-hero__alert"
      title="识别概览暂时无法更新，任务列表仍可正常使用。"
      type="warning"
      :closable="false"
      show-icon
    >
      <template #default>
        <ElButton link type="warning" :loading="loading" @click="emit('retry')">
          重新加载概览
        </ElButton>
      </template>
    </ElAlert>
  </div>
</template>

<script setup lang="ts">
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'

  interface MetricItem {
    label: string
    value: string | number
    note: string
    icon?: string
    tone?: BusinessWorkspaceMetric['tone']
  }

  const props = withDefaults(
    defineProps<{
      title: string
      subtitle: string
      metrics: MetricItem[]
      loading?: boolean
      error?: Error | null
    }>(),
    { loading: false, error: null }
  )
  const emit = defineEmits<{ retry: [] }>()
  const metricIcons = ['ri:file-search-line', 'ri:checkbox-circle-line', 'ri:time-line']
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() =>
    props.metrics.map((item, index) => ({
      label: item.label,
      value: item.value,
      description: item.note,
      icon: item.icon ?? metricIcons[index % metricIcons.length],
      tone: item.tone ?? (index === 1 ? 'success' : index === 2 ? 'warning' : 'primary'),
      loading: props.loading
    }))
  )
</script>

<style scoped lang="scss">
  .recognition-page-hero {
    flex: 0 0 auto;
    min-width: 0;

    &__alert {
      margin-top: 8px;

      :deep(.el-alert__content) {
        display: flex;
        flex-wrap: wrap;
        gap: 6px 12px;
        align-items: center;
      }
    }
  }
</style>
