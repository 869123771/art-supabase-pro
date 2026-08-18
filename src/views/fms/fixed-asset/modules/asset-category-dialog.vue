<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>类别定义折旧方法、默认使用寿命和残值率，新增资产时自动带入。</template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="18"
      label-width="106px"
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
  import { fetchAccountSetOptions, saveAssetCategory } from '@/api/fms'

  defineOptions({ name: 'FinanceAssetCategoryDialog' })
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const initial = (): Api.Fms.SaveAssetCategoryPayload => ({
    accountSetId: '',
    categoryCode: '',
    categoryName: '',
    depreciationMethod: 'straight_line',
    defaultUsefulLifeMonths: 60,
    defaultResidualRate: 0.05,
    isEnabled: true,
    sort: 100,
    remark: null
  })
  const form = reactive(initial())
  const rules: FormRules = {
    accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
    categoryCode: [{ required: true, message: '请输入类别编码', trigger: 'blur' }],
    categoryName: [{ required: true, message: '请输入类别名称', trigger: 'blur' }],
    defaultUsefulLifeMonths: [{ required: true, message: '请输入使用寿命', trigger: 'change' }]
  }
  const items = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      span: 24,
      props: { options: accountSetOptions.value, filterable: true }
    },
    {
      label: '类别编码',
      key: 'categoryCode',
      type: 'input',
      props: { maxlength: 40, placeholder: '例如：EQ' }
    },
    {
      label: '类别名称',
      key: 'categoryName',
      type: 'input',
      props: { maxlength: 80, placeholder: '例如：机器设备' }
    },
    {
      label: '折旧方法',
      key: 'depreciationMethod',
      type: 'select',
      props: { options: [{ label: '平均年限法', value: 'straight_line' }], disabled: true }
    },
    {
      label: '使用寿命',
      key: 'defaultUsefulLifeMonths',
      type: 'number',
      props: { min: 1, max: 1200, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '残值率',
      key: 'defaultResidualRate',
      type: 'number',
      props: {
        min: 0,
        max: 0.9999,
        step: 0.01,
        precision: 4,
        controlsPosition: 'right',
        class: '!w-full'
      }
    },
    {
      label: '排序',
      key: 'sort',
      type: 'number',
      props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
    },
    { label: '启用', key: 'isEnabled', type: 'switch' },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 300 }
    }
  ])
  async function submit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      await saveAssetCategory({
        ...form,
        categoryCode: form.categoryCode.trim().toUpperCase(),
        categoryName: form.categoryName.trim()
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    Object.assign(form, initial(), { accountSetId: accountSetOptions.value[0]?.value ?? '' })
    await dialogRef.value?.handleOpen(undefined, {
      title: '新建资产类别',
      confirmText: '创建类别',
      onConfirm: submit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }
  defineExpose({ handleOpen })
</script>
