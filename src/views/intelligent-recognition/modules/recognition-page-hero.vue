<template>
  <BusinessWorkspaceHeader
    class="recognition-hero"
    eyebrow="INTELLIGENT DOCUMENT HUB"
    :title="title"
    :description="subtitle"
    icon="ri:scan-2-line"
    :tags="[{ label: '人工复核闭环', type: 'success', effect: 'plain' }]"
    :metrics="workspaceMetrics"
  >
    <template v-if="$slots.action" #actions><slot name="action" /></template>
  </BusinessWorkspaceHeader>
</template>

<script setup lang="ts">
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'

  interface MetricItem {
    label: string
    value: string | number
    note: string
  }

  const props = defineProps<{ title: string; subtitle: string; metrics: MetricItem[] }>()
  const metricIcons = ['ri:file-search-line', 'ri:checkbox-circle-line', 'ri:time-line']
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() =>
    props.metrics.map((item, index) => ({
      label: item.label,
      value: item.value,
      description: item.note,
      icon: metricIcons[index % metricIcons.length],
      tone: index === 1 ? 'success' : index === 2 ? 'warning' : 'primary'
    }))
  )
</script>
