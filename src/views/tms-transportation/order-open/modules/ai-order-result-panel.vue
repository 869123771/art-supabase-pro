<template>
  <section class="ai-order-result art-card-xs">
    <div class="ai-order-result__heading">
      <ArtSectionTitle :show-line="false">识别结果</ArtSectionTitle>
      <ElTag :type="confidenceTagType">可信度 {{ confidencePercent }}%</ElTag>
    </div>

    <ElAlert :title="analysis.summary" type="success" :closable="false" show-icon />

    <ElDescriptions :column="2" border class="ai-order-result__descriptions">
      <ElDescriptionsItem label="发货方">
        {{ displayText(analysis.order.shippingCustomerName) }} /
        {{ displayText(analysis.order.shippingContactName) }}
      </ElDescriptionsItem>
      <ElDescriptionsItem label="收货方">
        {{ displayText(analysis.order.receivingCustomerName) }} /
        {{ displayText(analysis.order.receivingContactName) }}
      </ElDescriptionsItem>
      <ElDescriptionsItem label="运输线路">
        {{ displayText(analysis.order.originStationName) }} →
        {{ displayText(analysis.order.destinationStationName) }}
      </ElDescriptionsItem>
      <ElDescriptionsItem label="货物">{{ cargoSummary }}</ElDescriptionsItem>
      <ElDescriptionsItem label="发货地址" :span="2">
        {{ displayText(analysis.order.shippingAddressDetail) }}
      </ElDescriptionsItem>
      <ElDescriptionsItem label="收货地址" :span="2">
        {{ displayText(analysis.order.receivingAddressDetail) }}
      </ElDescriptionsItem>
    </ElDescriptions>

    <template v-if="analysis.missingFields.length || analysis.warnings.length">
      <ArtSectionTitle class="ai-order-result__confirm">需要确认</ArtSectionTitle>
      <div class="ai-order-result__warnings">
        <ElTag v-for="item in analysis.missingFields" :key="`missing-${item}`" type="warning">
          缺少：{{ item }}
        </ElTag>
        <ElTag v-for="item in analysis.warnings" :key="`warning-${item}`" type="info">
          {{ item }}
        </ElTag>
      </div>
    </template>
  </section>
</template>

<script setup lang="ts">
  import { trim } from 'lodash-es'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'

  defineOptions({ name: 'TmsAiOrderResultPanel' })

  const { analysis } = defineProps<{ analysis: Api.Tms.Order.AiOrderAnalyzeResponse }>()

  const confidencePercent = computed(() => Math.round(analysis.confidence * 100))
  const confidenceTagType = computed<'success' | 'warning' | 'danger'>(() => {
    if (confidencePercent.value >= 80) return 'success'
    if (confidencePercent.value >= 55) return 'warning'
    return 'danger'
  })
  const cargoSummary = computed(() => {
    const items = analysis.order.cargoItems ?? []
    if (!items.length) return '-'
    return items
      .map((item) =>
        [item.cargoName, item.quantity ? `${item.quantity}${item.unit || '件'}` : '']
          .filter(Boolean)
          .join(' ')
      )
      .join('、')
  })

  function displayText(value?: string | null): string {
    return trim(String(value ?? '')) || '-'
  }
</script>

<style scoped lang="scss">
  .ai-order-result {
    padding: 16px;

    &__heading {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;
    }

    &__descriptions {
      margin-top: 14px;
    }

    &__confirm {
      margin-top: 18px;
    }

    &__warnings {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 12px;
    }
  }
</style>
