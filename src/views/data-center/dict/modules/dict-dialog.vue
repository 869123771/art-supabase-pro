<template>
  <ArtDialog ref="dialogRef">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #color>
        <el-color-picker
          v-model="form.data.color"
          :predefine="['#67C23A', '#E6A23C', '#F56C6C', '#909399']"
        />
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import type { FormInstance, FormRules } from 'element-plus'
  import { cloneDeep, isEmpty, omit } from 'lodash-es'
  import { addDict, editDict } from '@/api/data-center'
  import { useUserStore } from '@/store/modules/user'
  import { uniqueValidator } from '@/utils'

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
    typeId: '',
    dictTypeName: '',
    label: '',
    code: '',
    value: '',
    i18nScope: '1',
    status: '1',
    sort: 1,
    color: '',
    remark: ''
  }
  const form = ref({
    data: cloneDeep(dataDefault) as DictListItem | Record<string, any>,
    items: computed(
      () =>
        [
          {
            label: '所属类型',
            key: 'dictTypeName',
            type: 'input',
            span: 24,
            props: {
              placeholder: '请输入所属类型',
              clearable: true,
              disabled: true
            }
          },
          {
            label: '字典标签',
            key: 'label',
            type: 'input',
            props: {
              placeholder: '请输入字典标签',
              clearable: true
            }
          },
          {
            label: '字典编码',
            key: 'code',
            type: 'input',
            props: {
              placeholder: '请输入字典编码',
              clearable: true
            }
          },
          {
            label: '字典值',
            key: 'value',
            type: 'input',
            props: {
              placeholder: '请输入字典值',
              clearable: true
            }
          },
          {
            label: '国际化',
            key: 'i18n',
            type: 'input',
            props: {
              placeholder: '请输入国际化',
              clearable: true
            }
          },
          {
            label: '国际化范围',
            key: 'i18nScope',
            type: 'radioGroup',
            props: {
              options: getDictMap.value.i18nScope ?? []
            }
          },
          {
            label: '状态',
            key: 'status',
            type: 'radioGroup',
            props: {
              options: getDictMap.value.status ?? []
            }
          },
          {
            label: '排序',
            key: 'sort',
            type: 'number',
            help: '值越小越靠前',
            props: {
              placeholder: '请输入排序'
            }
          },
          {
            label: '文字颜色',
            key: 'color',
            slots: 'color'
          },
          {
            label: '备注信息',
            key: 'remark',
            type: 'input',
            span: 24,
            props: {
              placeholder: '请输入描述',
              type: 'textarea',
              rows: 4,
              clearable: true
            }
          }
        ] as FormItem[]
    ),
    rules: computed<FormRules>(() => {
      return {
        label: [{ required: true, message: '字典标签不能为空', trigger: 'change' }],
        code: [
          { required: true, message: '字典编码不能为空', trigger: 'change' },
          {
            validator: uniqueValidator({
              table: 'sys_dictionary',
              field: 'code',
              getExcludeId: (): string | undefined => form.value.data?.id,
              extraWhere: (): Record<string, any> => ({
                type_id: form.value.data?.typeId
              }),
              message: '字典编码已存在'
            }),
            trigger: 'change'
          }
        ],
        value: [{ required: true, message: '字典值不能为空', trigger: 'change' }]
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
      }
    }

    await dialogRef.value?.handleOpen(data, {
      title: isEdit.value ? '编辑字典' : '新增字典',
      width: '60%',
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
      const params = omit<DictListItem>(
        {
          ...(rest as DictListItem)
        },
        ['dictTypeName']
      )
      if (!isEdit.value) {
        await addDict(params as DictListItem)
      } else {
        await editDict({ ...params, id } as DictListItem)
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
