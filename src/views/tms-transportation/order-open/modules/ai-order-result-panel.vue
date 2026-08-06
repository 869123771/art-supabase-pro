<template>
  <section class="ai-order-result art-card-xs">
    <div class="ai-order-result__heading">
      <ArtSectionTitle :show-line="false">识别结果</ArtSectionTitle>
      <ElTag :type="confidenceTagType">可信度 {{ confidencePercent }}%</ElTag>
    </div>

    <div class="ai-order-result__summary">
      <ArtSvgIcon icon="ri:checkbox-circle-line" />
      <div>
        <strong>识别完成</strong>
        <p>{{ analysis.summary }}</p>
      </div>
    </div>

    <div v-if="lowConfidenceFields.length" class="ai-order-result__confidence">
      <span>建议重点核对：</span>
      <ElTag v-for="field in lowConfidenceFields" :key="field" type="warning" effect="plain">
        {{ field }}
      </ElTag>
    </div>

    <ArtDescriptions
      :data="analysis.order"
      :items="descriptionItems"
      :columns="2"
      class="ai-order-result__descriptions"
    />

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

    <ArtAiFeedback
      :run-id="analysis.runId"
      context-label="AI 智能填单"
      class="ai-order-result__feedback"
    />
  </section>
</template>

<script setup lang="ts">
  import { trim } from 'lodash-es'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'

  defineOptions({ name: 'TmsAiOrderResultPanel' })

  const { analysis } = defineProps<{ analysis: Api.Tms.Order.AiOrderAnalyzeResponse }>()
  type AiOrder = Api.Tms.Order.AiOrderAnalyzeResponse['order']

  const confidencePercent = computed(() => Math.round(analysis.confidence * 100))
  const confidenceTagType = computed<'success' | 'warning' | 'danger'>(() => {
    if (confidencePercent.value >= 80) return 'success'
    if (confidencePercent.value >= 55) return 'warning'
    return 'danger'
  })
  const lowConfidenceFields = computed(() => {
    const labels: Record<string, string> = {
      originStationName: '发货站',
      destinationStationName: '到货站',
      deliveryMethod: '配送方式',
      shippingCustomerName: '发货客户',
      shippingContactName: '发货联系人',
      shippingContactPhone: '发货电话',
      shippingAddressDetail: '发货地址',
      receivingCustomerName: '收货客户',
      receivingContactName: '收货联系人',
      receivingContactPhone: '收货电话',
      receivingAddressDetail: '收货地址',
      cargoItems: '货物信息',
      paymentMethod: '付款方式',
      transportMode: '运输方式'
    }
    return Object.entries(analysis.fieldConfidence ?? {})
      .filter(([, confidence]) => confidence < 0.65)
      .map(([field]) => labels[field] ?? field)
      .slice(0, 8)
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
  const descriptionItems = computed<ArtDescriptionItem<AiOrder>[]>(() => [
    {
      key: 'shippingParty',
      label: '发货方',
      value: (data: AiOrder) =>
        `${displayText(data.shippingCustomerName)} / ${displayText(data.shippingContactName)}`
    },
    {
      key: 'receivingParty',
      label: '收货方',
      value: (data: AiOrder) =>
        `${displayText(data.receivingCustomerName)} / ${displayText(data.receivingContactName)}`
    },
    {
      key: 'route',
      label: '运输线路',
      value: (data: AiOrder) =>
        `${displayText(data.originStationName)} → ${displayText(data.destinationStationName)}`
    },
    { key: 'cargo', label: '货物', value: cargoSummary.value },
    { key: 'shippingAddress', label: '发货地址', field: 'shippingAddressDetail', span: 2 },
    { key: 'receivingAddress', label: '收货地址', field: 'receivingAddressDetail', span: 2 }
  ])

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

    &__summary {
      display: flex;
      gap: 10px;
      align-items: flex-start;
      padding: 12px 14px;
      color: var(--el-color-success-dark-2);
      background: color-mix(in srgb, var(--el-color-success) 8%, var(--default-box-color));
      border-left: 3px solid var(--el-color-success);
      border-radius: var(--el-border-radius-base);

      > svg {
        flex: none;
        margin-top: 2px;
        font-size: 18px;
      }

      strong,
      p {
        display: block;
      }

      p {
        margin: 4px 0 0;
        line-height: 1.55;
        color: var(--el-text-color-regular);
        overflow-wrap: anywhere;
      }
    }

    &__confidence {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
      margin-top: 12px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
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

    &__feedback {
      margin-top: 16px;
    }
  }
</style>
