<template>
  <div ref="rootRef" class="screen-gauge-chart">
    <div
      ref="chartRef"
      class="screen-gauge-chart__canvas"
      role="img"
      :aria-label="`${label} ${safeValue}${suffix}`"
    />
  </div>
</template>

<script setup lang="ts">
  import type { EChartsOption } from '@/plugins/echarts'
  import { useChartComponent } from '@/hooks/core/useChart'
  import type { BaseChartProps } from '@/types/component/chart'
  import { useScreenChartTheme } from './screen-chart-theme'

  interface Props extends BaseChartProps {
    value: number
    label: string
    suffix?: string
    accentVar?: string
  }

  const props = withDefaults(defineProps<Props>(), {
    suffix: '%',
    accentVar: '--screen-accent',
    isEmpty: false
  })

  const { rootRef, readScreenColor } = useScreenChartTheme()
  const safeValue = computed(() => Math.max(0, Math.min(100, Math.round(props.value))))

  const { chartRef, getAnimationConfig } = useChartComponent({
    props,
    watchSources: [() => props.value, () => props.label, () => props.accentVar],
    generateOptions: (): EChartsOption => {
      const accent = readScreenColor(props.accentVar, '#4f7cff')
      const strong = readScreenColor('--screen-text-strong', '#f4f8ff')
      const muted = readScreenColor('--screen-text-muted', '#84a0b8')
      const track = readScreenColor('--screen-chart-track', 'rgba(120, 157, 187, 0.14)')

      return {
        series: [
          {
            type: 'gauge',
            startAngle: 210,
            endAngle: -30,
            min: 0,
            max: 100,
            radius: '94%',
            center: ['50%', '54%'],
            pointer: { show: false },
            progress: {
              show: true,
              width: 11,
              roundCap: true,
              itemStyle: {
                color: accent,
                shadowBlur: 12,
                shadowColor: `${accent}66`
              }
            },
            axisLine: {
              roundCap: true,
              lineStyle: { width: 11, color: [[1, track]] }
            },
            axisTick: { show: false },
            splitLine: { show: false },
            axisLabel: { show: false },
            anchor: { show: false },
            title: {
              show: true,
              offsetCenter: [0, '34%'],
              color: muted,
              fontSize: 10,
              fontWeight: 500
            },
            detail: {
              valueAnimation: true,
              offsetCenter: [0, '-4%'],
              color: strong,
              formatter: (value: number) => `{score|${Math.round(value)}}{unit|${props.suffix}}`,
              rich: {
                score: { color: strong, fontSize: 32, fontWeight: 760 },
                unit: { color: muted, fontSize: 13, fontWeight: 700, padding: [0, 0, 0, 2] }
              }
            },
            data: [{ value: safeValue.value, name: props.label }],
            ...getAnimationConfig(260, 1100)
          }
        ]
      }
    }
  })
</script>

<style scoped lang="scss">
  .screen-gauge-chart,
  .screen-gauge-chart__canvas {
    width: 100%;
    height: 100%;
    min-height: 0;
  }
</style>
