<template>
  <ArtDialog ref="dialogRef" size="lg">
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
  import dayjs from 'dayjs'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { addWaybillCost, editWaybillCost, fetchFinanceWaybillOptions } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsWaybillCostDialog' })

  type WaybillCost = Api.Tms.Finance.WaybillCostRecord
  type WaybillOption = Api.Tms.Finance.WaybillOption

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<WaybillCost | undefined>>()
  const formRef = ref<FormExpose>()
  const waybillOptions = ref<WaybillOption[]>([])
  const lastAutoPayeeName = ref('')

  const createInitialForm = (): WaybillCost => ({
    id: undefined,
    waybillId: '',
    costType: 'toll',
    amount: 0,
    occurredOn: dayjs().format('YYYY-MM-DD'),
    payeeName: '',
    carrierId: null,
    driverId: null,
    remark: '',
    attachments: [],
    auditStatus: 'draft'
  })

  const form = reactive<WaybillCost>(createInitialForm())

  const formRules: FormRules<WaybillCost> = {
    waybillId: [{ required: true, message: '请选择运单', trigger: 'change' }],
    costType: [{ required: true, message: '请选择费用类型', trigger: 'change' }],
    amount: [
      { required: true, message: '请输入费用金额', trigger: 'blur' },
      {
        validator: (_rule, value, callback) =>
          Number(value) > 0 ? callback() : callback(new Error('费用金额必须大于 0')),
        trigger: 'blur'
      }
    ],
    occurredOn: [{ required: true, message: '请选择发生日期', trigger: 'change' }],
    payeeName: [{ max: 120, message: '收款方不能超过 120 个字符', trigger: 'blur' }],
    remark: [{ max: 500, message: '费用说明不能超过 500 个字符', trigger: 'blur' }]
  }

  const selectedWaybill = computed(() =>
    waybillOptions.value.find((item) => item.id === form.waybillId)
  )

  const formatWaybillOption = (option: WaybillOption): string => {
    const route = [option.originCity, option.destinationCity].filter(Boolean).join(' → ')
    const plateNo = option.order?.dispatchPlateNo
    return [option.waybillNo, route, plateNo].filter(Boolean).join(' · ')
  }

  const syncWaybillOptions = (result: unknown): unknown => {
    const response = result as { data?: WaybillOption[] | null }
    waybillOptions.value = response.data ?? []
    return result
  }

  const suggestPayeeName = (): string => {
    const waybill = selectedWaybill.value
    if (!waybill) return ''
    if (form.costType === 'carrier_freight') {
      return waybill.carrier?.companyName || waybill.order?.dispatchPlateNo || ''
    }
    if (form.costType === 'driver_expense') {
      return waybill.driver?.driverName || waybill.order?.dispatchDriverName || ''
    }
    return ''
  }

  const applySuggestedPayee = (): void => {
    if (form.payeeName && form.payeeName !== lastAutoPayeeName.value) return
    const nextPayeeName = suggestPayeeName()
    form.payeeName = nextPayeeName
    lastAutoPayeeName.value = nextPayeeName
  }

  const handleWaybillChange = (): void => {
    const waybill = selectedWaybill.value
    form.carrierId = waybill?.carrierId || null
    form.driverId = waybill?.driverId || null
    applySuggestedPayee()
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '费用信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '关联运单',
      key: 'waybillId',
      type: 'select',
      span: 24,
      api: fetchFinanceWaybillOptions,
      resultField: 'data',
      labelField: 'waybillNo',
      valueField: 'id',
      labelFn: (option) => formatWaybillOption(option as WaybillOption),
      afterFetch: syncWaybillOptions,
      props: {
        filterable: true,
        clearable: true,
        placeholder: '请选择未取消的运单',
        onChange: handleWaybillChange
      }
    },
    {
      label: '费用类型',
      key: 'costType',
      type: 'select',
      props: {
        options: getDictMap.value.tmsWaybillCostType ?? [],
        placeholder: '请选择费用类型',
        onChange: applySuggestedPayee
      }
    },
    {
      label: '费用金额',
      key: 'amount',
      type: 'number',
      props: {
        min: 0.01,
        precision: 2,
        step: 100,
        controlsPosition: 'right',
        class: '!w-full'
      }
    },
    {
      label: '发生日期',
      key: 'occurredOn',
      type: 'date',
      props: {
        valueFormat: 'YYYY-MM-DD',
        placeholder: '请选择发生日期',
        class: '!w-full'
      }
    },
    {
      label: '收款方',
      key: 'payeeName',
      type: 'input',
      props: { maxlength: 120, placeholder: '承运商、司机或服务商，可选' }
    },
    {
      label: '费用说明',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '填写费用产生原因、票据说明等信息'
      }
    }
  ])

  const replaceForm = (nextForm: WaybillCost): void => {
    Object.keys(form).forEach((key) => delete form[key as keyof WaybillCost])
    Object.assign(form, nextForm)
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    lastAutoPayeeName.value = ''
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload: WaybillCost = {
        ...structuredClone(toRaw(form)),
        amount: Number(form.amount),
        payeeName: form.payeeName?.trim() || null,
        remark: form.remark?.trim() || null
      }
      const type = form.id ? 'edit' : 'add'
      if (type === 'edit') await editWaybillCost(payload)
      else await addWaybillCost(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: WaybillCost): Promise<void> => {
    await resetForm()
    if (row) {
      replaceForm({
        ...createInitialForm(),
        ...structuredClone(toRaw(row)),
        waybill: undefined
      })
    }

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑运单费用' : '登记运单费用',
      subtitle: '费用审核通过后才会计入运单利润和后续结算',
      contentMaxHeight: '70vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
