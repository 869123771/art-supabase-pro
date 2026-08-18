<template>
  <ArtDialog ref="dialogRef" size="sm">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="24"
      label-width="96px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { transitionVoucher } from '@/api/fms'

  defineOptions({ name: 'FinanceVoucherActionDialog' })

  type Action = 'reject' | 'void' | 'reverse'

  interface FormData {
    reason: string
    actionDate: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: FormData
    items: ComputedRef<FormItem[]>
    rules: FormRules<FormData>
  }

  const emit = defineEmits<{ success: [action: Action] }>()
  const dialogRef = ref<ArtDialogExpose<Api.Fms.VoucherRecord>>()
  const formRef = ref<FormExpose>()
  const current = shallowRef<Api.Fms.VoucherRecord>()
  const action = ref<Action>('reject')

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: { reason: '', actionDate: dayjs().format('YYYY-MM-DD') },
    items: computed<FormItem[]>(() => [
      ...(action.value === 'reverse'
        ? [
            {
              label: '冲销日期',
              key: 'actionDate',
              type: 'date' as const,
              props: { type: 'date', valueFormat: 'YYYY-MM-DD', class: '!w-full' }
            }
          ]
        : []),
      {
        label: reasonLabel.value,
        key: 'reason',
        type: 'input',
        props: {
          type: 'textarea',
          rows: 4,
          maxlength: 500,
          showWordLimit: true,
          placeholder: `请填写${reasonLabel.value}`
        }
      }
    ]),
    rules: {
      reason: [{ required: true, message: '请填写操作原因', trigger: 'blur' }],
      actionDate: [{ required: true, message: '请选择冲销日期', trigger: 'change' }]
    }
  })

  const reasonLabel = computed(
    () => ({ reject: '驳回原因', void: '作废原因', reverse: '冲销原因' })[action.value]
  )
  const title = computed(
    () =>
      ({ reject: '驳回会计凭证', void: '作废会计凭证', reverse: '冲销已过账凭证' })[action.value]
  )
  const confirmText = computed(
    () => ({ reject: '确认驳回', void: '确认作废', reverse: '生成冲销凭证' })[action.value]
  )

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (!current.value) return false
      await transitionVoucher(
        current.value.id,
        action.value,
        form.data.reason.trim(),
        action.value === 'reverse' ? form.data.actionDate : null
      )
      emit('success', action.value)
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row: Api.Fms.VoucherRecord, nextAction: Action): Promise<void> {
    current.value = row
    action.value = nextAction
    Object.assign(form.data, { reason: '', actionDate: dayjs().format('YYYY-MM-DD') })
    await dialogRef.value?.handleOpen(row, {
      title: `${title.value} · ${row.voucherNo}`,
      subtitle:
        nextAction === 'reverse'
          ? '系统将生成借贷方向相反的新凭证并自动过账，原凭证保持完整历史。'
          : '本次操作会写入凭证审计流水。',
      confirmText: confirmText.value,
      dialogProps: { closeOnClickModal: false },
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate()
    })
  }

  defineExpose({ handleOpen })
</script>
