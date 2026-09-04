<template>
  <ArtDialog ref="dialogRef" size="md">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="24"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormInstance, FormRules } from 'element-plus'
  import { omit } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { addDictType, editDictType, fetchGetDictDirectoryTree } from '@/api/data-center'
  import { useUserStore } from '@/store/modules/user'
  import { uniqueValidator } from '@/utils/form/validator'

  type DictTypeItem = Api.DataCenter.DictTypeItem

  interface ArtFormExpose {
    ref: Ref<FormInstance | undefined>
    validate: () => Promise<boolean | void>
  }

  interface OpenOptions {
    parentId?: string
  }

  interface FormGroup {
    data: DictTypeItem
    editing: boolean
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules>
  }

  const emit = defineEmits<{
    success: []
  }>()

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const dialogRef = ref<ArtDialogExpose<DictTypeItem>>()
  const formRef = ref<ArtFormExpose>()

  const createInitialForm = (): DictTypeItem => ({
    id: undefined,
    parentId: undefined,
    nodeType: 'directory',
    name: '',
    code: '',
    status: '1',
    sort: 0,
    remark: ''
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    editing: false,
    items: computed<FormItem[]>((): FormItem[] => [
      {
        label: '节点类型',
        key: 'nodeType',
        type: 'radioGroup',
        props: {
          disabled: form.editing,
          options: [
            { label: '目录', value: 'directory' },
            { label: '字典类型', value: 'dictionary' }
          ]
        }
      },
      {
        label: '上级目录',
        key: 'parentId',
        type: 'cascader',
        api: fetchGetDictDirectoryTree,
        params: {
          excludeId: form.editing && form.data.nodeType === 'directory' ? form.data.id : undefined
        },
        resultField: 'data',
        labelField: 'name',
        valueField: 'id',
        childrenField: 'children',
        description: '仅展示目录节点；不选择则创建为根节点。',
        props: {
          clearable: true,
          filterable: true,
          separator: ' / ',
          placeholder: '请选择上级目录',
          style: { width: '100%' },
          props: {
            checkStrictly: true,
            emitPath: false
          }
        }
      },
      {
        label: form.data.nodeType === 'directory' ? '目录名称' : '类型名称',
        key: 'name',
        type: 'input',
        props: {
          maxlength: 100
        }
      },
      {
        label: form.data.nodeType === 'directory' ? '目录编码' : '类型编码',
        key: 'code',
        type: 'input',
        props: {
          maxlength: 100
        }
      },
      {
        label: '排序',
        key: 'sort',
        type: 'number',
        help: '值越小越靠前',
        props: {
          min: 0,
          step: 1,
          stepStrictly: true
        }
      },
      {
        label: '状态',
        key: 'status',
        type: 'radioGroup',
        props: {
          options: getDictMap.value?.status ?? []
        }
      },
      {
        label: '描述',
        key: 'remark',
        type: 'input',
        props: {
          type: 'textarea',
          rows: 4,
          maxlength: 500,
          showWordLimit: true
        }
      }
    ]),
    rules: computed<FormRules>(() => ({
      nodeType: [{ required: true, message: '请选择节点类型', trigger: 'change' }],
      name: [{ required: true, message: '请输入名称', trigger: 'change' }],
      code: [
        { required: true, message: '请输入编码', trigger: 'change' },
        {
          validator: uniqueValidator({
            table: 'sys_dict_type',
            field: 'code',
            getExcludeId: (): string | undefined => form.data.id,
            message: '编码已存在'
          }),
          trigger: 'change'
        }
      ]
    }))
  })

  const resetForm = (): void => {
    Object.assign(form.data, createInitialForm())
    formRef.value?.ref.value?.clearValidate()
  }

  const normalizePayload = (data: DictTypeItem): DictTypeItem => ({
    ...data,
    parentId: data.parentId === '' ? null : data.parentId
  })

  const handleOpen = async (data?: DictTypeItem, options: OpenOptions = {}): Promise<void> => {
    resetForm()
    form.editing = !!data?.id

    if (data) {
      Object.assign(form.data, structuredClone(omit(data, ['children'])))
    } else {
      form.data.parentId = options.parentId
      form.data.nodeType = options.parentId ? 'dictionary' : 'directory'
    }

    await dialogRef.value?.handleOpen(data, {
      title: form.editing
        ? form.data.nodeType === 'directory'
          ? '编辑字典目录'
          : '编辑字典类型'
        : '新增字典节点',
      onConfirm: handleSubmit,
      onReset: resetForm
    })
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = normalizePayload(
        omit(toRaw(form.data), [
          'children',
          'tenantId',
          'createBy',
          'createTime',
          'updateBy',
          'updateTime'
        ]) as DictTypeItem
      )

      if (form.data.id) {
        await editDictType(payload)
      } else {
        await addDictType(payload)
      }
      await userStore.fetchDictList()
      emit('success')
      return true
    } catch {
      return false
    }
  }

  defineExpose({
    handleOpen
  })
</script>
