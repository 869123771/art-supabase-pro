<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle
      >资产先以草稿登记；确认转固后进入折旧与处置生命周期，核心价值字段不可直接修改。</template
    >
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
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
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchAccountSetOptions, fetchAssetCategoryList, saveFixedAsset } from '@/api/fms'

  defineOptions({ name: 'FinanceFixedAssetDialog' })
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const categoryOptions = ref<Array<{ label: string; value: string; life: number; rate: number }>>(
    []
  )
  const initial = (): Api.Fms.SaveFixedAssetPayload => ({
    accountSetId: '',
    categoryId: '',
    assetNo: '',
    assetName: '',
    acquisitionDate: dayjs().format('YYYY-MM-DD'),
    readyForUseDate: dayjs().format('YYYY-MM-DD'),
    depreciationStartDate: dayjs().format('YYYY-MM-DD'),
    originalValue: 0,
    residualValue: 0,
    usefulLifeMonths: 60,
    location: null,
    specification: null,
    serialNo: null,
    remark: null
  })
  const form = reactive(initial())
  const rules: FormRules = {
    accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
    categoryId: [{ required: true, message: '请选择资产类别', trigger: 'change' }],
    assetName: [{ required: true, message: '请输入资产名称', trigger: 'blur' }],
    acquisitionDate: [{ required: true, message: '请选择购置日期', trigger: 'change' }],
    readyForUseDate: [{ required: true, message: '请选择达到可用日期', trigger: 'change' }],
    originalValue: [{ required: true, message: '请输入资产原值', trigger: 'change' }]
  }
  const items = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      span: 24,
      props: { options: accountSetOptions.value, filterable: true, disabled: Boolean(form.id) }
    },
    {
      label: '资产类别',
      key: 'categoryId',
      type: 'select',
      props: { options: categoryOptions.value, filterable: true }
    },
    {
      label: '资产编号',
      key: 'assetNo',
      type: 'input',
      props: { maxlength: 60, placeholder: '留空自动生成' }
    },
    { label: '资产名称', key: 'assetName', type: 'input', props: { maxlength: 120 } },
    { label: '序列号', key: 'serialNo', type: 'input', props: { maxlength: 120 } },
    {
      label: '购置日期',
      key: 'acquisitionDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '达到可用日',
      key: 'readyForUseDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '折旧起始日',
      key: 'depreciationStartDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '资产原值',
      key: 'originalValue',
      type: 'number',
      props: { min: 0.01, precision: 2, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '预计残值',
      key: 'residualValue',
      type: 'number',
      props: { min: 0, precision: 2, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '使用寿命',
      key: 'usefulLifeMonths',
      type: 'number',
      props: { min: 1, max: 1200, controlsPosition: 'right', class: '!w-full' }
    },
    { label: '存放地点', key: 'location', type: 'input', props: { maxlength: 160 } },
    { label: '规格型号', key: 'specification', type: 'input', props: { maxlength: 160 } },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500 }
    }
  ])
  async function loadCategories(accountSetId: string): Promise<void> {
    const { data } = await fetchAssetCategoryList(accountSetId)
    categoryOptions.value = (data ?? [])
      .filter((item) => item.isEnabled)
      .map((item) => ({
        label: `${item.categoryName}（${item.categoryCode}）`,
        value: item.id,
        life: item.defaultUsefulLifeMonths,
        rate: item.defaultResidualRate
      }))
  }
  watch(
    () => form.accountSetId,
    async (value) => {
      if (value) await loadCategories(value)
    }
  )
  watch(
    () => form.categoryId,
    (value) => {
      const item = categoryOptions.value.find((option) => option.value === value)
      if (item && !form.id) {
        form.usefulLifeMonths = item.life
        form.residualValue = Number((form.originalValue * item.rate).toFixed(2))
      }
    }
  )
  async function submit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (
        dayjs(form.readyForUseDate).isBefore(form.acquisitionDate) ||
        dayjs(form.depreciationStartDate).isBefore(form.readyForUseDate)
      ) {
        ElMessage.warning('资产日期顺序不正确')
        return false
      }
      await saveFixedAsset({
        ...form,
        assetNo: form.assetNo.trim(),
        assetName: form.assetName.trim()
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(row?: Api.Fms.FixedAssetRecord): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    Object.assign(
      form,
      initial(),
      row && {
        id: row.id,
        accountSetId: row.accountSetId,
        categoryId: row.categoryId,
        assetNo: row.assetNo,
        assetName: row.assetName,
        acquisitionDate: row.acquisitionDate,
        readyForUseDate: row.readyForUseDate,
        depreciationStartDate: row.depreciationStartDate,
        originalValue: row.originalValue,
        residualValue: row.residualValue,
        usefulLifeMonths: row.usefulLifeMonths,
        location: row.location,
        specification: row.specification,
        serialNo: row.serialNo,
        remark: row.remark
      }
    )
    if (!row) form.accountSetId = accountSetOptions.value[0]?.value ?? ''
    if (form.accountSetId) await loadCategories(form.accountSetId)
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑资产 · ${row.assetNo}` : '新建固定资产',
      confirmText: row ? '保存修改' : '创建草稿',
      onConfirm: submit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }
  defineExpose({ handleOpen })
</script>
