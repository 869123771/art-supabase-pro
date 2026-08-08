<template>
  <ArtDialog ref="dialogRef" size="sm">
    <ElAlert
      class="invoice-counterparty-create__notice"
      :type="form.data.requiresReview ? 'warning' : 'info'"
      :closable="false"
      show-icon
      :title="form.data.direction === 'output' ? '创建客户档案' : '创建承运商档案'"
      :description="noticeDescription"
    />

    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="24"
      label-width="112px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import { ElMessage, type FormRules } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { createInvoiceCounterpartyFromOcr } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsInvoiceCounterpartyCreateDialog' })

  interface CounterpartyCreateOpenData {
    artifactId: string
    direction: Api.Tms.Finance.InvoiceDirection
    name: string
    taxNo?: string | null
    requiresReview: boolean
  }

  interface CounterpartyCreateFormModel extends CounterpartyCreateOpenData {
    carrierType: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: CounterpartyCreateFormModel
    items: ComputedRef<FormItem[]>
    rules: FormRules<CounterpartyCreateFormModel>
  }

  const emit = defineEmits<{
    success: [result: Api.Tms.Finance.CreateInvoiceCounterpartyFromOcrResponse]
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<CounterpartyCreateOpenData>>()
  const formRef = ref<FormExpose>()

  const createInitialForm = (): CounterpartyCreateFormModel => ({
    artifactId: '',
    direction: 'output',
    name: '',
    taxNo: '',
    carrierType: '',
    requiresReview: false
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: reactive<CounterpartyCreateFormModel>(createInitialForm()),
    items: computed(() => [
      {
        label: form.data.direction === 'output' ? '客户名称' : '承运商名称',
        key: 'name',
        type: 'input',
        props: { maxlength: 100, placeholder: '请核对票面单位全称' }
      },
      {
        label: '纳税人识别号',
        key: 'taxNo',
        type: 'input',
        props: { maxlength: 40, placeholder: '请核对统一社会信用代码或税号' }
      },
      {
        label: '承运商类型',
        key: 'carrierType',
        type: 'select',
        hidden: form.data.direction !== 'input',
        props: {
          options: getDictMap.value.tmsCarrierType ?? [],
          placeholder: '请选择承运商类型'
        }
      }
    ]),
    rules: {
      name: [
        { required: true, message: '请输入往来单位名称', trigger: 'blur' },
        { min: 2, max: 100, message: '名称长度应为 2 到 100 个字符', trigger: 'blur' }
      ],
      taxNo: [
        {
          pattern: /^[0-9A-Za-z]{15,20}$/,
          message: '税号应为 15 到 20 位数字或字母',
          trigger: 'blur'
        }
      ],
      carrierType: [
        {
          validator: (_rule, value, callback) => {
            if (form.data.direction === 'input' && !value) {
              callback(new Error('请选择承运商类型'))
              return
            }
            callback()
          },
          trigger: 'change'
        }
      ]
    }
  })

  const noticeDescription = computed(() =>
    form.data.requiresReview
      ? '本次识别可信度较低，请逐项核对后再确认。确认建档会复用当前账号已有的客户或承运商新增权限。'
      : '确认后将按当前租户的税号和完整名称原子查重；已有新增权限即可建档，已存在时直接复用。'
  )

  async function resetForm(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const { data } = await createInvoiceCounterpartyFromOcr({
        artifactId: form.data.artifactId,
        name: form.data.name.trim(),
        taxNo: form.data.taxNo?.trim() || null,
        carrierType: form.data.direction === 'input' ? form.data.carrierType : null
      })
      if (!data) return false
      emit('success', data)
      ElMessage.success(data.created ? '往来单位已建档并自动带入' : '已复用现有往来单位')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(data: CounterpartyCreateOpenData): Promise<void> {
    await resetForm()
    Object.assign(form.data, structuredClone(toRaw(data)), { carrierType: '' })
    await dialogRef.value?.handleOpen(data, {
      title: '确认往来单位建档',
      subtitle: '请核对识别信息，确认后自动回填到当前发票',
      confirmText: '确认建档并带入',
      contentMaxHeight: '65vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .invoice-counterparty-create {
    &__notice {
      margin-bottom: 16px;
    }
  }
</style>
