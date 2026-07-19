<template>
  <section class="ai-order-reference art-card-xs">
    <ArtSectionTitle>主数据匹配</ArtSectionTitle>
    <div class="ai-order-reference__list">
      <div v-for="item in rows" :key="item.key">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
        <ElTag :type="tagType(item.status)" effect="light">
          {{ statusText(item.status) }}
        </ElTag>
      </div>
    </div>
    <p class="ai-order-reference__hint">
      已匹配资料会直接关联；未匹配且资料完整的项目可在下方确认后一键建档。
    </p>
  </section>
</template>

<script setup lang="ts">
  import { trim } from 'lodash-es'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import type { AiOrderReferenceMatches, AiReferenceStatus } from './ai-order-types'

  defineOptions({ name: 'TmsAiOrderReferencePanel' })

  type ReferenceKey = Exclude<keyof AiOrderReferenceMatches, 'cargoItems'>

  interface ReferenceRow {
    key: string
    label: string
    value: string
    status: AiReferenceStatus
  }

  const { analysis, references } = defineProps<{
    analysis: Api.Tms.Order.AiOrderAnalyzeResponse
    references: AiOrderReferenceMatches
  }>()

  const rows = computed<ReferenceRow[]>(() => {
    const baseRows = [
      createRow('originStation', '发货站', analysis.order.originStationName),
      createRow('destinationStation', '到货站', analysis.order.destinationStationName),
      createRow('transferStation', '中转站', analysis.order.transferStationName),
      createRow('shippingCustomer', '发货客户', analysis.order.shippingCustomerName),
      createRow('shippingAddress', '发货地址', analysis.order.shippingAddressDetail),
      createRow('receivingCustomer', '收货客户', analysis.order.receivingCustomerName),
      createRow('receivingAddress', '收货地址', analysis.order.receivingAddressDetail)
    ]
    const cargoRows = references.cargoItems.map((reference) => ({
      key: `cargo:${reference.index}`,
      label: `货物 ${reference.index + 1}`,
      value:
        reference.label ||
        trim(String(analysis.order.cargoItems?.[reference.index]?.cargoName ?? '')) ||
        '-',
      status: reference.status
    }))
    return [...baseRows, ...cargoRows]
  })

  function createRow(key: ReferenceKey, label: string, source?: string | null): ReferenceRow {
    const match = references[key]
    return {
      key,
      label,
      value: match.label || trim(String(source ?? '')) || '-',
      status: match.status
    }
  }

  function tagType(status: AiReferenceStatus): 'success' | 'warning' | 'info' {
    if (status === 'matched') return 'success'
    if (status === 'unmatched') return 'warning'
    return 'info'
  }

  function statusText(status: AiReferenceStatus): string {
    if (status === 'matched') return '已匹配'
    if (status === 'unmatched') return '待建档'
    return '未识别'
  }
</script>

<style scoped lang="scss">
  .ai-order-reference {
    padding: 16px;

    &__list {
      display: grid;
      gap: 10px;
      margin-top: 12px;

      > div {
        display: grid;
        grid-template-columns: 92px minmax(0, 1fr) auto;
        gap: 12px;
        align-items: center;
        min-height: 34px;
      }

      span {
        color: var(--el-text-color-secondary);
      }

      strong {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-weight: 500;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    &__hint {
      margin: 12px 0 0;
      line-height: 1.6;
      color: var(--el-text-color-secondary);
    }
  }
</style>
