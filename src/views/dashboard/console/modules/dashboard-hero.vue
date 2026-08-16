<template>
  <BusinessWorkspaceHeader
    class="dashboard-hero"
    eyebrow="TRANSPORT OPERATIONS"
    :title="`${greeting}，${userName}`"
    description="优先处理调度任务与车辆风险，持续掌握今日运输执行状态。"
    icon="ri:dashboard-3-line"
    :tags="workspaceTags"
    :metrics="workspaceMetrics"
  >
    <template #actions>
      <ElButton :icon="RefreshRight" @click="emit('refresh')">刷新数据</ElButton>
      <ElButton :icon="Van" @click="emit('dispatch')">处理调度</ElButton>
      <ElButton type="primary" :icon="EditPen" @click="emit('create-order')">立即开单</ElButton>
    </template>
  </BusinessWorkspaceHeader>
</template>

<script setup lang="ts">
  import { EditPen, RefreshRight, Van } from '@element-plus/icons-vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric,
    type BusinessWorkspaceTag
  } from '@/components/business/business-workspace-header/index.vue'

  const props = defineProps<{
    greeting: string
    userName: string
    userContext: string
    dateText: string
    todayOrderCount: number
    pendingDispatchCount: number
    inTransitCount: number
  }>()

  const workspaceTags = computed<BusinessWorkspaceTag[]>(() => [
    ...(props.userContext ? [{ label: props.userContext, type: 'info' as const }] : []),
    { label: props.dateText, type: 'primary', effect: 'plain' },
    { label: '运营数据已同步', type: 'success', effect: 'light' }
  ])
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '今日开单',
      value: props.todayOrderCount,
      description: '今日创建的运输订单',
      icon: 'ri:file-add-line'
    },
    {
      label: '待调度',
      value: props.pendingDispatchCount,
      description: '等待分配车辆与司机',
      icon: 'ri:route-line',
      tone: 'warning'
    },
    {
      label: '运输中',
      value: props.inTransitCount,
      description: '正在执行的运输任务',
      icon: 'ri:truck-line',
      tone: 'success'
    }
  ])

  const emit = defineEmits<{
    'create-order': []
    dispatch: []
    refresh: []
  }>()
</script>
