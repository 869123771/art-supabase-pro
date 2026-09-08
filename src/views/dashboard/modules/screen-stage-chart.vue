<template>
  <div ref="rootRef" class="screen-stage-chart">
    <div ref="chartRef" class="screen-stage-chart__canvas" role="img" :aria-label="chartSummary" />
  </div>
</template>

<script setup lang="ts">
  import type { EChartsOption } from '@/plugins/echarts'
  import { echarts } from '@/plugins/echarts'
  import { useChartComponent } from '@/hooks/core/useChart'
  import type { BaseChartProps } from '@/types/component/chart'
  import { useScreenChartTheme } from './screen-chart-theme'

  export interface ScreenStageChartItem {
    label: string
    value: number
    caption?: string
  }

  interface Props extends BaseChartProps {
    items: ScreenStageChartItem[]
    unit?: string
    accentVar?: string
  }

  const props = withDefaults(defineProps<Props>(), {
    unit: '单',
    accentVar: '--screen-accent',
    isEmpty: false
  })

  const { rootRef, readScreenColor } = useScreenChartTheme()
  const chartSummary = computed(
    () =>
      `阶段分布：${props.items.map((item) => `${item.label} ${item.value}${props.unit}`).join('，')}`
  )

  const { chartRef, getAnimationConfig } = useChartComponent({
    props,
    watchSources: [() => props.items, () => props.unit, () => props.accentVar],
    generateOptions: (): EChartsOption => {
      const accent = readScreenColor(props.accentVar, '#4f7cff')
      const cyan = readScreenColor('--screen-cyan', '#35c7d7')
      const strong = readScreenColor('--screen-text-strong', '#f4f8ff')
      const muted = readScreenColor('--screen-text-muted', '#84a0b8')
      const gridLine = readScreenColor('--screen-chart-grid', 'rgba(120, 157, 187, 0.13)')
      const captionMap = new Map(props.items.map((item) => [item.label, item.caption ?? '']))

      return {
        animation: true,
        grid: { left: 8, right: 8, top: 24, bottom: 56, containLabel: false },
        tooltip: {
          trigger: 'axis',
          axisPointer: { type: 'shadow' },
          backgroundColor: 'rgba(5, 17, 29, 0.94)',
          borderColor: gridLine,
          textStyle: { color: strong, fontSize: 11 },
          formatter: (params) => {
            const first = Array.isArray(params) ? params[0] : params
            if (!first || typeof first !== 'object' || !('name' in first)) return ''
            const name = String(first.name)
            const value = 'value' in first ? Number(first.value) : 0
            const caption = captionMap.get(name)
            return `${name}<br/><strong>${value}${props.unit}</strong>${caption ? `<br/>${caption}` : ''}`
          }
        },
        xAxis: {
          type: 'category',
          data: props.items.map((item) => item.label),
          axisLine: { lineStyle: { color: gridLine } },
          axisTick: { show: false },
          axisLabel: {
            interval: 0,
            margin: 10,
            color: muted,
            fontSize: 10,
            formatter: (value: string) => {
              const caption = captionMap.get(value)
              return caption ? `{label|${value}}\n{caption|${caption}}` : `{label|${value}}`
            },
            rich: {
              label: { color: muted, fontSize: 10, lineHeight: 15 },
              caption: { color: '#607e96', fontSize: 8, lineHeight: 12 }
            }
          }
        },
        yAxis: {
          type: 'value',
          minInterval: 1,
          axisLabel: { show: false },
          axisLine: { show: false },
          axisTick: { show: false },
          splitLine: { lineStyle: { color: gridLine, type: 'dashed' } }
        },
        series: [
          {
            type: 'bar',
            data: props.items.map((item) => item.value),
            barMaxWidth: 34,
            barMinHeight: 2,
            showBackground: true,
            backgroundStyle: { color: gridLine, borderRadius: 4 },
            itemStyle: {
              borderRadius: [4, 4, 1, 1],
              color: new echarts.graphic.LinearGradient(0, 1, 0, 0, [
                { offset: 0, color: accent },
                { offset: 1, color: cyan }
              ])
            },
            label: {
              show: true,
              position: 'top',
              distance: 5,
              color: strong,
              fontSize: 12,
              fontWeight: 700,
              formatter: `{c}${props.unit}`
            },
            ...getAnimationConfig(180, 900)
          }
        ]
      }
    }
  })
</script>

<style scoped lang="scss">
  .screen-stage-chart,
  .screen-stage-chart__canvas {
    width: 100%;
    height: 100%;
    min-height: 0;
  }
</style>
