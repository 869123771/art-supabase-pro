<template>
  <ArtDialog ref="dialogRef" width="760px">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsFinanceRecordDialog' })

  export type FinanceRecordModule = 'cash' | 'invoice' | 'cost'
  interface FormModel {
    direction: string
    counterpartyName: string
    businessDate: string
    amount: number | undefined
    paymentMethod: string
    bankReference: string
    invoiceType: string
    invoiceNo: string
    taxAmount: number | undefined
    waybillNo: string
    costType: string
    vendorName: string
    remark: string
  }
  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<FinanceRecordModule>>()
  const formRef = ref<FormExpose>()
  const currentModule = ref<FinanceRecordModule>('cash')

  const createInitialForm = (): FormModel => ({
    direction: 'receipt',
    counterpartyName: '',
    businessDate: '',
    amount: undefined,
    paymentMethod: 'bank_transfer',
    bankReference: '',
    invoiceType: 'vat_special',
    invoiceNo: '',
    taxAmount: undefined,
    waybillNo: '',
    costType: 'toll',
    vendorName: '',
    remark: ''
  })
  const form = reactive<FormModel>(createInitialForm())

  const formRules: FormRules<FormModel> = {
    counterpartyName: [{ required: true, message: '请输入往来单位', trigger: 'blur' }],
    businessDate: [{ required: true, message: '请选择业务日期', trigger: 'change' }],
    amount: [{ required: true, message: '请输入金额', trigger: 'blur' }],
    waybillNo: [{ required: true, message: '请输入运单号', trigger: 'blur' }]
  }

  const formItems = computed<FormItem[]>(() => {
    if (currentModule.value === 'cash') {
      return [
        {
          label: '收付方向',
          key: 'direction',
          type: 'select',
          props: { options: getDictMap.value.tmsCashDirection ?? [] }
        },
        {
          label: '往来单位',
          key: 'counterpartyName',
          type: 'input',
          props: { placeholder: '客户或承运商名称' }
        },
        {
          label: '收付日期',
          key: 'businessDate',
          type: 'date',
          props: { valueFormat: 'YYYY-MM-DD', placeholder: '请选择日期' }
        },
        {
          label: '收付金额',
          key: 'amount',
          type: 'inputNumber',
          props: { min: 0.01, precision: 2, controlsPosition: 'right' }
        },
        {
          label: '支付方式',
          key: 'paymentMethod',
          type: 'select',
          props: { options: getDictMap.value.tmsCashPaymentMethod ?? [] }
        },
        {
          label: '银行流水号',
          key: 'bankReference',
          type: 'input',
          props: { placeholder: '选填' }
        },
        {
          label: '备注',
          key: 'remark',
          type: 'input',
          span: 24,
          props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
        }
      ]
    }
    if (currentModule.value === 'invoice') {
      return [
        {
          label: '发票方向',
          key: 'direction',
          type: 'select',
          props: { options: getDictMap.value.tmsInvoiceDirection ?? [] }
        },
        {
          label: '往来单位',
          key: 'counterpartyName',
          type: 'input',
          props: { placeholder: '客户或承运商名称' }
        },
        {
          label: '发票类型',
          key: 'invoiceType',
          type: 'select',
          props: { options: getDictMap.value.tmsInvoiceType ?? [] }
        },
        {
          label: '发票号码',
          key: 'invoiceNo',
          type: 'input',
          props: { placeholder: '草稿可暂不填写' }
        },
        {
          label: '开票日期',
          key: 'businessDate',
          type: 'date',
          props: { valueFormat: 'YYYY-MM-DD', placeholder: '请选择日期' }
        },
        {
          label: '不含税金额',
          key: 'amount',
          type: 'inputNumber',
          props: { min: 0.01, precision: 2, controlsPosition: 'right' }
        },
        {
          label: '税额',
          key: 'taxAmount',
          type: 'inputNumber',
          props: { min: 0, precision: 2, controlsPosition: 'right' }
        },
        {
          label: '备注',
          key: 'remark',
          type: 'input',
          span: 24,
          props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
        }
      ]
    }
    return [
      { label: '运单号', key: 'waybillNo', type: 'input', props: { placeholder: '请输入运单号' } },
      {
        label: '费用类型',
        key: 'costType',
        type: 'select',
        props: { options: getDictMap.value.tmsWaybillCostType ?? [] }
      },
      {
        label: '发生日期',
        key: 'businessDate',
        type: 'date',
        props: { valueFormat: 'YYYY-MM-DD', placeholder: '请选择日期' }
      },
      {
        label: '费用金额',
        key: 'amount',
        type: 'inputNumber',
        props: { min: 0.01, precision: 2, controlsPosition: 'right' }
      },
      {
        label: '收款方',
        key: 'vendorName',
        type: 'input',
        span: 24,
        props: { placeholder: '承运商、司机或服务商' }
      },
      {
        label: '费用说明',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]
  })

  async function handleOpen(module: FinanceRecordModule): Promise<void> {
    currentModule.value = module
    Object.assign(form, createInitialForm(), module === 'invoice' ? { direction: 'output' } : {})
    await nextTick()
    formRef.value?.clearValidate()
    const titleMap = { cash: '登记收付款', invoice: '登记发票', cost: '登记运单费用' }
    await dialogRef.value?.handleOpen(module, {
      title: titleMap[module],
      subtitle: '当前为前端交互骨架，下一阶段接入保存、审核和核销逻辑',
      onConfirm: handleSubmit,
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    emit('success')
    return true
  }

  defineExpose({ handleOpen })
</script>
