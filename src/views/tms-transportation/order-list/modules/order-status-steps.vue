<template>
  <div class="order-status-steps">
    <div
      v-for="(item, index) in steps"
      :key="item.value"
      class="order-status-steps__item"
      :class="{
        'is-finished': index < activeIndex,
        'is-active': index === activeIndex,
        'is-pending': index > activeIndex
      }"
    >
      <div class="order-status-steps__node">
        <span class="order-status-steps__icon">
          <ArtSvgIcon :icon="resolveIcon(item.value, index)" />
        </span>
        <span class="order-status-steps__dot">
          <ArtSvgIcon v-if="index <= activeIndex" icon="ri:check-line" />
        </span>
      </div>

      <div v-if="index < steps.length - 1" class="order-status-steps__line" />

      <div class="order-status-steps__content">
        <div class="order-status-steps__title">
          <ArtDictDisplay
            v-if="dictCode && item.value !== 'created'"
            :dict-code="dictCode"
            :value="item.value"
            display="text"
          />
          <template v-else>{{ item.label }}</template>
        </div>
        <div class="order-status-steps__time">{{ item.timeText ?? timeText }}</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'

  defineOptions({ name: 'OrderStatusSteps' })

  interface StatusStep {
    label: string
    value: string
    timeText?: string
  }

  withDefaults(
    defineProps<{
      steps: StatusStep[]
      activeIndex: number
      timeText?: string
      dictCode?: string
    }>(),
    {
      timeText: '-',
      dictCode: 'tmsOrderStatus'
    }
  )

  const iconMap: Record<string, string> = {
    created: 'ri:file-list-3-line',
    pending_load: 'ri:node-tree',
    pending_order: 'ri:hourglass-line',
    pending_pickup: 'ri:archive-drawer-line',
    transporting: 'ri:truck-line',
    signed: 'ri:time-line',
    completed: 'ri:checkbox-circle-fill',
    cancelled: 'ri:close-circle-line'
  }

  const fallbackIcons = [
    'ri:file-list-3-line',
    'ri:node-tree',
    'ri:truck-line',
    'ri:time-line',
    'ri:checkbox-circle-fill'
  ]

  function resolveIcon(value: string, index: number): string {
    return iconMap[value] || fallbackIcons[index] || 'ri:checkbox-circle-line'
  }
</script>

<style scoped lang="scss">
  .order-status-steps {
    display: flex;
    width: 100%;
    padding: 10px 12px 4px;

    &__item {
      position: relative;
      display: flex;
      flex: 1;
      flex-direction: column;
      align-items: center;
      min-width: 0;
      color: var(--art-text-gray-500);

      &.is-finished,
      &.is-active {
        color: var(--el-color-primary);
      }

      &.is-pending {
        .order-status-steps__icon {
          color: var(--art-text-gray-400);
          background: var(--el-fill-color-light);
        }

        .order-status-steps__line {
          border-color: var(--el-border-color);
        }
      }
    }

    &__node {
      position: relative;
      z-index: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 8px;
    }

    &__icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 38px;
      height: 38px;
      font-size: 20px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__dot {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 10px;
      height: 10px;
      font-size: 10px;
      color: var(--el-color-white);
      background: var(--el-color-primary);
      border: 1px solid var(--el-color-primary);
      border-radius: 50%;
    }

    &__line {
      position: absolute;
      top: 51px;
      left: calc(50% + 12px);
      width: calc(100% - 24px);
      border-top: 1px dashed var(--el-color-primary);
    }

    &__content {
      display: grid;
      gap: 4px;
      justify-items: center;
      margin-top: 8px;
      text-align: center;
    }

    &__title {
      font-weight: 600;
      color: var(--art-text-gray-800);
    }

    &__time {
      line-height: 1.4;
      color: var(--el-text-color-secondary);
      white-space: pre-line;
    }
  }

  @media (width <= 992px) {
    .order-status-steps {
      overflow-x: auto;

      &__item {
        flex: 0 0 120px;
      }
    }
  }
</style>
