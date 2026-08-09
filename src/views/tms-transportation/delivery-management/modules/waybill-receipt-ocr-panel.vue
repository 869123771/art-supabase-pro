<template>
  <section class="receipt-ocr art-card-xs">
    <header class="receipt-ocr__header">
      <div class="receipt-ocr__identity">
        <span class="receipt-ocr__icon"><ArtSvgIcon icon="ri-file-search-line" /></span>
        <div>
          <span class="receipt-ocr__eyebrow">AI 回单核验</span>
          <h3>识别签收信息与异常</h3>
          <p>核对运单号、时间、货量及破损、少货、拒收等风险。</p>
        </div>
      </div>
      <ElButton
        type="primary"
        :loading="analyzing"
        :disabled="!imageUrls.length"
        @click="handleAnalyze"
      >
        <ArtSvgIcon v-if="!analyzing" icon="ri-sparkling-2-line" />
        {{ result ? '重新核验' : '开始核验' }}
      </ElButton>
    </header>

    <div class="receipt-ocr__context">
      <span
        ><small>当前运单</small><strong>{{ order.orderNo }}</strong></span
      >
      <span
        ><small>收货人</small><strong>{{ order.receiverName || '未填写' }}</strong></span
      >
      <span
        ><small>计划到达</small
        ><strong>{{ formatDateTime(order.plannedArrivalTime) }}</strong></span
      >
      <span
        ><small>运单数量</small><strong>{{ order.cargoQuantityTotal ?? '未填写' }}</strong></span
      >
    </div>

    <div class="receipt-ocr__body">
      <div class="receipt-ocr__upload">
        <ArtUploadImage v-model="imageUrls" title="上传回单" :size="88" :limit="3" multiple />
        <div>
          <strong>{{
            imageUrls.length ? `已上传 ${imageUrls.length} 张` : '上传 1–3 张回单'
          }}</strong>
          <span>保持运单号、签字、日期及异常备注清晰可见。</span>
        </div>
      </div>

      <div v-if="!result" class="receipt-ocr__guide">
        <div v-for="item in guideItems" :key="item.title">
          <ArtSvgIcon :icon="item.icon" />
          <span
            ><strong>{{ item.title }}</strong
            ><small>{{ item.description }}</small></span
          >
        </div>
      </div>

      <div v-else class="receipt-ocr__result">
        <div class="receipt-ocr__result-head">
          <div>
            <strong>核验完成</strong>
            <ElTag :type="riskTagType" effect="light" round>{{ riskLabel }}</ElTag>
            <ElTag type="info" effect="plain" round>可信度 {{ confidencePercent }}%</ElTag>
          </div>
          <div class="receipt-ocr__result-actions">
            <ElInput
              v-if="
                result.assessment.signals.length &&
                isPlatformSuper &&
                workOrderNumber.rule.value &&
                !workOrderNumber.automatic.value &&
                !workOrder
              "
              v-model="manualWorkOrderNo"
              maxlength="50"
              placeholder="请输入异常工单号"
            />
            <ElButton
              v-if="result.assessment.signals.length && isPlatformSuper"
              type="warning"
              plain
              :loading="creatingWorkOrder"
              :disabled="Boolean(workOrder)"
              @click="handleCreateWorkOrder"
            >
              <ArtSvgIcon icon="ri-file-warning-line" />
              {{ workOrder ? '已生成异常工单' : '生成异常工单' }}
            </ElButton>
            <ElButton type="primary" plain @click="emit('apply', result)">采用识别结果</ElButton>
          </div>
        </div>
        <p>{{ result.summary }}</p>
        <div class="receipt-ocr__fields">
          <span v-for="field in fields" :key="field.label">
            <small>{{ field.label }}</small>
            <strong :class="{ 'is-empty': field.empty }">{{ field.value }}</strong>
          </span>
        </div>
        <div v-if="result.assessment.signals.length" class="receipt-ocr__signals">
          <div v-for="signal in result.assessment.signals" :key="signal.type">
            <ArtSvgIcon icon="ri-error-warning-line" />
            <span
              ><strong>{{ signal.title }}</strong
              ><small>{{ signal.detail }}</small></span
            >
          </div>
          <p v-if="!isPlatformSuper" class="receipt-ocr__readonly-note">
            当前为只读分析模式；异常工单需由平台超级管理员生成并流转。
          </p>
        </div>
        <ElAlert
          v-else
          type="success"
          :closable="false"
          show-icon
          title="未检测到签收异常，仍需人工核对原始回单"
        />
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import { ElMessage } from 'element-plus'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import { analyzeWaybillReceiptByAi, createReceiptExceptionWorkOrder } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'

  defineOptions({ name: 'TmsWaybillReceiptOcrPanel' })

  interface OrderContext {
    id: string
    orderNo: string
    receiverName?: string | null
    plannedArrivalTime?: string | null
    cargoQuantityTotal?: number | null
  }

  const props = defineProps<{ modelValue?: string[]; order: OrderContext }>()
  const emit = defineEmits<{
    'update:modelValue': [value: string[]]
    apply: [result: Api.Tms.Delivery.ReceiptOcrAnalyzeResponse]
    analyzed: [result: Api.Tms.Delivery.ReceiptOcrAnalyzeResponse]
    'work-order-created': [workOrder: Api.Tms.Delivery.ReceiptExceptionWorkOrder]
  }>()

  const guideItems = [
    { icon: 'ri-qr-scan-2-line', title: '票面识别', description: '运单号、签收人、签收时间' },
    { icon: 'ri-scales-3-line', title: '运单核对', description: '收货人、计划时间与货量' },
    { icon: 'ri-alarm-warning-line', title: '异常检测', description: '破损、少货、拒收、部分签收' }
  ]
  const analyzing = ref(false)
  const creatingWorkOrder = ref(false)
  const workOrder = ref<Api.Tms.Delivery.ReceiptExceptionWorkOrder>()
  const manualWorkOrderNo = ref('')
  const workOrderNumber = useDocumentNumberRule('tms.receipt_exception')
  const { isPlatformSuper } = storeToRefs(useUserStore())
  const result = ref<Api.Tms.Delivery.ReceiptOcrAnalyzeResponse>()
  const imageUrls = computed<string[]>({
    get: () => props.modelValue ?? [],
    set: (value) => {
      result.value = undefined
      emit('update:modelValue', value)
    }
  })
  const confidencePercent = computed(() => Math.round((result.value?.confidence ?? 0) * 100))
  const riskTagType = computed(() => {
    const level = result.value?.assessment.riskLevel
    return level === 'critical' || level === 'high'
      ? 'danger'
      : level === 'medium'
        ? 'warning'
        : 'success'
  })
  const riskLabel = computed(() => {
    const labels: Record<Api.Tms.Delivery.ReceiptRiskLevel, string> = {
      none: '未见异常',
      medium: '需要复核',
      high: '高风险',
      critical: '阻断风险'
    }
    return labels[result.value?.assessment.riskLevel ?? 'none']
  })
  const fields = computed(() => {
    const receipt = result.value?.receipt
    if (!receipt) return []
    const resultLabel: Record<Api.Tms.Delivery.ReceiptDeliveryResult, string> = {
      normal: '正常签收',
      damaged: '货物破损',
      shortage: '货物短少',
      refused: '拒收',
      partial: '部分签收',
      unclear: '结论不清'
    }
    return [
      { label: '回单运单号', value: receipt.waybillNo || '未识别', empty: !receipt.waybillNo },
      { label: '签收人', value: receipt.signerName || '未识别', empty: !receipt.signerName },
      { label: '签收时间', value: formatDateTime(receipt.signedAt), empty: !receipt.signedAt },
      { label: '签收结论', value: resultLabel[receipt.deliveryResult], empty: false },
      {
        label: '签收数量',
        value: receipt.signedQuantity === null ? '未识别' : String(receipt.signedQuantity),
        empty: receipt.signedQuantity === null
      },
      {
        label: '破损 / 少货',
        value: `${receipt.damagedQuantity ?? 0} / ${receipt.shortageQuantity ?? 0}`,
        empty: false
      }
    ]
  })

  function formatDateTime(value?: string | null): string {
    return value && dayjs(value).isValid() ? dayjs(value).format('YYYY-MM-DD HH:mm') : '未识别'
  }

  function errorMessage(error: unknown): string {
    if (error && typeof error === 'object' && 'message' in error) {
      const message = (error as { message?: unknown }).message
      if (typeof message === 'string' && message) return message
    }
    return 'AI 回单识别失败，请稍后重试'
  }

  async function handleAnalyze(): Promise<void> {
    if (!imageUrls.value.length || analyzing.value) return
    analyzing.value = true
    try {
      const response = await analyzeWaybillReceiptByAi({
        action: 'analyze',
        imageUrls: imageUrls.value,
        orderId: props.order.id,
        orderNo: props.order.orderNo,
        receiverName: props.order.receiverName,
        plannedArrivalTime: props.order.plannedArrivalTime,
        cargoQuantityTotal: props.order.cargoQuantityTotal
      })
      if (response.error || !response.data) throw response.error || new Error('未返回识别结果')
      result.value = response.data
      workOrder.value = undefined
      emit('analyzed', response.data)
      ElMessage.success('回单核验完成，请确认异常信息')
    } catch (error) {
      ElMessage.error(errorMessage(error))
    } finally {
      analyzing.value = false
    }
  }

  async function handleCreateWorkOrder(): Promise<void> {
    if (!result.value?.assessment.signals.length || creatingWorkOrder.value) return
    if (workOrderNumber.manualRequired(false) && !manualWorkOrderNo.value.trim()) {
      ElMessage.warning('当前异常工单号规则为手工填写，请输入工单号')
      return
    }
    creatingWorkOrder.value = true
    try {
      const created = await createReceiptExceptionWorkOrder({
        artifactId: result.value.artifactId,
        orderId: props.order.id,
        evidenceUrls: imageUrls.value,
        workOrderNo: manualWorkOrderNo.value.trim() || null
      })
      if (!created) throw new Error('异常工单创建结果未返回')
      workOrder.value = created
      emit('work-order-created', created)
      ElMessage.success(`异常工单 ${created.workOrderNo} 已生成`)
    } catch (error) {
      ElMessage.error(errorMessage(error))
    } finally {
      creatingWorkOrder.value = false
    }
  }

  onMounted(() => {
    void workOrderNumber.loadRule()
  })

  function reset(): void {
    result.value = undefined
    analyzing.value = false
    creatingWorkOrder.value = false
    workOrder.value = undefined
  }

  defineExpose({ reset })
</script>

<style scoped lang="scss">
  .receipt-ocr {
    padding: 16px;
    margin-bottom: 16px;
    box-shadow: inset 3px 0 0 rgb(var(--ui-primary) / 72%);

    &__header,
    &__identity,
    &__upload,
    &__result-head,
    &__result-head > div,
    &__guide > div,
    &__signals > div {
      display: flex;
      align-items: center;
    }

    &__header,
    &__result-head {
      gap: 16px;
      justify-content: space-between;
    }

    &__identity {
      gap: 10px;
      min-width: 0;

      h3 {
        margin: 1px 0 2px;
        font-size: 15px;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }
    }

    &__icon {
      display: grid;
      flex: 0 0 38px;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 19px;
      color: rgb(var(--ui-primary));
      background: rgb(var(--ui-primary) / 10%);
      border-radius: var(--el-border-radius-base);
    }

    &__eyebrow {
      font-size: 11px;
      font-weight: 600;
      color: rgb(var(--ui-primary));
      letter-spacing: 0.04em;
    }

    &__context {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
      padding: 10px 0;
      margin-top: 12px;
      border-top: 1px solid var(--art-border-dashed-color);
      border-bottom: 1px solid var(--art-border-dashed-color);

      span,
      small,
      strong {
        min-width: 0;
      }

      span {
        display: flex;
        flex-direction: column;
        gap: 3px;
      }

      small {
        font-size: 11px;
        color: var(--art-text-gray-500);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--art-text-gray-800);
        white-space: nowrap;
      }
    }

    &__body {
      display: grid;
      grid-template-columns: minmax(240px, 0.75fr) minmax(0, 2fr);
      gap: 12px;
      padding-top: 12px;
    }

    &__upload {
      gap: 10px;
      align-items: center;
      min-width: 0;

      > div {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      strong {
        font-size: 13px;
        color: var(--art-text-gray-800);
      }

      span {
        font-size: 12px;
        line-height: 1.5;
        color: var(--art-text-gray-500);
      }
    }

    &__guide {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 8px;

      > div {
        gap: 8px;
        min-width: 0;
        padding: 10px;
        background: rgb(var(--ui-primary) / 3%);
        border: 1px solid rgb(var(--ui-primary) / 10%);
        border-radius: var(--el-border-radius-base);

        > svg {
          flex: 0 0 auto;
          color: rgb(var(--ui-primary));
        }

        span {
          display: flex;
          flex-direction: column;
          gap: 3px;
          min-width: 0;
        }

        strong {
          font-size: 12px;
          color: var(--art-text-gray-800);
        }

        small {
          font-size: 11px;
          line-height: 1.45;
          color: var(--art-text-gray-500);
        }
      }
    }

    &__result {
      min-width: 0;

      > p {
        margin: 8px 0;
        font-size: 12px;
        color: var(--art-text-gray-600);
      }
    }

    &__result-head > div {
      gap: 8px;
    }

    &__result-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
    }

    &__fields {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 8px;
      margin-bottom: 10px;

      span {
        display: flex;
        flex-direction: column;
        gap: 3px;
        min-width: 0;
        padding: 8px 10px;
        background: var(--art-gray-50);
        border-radius: var(--el-border-radius-small);
      }

      small {
        font-size: 11px;
        color: var(--art-text-gray-500);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--art-text-gray-800);
        white-space: nowrap;

        &.is-empty {
          font-weight: 400;
          color: var(--art-text-gray-400);
        }
      }
    }

    &__signals {
      display: grid;
      gap: 6px;

      > div {
        gap: 8px;
        align-items: flex-start;
        padding: 8px 10px;
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
        border-radius: var(--el-border-radius-small);

        span {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        strong {
          font-size: 12px;
        }

        small {
          font-size: 11px;
          line-height: 1.45;
        }
      }
    }

    &__readonly-note {
      padding: 8px 10px;
      margin: 0;
      font-size: 11px;
      color: var(--art-text-gray-500);
      background: var(--art-gray-50);
      border-radius: var(--el-border-radius-small);
    }

    @media (width <= 900px) {
      &__context,
      &__guide,
      &__fields {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__body {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
