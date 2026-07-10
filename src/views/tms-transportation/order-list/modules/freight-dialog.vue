<template>
  <ArtDialog ref="dialogRef" width="560px">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      root-class="order-freight-dialog__form"
      :items="form.items"
      :rules="form.rules"
      :span="24"
      label-width="86px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import { toNumber } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { editOrderFreight } from '@/api/tms'

  defineOptions({ name: 'TmsOrderFreightDialog' })

  type OrderRecord = Api.Tms.Order.OrderRecord
  type FreightForm = Api.Tms.Order.OrderFreightPayload & {
    orderNo?: string
    cargoNo?: string | null
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: FreightForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<FreightForm>
  }

  const emit = defineEmits<{
    success: []
  }>()

  const dialogRef = ref<ArtDialogExpose<OrderRecord>>()
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
      totalFee: [{ required: true, message: '请输入总运费', trigger: 'blur' }]
    },
    items: computed<FormItem[]>(() => [
      { label: '运单号', key: 'orderNo', type: 'text', span: 12 },
      { label: '货号', key: 'cargoNo', type: 'text', span: 12 },
      { label: '总运费', key: 'totalFee', type: 'number', props: moneyProps }
    ])
  })

  function createInitialForm(): FreightForm {
    return {
      id: undefined,
      orderNo: '',
      cargoNo: '',
      totalFee: 0
    }
  }

  function resetForm(): void {
    Object.assign(form.data, createInitialForm())
    void nextTick(() => formRef.value?.clearValidate())
  }

  function moneyValue(value?: number | string | null): number {
    const parsed = toNumber(value ?? 0)
    return Number.isFinite(parsed) ? parsed : 0
  }

  function normalizePayload(): Api.Tms.Order.OrderFreightPayload {
    return {
      id: form.data.id,
      totalFee: moneyValue(form.data.totalFee)
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      await editOrderFreight(normalizePayload())
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row: OrderRecord): Promise<void> {
    Object.assign(form.data, createInitialForm(), {
      id: row.id,
      orderNo: row.orderNo,
      cargoNo: row.cargoNo,
      totalFee: moneyValue(row.totalFee)
    })
    await dialogRef.value?.handleOpen(row, {
      title: '修改运费',
      onConfirm: handleSubmit,
      onClose: resetForm
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss"></style>
