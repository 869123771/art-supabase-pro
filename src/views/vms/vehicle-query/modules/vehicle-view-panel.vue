<template>
  <ArtPageSection :card="false" title="车辆视图">
    <div class="vehicle-view-panel">
      <div class="vehicle-view-panel__canvas">
        <svg viewBox="0 0 980 420" role="img" aria-label="车辆视图">
          <path
            class="vehicle-view-panel__body"
            d="M150 255 L180 165 L295 165 L330 220 L760 220 L790 315 L170 315 Z"
          />
          <path class="vehicle-view-panel__body" d="M330 90 H840 Q870 90 870 120 V315 H330 Z" />
          <path class="vehicle-view-panel__line" d="M350 120 H835 V220 H350 Z" />
          <path
            class="vehicle-view-panel__line"
            d="M198 180 L280 180 Q305 180 315 220 L185 220 Z"
          />
          <circle class="vehicle-view-panel__wheel" cx="260" cy="315" r="52" />
          <circle class="vehicle-view-panel__wheel" cx="700" cy="315" r="52" />
          <circle class="vehicle-view-panel__wheel-inner" cx="260" cy="315" r="18" />
          <circle class="vehicle-view-panel__wheel-inner" cx="700" cy="315" r="18" />
          <path class="vehicle-view-panel__dash" d="M230 315 H170 V370 H92" />
          <path class="vehicle-view-panel__dash" d="M560 300 V370 H640" />
          <circle class="vehicle-view-panel__point" cx="205" cy="260" r="9" />
          <circle class="vehicle-view-panel__point" cx="300" cy="162" r="9" />
          <circle class="vehicle-view-panel__point" cx="560" cy="295" r="9" />
        </svg>
        <div class="vehicle-view-panel__tip vehicle-view-panel__tip--left">
          <p>胎压：{{ tirePressure }}</p>
          <p>损坏：{{ damageText }}</p>
          <p>上次检测：{{ lastCheckDate }}</p>
        </div>
        <div class="vehicle-view-panel__tip vehicle-view-panel__tip--right">
          <p>灭火装置</p>
          <p>检测结果：{{ routineResult }}</p>
          <p>上次检测：{{ lastCheckDate }}</p>
        </div>
      </div>
    </div>
  </ArtPageSection>
</template>

<script setup lang="ts">
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import type { VehicleArchive } from './types'
  import { formatDate } from './query-format'

  defineOptions({ name: 'VehicleQueryViewPanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const tirePressure = computed(() => (props.vehicle.tireCount ? '2.5BAR' : '--'))
  const damageText = computed(() => '轻微')
  const lastCheckDate = computed(() => formatDate(props.vehicle.inspectionStartDate))
  const routineResult = computed(() => '正常')
</script>

<style scoped lang="scss">
  .vehicle-view-panel {
    min-height: 560px;
    padding-top: 32px;

    &__canvas {
      position: relative;
      max-width: 980px;
      margin: 0 auto;
    }

    svg {
      width: 100%;
      height: auto;
    }

    &__body {
      fill: #c7c9cc;
      stroke: #4c4f52;
      stroke-width: 2;
    }

    &__line {
      fill: none;
      stroke: #4c4f52;
      stroke-width: 2;
    }

    &__wheel {
      fill: #111;
      stroke: #111;
    }

    &__wheel-inner {
      fill: #e5e7eb;
      stroke: #111;
      stroke-width: 8;
    }

    &__dash {
      fill: none;
      stroke: #3ba6dd;
      stroke-width: 3;
      stroke-dasharray: 12 8;
    }

    &__point {
      opacity: 0.85;
      fill: #9adb6e;
    }

    &__tip {
      position: absolute;
      min-width: 150px;
      padding: 10px 12px;
      font-weight: 600;
      line-height: 1.5;
      color: #fff;
      background: rgb(80 80 80 / 65%);
      box-shadow: 0 6px 12px rgb(0 0 0 / 18%);

      p {
        margin: 0;
      }

      &--left {
        bottom: 4%;
        left: 6%;
      }

      &--right {
        right: 18%;
        bottom: 2%;
      }
    }
  }
</style>
