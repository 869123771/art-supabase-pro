<template>
  <ElDialog
    v-model="visible"
    :title="dialogType === 'add' ? '新增角色' : '编辑角色'"
    width="30%"
    align-center
    @close="handleClose"
  >
    <ElForm ref="formRef" :model="form" :rules="rules" label-width="120px" class="pr-6">
      <ElFormItem label="角色名称" prop="roleName">
        <ElInput v-model="form.roleName" placeholder="请输入角色名称" />
      </ElFormItem>
      <ElFormItem label="角色编码" prop="roleCode">
        <ElInput v-model="form.roleCode" placeholder="请输入角色编码" />
      </ElFormItem>
      <ElFormItem label="描述" prop="description">
        <ElInput
          v-model="form.description"
          type="textarea"
          :rows="3"
          placeholder="请输入角色描述"
        />
      </ElFormItem>
      <ElFormItem label="启用">
        <ElSwitch v-model="form.enabled" />
      </ElFormItem>
    </ElForm>
    <template #footer>
      <ElButton @click="handleClose">取消</ElButton>
      <ElButton type="primary" @click="handleSubmit" :loading="loading">提交</ElButton>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import type { FormInstance, FormRules } from 'element-plus'

  import { addRole, editRole } from '@/api/system-manage'
  import { uniqueValidator } from '@/utils'

  type RoleListItem = Api.SystemManage.RoleListItem

  interface Props {
    modelValue: boolean
    dialogType: 'add' | 'edit'
    roleData?: RoleListItem
  }

  interface Emits {
    (e: 'update:modelValue', value: boolean): void
    (e: 'success'): void
  }

  const props = withDefaults(defineProps<Props>(), {
    modelValue: false,
    dialogType: 'add',
    roleData: undefined
  })

  const emit = defineEmits<Emits>()

  const formRef = ref<FormInstance>()

  const loading = ref(false)

  /**
   * 弹窗显示状态双向绑定
   */
  const visible = computed({
    get: () => props.modelValue,
    set: (value) => emit('update:modelValue', value)
  })

  /**
   * 表单验证规则
   */
  const rules = reactive<FormRules>({
    roleName: [
      { required: true, message: '请输入角色名称', trigger: 'change' },
      { min: 2, max: 20, message: '长度在 2 到 20 个字符', trigger: 'change' }
    ],
    roleCode: [
      { required: true, message: '请输入角色编码', trigger: 'change' },
      { min: 2, max: 50, message: '长度在 2 到 50 个字符', trigger: 'change' },
      {
        validator: uniqueValidator({
          table: 'roles',
          field: 'role_code',
          getExcludeId: (): string | undefined => form?.id,
          message: '角色编码已存在'
        }),
        trigger: 'change'
      }
    ],
    description: [{ required: true, message: '请输入角色描述', trigger: 'change' }]
  })

  /**
   * 表单数据
   */
  const form = reactive<RoleListItem>({
    roleName: '',
    roleCode: '',
    description: '',
    enabled: true
  })

  /**
   * 监听弹窗打开，初始化表单数据
   */
  watch(
    () => props.modelValue,
    (newVal) => {
      if (newVal) initForm()
    }
  )

  /**
   * 监听角色数据变化，更新表单
   */
  watch(
    () => props.roleData,
    (newData) => {
      if (newData && props.modelValue) initForm()
    },
    { deep: true }
  )

  /**
   * 初始化表单数据
   * 根据弹窗类型填充表单或重置表单
   */
  const initForm = () => {
    const { id, roleName, roleCode, description, enabled } = props.roleData ?? {}

    Object.assign(form, {
      id,
      roleName,
      roleCode,
      description,
      enabled
    })
  }

  /**
   * 关闭弹窗并重置表单
   */
  const handleClose = () => {
    visible.value = false
    formRef.value?.resetFields()
  }

  /**
   * 提交表单
   * 验证通过后调用接口保存数据
   */
  const handleSubmit = async () => {
    if (!formRef.value) return

    try {
      await formRef.value.validate()
      try {
        loading.value = true
        const { id, ...rest } = toRaw(form)
        const params = {
          ...rest
        }
        if (props.dialogType === 'add') {
          await addRole(params)
        } else {
          await editRole({ ...params, id })
        }
      } finally {
        loading.value = false
      }
      emit('success')
      handleClose()
    } catch (error) {
      console.log('表单验证失败:', error)
    }
  }
</script>
