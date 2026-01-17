<template>
  <ElDialog
    v-model="dialog.visible"
    :title="isEdit ? '编辑字典分类' : '新增字典分类'"
    width="30%"
    align-center
    destroy-on-close
  >
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
    <template #footer>
      <span class="dialog-footer">
        <ElButton @click="handleClose">取 消</ElButton>
        <ElButton type="primary" @click="handleSubmit" :loading="dialog.loading">确 定</ElButton>
      </span>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import type { FormRules } from 'element-plus'
  import { cloneDeep, isEmpty } from 'lodash-es'
  import { addDictType, editDictType } from '@/api/data-center'
  import { useUserStore } from '@/store/modules/user'
  import { uniqueValidator } from '@/utils/form/validator'

  type DictListItem = Api.DataCenter.DictListItem

  const emits = defineEmits(['success'])

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore) as Record<string, any>

  const formRef = ref<HTMLFormElement>()

  const dialog = ref({
    visible: false,
    loading: false
  })

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
          type: 'radiogroup',
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
              table: 'dict_type',
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
  }

  const handleOpen = (data: DictListItem = {} as DictListItem) => {
    dialog.value = {
      ...unref(dialog),
      visible: true
    }
    if (!isEmpty(data)) {
      form.value.data = data
    }
  }
  const handleClose = () => {
    handleResetFields()
    dialog.value = {
      ...unref(dialog),
      visible: false
    }
  }

  const handleSubmit = async () => {
    if (!formRef.value) return

    try {
      await formRef.value.validate()
      try {
        dialog.value.loading = true
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
        //获取新的字典列表
        await useUserStore().fetchDictList()
        emits('success')
        handleClose()
      } finally {
        dialog.value.loading = false
      }
    } catch (error) {
      console.log('表单验证失败:', error)
    }
  }

  defineExpose({
    handleOpen
  })

  const isEdit = computed(() => !!form.value.data?.id)
</script>

<style scoped lang="scss"></style>
