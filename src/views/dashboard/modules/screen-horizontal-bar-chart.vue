<template>
  <div ref="rootRef" class="screen-horizontal-bar-chart">
    <div
      ref="chartRef"
      class="screen-horizontal-bar-chart__canvas"
      role="img"
      :aria-label="chartSummary"
    />
  </div>
</template>

<script setup lang="ts">
  import type { EChartsOption } from '@/plugins/echarts'
  import { echarts } from '@/plugins/echarts'
  import { useChartComponent } from '@/hooks/core/useChart'
  import type { BaseChartProps } from '@/types/component/chart'
  import { useScreenChartTheme } from './screen-chart-theme'

  export interface ScreenHorizontalBarItem {
    label: string
    value: number
    riskValue?: number
    caption?: string
    tone?: 'primary' | 'success' | 'warning' | 'danger' | 'info'
  }

  interface Props extends BaseChartProps {
    items: ScreenHorizontalBarItem[]
    unit?: string
    summaryLabel?: string
    valueLabel?: string
    riskLabel?: string
  }

  const props = withDefaults(defineProps<Props>(), {
    unit: '台',
    summaryLabel: '指标对比',
    valueLabel: '数量',
    riskLabel: '',
    isEmpty: false
  })
  const { rootRef, readScreenColor } = useScreenChartTheme()
  const chartSummary = computed(
    () =>
      `${props.summaryLabel}：${props.items
        .map(
          (item) =>
            `${item.label} ${item.value}${props.unit}${props.riskLabel ? `，${props.riskLabel} ${item.riskValue ?? 0}${props.unit}` : ''}`
        )
        .join('；')}`
  )

  const { chartRef, getAnimationConfig } = useChartComponent({
    props,
    watchSources: [() => props.items, () => props.unit],
    generateOptions: (): EChartsOption => {
      const cyan = readScreenColor('--screen-cyan', '#35c7d7')
      const green = readScreenColor('--asset-green', '#20e3b2')
      const danger = readScreenColor('--screen-danger', '#ff6474')
      const strong = readScreenColor('--screen-text-strong', '#f4f8ff')
      const muted = readScreenColor('--screen-text-muted', '#84a0b8')
      const gridLine = readScreenColor('--screen-chart-grid', 'rgba(105, 168, 185, 0.12)')
      const captionMap = new Map(props.items.map((item) => [item.label, item.caption ?? '']))

      return {
        grid: { left: 4, right: 58, top: 8, bottom: 4, containLabel: true },
        tooltip: {
          trigger: 'axis',
          axisPointer: { type: 'shadow' },
          backgroundColor: 'rgba(5, 17, 29, 0.95)',
          borderColor: gridLine,
          textStyle: { color: strong, fontSize: 11 },
          formatter: (params) => {
            const list = Array.isArray(params) ? params : [params]
            const name =
              list[0] && typeof list[0] === 'object' && 'name' in list[0]
                ? String(list[0].name)
                : ''
            const item = props.items.find((entry) => entry.label === name)
            if (!item) return ''
            return `${name}<br/>${props.valueLabel} ${item.value}${props.unit}${props.riskLabel ? `<br/>${props.riskLabel} ${item.riskValue ?? 0}${props.unit}` : ''}${item.caption ? `<br/>${item.caption}` : ''}`
          }
        },
        xAxis: {
          type: 'value',
          minInterval: 1,
          axisLabel: { show: false },
          axisLine: { show: false },
          axisTick: { show: false },
          splitLine: { show: false }
        },
        yAxis: {
          type: 'category',
          inverse: true,
          data: props.items.map((item) => item.label),
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: {
            width: 72,
            overflow: 'truncate',
            margin: 10,
            color: muted,
            fontSize: 10,
            formatter: (value: string) =>
              `{name|${value}}\n{caption|${captionMap.get(value) ?? ''}}`,
            rich: {
              name: { color: strong, fontSize: 10, fontWeight: 600, lineHeight: 15 },
              caption: { color: muted, fontSize: 8, lineHeight: 12 }
            }
          }
        },
        series: [
          {
            name: props.valueLabel,
            type: 'bar',
            data: props.items.map((item) => ({
              value: item.value,
              itemStyle: item.tone
                ? {
                    color: {
                      primary: readScreenColor('--screen-accent', '#635bff'),
                      success: green,
                      warning: readScreenColor('--screen-warning', '#f4b653'),
                      danger,
                      info: cyan
                    }[item.tone]
                  }
                : undefined
            })),
            barWidth: 12,
            showBackground: true,
            backgroundStyle: { color: gridLine, borderRadius: 6 },
            itemStyle: {
              borderRadius: 6,
              color: new echarts.graphic.LinearGradient(0, 0, 1, 0, [
                { offset: 0, color: green },
                { offset: 1, color: cyan }
              ])
            },
            label: {
              show: true,
              position: 'right',
              distance: 7,
              color: strong,
              fontSize: 11,
              fontWeight: 700,
              formatter: `{c}${props.unit}`
            },
            ...getAnimationConfig(140, 900)
          },
          ...(props.riskLabel
            ? [
                {
                  name: props.riskLabel,
                  type: 'bar' as const,
                  data: props.items.map((item) => item.riskValue ?? 0),
                  barWidth: 4,
                  barGap: '-67%',
                  itemStyle: { color: danger, borderRadius: 3 },
                  z: 3,
                  ...getAnimationConfig(260, 900)
                }
              ]
            : [])
        ]
      }
    }
  })
</script>

<style scoped lang="scss">
  .screen-horizontal-bar-chart,
  .screen-horizontal-bar-chart__canvas {
    width: 100%;
    height: 100%;
    min-height: 0;
  }
</style>
