<template>
  <div ref="rootRef" class="screen-donut-chart">
    <div ref="chartRef" class="screen-donut-chart__canvas" role="img" :aria-label="chartSummary" />
    <div class="screen-donut-chart__legend" aria-hidden="true">
      <div v-for="(item, index) in items.slice(0, 4)" :key="item.label">
        <i :style="{ backgroundColor: resolvedColors[index] }" />
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import type { EChartsOption } from '@/plugins/echarts'
  import { useChartComponent } from '@/hooks/core/useChart'
  import type { BaseChartProps } from '@/types/component/chart'
  import { useScreenChartTheme } from './screen-chart-theme'

  export interface ScreenDonutItem {
    label: string
    value: number
  }

  interface Props extends BaseChartProps {
    items: ScreenDonutItem[]
    centerLabel?: string
    unit?: string
  }

  const props = withDefaults(defineProps<Props>(), {
    centerLabel: '合计',
    unit: '项',
    isEmpty: false
  })
  const { rootRef, readScreenColor } = useScreenChartTheme()
  const total = computed(() => props.items.reduce((sum, item) => sum + item.value, 0))
  const resolvedColors = computed(() => [
    readScreenColor('--screen-warning', '#f4b653'),
    readScreenColor('--screen-danger', '#ff6474'),
    readScreenColor('--screen-cyan', '#35c7d7'),
    readScreenColor('--screen-accent', '#635bff'),
    readScreenColor('--screen-success', '#2bd49b')
  ])
  const chartSummary = computed(
    () =>
      `${props.centerLabel} ${total.value}${props.unit}：${props.items.map((item) => `${item.label} ${item.value}${props.unit}`).join('，')}`
  )

  const { chartRef, getAnimationConfig } = useChartComponent({
    props,
    watchSources: [() => props.items, () => props.centerLabel, () => props.unit],
    generateOptions: (): EChartsOption => {
      const strong = readScreenColor('--screen-text-strong', '#f4f8ff')
      const muted = readScreenColor('--screen-text-muted', '#84a0b8')
      const track = readScreenColor('--screen-chart-track', 'rgba(120, 157, 187, 0.13)')
      const hasValue = total.value > 0
      const chartData = hasValue
        ? props.items
        : [{ label: '暂无异常', value: 1, itemStyle: { color: track } }]

      return {
        title: {
          text: String(total.value),
          subtext: props.centerLabel,
          left: '29%',
          top: '37%',
          textAlign: 'center',
          textStyle: { color: strong, fontSize: 29, fontWeight: 760 },
          subtextStyle: { color: muted, fontSize: 9, lineHeight: 18 }
        },
        tooltip: hasValue
          ? {
              trigger: 'item',
              backgroundColor: 'rgba(5, 17, 29, 0.95)',
              borderColor: track,
              textStyle: { color: strong, fontSize: 11 },
              formatter: `{b}<br/><strong>{c}${props.unit}</strong> · {d}%`
            }
          : { show: false },
        series: [
          {
            type: 'pie',
            radius: ['57%', '78%'],
            center: ['30%', '50%'],
            avoidLabelOverlap: false,
            label: { show: false },
            labelLine: { show: false },
            silent: !hasValue,
            itemStyle: { borderColor: '#091827', borderWidth: hasValue ? 2 : 0, borderRadius: 4 },
            data: chartData.map((item, index) => ({
              name: item.label,
              value: item.value,
              itemStyle:
                'itemStyle' in item ? item.itemStyle : { color: resolvedColors.value[index] }
            })),
            ...getAnimationConfig(180, 900)
          }
        ]
      }
    }
  })
</script>

<style scoped lang="scss">
  .screen-donut-chart {
    position: relative;
    width: 100%;
    height: 100%;
    min-height: 0;

    &__canvas {
      width: 100%;
      height: 100%;
    }

    &__legend {
      position: absolute;
      top: 50%;
      right: 0;
      display: grid;
      gap: 7px;
      width: 44%;
      transform: translateY(-50%);

      > div {
        display: grid;
        grid-template-columns: 6px minmax(0, 1fr) auto;
        gap: 6px;
        align-items: center;
      }

      i {
        width: 5px;
        height: 5px;
        border-radius: 50%;
      }

      span {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 9px;
        color: var(--screen-text-muted);
        white-space: nowrap;
      }

      strong {
        font-size: 12px;
        color: var(--screen-text-strong);
      }
    }
  }
</style>
