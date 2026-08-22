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
  import {
    fetchAccountSetOptions,
    fetchAssetCategoryList,
    fetchFixedAssetDetail,
    saveFixedAsset
  } from '@/api/fms'
  import { canEditField, canViewField } from '@/utils/field-permission'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinanceFixedAssetDialog' })
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const currentRecord = shallowRef<Api.Fms.FixedAssetRecord>()
  const fieldAccess = ref<Api.Fms.FixedAssetFieldAccessMap>({})
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
    departmentId: null,
    employeeId: null,
    location: null,
    specification: null,
    serialNo: null,
    sourceType: null,
    sourceId: null,
    sourceNo: null,
    remark: null
  })
  const form = reactive(initial())
  const isEditing = computed(() => Boolean(form.id))
  const canView = (field: Api.Fms.FixedAssetFieldKey): boolean =>
    !isEditing.value || canViewField(fieldAccess.value, field)
  const canEdit = (field: Api.Fms.FixedAssetFieldKey): boolean =>
    !isEditing.value || canEditField(fieldAccess.value, field)
  const rules: FormRules = {
    accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
    categoryId: [{ required: true, message: '请选择资产类别', trigger: 'change' }],
    assetName: [{ required: true, message: '请输入资产名称', trigger: 'blur' }],
    acquisitionDate: [{ required: true, message: '请选择购置日期', trigger: 'change' }],
    readyForUseDate: [{ required: true, message: '请选择达到可用日期', trigger: 'change' }],
    originalValue: [
      {
        validator: (_rule, value, callback) => {
          if (!canEdit('assetValues') || Number(value) > 0) return callback()
          callback(new Error('请输入大于 0 的资产原值'))
        },
        trigger: 'change'
      }
    ]
  }
  const items = computed<FormItem[]>(() => {
    const result: FormItem[] = [
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
      { label: '资产名称', key: 'assetName', type: 'input', props: { maxlength: 120 } }
    ]

    if (canView('assetReferences')) {
      const referenceItems: Array<[string, 'serialNo' | 'specification' | 'sourceNo', string]> = [
        ['序列号', 'serialNo', '设备序列号或唯一标识'],
        ['规格型号', 'specification', '资产规格、品牌或型号'],
        ['来源单号', 'sourceNo', '采购单、验收单或调拨单号']
      ]
      result.push(
        ...referenceItems.map(([label, key, placeholder]) =>
          canEdit('assetReferences')
            ? {
                label,
                key,
                type: 'input' as const,
                props: { maxlength: 160, placeholder }
              }
            : {
                label,
                key: `__${key}Display`,
                type: 'input' as const,
                props: { modelValue: currentRecord.value?.[key] || '--', disabled: true }
              }
        )
      )
    }

    result.push(
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
      }
    )

    if (canView('assetValues')) {
      result.push(
        ...(canEdit('assetValues')
          ? [
              {
                label: '资产原值',
                key: 'originalValue',
                type: 'number' as const,
                props: {
                  min: 0.01,
                  precision: 2,
                  controlsPosition: 'right',
                  class: '!w-full'
                }
              },
              {
                label: '预计残值',
                key: 'residualValue',
                type: 'number' as const,
                props: { min: 0, precision: 2, controlsPosition: 'right', class: '!w-full' }
              }
            ]
          : [
              {
                label: '资产原值',
                key: '__originalValueDisplay',
                type: 'input' as const,
                props: {
                  modelValue: formatProtectedAmount(currentRecord.value?.originalValue),
                  disabled: true
                }
              },
              {
                label: '预计残值',
                key: '__residualValueDisplay',
                type: 'input' as const,
                props: {
                  modelValue: formatProtectedAmount(currentRecord.value?.residualValue),
                  disabled: true
                }
              }
            ])
      )
    }

    result.push({
      label: '使用寿命',
      key: 'usefulLifeMonths',
      type: 'number',
      props: { min: 1, max: 1200, controlsPosition: 'right', class: '!w-full' }
    })

    if (canView('assetCustody')) {
      result.push(
        canEdit('assetCustody')
          ? {
              label: '存放地点',
              key: 'location',
              type: 'input',
              props: { maxlength: 160, placeholder: '仓库、办公室或设备安装地点' }
            }
          : {
              label: '存放地点',
              key: '__locationDisplay',
              type: 'input',
              props: { modelValue: currentRecord.value?.location || '--', disabled: true }
            }
      )
    }

    result.push({
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500 }
    })
    return result
  })
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
        form.residualValue = Number((Number(form.originalValue ?? 0) * item.rate).toFixed(2))
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
      const payload: Api.Fms.SaveFixedAssetPayload = {
        id: form.id,
        accountSetId: form.accountSetId,
        categoryId: form.categoryId,
        assetNo: form.assetNo.trim(),
        assetName: form.assetName.trim(),
        acquisitionDate: form.acquisitionDate,
        readyForUseDate: form.readyForUseDate,
        depreciationStartDate: form.depreciationStartDate,
        usefulLifeMonths: form.usefulLifeMonths,
        ...(canEdit('assetValues')
          ? {
              originalValue: Number(form.originalValue),
              residualValue: Number(form.residualValue ?? 0)
            }
          : {}),
        ...(canEdit('assetCustody')
          ? {
              departmentId: form.departmentId || null,
              employeeId: form.employeeId || null,
              location: form.location?.trim() || null
            }
          : {}),
        ...(canEdit('assetReferences')
          ? {
              specification: form.specification?.trim() || null,
              serialNo: form.serialNo?.trim() || null,
              sourceType: form.sourceType || null,
              sourceId: form.sourceId || null,
              sourceNo: form.sourceNo?.trim() || null
            }
          : {}),
        remark: form.remark?.trim() || null
      }
      await saveFixedAsset(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(row?: Api.Fms.FixedAssetRecord): Promise<void> {
    const { data: accountSets } = await fetchAccountSetOptions({
      status: 'active',
      from: 0,
      to: 999
    })
    accountSetOptions.value = accountSets ?? []
    const record = row ? ((await fetchFixedAssetDetail(row.id)).data ?? row) : undefined
    currentRecord.value = record
    fieldAccess.value = record?.fieldAccess ?? {}
    Object.assign(
      form,
      initial(),
      record && {
        id: record.id,
        accountSetId: record.accountSetId,
        categoryId: record.categoryId,
        assetNo: record.assetNo,
        assetName: record.assetName,
        acquisitionDate: record.acquisitionDate,
        readyForUseDate: record.readyForUseDate,
        depreciationStartDate: record.depreciationStartDate,
        originalValue: canEditField(record.fieldAccess, 'assetValues')
          ? toEditableNumber(record.originalValue)
          : undefined,
        residualValue: canEditField(record.fieldAccess, 'assetValues')
          ? toEditableNumber(record.residualValue)
          : undefined,
        usefulLifeMonths: record.usefulLifeMonths,
        departmentId: canEditField(record.fieldAccess, 'assetCustody') ? record.departmentId : null,
        employeeId: canEditField(record.fieldAccess, 'assetCustody') ? record.employeeId : null,
        location: canEditField(record.fieldAccess, 'assetCustody') ? record.location : null,
        specification: canEditField(record.fieldAccess, 'assetReferences')
          ? record.specification
          : null,
        serialNo: canEditField(record.fieldAccess, 'assetReferences') ? record.serialNo : null,
        sourceType: canEditField(record.fieldAccess, 'assetReferences') ? record.sourceType : null,
        sourceId: canEditField(record.fieldAccess, 'assetReferences') ? record.sourceId : null,
        sourceNo: canEditField(record.fieldAccess, 'assetReferences') ? record.sourceNo : null,
        remark: record.remark
      }
    )
    if (!record) form.accountSetId = accountSetOptions.value[0]?.value ?? ''
    if (form.accountSetId) await loadCategories(form.accountSetId)
    await dialogRef.value?.handleOpen(undefined, {
      title: record ? `编辑资产 · ${record.assetNo}` : '新建固定资产',
      confirmText: record ? '保存修改' : '创建草稿',
      onConfirm: submit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }

  function toEditableNumber(
    value: Api.Tms.BasicData.SensitiveNumber | undefined
  ): number | undefined {
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : undefined
  }

  function formatProtectedAmount(value: Api.Tms.BasicData.SensitiveNumber | undefined): string {
    if (value === null || value === undefined || value === '') return '--'
    return formatCurrencyValue(value)
  }
  defineExpose({ handleOpen })
</script>
