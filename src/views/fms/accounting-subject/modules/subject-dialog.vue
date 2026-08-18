<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      下级科目编码必须以上级编码开头，并自动继承上级科目类别与余额方向。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :validate-on-rule-change="false"
      :span="12"
      :gutter="20"
      label-width="110px"
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
  import { saveSubject } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import TreeUtils from '@/utils/tree'

  defineOptions({ name: 'FinanceAccountingSubjectDialog' })

  type Subject = Api.Fms.SubjectRecord
  type SubjectPayload = Api.Fms.SaveSubjectPayload
  type SubjectForm = Omit<SubjectPayload, 'auxiliaryConfigs'> & {
    auxiliaryTypeIds: string[]
    requiredAuxiliaryTypeIds: string[]
  }
  type AccountSetOption = {
    label: string
    value: string
    status: Api.Fms.AccountSetStatus
    tenantId: string
  }

  interface FormGroup {
    data: SubjectForm
    rules: FormRules<SubjectForm>
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const context = reactive({
    accountSet: undefined as AccountSetOption | undefined,
    subjects: [] as Subject[],
    auxiliaryTypes: [] as Api.Fms.AuxiliaryTypeRecord[],
    current: undefined as Subject | undefined
  })
  const subjectTree = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const createInitialForm = (): SubjectForm => ({
    id: undefined,
    tenantId: '',
    accountSetId: '',
    parentId: null,
    subjectCode: '',
    subjectName: '',
    category: 'asset',
    balanceDirection: 'debit',
    isEnabled: true,
    allowQuantity: false,
    unitName: null,
    allowForeignCurrency: false,
    allowPeriodEndRevaluation: false,
    cashFlowRequired: false,
    sort: 100,
    remark: null,
    auxiliaryTypeIds: [],
    requiredAuxiliaryTypeIds: []
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      subjectCode: [
        { required: true, message: '请输入科目编码', trigger: 'blur' },
        { pattern: /^[0-9]{1,40}$/, message: '科目编码仅支持数字，最多 40 位', trigger: 'blur' }
      ],
      subjectName: [
        { required: true, message: '请输入科目名称', trigger: 'blur' },
        { max: 120, message: '科目名称不能超过 120 个字符', trigger: 'blur' }
      ],
      category: [{ required: true, message: '请选择科目类别', trigger: 'change' }],
      balanceDirection: [{ required: true, message: '请选择余额方向', trigger: 'change' }],
      unitName: [
        {
          validator: (_rule, value, callback) => {
            if (form.data.allowQuantity && !String(value ?? '').trim())
              callback(new Error('数量核算必须填写计量单位'))
            else callback()
          },
          trigger: 'blur'
        }
      ]
    }
  })

  const categoryOptions = computed(() => getDictMap.value.fmsSubjectCategory ?? [])
  const directionOptions = computed(() => getDictMap.value.fmsBalanceDirection ?? [])
  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )
  const auxiliaryTypeOptions = computed(() =>
    context.auxiliaryTypes
      .filter((item) => item.isEnabled)
      .map((item) => ({ label: `${item.typeName}（${item.typeCode}）`, value: item.id }))
  )

  const parentOptions = computed(() => {
    const tree = subjectTree.listToTree(context.subjects)
    const excludedIds = new Set(
      context.current?.id
        ? subjectTree.getDescendants<Subject>(tree, context.current.id, true).map((item) => item.id)
        : []
    )
    return context.subjects
      .filter((item) => !excludedIds.has(item.id))
      .map((item) => ({
        label: `${'　'.repeat(Math.max(item.level - 1, 0))}${item.subjectCode} ${item.subjectName}`,
        value: item.id
      }))
  })

  const parentSubject = computed(() =>
    context.subjects.find((item) => item.id === form.data.parentId)
  )

  const formItems = computed<FormItem[]>(() => [
    { label: '基本信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '上级科目',
      key: 'parentId',
      type: 'select',
      span: 24,
      help: '存在下级科目后，当前科目的上级和编码不可变更。',
      props: {
        options: parentOptions.value,
        clearable: true,
        filterable: true,
        placeholder: '不选择表示一级科目',
        onChange: handleParentChange
      }
    },
    {
      label: '科目编码',
      key: 'subjectCode',
      type: 'input',
      span: 12,
      props: {
        maxlength: 40,
        placeholder: parentSubject.value
          ? `必须以 ${parentSubject.value.subjectCode} 开头`
          : '例如：1001'
      }
    },
    {
      label: '科目名称',
      key: 'subjectName',
      type: 'input',
      span: 12,
      props: { maxlength: 120, placeholder: '请输入会计科目名称' }
    },
    {
      label: '科目类别',
      key: 'category',
      type: 'select',
      span: 12,
      props: { options: categoryOptions.value, disabled: Boolean(parentSubject.value) }
    },
    {
      label: '余额方向',
      key: 'balanceDirection',
      type: 'radioGroup',
      span: 12,
      props: { options: directionOptions.value, disabled: Boolean(parentSubject.value) }
    },
    { label: '核算属性', key: 'attributeSection', type: 'divider', span: 24 },
    {
      label: '数量核算',
      key: 'allowQuantity',
      type: 'radioGroup',
      span: 12,
      props: { options: booleanOptions.value }
    },
    {
      label: '计量单位',
      key: 'unitName',
      type: 'input',
      span: 12,
      props: { maxlength: 20, disabled: !form.data.allowQuantity, placeholder: '例如：吨、公里' }
    },
    {
      label: '外币核算',
      key: 'allowForeignCurrency',
      type: 'radioGroup',
      span: 12,
      props: { options: booleanOptions.value, onChange: handleForeignCurrencyChange }
    },
    {
      label: '期末调汇',
      key: 'allowPeriodEndRevaluation',
      type: 'radioGroup',
      span: 12,
      help: '仅资产、负债类外币科目可启用期末调汇。',
      props: {
        options: booleanOptions.value,
        disabled: !canRevalue.value
      }
    },
    {
      label: '现金流必录',
      key: 'cashFlowRequired',
      type: 'radioGroup',
      span: 12,
      props: { options: booleanOptions.value }
    },
    {
      label: '启用状态',
      key: 'isEnabled',
      type: 'radioGroup',
      span: 12,
      props: { options: booleanOptions.value }
    },
    { label: '辅助核算', key: 'auxiliarySection', type: 'divider', span: 24 },
    {
      label: '核算维度',
      key: 'auxiliaryTypeIds',
      type: 'select',
      span: 24,
      help: '凭证和期初余额将按所选维度记录客户、承运商、部门、员工或项目。',
      props: {
        options: auxiliaryTypeOptions.value,
        multiple: true,
        filterable: true,
        clearable: true,
        placeholder: '可多选辅助核算维度',
        onChange: handleAuxiliaryTypesChange
      }
    },
    {
      label: '必录维度',
      key: 'requiredAuxiliaryTypeIds',
      type: 'select',
      span: 24,
      help: '设为必录后，凭证分录和期初余额缺少该维度时数据库将拒绝保存。',
      props: {
        options: auxiliaryTypeOptions.value.filter((item) =>
          form.data.auxiliaryTypeIds.includes(String(item.value))
        ),
        multiple: true,
        filterable: true,
        clearable: true,
        placeholder: '选择需要强制填写的维度'
      }
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

  const canRevalue = computed(
    () =>
      form.data.allowForeignCurrency &&
      (form.data.category === 'asset' || form.data.category === 'liability')
  )

  function handleParentChange(parentId?: string): void {
    const parent = context.subjects.find((item) => item.id === parentId)
    if (!parent) return
    form.data.category = parent.category
    form.data.balanceDirection = parent.balanceDirection
    if (!form.data.subjectCode.startsWith(parent.subjectCode)) {
      form.data.subjectCode = parent.subjectCode
    }
  }

  function handleForeignCurrencyChange(value: boolean): void {
    if (!value) form.data.allowPeriodEndRevaluation = false
  }

  function handleAuxiliaryTypesChange(values: string[]): void {
    form.data.requiredAuxiliaryTypeIds = form.data.requiredAuxiliaryTypeIds.filter((id) =>
      values.includes(id)
    )
  }

  function createPayload(): SubjectPayload {
    return {
      id: form.data.id,
      tenantId: form.data.tenantId,
      accountSetId: form.data.accountSetId,
      parentId: form.data.parentId || null,
      subjectCode: form.data.subjectCode.trim(),
      subjectName: form.data.subjectName.trim(),
      category: form.data.category,
      balanceDirection: form.data.balanceDirection,
      isEnabled: form.data.isEnabled,
      allowQuantity: form.data.allowQuantity,
      unitName: form.data.allowQuantity ? form.data.unitName?.trim() || null : null,
      allowForeignCurrency: form.data.allowForeignCurrency,
      allowPeriodEndRevaluation: canRevalue.value && form.data.allowPeriodEndRevaluation,
      cashFlowRequired: form.data.cashFlowRequired,
      sort: form.data.sort,
      remark: form.data.remark?.trim() || null,
      auxiliaryConfigs: form.data.auxiliaryTypeIds.map((auxiliaryTypeId, index) => ({
        auxiliaryTypeId,
        isRequired: form.data.requiredAuxiliaryTypeIds.includes(auxiliaryTypeId),
        sort: (index + 1) * 10
      }))
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      await saveSubject(createPayload())
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(
    accountSet: AccountSetOption,
    subjects: Subject[],
    auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[],
    row?: Subject
  ): Promise<void> {
    context.accountSet = accountSet
    context.subjects = subjects
    context.auxiliaryTypes = auxiliaryTypes
    context.current = row
    Object.assign(form.data, createInitialForm(), {
      ...(row ?? {}),
      id: row?.id,
      tenantId: accountSet.tenantId,
      accountSetId: accountSet.value,
      parentId: row?.parentId ?? null,
      unitName: row?.unitName ?? null,
      remark: row?.remark ?? null,
      auxiliaryTypeIds: (row?.auxiliaryConfigs ?? []).map((item) => item.auxiliaryTypeId),
      requiredAuxiliaryTypeIds: (row?.auxiliaryConfigs ?? [])
        .filter((item) => item.isRequired)
        .map((item) => item.auxiliaryTypeId)
    })

    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑科目 · ${row.subjectCode}` : '新增会计科目',
      confirmText: row ? '保存修改' : '创建科目',
      contentMaxHeight: '72vh',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
