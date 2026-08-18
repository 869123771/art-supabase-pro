<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>
      手工项目仅适用于自定义或项目维度；业务同步维度请回到对应主数据维护。
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
  import type { FormRules } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { saveAuxiliaryItem } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceAuxiliaryItemDialog' })

  type AuxiliaryItem = Api.Fms.AuxiliaryItemRecord
  type FormData = Api.Fms.SaveAuxiliaryItemPayload

  interface FormGroup {
    data: FormData
    rules: FormRules<FormData>
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()

  const createInitialForm = (): FormData => ({
    id: undefined,
    tenantId: '',
    accountSetId: '',
    auxiliaryTypeId: '',
    itemCode: '',
    itemName: '',
    isEnabled: true,
    sort: 100,
    remark: null
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      itemCode: [
        { required: true, message: '请输入项目编码', trigger: 'blur' },
        { max: 60, message: '项目编码不能超过 60 个字符', trigger: 'blur' }
      ],
      itemName: [
        { required: true, message: '请输入项目名称', trigger: 'blur' },
        { max: 120, message: '项目名称不能超过 120 个字符', trigger: 'blur' }
      ]
    }
  })

  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )
  const formItems = computed<FormItem[]>(() => [
    {
      label: '项目编码',
      key: 'itemCode',
      type: 'input',
      span: 12,
      props: { maxlength: 60, placeholder: '请输入唯一项目编码' }
    },
    {
      label: '项目名称',
      key: 'itemName',
      type: 'input',
      span: 12,
      props: { maxlength: 120, placeholder: '请输入项目名称' }
    },
    {
      label: '启用状态',
      key: 'isEnabled',
      type: 'radioGroup',
      span: 12,
      props: { options: booleanOptions.value }
    },
    {
      label: '排序号',
      key: 'sort',
      type: 'number',
      span: 12,
      props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  function createPayload(): FormData {
    return {
      ...toRaw(form.data),
      itemCode: form.data.itemCode.trim(),
      itemName: form.data.itemName.trim(),
      remark: form.data.remark?.trim() || null
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      await saveAuxiliaryItem(createPayload())
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(
    accountSet: Api.Fms.AccountSetOption,
    type: Api.Fms.AuxiliaryTypeRecord,
    row?: AuxiliaryItem
  ): Promise<void> {
    Object.assign(form.data, createInitialForm(), {
      ...(row ?? {}),
      id: row?.id,
      tenantId: accountSet.tenantId,
      accountSetId: accountSet.value,
      auxiliaryTypeId: type.id,
      remark: row?.remark ?? null
    })
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑项目 · ${row.itemName}` : `新增项目 · ${type.typeName}`,
      confirmText: row ? '保存修改' : '创建项目',
      contentMaxHeight: '65vh',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
