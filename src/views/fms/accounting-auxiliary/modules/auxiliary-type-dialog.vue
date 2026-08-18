<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>
      系统维度的编码和主数据来源受保护；手工维度可用于企业自定义核算口径。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="108px"
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
  import { saveAuxiliaryType } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceAuxiliaryTypeDialog' })

  type AuxiliaryType = Api.Fms.AuxiliaryTypeRecord
  type FormData = Api.Fms.SaveAuxiliaryTypePayload

  interface FormGroup {
    data: FormData
    rules: FormRules<FormData>
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const context = reactive({ isSystem: false })

  const createInitialForm = (): FormData => ({
    id: undefined,
    tenantId: '',
    accountSetId: '',
    typeCode: '',
    typeName: '',
    sourceType: 'manual',
    isEnabled: true,
    sort: 100,
    remark: null
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      typeCode: [
        { required: true, message: '请输入维度编码', trigger: 'blur' },
        {
          pattern: /^[A-Z][A-Z0-9_]{1,29}$/,
          message: '使用 2 到 30 位大写字母、数字或下划线',
          trigger: 'blur'
        }
      ],
      typeName: [
        { required: true, message: '请输入维度名称', trigger: 'blur' },
        { max: 60, message: '维度名称不能超过 60 个字符', trigger: 'blur' }
      ],
      sourceType: [{ required: true, message: '请选择主数据来源', trigger: 'change' }]
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
      label: '维度名称',
      key: 'typeName',
      type: 'input',
      span: 12,
      props: { maxlength: 60, placeholder: '例如：业务区域' }
    },
    {
      label: '维度编码',
      key: 'typeCode',
      type: 'input',
      span: 12,
      props: {
        maxlength: 30,
        disabled: context.isSystem,
        placeholder: '例如：REGION',
        onInput: (value: string) => {
          form.data.typeCode = value.toUpperCase()
        }
      }
    },
    {
      label: '主数据来源',
      key: 'sourceType',
      type: 'select',
      span: 12,
      help: '客户、承运商、部门和员工维度由对应业务档案同步。',
      props: {
        options: getDictMap.value.fmsAuxiliarySourceType ?? [],
        disabled: context.isSystem,
        placeholder: '请选择来源'
      }
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
      typeCode: form.data.typeCode.trim().toUpperCase(),
      typeName: form.data.typeName.trim(),
      remark: form.data.remark?.trim() || null
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      await saveAuxiliaryType(createPayload())
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(
    accountSet: Api.Fms.AccountSetOption,
    row?: AuxiliaryType
  ): Promise<void> {
    context.isSystem = row?.isSystem ?? false
    Object.assign(form.data, createInitialForm(), {
      ...(row ?? {}),
      id: row?.id,
      tenantId: accountSet.tenantId,
      accountSetId: accountSet.value,
      remark: row?.remark ?? null
    })
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑维度 · ${row.typeName}` : '新增辅助核算维度',
      confirmText: row ? '保存修改' : '创建维度',
      contentMaxHeight: '65vh',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
