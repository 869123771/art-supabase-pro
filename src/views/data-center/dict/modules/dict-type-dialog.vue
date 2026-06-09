<template>
  <ArtDialog ref="dialogRef">
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
    >
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import type { FormInstance, FormRules } from 'element-plus'
  import { cloneDeep, isEmpty } from 'lodash-es'
  import { addDictType, editDictType } from '@/api/data-center'
  import { useUserStore } from '@/store/modules/user'
  import { uniqueValidator } from '@/utils/form/validator'

  type DictListItem = Api.DataCenter.DictListItem
  interface ArtFormExpose {
    ref: Ref<FormInstance | undefined>
    validate: () => Promise<boolean | void>
  }

  const emits = defineEmits(['success'])

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore) as Record<string, any>

  const dialogRef = ref<ArtDialogExpose<DictListItem>>()
  const formRef = ref<ArtFormExpose>()

  const dataDefault = {
    name: '',
    code: '',
    status: '1',
    remark: ''
  }
  const form = ref({
    data: cloneDeep(dataDefault) as DictListItem,
    items: computed<FormItem[]>(() => {
      return [
        {
          label: '分类名称',
          key: 'name',
          type: 'input',
          props: {
            placeholder: '请输入分类名称',
            clearable: true
          }
        },
        {
          label: '分类编码',
          key: 'code',
          type: 'input',
          props: {
            placeholder: '请输入分类编码',
            clearable: true
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
            placeholder: '请输入描述',
            type: 'textarea',
            rows: 4,
            clearable: true
          }
        }
      ]
    }),
    rules: computed<FormRules>(() => {
      return {
        name: [{ required: true, message: '分类名称不能为空', trigger: 'change' }],
        code: [
          { required: true, message: '分类编码不能为空', trigger: 'change' },
          {
            validator: uniqueValidator({
              table: 'sys_dict_type',
              field: 'code',
              getExcludeId: (): string | undefined => form.value.data?.id,
              message: '分类编码已存在'
            }),
            trigger: 'change'
          }
        ]
      }
    })
  })

  const handleResetFields = () => {
    form.value.data = cloneDeep(dataDefault)
    formRef.value?.ref.value?.clearValidate()
  }

  const handleOpen = async (data: DictListItem = {} as DictListItem): Promise<void> => {
    handleResetFields()
    if (!isEmpty(data)) {
      form.value.data = {
        ...form.value.data,
        ...cloneDeep(data)
      } as DictListItem
    }

    await dialogRef.value?.handleOpen(data, {
      title: isEdit.value ? '编辑字典分类' : '新增字典分类',
      width: '30%',
      onConfirm: handleSubmit,
      onReset: handleResetFields
    })
  }

  const handleSubmit = async (): Promise<boolean> => {
    if (!formRef.value) return false

    try {
      await formRef.value.validate()
      const {
        data: { id, ...rest }
      } = form.value
      const params: DictListItem = {
        ...rest
      }
      if (!isEdit.value) {
        await addDictType(params)
      } else {
        await editDictType({ ...params, id })
      }
      await useUserStore().fetchDictList()
      emits('success')
      return true
    } catch (error) {
      console.log('表单验证失败:', error)
      return false
    }
  }

  defineExpose({
    handleOpen
  })

  const isEdit = computed(() => !!form.value.data?.id)
</script>

<style scoped lang="scss"></style>
