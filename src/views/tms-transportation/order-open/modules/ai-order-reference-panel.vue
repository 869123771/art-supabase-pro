<template>
  <section class="ai-order-reference art-card-xs">
    <div class="ai-order-reference__heading">
      <div>
        <ArtSectionTitle :show-line="false">主数据匹配</ArtSectionTitle>
        <p>系统已按当前租户检索可关联档案。</p>
      </div>
      <div>
        <ElTag type="success" effect="plain">已匹配 {{ matchedCount }}</ElTag>
        <ElTag v-if="pendingCount" type="warning" effect="plain"> 待建档 {{ pendingCount }} </ElTag>
      </div>
    </div>
    <div class="ai-order-reference__list">
      <div v-for="item in rows" :key="item.key">
        <span class="ai-order-reference__item-label">{{ item.label }}</span>
        <span class="ai-order-reference__item-content">
          <strong :title="item.value">{{ item.value }}</strong>
          <ElTag :type="tagType(item.status)" effect="light" size="small">
            {{ statusText(item.status) }}
          </ElTag>
        </span>
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
  const matchedCount = computed(() => rows.value.filter((item) => item.status === 'matched').length)
  const pendingCount = computed(
    () => rows.value.filter((item) => item.status === 'unmatched').length
  )

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

    &__heading {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;

      p {
        margin: 6px 0 0;
        color: var(--el-text-color-secondary);
      }

      > div:last-child {
        display: flex;
        flex: none;
        flex-wrap: wrap;
        gap: 6px;
        justify-content: flex-end;
      }
    }

    &__list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
      margin-top: 14px;

      > div {
        min-width: 0;
        padding: 10px 12px;
        background: var(--art-main-bg-color);
        border-radius: var(--el-border-radius-base);
      }
    }

    &__item-label {
      display: block;
      margin-bottom: 6px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    &__item-content {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
      min-width: 0;

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

    @media (width <= 620px) {
      &__heading {
        flex-direction: column;

        > div:last-child {
          justify-content: flex-start;
        }
      }

      &__list {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
