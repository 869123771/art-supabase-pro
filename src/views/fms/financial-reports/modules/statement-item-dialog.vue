<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      报表行结构、取数方式和现金流方向均进入账套级配置；下拉枚举统一来自系统字典。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :validate-on-rule-change="false"
      :span="12"
      :gutter="20"
      label-width="112px"
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
  import { saveFinancialStatementItem } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceStatementItemDialog' })

  type Item = Api.Fms.FinancialStatementItemRecord
  type FormData = Api.Fms.SaveFinancialStatementItemPayload

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const context = reactive({ items: [] as Item[] })

  const createInitialForm = (): FormData => ({
    id: undefined,
    accountSetId: '',
    statementType: 'balance_sheet',
    parentId: null,
    itemCode: '',
    itemName: '',
    lineNo: 10,
    itemLevel: 1,
    displayStyle: 'normal',
    calculationMethod: 'mapping',
    cashFlowDirection: null,
    isEnabled: true,
    remark: null
  })

  const form = reactive<{ data: FormData; rules: FormRules<FormData> }>({
    data: createInitialForm(),
    rules: {
      itemCode: [
        { required: true, message: '请输入报表项目编码', trigger: 'blur' },
        {
          pattern: /^[A-Z0-9_-]{2,30}$/,
          message: '使用 2 到 30 位大写字母、数字、横线或下划线',
          trigger: 'blur'
        }
      ],
      itemName: [
        { required: true, message: '请输入报表项目名称', trigger: 'blur' },
        { max: 120, message: '项目名称不能超过 120 个字符', trigger: 'blur' }
      ],
      lineNo: [{ required: true, message: '请输入行次', trigger: 'change' }],
      calculationMethod: [{ required: true, message: '请选择计算方式', trigger: 'change' }],
      cashFlowDirection: [
        {
          validator: (_rule, value, callback) => {
            if (
              form.data.statementType === 'cash_flow_statement' &&
              form.data.calculationMethod === 'mapping' &&
              !value
            )
              callback(new Error('现金流量直接取数行必须设置流量方向'))
            else callback()
          },
          trigger: 'change'
        }
      ]
    }
  })

  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const parentOptions = computed(() =>
    context.items
      .filter((item) => item.id !== form.data.id)
      .map((item) => ({
        label: `${'　'.repeat(Math.max(item.itemLevel - 1, 0))}${item.itemCode} ${item.itemName}`,
        value: item.id
      }))
  )

  const formItems = computed<FormItem[]>(() => [
    { label: '项目结构', key: 'structureSection', type: 'divider', span: 24 },
    {
      label: '项目编码',
      key: 'itemCode',
      type: 'input',
      props: {
        maxlength: 30,
        placeholder: '例如：BS510',
        onInput: (value: string) => {
          form.data.itemCode = value.toUpperCase()
        }
      }
    },
    {
      label: '项目名称',
      key: 'itemName',
      type: 'input',
      props: { maxlength: 120, placeholder: '请输入报表展示名称' }
    },
    {
      label: '上级项目',
      key: 'parentId',
      type: 'select',
      span: 24,
      props: {
        options: parentOptions.value,
        filterable: true,
        clearable: true,
        placeholder: '不选择表示一级项目'
      }
    },
    {
      label: '行次',
      key: 'lineNo',
      type: 'number',
      props: { min: 1, max: 99999, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '显示层级',
      key: 'itemLevel',
      type: 'number',
      props: { min: 1, max: 8, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '行样式',
      key: 'displayStyle',
      type: 'select',
      props: { options: getDictMap.value.fmsStatementDisplayStyle ?? [] }
    },
    {
      label: '启用状态',
      key: 'isEnabled',
      type: 'radioGroup',
      props: { options: booleanOptions.value }
    },
    { label: '取数规则', key: 'calculationSection', type: 'divider', span: 24 },
    {
      label: '计算方式',
      key: 'calculationMethod',
      type: 'select',
      span: 12,
      help: '科目取数用于明细行，公式计算用于合计行，标题行不产生金额。',
      props: {
        options: getDictMap.value.fmsStatementCalculationMethod ?? [],
        onChange: (value: Api.Fms.FinancialStatementCalculationMethod) => {
          if (value !== 'mapping') form.data.cashFlowDirection = null
        }
      }
    },
    {
      label: '现金流方向',
      key: 'cashFlowDirection',
      type: 'select',
      span: 12,
      hidden:
        form.data.statementType !== 'cash_flow_statement' ||
        form.data.calculationMethod !== 'mapping',
      props: {
        options: getDictMap.value.fmsCashFlowDirection ?? [],
        clearable: false,
        placeholder: '请选择流入或流出'
      }
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
      await saveFinancialStatementItem({
        ...toRaw(form.data),
        itemCode: form.data.itemCode.trim().toUpperCase(),
        itemName: form.data.itemName.trim(),
        parentId: form.data.parentId || null,
        cashFlowDirection:
          form.data.statementType === 'cash_flow_statement' &&
          form.data.calculationMethod === 'mapping'
            ? form.data.cashFlowDirection
            : null,
        remark: form.data.remark?.trim() || null
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(
    accountSetId: string,
    statementType: Api.Fms.FinancialStatementType,
    items: Item[],
    row?: Item
  ): Promise<void> {
    context.items = items
    Object.assign(form.data, createInitialForm(), {
      ...(row ?? {}),
      id: row?.id,
      accountSetId,
      statementType,
      parentId: row?.parentId ?? null,
      cashFlowDirection: row?.cashFlowDirection ?? null,
      remark: row?.remark ?? null
    })
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑报表项目 · ${row.itemCode}` : '新增报表项目',
      confirmText: row ? '保存修改' : '创建项目',
      contentMaxHeight: '72vh',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
