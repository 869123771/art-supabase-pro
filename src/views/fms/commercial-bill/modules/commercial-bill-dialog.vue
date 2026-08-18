<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      先登记票面与往来信息，保存为草稿；确认收票或出票后进入受控生命周期，不再允许直接修改。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import { storeToRefs } from 'pinia'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchAccountSetOptions, saveCommercialBill } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceCommercialBillDialog' })

  type FormData = Api.Fms.SaveCommercialBillPayload
  type Bill = Api.Fms.CommercialBillRecord

  const emit = defineEmits<{ success: [type: 'add' | 'edit'] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])

  const createInitialForm = (): FormData => ({
    accountSetId: '',
    billNo: '',
    externalBillNo: null,
    direction: 'receivable',
    billType: 'bank_acceptance',
    drawerName: '',
    payeeName: '',
    acceptorName: '',
    counterpartyName: null,
    issueDate: dayjs().format('YYYY-MM-DD'),
    dueDate: dayjs().add(6, 'month').format('YYYY-MM-DD'),
    faceAmount: 0,
    currencyCode: 'CNY',
    transferable: true,
    sourceType: null,
    sourceId: null,
    sourceNo: null,
    attachmentIds: [],
    remark: null
  })

  const form = reactive<{ data: FormData; rules: FormRules<FormData> }>({
    data: createInitialForm(),
    rules: {
      accountSetId: [{ required: true, message: '请选择所属账套', trigger: 'change' }],
      direction: [{ required: true, message: '请选择票据方向', trigger: 'change' }],
      billType: [{ required: true, message: '请选择票据类型', trigger: 'change' }],
      drawerName: [{ required: true, message: '请输入出票人', trigger: 'blur' }],
      payeeName: [{ required: true, message: '请输入收款人', trigger: 'blur' }],
      acceptorName: [{ required: true, message: '请输入承兑人', trigger: 'blur' }],
      issueDate: [{ required: true, message: '请选择出票日', trigger: 'change' }],
      dueDate: [{ required: true, message: '请选择到期日', trigger: 'change' }],
      faceAmount: [
        { required: true, message: '请输入票面金额', trigger: 'change' },
        {
          validator: (_rule, value, callback) =>
            Number(value) > 0 ? callback() : callback(new Error('票面金额必须大于 0')),
          trigger: 'change'
        }
      ],
      currencyCode: [{ required: true, message: '请输入币种代码', trigger: 'blur' }]
    }
  })

  const formItems = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      span: 24,
      props: {
        options: accountSetOptions.value,
        filterable: true,
        disabled: Boolean(form.data.id),
        placeholder: '选择核算账套'
      }
    },
    {
      label: '票据方向',
      key: 'direction',
      type: 'select',
      props: { options: getDictMap.value.fmsBillDirection ?? [], placeholder: '选择方向' }
    },
    {
      label: '票据类型',
      key: 'billType',
      type: 'select',
      props: { options: getDictMap.value.fmsBillType ?? [], placeholder: '选择类型' }
    },
    {
      label: '内部编号',
      key: 'billNo',
      type: 'input',
      props: { maxlength: 60, placeholder: '留空则按票据编号规则自动生成' }
    },
    {
      label: '票面号码',
      key: 'externalBillNo',
      type: 'input',
      props: { maxlength: 120, placeholder: '选填，票面或电子票据号码' }
    },
    {
      label: '出票人',
      key: 'drawerName',
      type: 'input',
      props: { maxlength: 160, placeholder: '出票主体全称' }
    },
    {
      label: '收款人',
      key: 'payeeName',
      type: 'input',
      props: { maxlength: 160, placeholder: '票面收款主体全称' }
    },
    {
      label: '承兑人',
      key: 'acceptorName',
      type: 'input',
      props: { maxlength: 160, placeholder: '银行或企业承兑主体' }
    },
    {
      label: '往来单位',
      key: 'counterpartyName',
      type: 'input',
      props: { maxlength: 160, placeholder: '客户、承运商或其他往来主体' }
    },
    {
      label: '出票日期',
      key: 'issueDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '到期日期',
      key: 'dueDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '票面金额',
      key: 'faceAmount',
      type: 'number',
      props: { min: 0.01, precision: 2, step: 1000, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '币种代码',
      key: 'currencyCode',
      type: 'input',
      props: { maxlength: 3, placeholder: 'CNY' }
    },
    {
      label: '允许背书',
      key: 'transferable',
      type: 'switch',
      props: { activeText: '允许', inactiveText: '禁止' }
    },
    {
      label: '来源单号',
      key: 'sourceNo',
      type: 'input',
      props: { maxlength: 120, placeholder: '选填，对账单、发票或合同编号' }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (dayjs(form.data.dueDate).isBefore(dayjs(form.data.issueDate), 'day')) {
        ElMessage.warning('到期日期不能早于出票日期')
        return false
      }
      await saveCommercialBill({
        ...form.data,
        billNo: form.data.billNo.trim(),
        externalBillNo: form.data.externalBillNo?.trim() || null,
        drawerName: form.data.drawerName.trim(),
        payeeName: form.data.payeeName.trim(),
        acceptorName: form.data.acceptorName.trim(),
        counterpartyName: form.data.counterpartyName?.trim() || null,
        currencyCode: form.data.currencyCode.trim().toUpperCase(),
        sourceNo: form.data.sourceNo?.trim() || null,
        remark: form.data.remark?.trim() || null
      })
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row?: Bill): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    Object.assign(
      form.data,
      createInitialForm(),
      row && {
        id: row.id,
        accountSetId: row.accountSetId,
        billNo: row.billNo,
        externalBillNo: row.externalBillNo ?? null,
        direction: row.direction,
        billType: row.billType,
        drawerName: row.drawerName,
        payeeName: row.payeeName,
        acceptorName: row.acceptorName,
        counterpartyName: row.counterpartyName ?? null,
        issueDate: row.issueDate,
        dueDate: row.dueDate,
        faceAmount: row.faceAmount,
        currencyCode: row.currencyCode,
        transferable: row.transferable,
        sourceType: row.sourceType ?? null,
        sourceId: row.sourceId ?? null,
        sourceNo: row.sourceNo ?? null,
        attachmentIds: row.attachmentIds ?? [],
        remark: row.remark ?? null
      }
    )
    if (!row) form.data.accountSetId = accountSetOptions.value[0]?.value ?? ''
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑票据 · ${row.billNo}` : '新建商业票据',
      confirmText: row ? '保存修改' : '创建草稿',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false, destroyOnClose: true }
    })
  }

  defineExpose({ handleOpen })
</script>
