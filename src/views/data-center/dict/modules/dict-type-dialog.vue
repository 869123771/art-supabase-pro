<template>
  <ArtDialog ref="dialogRef" width="620px">
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
  import { addDictType, editDictType } from '@/api/data-center'
  import { useUserStore } from '@/store/modules/user'
  import { uniqueValidator } from '@/utils/form/validator'

  type DictTypeItem = Api.DataCenter.DictTypeItem

  interface ArtFormExpose {
    ref: Ref<FormInstance | undefined>
    validate: () => Promise<boolean | void>
  }

  interface OpenOptions {
    parentId?: string
    treeData: DictTypeItem[]
  }

  interface FormGroup {
    data: DictTypeItem
    editing: boolean
    parentOptions: DictTypeItem[]
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
    parentOptions: [] as DictTypeItem[],
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
        type: 'treeSelect',
        props: {
          data: form.parentOptions,
          clearable: true,
          checkStrictly: true,
          defaultExpandAll: true,
          renderAfterExpand: false,
          placeholder: '不选择则为根节点',
          props: {
            label: 'name',
            value: 'id',
            children: 'children'
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

  const normalizeDirectoryOptions = (
    nodes: DictTypeItem[],
    excludedIds: Set<string>
  ): DictTypeItem[] =>
    nodes
      .filter(
        (node) => node.nodeType === 'directory' && !!node.id && !excludedIds.has(String(node.id))
      )
      .map((node) => ({
        ...node,
        children: normalizeDirectoryOptions(node.children ?? [], excludedIds)
      }))

  const collectNodeIds = (node?: DictTypeItem): Set<string> => {
    const ids = new Set<string>()
    const walk = (current?: DictTypeItem): void => {
      if (!current) return
      if (current.id) ids.add(current.id)
      current.children?.forEach(walk)
    }
    walk(node)
    return ids
  }

  const resetForm = (): void => {
    Object.assign(form.data, createInitialForm())
    formRef.value?.ref.value?.clearValidate()
  }

  const normalizePayload = (data: DictTypeItem): DictTypeItem => ({
    ...data,
    parentId: data.parentId === '' ? null : data.parentId
  })

  const handleOpen = async (
    data?: DictTypeItem,
    options: OpenOptions = { treeData: [] }
  ): Promise<void> => {
    resetForm()
    form.editing = !!data?.id

    if (data) {
      Object.assign(form.data, structuredClone(omit(data, ['children'])))
    } else {
      form.data.parentId = options.parentId
      form.data.nodeType = options.parentId ? 'dictionary' : 'directory'
    }

    form.parentOptions = normalizeDirectoryOptions(options.treeData, collectNodeIds(data))

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
