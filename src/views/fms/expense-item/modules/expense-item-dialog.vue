<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>分组用于组织层级；可记账项目会出现在运单费用的必选字段中。</template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :validate-on-rule-change="false"
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
  import { addExpenseItem, editExpenseItem, fetchExpenseItemTree } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceExpenseItemDialog' })

  type ExpenseItem = Api.Fms.ExpenseItem
  type ExpenseItemForm = Omit<ExpenseItem, 'children'>

  const emit = defineEmits<{ success: [type: 'add' | 'edit'] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<{ row?: ExpenseItem; parent?: ExpenseItem }>>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()

  const createInitialForm = (): ExpenseItemForm => ({
    id: undefined,
    parentId: null,
    itemCode: '',
    itemName: '',
    businessCategory: null,
    isSelectable: false,
    reimbursementAllowed: false,
    isEnabled: true,
    sort: 100,
    remark: ''
  })

  const form = reactive<ExpenseItemForm>(createInitialForm())

  const rules = computed<FormRules<ExpenseItemForm>>(() => ({
    itemName: [
      { required: true, message: '请输入费用项目名称', trigger: 'blur' },
      { min: 2, max: 80, message: '长度应为 2 到 80 个字符', trigger: 'blur' }
    ],
    itemCode: [
      { required: true, message: '请输入项目编码', trigger: 'blur' },
      {
        pattern: /^[A-Za-z0-9_-]{2,50}$/,
        message: '编码仅支持字母、数字、下划线和中横线，长度 2 到 50',
        trigger: 'blur'
      }
    ],
    businessCategory: form.isSelectable
      ? [{ required: true, message: '请选择业务分类', trigger: 'change' }]
      : [],
    sort: [{ type: 'number', min: 0, max: 9999, message: '排序范围为 0 到 9999' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }))

  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const items = computed<FormItem[]>(() => [
    { label: '层级与编码', key: 'structureSection', type: 'divider', span: 24 },
    {
      label: '上级项目',
      key: 'parentId',
      type: 'treeSelect',
      span: 24,
      api: fetchExpenseItemTree,
      afterFetch: (result: unknown) => excludeCurrentNode(result),
      labelField: 'itemName',
      valueField: 'id',
      childrenField: 'children',
      props: {
        clearable: true,
        checkStrictly: true,
        defaultExpandAll: true,
        renderAfterExpand: false,
        placeholder: '不选则为一级项目'
      }
    },
    { label: '项目名称', key: 'itemName', type: 'input', span: 24, props: { maxlength: 80 } },
    { label: '项目编码', key: 'itemCode', type: 'input', props: { maxlength: 50 } },
    {
      label: '排序',
      key: 'sort',
      type: 'number',
      props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
    },
    { label: '业务设置', key: 'businessSection', type: 'divider', span: 24 },
    {
      label: '节点用途',
      key: 'isSelectable',
      type: 'radioGroup',
      span: 24,
      props: {
        options: [
          { label: '仅作为分组', value: false },
          { label: '可记账项目', value: true }
        ]
      }
    },
    {
      label: '业务分类',
      key: 'businessCategory',
      type: 'select',
      span: 24,
      hidden: !form.isSelectable,
      props: {
        options: getDictMap.value.tmsWaybillCostType ?? [],
        placeholder: '用于兼容结算、利润分析等内部规则'
      }
    },
    {
      label: '允许报销',
      key: 'reimbursementAllowed',
      type: 'radioGroup',
      hidden: !form.isSelectable,
      props: { options: booleanOptions.value }
    },
    {
      label: '启用状态',
      key: 'isEnabled',
      type: 'radioGroup',
      props: { options: booleanOptions.value }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  function excludeCurrentNode(result: unknown): ExpenseItem[] {
    const records = (result as { data?: ExpenseItem[] })?.data ?? []
    const walk = (nodes: ExpenseItem[]): ExpenseItem[] =>
      nodes
        .filter((node) => node.id !== form.id)
        .map((node) => ({ ...node, children: walk(node.children ?? []) }))
    return walk(records)
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (!form.isSelectable) {
        form.businessCategory = null
        form.reimbursementAllowed = false
      }
      const type = form.id ? 'edit' : 'add'
      await (form.id ? editExpenseItem(form) : addExpenseItem(form))
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row?: ExpenseItem, parent?: ExpenseItem): Promise<void> {
    Object.assign(form, createInitialForm(), row ? structuredClone(toRaw(row)) : {})
    delete (form as ExpenseItem).children
    if (!row && parent?.id) form.parentId = parent.id
    await dialogRef.value?.handleOpen(
      { row, parent },
      {
        title: row
          ? `编辑费用项目 · ${row.itemName}`
          : parent
            ? `新增“${parent.itemName}”下级`
            : '新增一级费用项目',
        confirmText: row ? '保存修改' : '确认新增',
        onConfirm: handleSubmit,
        onOpen: () => formRef.value?.clearValidate(),
        dialogProps: { appendToBody: true, closeOnClickModal: false }
      }
    )
  }

  defineExpose({ handleOpen })
</script>
