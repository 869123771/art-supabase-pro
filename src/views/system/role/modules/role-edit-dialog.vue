<template>
  <ArtDialog ref="dialogRef">
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
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormInstance, FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import { addRole, editRole } from '@/api/system-manage'
  import { uniqueValidator } from '@/utils'

  type RoleListItem = Api.SystemManage.RoleListItem
  type DialogType = 'add' | 'edit'

  interface RoleEditDialogOpenData {
    type: DialogType
    roleData?: RoleListItem
  }

  interface Emits {
    (e: 'success'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<RoleEditDialogOpenData>>()
  const formRef = ref<FormInstance>()
  const dialogType = ref<DialogType>('add')

  const createInitialForm = (): RoleListItem => ({
    id: undefined,
    roleName: '',
    roleCode: '',
    description: '',
    enabled: true,
    createBy: undefined
  })

  const form = reactive<RoleListItem>(createInitialForm())

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
          table: 'sys_role',
          field: 'role_code',
          getExcludeId: (): string | undefined => form.id,
          extraWhere: () => ({
            create_by: form.createBy
          }),
          message: '角色编码已存在'
        }),
        trigger: 'change'
      }
    ],
    description: [{ required: true, message: '请输入角色描述', trigger: 'change' }]
  })

  const resetForm = async (): Promise<void> => {
    Object.assign(form, createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const initializeForm = async (data: RoleEditDialogOpenData): Promise<void> => {
    await resetForm()
    dialogType.value = data.type

    if (data.roleData) {
      const { id, roleName, roleCode, description, enabled, createBy } = data.roleData
      Object.assign(form, {
        id,
        roleName,
        roleCode,
        description,
        enabled,
        createBy
      })
    }
  }

  const handleSubmit = async (): Promise<boolean> => {
    if (!formRef.value) return false

    try {
      await formRef.value.validate()
    } catch {
      return false
    }

    try {
      const { id, ...params } = toRaw(form)
      if (dialogType.value === 'add') {
        await addRole(params)
      } else {
        await editRole({ ...params, id })
      }
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (data: RoleEditDialogOpenData): Promise<void> => {
    await initializeForm(data)
    await dialogRef.value?.handleOpen(data, {
      title: data.type === 'add' ? '新增角色' : '编辑角色',
      width: '35%',
      onConfirm: handleSubmit,
      onReset: () => {
        void resetForm()
      }
    })
  }

  defineExpose({
    handleOpen,
    handleSubmit,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
