<template>
  <ArtDialog ref="dialogRef" size="sm">
    <div class="delivery-sign-dialog">
      <div class="delivery-sign-dialog__summary">
        <span>运单号：{{ form.data.orderNo || '-' }}</span>
        <span>货号：{{ form.data.cargoNo || '-' }}</span>
      </div>
      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="24"
        label-width="86px"
        :show-reset="false"
        :show-submit="false"
      >
        <template #receiptImageUrls>
          <ArtUploadImage
            v-model="form.data.receiptImageUrls"
            title="上传回单"
            :size="128"
            :limit="3"
            multiple
          />
        </template>
      </ArtForm>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import { toNumber } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import { signDeliveryOrder } from '@/api/tms'

  defineOptions({ name: 'TmsDeliverySignDialog' })

  type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
  type SignForm = Api.Tms.Delivery.DeliverySignPayload & {
    orderNo?: string
    cargoNo?: string | null
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: SignForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<SignForm>
  }

  const emit = defineEmits<{
    success: []
  }>()

  const dialogRef = ref<ArtDialogExpose<DeliveryRecord>>()
  const formRef = ref<FormExpose>()

  const moneyProps = {
    min: 0,
    precision: 2,
    controlsPosition: 'right' as const,
    class: '!w-full'
  }

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      receiptImageUrls: [
        {
          required: true,
          validator: (_rule, value: string[] | undefined, callback: (error?: Error) => void) => {
            if (value?.length) {
              callback()
              return
            }
            callback(new Error('请上传回单'))
          },
          trigger: 'change'
        }
      ]
    },
    items: computed<FormItem[]>(() => [
      { label: '代收货款', key: 'signedCodAmount', type: 'number', props: moneyProps },
      { label: '上传回单', key: 'receiptImageUrls', span: 24 }
    ])
  })

  function createInitialForm(): SignForm {
    return {
      id: undefined,
      orderNo: '',
      cargoNo: '',
      orderStatus: 'completed',
      signedCodAmount: 0,
      receiptImageUrls: [],
      signedAt: null
    }
  }

  function moneyValue(value?: number | string | null): number {
    const numericValue = toNumber(value)
    return Number.isFinite(numericValue) ? numericValue : 0
  }

  function normalizePayload(): Api.Tms.Delivery.DeliverySignPayload {
    return {
      id: form.data.id,
      orderStatus: 'completed',
      signedCodAmount: moneyValue(form.data.signedCodAmount),
      receiptImageUrls: [...(form.data.receiptImageUrls ?? [])],
      signedAt: new Date().toISOString()
    }
  }

  async function handleSubmit(): Promise<boolean> {
    if (!form.data.receiptImageUrls?.length) {
      ElMessage.warning('请上传回单')
      return false
    }

    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      await signDeliveryOrder(normalizePayload())
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function resetForm(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleOpen(row: DeliveryRecord): Promise<void> {
    Object.assign(form.data, createInitialForm(), {
      id: row.id,
      orderNo: row.orderNo,
      cargoNo: row.cargoNo,
      signedCodAmount: moneyValue(row.codAmount)
    })
    await dialogRef.value?.handleOpen(row, {
      title: '签收',
      onConfirm: handleSubmit,
      onClose: resetForm
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .delivery-sign-dialog {
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
  }
</style>
