<template>
  <ArtDialog ref="dialogRef" size="lg">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="8"
      :gutter="20"
      label-width="112px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { omit } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import { addCargo, editCargo } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsCargoDialog' })

  type Cargo = Api.Tms.BasicData.Cargo
  type CargoForm = Cargo

  interface DialogExposeForm {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Cargo | undefined>>()
  const formRef = ref<DialogExposeForm>()
  const cargoNumber = useDocumentNumberRule('master.cargo')

  const cargoUnitOptions = computed(() => getDictMap.value.tmsCargoUnit ?? [])

  const createInitialForm = (): CargoForm => ({
    id: undefined,
    cargoCode: '',
    cargoName: '',
    unit: '',
    lengthM: null,
    widthM: null,
    heightM: null,
    volumeM3: null,
    weightKg: null,
    valueAmount: null,
    enabled: true,
    remark: ''
  })

  const form = reactive<CargoForm>(createInitialForm())

  const formRules: FormRules<CargoForm> = {
    cargoCode: [
      {
        validator: (_rule, value, callback) =>
          cargoNumber.manualRequired(Boolean(form.id)) && !String(value || '').trim()
            ? callback(new Error('请输入货物编码'))
            : callback(),
        trigger: 'blur'
      }
    ],
    cargoName: [
      { required: true, message: '请输入货物名称', trigger: 'blur' },
      { min: 2, max: 80, message: '长度应为 2 到 80 个字符', trigger: 'blur' }
    ],
    unit: [{ required: true, message: '请选择计量单位', trigger: 'change' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const numberInputProps = {
    min: 0,
    precision: 2,
    controlsPosition: 'right',
    class: '!w-full'
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '货物编码',
      key: 'cargoCode',
      type: 'input',
      props: {
        maxlength: 30,
        ...cargoNumber.inputProps(Boolean(form.id), '请输入货物编码', true)
      },
      description: cargoNumber.description.value
    },
    {
      label: '货物名称',
      key: 'cargoName',
      type: 'input',
      props: { maxlength: 80, placeholder: '请输入货物名称' }
    },
    {
      label: '计量单位',
      key: 'unit',
      type: 'select',
      props: {
        options: cargoUnitOptions.value,
        clearable: true,
        placeholder: '请选择计量单位'
      }
    },
    {
      label: '长(m)',
      key: 'lengthM',
      type: 'number',
      props: numberInputProps
    },
    {
      label: '宽(m)',
      key: 'widthM',
      type: 'number',
      props: numberInputProps
    },
    {
      label: '高(m)',
      key: 'heightM',
      type: 'number',
      props: numberInputProps
    },
    {
      label: '体积(m³)',
      key: 'volumeM3',
      type: 'number',
      props: {
        ...numberInputProps,
        precision: 3
      }
    },
    {
      label: '重量(kg)',
      key: 'weightKg',
      type: 'number',
      props: numberInputProps
    },
    {
      label: '价值(元)',
      key: 'valueAmount',
      type: 'number',
      props: numberInputProps
    },
    {
      label: '状态',
      key: 'enabled',
      type: 'switch',
      props: {
        activeText: '启用',
        inactiveText: '停用',
        inlinePrompt: true
      }
    },
    {
      label: '备注信息',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '请输入备注信息'
      }
    }
  ])

  const replaceForm = (nextForm: CargoForm): void => {
    Object.keys(form).forEach((key) => delete form[key as keyof CargoForm])
    Object.assign(form, nextForm)
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const normalizeNumber = (value?: number | null): number | null => {
    if (value === null || value === undefined || Number.isNaN(Number(value))) return null
    return Number(value)
  }

  const normalizePayload = (): Cargo => {
    const payload = omit(structuredClone(toRaw(form)), [
      'tenantId',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as Cargo

    return {
      ...payload,
      lengthM: normalizeNumber(payload.lengthM),
      widthM: normalizeNumber(payload.widthM),
      heightM: normalizeNumber(payload.heightM),
      volumeM3: normalizeNumber(payload.volumeM3),
      weightKg: normalizeNumber(payload.weightKg),
      valueAmount: normalizeNumber(payload.valueAmount),
      remark: payload.remark || null
    }
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = normalizePayload()
      const type = form.id ? 'edit' : 'add'
      if (type === 'edit') await editCargo(payload)
      else await addCargo(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Cargo): Promise<void> => {
    await Promise.all([resetForm(), cargoNumber.loadRule()])
    const isEdit = Boolean(row?.id)
    if (row) {
      replaceForm({
        ...createInitialForm(),
        ...structuredClone(toRaw(row))
      })
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑货物' : '新增货物',
      subtitle: '维护货物基础信息、尺寸重量和计量单位',
      contentMaxHeight: '70vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
