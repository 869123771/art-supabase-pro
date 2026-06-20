<template>
  <ArtDialog ref="dialogRef" width="760px">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
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
  import {
    addPartsCategory,
    editPartsCategory,
    fetchPartsCategoryTree
  } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'

  type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory
  type PartsCategoryForm = Omit<PartsCategory, 'children'>

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<PartsCategory | undefined>>()
  const formRef = ref<{
    validate: () => Promise<boolean>
    clearValidate: () => void
  }>()

  const createInitialForm = (): PartsCategoryForm => ({
    id: undefined,
    parentId: null,
    categoryName: '',
    categoryCode: '',
    categoryLevel: 1,
    sort: 1,
    status: '1',
    remark: ''
  })

  const form = reactive<PartsCategoryForm>(createInitialForm())

  const normalizeTreeOptions = (records: PartsCategory[], excludeId?: string): PartsCategory[] => {
    const nodeMap = new Map<string, PartsCategory>()
    const roots: PartsCategory[] = []

    records.forEach((item) => {
      if (!item.id || item.id === excludeId) return
      nodeMap.set(item.id, { ...item, children: [] })
    })

    nodeMap.forEach((node) => {
      if (node.parentId && node.parentId !== excludeId && nodeMap.has(node.parentId)) {
        nodeMap.get(node.parentId)?.children?.push(node)
      } else {
        roots.push(node)
      }
    })

    return roots
  }

  const rules: FormRules<PartsCategoryForm> = {
    categoryName: [
      { required: true, message: '请输入类别名称', trigger: 'blur' },
      { min: 2, max: 80, message: '长度应为 2 到 80 个字符', trigger: 'blur' }
    ],
    categoryCode: [
      { required: true, message: '请输入类别编码', trigger: 'blur' },
      {
        pattern: /^[A-Za-z0-9_-]{2,50}$/,
        message: '编码仅支持字母、数字、下划线和中横线，长度 2 到 50',
        trigger: 'blur'
      }
    ],
    sort: [{ type: 'number', min: 0, max: 9999, message: '排序范围为 0 到 9999', trigger: 'blur' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const items = computed<FormItem[]>(() => [
    {
      label: '上级类别',
      key: 'parentId',
      type: 'treeSelect',
      span: 24,
      api: fetchPartsCategoryTree,
      afterFetch: (result: unknown) => {
        const records = (result as { data?: PartsCategory[] })?.data ?? []
        return normalizeTreeOptions(records, form.id)
      },
      labelField: 'categoryName',
      valueField: 'id',
      childrenField: 'children',
      props: {
        clearable: true,
        checkStrictly: true,
        defaultExpandAll: true,
        renderAfterExpand: false,
        placeholder: '不选则为一级类别'
      }
    },
    {
      label: '类别名称',
      key: 'categoryName',
      type: 'input',
      span: 24,
      props: {
        maxlength: 80
      }
    },
    {
      label: '类别编码',
      key: 'categoryCode',
      type: 'input',
      span: 14,
      props: {
        maxlength: 50,
        placeholder: '如 engine_part'
      }
    },
    {
      label: '排序',
      key: 'sort',
      type: 'number',
      span: 10,
      props: {
        min: 0,
        max: 9999,
        controlsPosition: 'right',
        class: '!w-full'
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'radioGroup',
      span: 24,
      props: {
        options: getDictMap.value.status ?? []
      }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 500,
        showWordLimit: true
      }
    }
  ])

  const replaceForm = (nextForm: PartsCategoryForm): void => {
    Object.keys(form).forEach((key) => {
      delete form[key as keyof PartsCategoryForm]
    })
    Object.assign(form, nextForm)
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = toRaw(form)
      payload.parentId = payload.parentId || null
      if (form.id) {
        await editPartsCategory(payload)
      } else {
        await addPartsCategory(payload)
      }
      emit('success', form.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: PartsCategory, parent?: PartsCategory): Promise<void> => {
    await resetForm()
    const isEdit = !!row?.id

    if (isEdit) {
      replaceForm({
        ...createInitialForm(),
        ...(structuredClone(toRaw(row)) as PartsCategoryForm)
      })
    } else if (parent?.id) {
      form.parentId = parent.id
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑零部件类别' : parent?.id ? '新增子类别' : '新增零部件类别',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
