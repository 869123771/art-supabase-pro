<template>
  <ArtDialog ref="dialogRef" size="xl">
    <div class="delivery-receipt-dialog">
      <div class="delivery-receipt-dialog__summary">
        <span>运单号：{{ form.data.orderNo || '-' }}</span>
        <span>货号：{{ form.data.cargoNo || '-' }}</span>
      </div>
      <ElAlert
        class="delivery-receipt-dialog__flow-alert"
        type="info"
        :closable="false"
        show-icon
        title="本操作只归档和复核回单，不会结束运输运单；司机仍需提交回场时间、里程与照片。"
      />
      <WaybillReceiptOcrPanel
        ref="ocrPanelRef"
        v-model="form.data.receiptImageUrls"
        :order="orderContext"
        @analyzed="handleAnalyzed"
        @apply="handleApplyOcrResult"
      />
      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="12"
        :gutter="20"
        label-width="86px"
        :show-reset="false"
        :show-submit="false"
      />
      <ElAlert
        v-if="ocrResult?.assessment.signals.length"
        class="delivery-receipt-dialog__review-alert"
        :type="ocrResult.assessment.riskLevel === 'critical' ? 'error' : 'warning'"
        :closable="false"
        show-icon
      >
        <template #title>
          AI 检测到 {{ ocrResult.assessment.signals.length }} 项异常，回单归档前必须人工复核
        </template>
        <ElCheckbox v-model="anomalyAcknowledged">
          我已核对原始回单和运单，确认按当前信息归档
        </ElCheckbox>
      </ElAlert>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import { toNumber } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { archiveDeliveryReceipt, reviewWaybillReceiptOcrArtifact } from '@/api/tms'
  import WaybillReceiptOcrPanel from './waybill-receipt-ocr-panel.vue'

  defineOptions({ name: 'TmsDeliveryReceiptArchiveDialog' })

  type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
  type ReceiptArchiveForm = Api.Tms.Delivery.DeliveryReceiptArchivePayload & {
    orderNo?: string
    cargoNo?: string | null
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: ReceiptArchiveForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<ReceiptArchiveForm>
  }

  interface OcrPanelExpose {
    reset: () => void
  }

  const emit = defineEmits<{
    success: []
  }>()

  const dialogRef = ref<ArtDialogExpose<DeliveryRecord>>()
  const formRef = ref<FormExpose>()
  const ocrPanelRef = ref<OcrPanelExpose>()
  const ocrResult = ref<Api.Tms.Delivery.ReceiptOcrAnalyzeResponse>()
  const anomalyAcknowledged = ref(false)
  const currentRow = shallowRef<DeliveryRecord>()

  const moneyProps = {
    min: 0,
    precision: 2,
    controlsPosition: 'right' as const,
    class: '!w-full'
  }

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      signedAt: [{ required: true, message: '请选择签收时间', trigger: 'change' }]
    },
    items: computed<FormItem[]>(() => [
      { label: '回单归档', key: 'receiptSection', type: 'divider', span: 24 },
      { label: '代收货款', key: 'signedCodAmount', type: 'number', span: 12, props: moneyProps },
      {
        label: '签收时间',
        key: 'signedAt',
        type: 'date',
        span: 12,
        props: {
          type: 'datetime',
          valueFormat: 'YYYY-MM-DD HH:mm:ss',
          class: '!w-full',
          placeholder: '请选择签收时间'
        }
      }
    ])
  })

  const orderContext = computed(() => ({
    id: String(form.data.id ?? ''),
    orderNo: form.data.orderNo || '',
    receiverName: currentRow.value?.receivingContactName,
    plannedArrivalTime: currentRow.value?.plannedArrivalTime,
    cargoQuantityTotal: currentRow.value?.cargoQuantityTotal
  }))

  function createInitialForm(): ReceiptArchiveForm {
    return {
      id: undefined,
      orderNo: '',
      cargoNo: '',
      signedCodAmount: 0,
      receiptImageUrls: [],
      signedAt: dayjs().format('YYYY-MM-DD HH:mm:ss')
    }
  }

  function moneyValue(value?: number | string | null): number {
    const numericValue = toNumber(value)
    return Number.isFinite(numericValue) ? numericValue : 0
  }

  function normalizePayload(): Api.Tms.Delivery.DeliveryReceiptArchivePayload {
    const parsedSignedAt = dayjs(form.data.signedAt)
    return {
      id: form.data.id,
      signedCodAmount: moneyValue(form.data.signedCodAmount),
      receiptImageUrls: [...(form.data.receiptImageUrls ?? [])],
      signedAt: parsedSignedAt.isValid() ? parsedSignedAt.toISOString() : new Date().toISOString()
    }
  }

  async function handleSubmit(): Promise<boolean> {
    if (!form.data.receiptImageUrls?.length) {
      ElMessage.warning('请上传回单')
      return false
    }
    if (ocrResult.value?.assessment.signals.length && !anomalyAcknowledged.value) {
      ElMessage.warning('AI 检测到签收异常，请先核对并勾选人工确认')
      return false
    }

    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      await archiveDeliveryReceipt(normalizePayload())
      await recordOcrReview()
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function resetForm(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    currentRow.value = undefined
    ocrResult.value = undefined
    anomalyAcknowledged.value = false
    ocrPanelRef.value?.reset()
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleOpen(row: DeliveryRecord): Promise<void> {
    if (!row.id) {
      ElMessage.warning('缺少订单 ID，无法归档回单')
      return
    }
    currentRow.value = row
    Object.assign(form.data, createInitialForm(), {
      id: row.id,
      orderNo: row.orderNo,
      cargoNo: row.cargoNo,
      signedCodAmount: moneyValue(row.codAmount),
      receiptImageUrls: [...(row.receiptImageUrls ?? [])],
      signedAt: row.signedAt
        ? dayjs(row.signedAt).format('YYYY-MM-DD HH:mm:ss')
        : dayjs().format('YYYY-MM-DD HH:mm:ss')
    })
    await dialogRef.value?.handleOpen(row, {
      title: '回单复核与归档',
      subtitle: '核对签收凭证与代收款信息；运输完成仍以回场记录为准',
      confirmText: '确认归档',
      contentMaxHeight: '76vh',
      onConfirm: handleSubmit,
      onClose: resetForm
    })
  }

  function handleAnalyzed(result: Api.Tms.Delivery.ReceiptOcrAnalyzeResponse): void {
    ocrResult.value = result
    anomalyAcknowledged.value = false
  }

  function handleApplyOcrResult(result: Api.Tms.Delivery.ReceiptOcrAnalyzeResponse): void {
    handleAnalyzed(result)
    if (result.receipt.signedAt) {
      form.data.signedAt = dayjs(result.receipt.signedAt).format('YYYY-MM-DD HH:mm:ss')
    }
    void nextTick(() => formRef.value?.clearValidate())
    ElMessage.success('识别的签收时间已填入，请继续核对异常信息')
  }

  async function recordOcrReview(): Promise<void> {
    if (!ocrResult.value || !form.data.id) return
    const finalPayload = {
      ...ocrResult.value.receipt,
      signedAt: form.data.signedAt,
      signedCodAmount: moneyValue(form.data.signedCodAmount),
      anomalyAcknowledged: anomalyAcknowledged.value,
      receiptImageUrls: [...(form.data.receiptImageUrls ?? [])]
    }
    const { error } = await reviewWaybillReceiptOcrArtifact({
      action: 'review',
      artifactId: ocrResult.value.artifactId,
      entityId: form.data.id,
      outcome: 'applied',
      finalPayload
    })
    if (error) ElMessage.warning('回单已归档，但 AI 质量记录失败；不影响正式业务数据')
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .delivery-receipt-dialog {
    &__summary {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
      padding: 10px 12px;
      margin-bottom: 16px;
      color: var(--art-gray-700);
      background: var(--art-gray-100);
      border-radius: var(--el-border-radius-base);
    }

    &__review-alert {
      margin-top: 16px;

      :deep(.el-alert__content) {
        width: 100%;
      }

      :deep(.el-checkbox) {
        margin-top: 8px;
        white-space: normal;
      }
    }

    &__flow-alert {
      margin-bottom: 16px;
    }
  }
</style>
