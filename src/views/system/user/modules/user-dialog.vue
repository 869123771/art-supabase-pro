<template>
  <ArtDialog ref="dialogRef">
    <ElForm ref="formRef" :model="formData" :rules="rules" label-width="100px" class="pr-4">
      <ElRow>
        <ElCol :xs="24" :sm="24" :lg="24">
          <ElFormItem label="图像" prop="avatar">
            <ArtUploadImage v-model="formData.avatar" />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="用户名" prop="userName">
            <ElInput v-model="formData.userName" placeholder="请输入用户名" />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="昵称" prop="nickName">
            <ElInput v-model="formData.nickName" placeholder="请输入昵称" />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="手机号" prop="userPhone">
            <ElInput v-model="formData.userPhone" placeholder="请输入手机号" />
          </ElFormItem>
        </ElCol>
        <ElCol v-if="dialogType === 'add'" :xs="24" :sm="24" :lg="12">
          <ElFormItem label="邮箱" prop="userEmail">
            <ElInput v-model="formData.userEmail" placeholder="请输入邮箱" />
          </ElFormItem>
        </ElCol>

        <template v-if="dialogType === 'add'">
          <ElCol :xs="24" :sm="24" :lg="12">
            <ElFormItem label="密码" prop="password">
              <ElInput
                v-model.trim="formData.password"
                placeholder="请输入密码"
                type="password"
                autocomplete="off"
                show-password
              />
            </ElFormItem>
          </ElCol>
          <ElCol :xs="24" :sm="24" :lg="12">
            <ElFormItem label="确认密码" prop="confirmPassword">
              <ElInput
                v-model.trim="formData.confirmPassword"
                placeholder="请再次输入密码"
                type="password"
                autocomplete="off"
                show-password
              />
            </ElFormItem>
          </ElCol>
        </template>

        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="性别" prop="userGender">
            <ElSelect v-model="formData.userGender">
              <ElOption
                v-for="{ label, value } in getDictMap.sex"
                :key="value"
                :value="value"
                :label="label"
              />
            </ElSelect>
          </ElFormItem>
        </ElCol>
        <ElCol v-if="dialogType === 'add'" :xs="24" :sm="24" :lg="12">
          <ElFormItem label="用户类型" prop="userType">
            <ElRadioGroup v-model="formData.userType">
              <ElRadioButton
                v-for="{ label, value } in getDictMap.userType"
                :key="value"
                :value="value"
                :label="label"
              />
            </ElRadioGroup>
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="24">
          <ElFormItem label="备注" prop="remark">
            <ElInput
              v-model.trim="formData.remark"
              placeholder="请输入备注"
              type="textarea"
              :rows="3"
            />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="24">
          <ElFormItem label="状态" prop="status">
            <ElRadioGroup v-model="formData.status">
              <ElRadio
                v-for="{ label, value } in getDictMap.status"
                :key="value"
                :value="value"
                :label="label"
              />
            </ElRadioGroup>
          </ElFormItem>
        </ElCol>
      </ElRow>
    </ElForm>
  </ArtDialog>
</template>

<script setup lang="tsx">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import type { FormInstance, FormRules } from 'element-plus'
  import { useI18n } from 'vue-i18n'
  import { cloneDeep } from 'lodash-es'
  import { useUserStore } from '@/store/modules/user'
  import { addUser, editUser } from '@/api/system-manage'

  type UserListItem = Api.SystemManage.UserListItem
  type DialogType = 'add' | 'edit'

  interface UserDialogOpenData {
    type: DialogType
    userData?: Partial<UserListItem>
  }

  interface Emits {
    (e: 'submit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore())
  const { t } = useI18n()
  const dialogRef = ref<ArtDialogExpose<UserDialogOpenData>>()
  const formRef = ref<FormInstance>()
  const dialogType = ref<DialogType>('add')

  const createInitialForm = (): UserListItem => ({
    id: undefined,
    authUserId: undefined,
    avatar: null,
    userName: '',
    nickName: '',
    userPhone: '',
    userGender: '1',
    userEmail: '',
    password: '',
    confirmPassword: '',
    userType: '1',
    userRoles: [],
    remark: '',
    status: '1'
  })

  const formData = reactive<UserListItem>(createInitialForm())

  const rules: FormRules = {
    userName: [{ min: 2, max: 20, message: '长度在 2 到 20 个字符', trigger: 'change' }],
    userPhone: [{ pattern: /^1[3-9]\d{9}$/, message: '请输入正确的手机号格式', trigger: 'change' }],
    userEmail: [{ required: true, type: 'email', message: '请输入正确的邮箱', trigger: 'change' }],
    password: [
      { required: true, validator: validatePassword, trigger: 'change' },
      { min: 6, message: t('register.rule.passwordLength'), trigger: 'change' }
    ],
    confirmPassword: [{ required: true, validator: validateConfirmPassword, trigger: 'change' }]
  }

  function validatePassword(_rule: unknown, value: string, callback: (error?: Error) => void) {
    if (!value) {
      callback(new Error(t('register.placeholder.password')))
      return
    }

    if (formData.confirmPassword) {
      void formRef.value?.validateField('confirmPassword')
    }
    callback()
  }

  function validateConfirmPassword(
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) {
    if (!value) {
      callback(new Error(t('register.rule.confirmPasswordRequired')))
      return
    }

    if (value !== formData.password) {
      callback(new Error(t('register.rule.passwordMismatch')))
      return
    }
    callback()
  }

  const resetForm = async (): Promise<void> => {
    Object.assign(formData, cloneDeep(createInitialForm()))
    await nextTick()
    formRef.value?.clearValidate()
  }

  const initializeForm = async (data: UserDialogOpenData): Promise<void> => {
    await resetForm()
    dialogType.value = data.type

    if (data.userData) {
      const {
        id,
        avatar,
        userName,
        nickName,
        userPhone,
        userGender,
        userEmail,
        userRoles,
        remark,
        status,
        userType,
        authUserId
      } = data.userData
      Object.assign(formData, {
        id,
        avatar,
        userName,
        nickName,
        userPhone,
        userEmail,
        userGender,
        userRoles,
        remark,
        status,
        userType,
        authUserId
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
      const { id, userEmail, password, authUserId, ...rest } = toRaw(formData)
      const params: UserListItem = {
        userEmail,
        password,
        ...rest
      }

      if (dialogType.value === 'add') {
        await addUser(params)
      } else {
        await editUser({ ...params, id, authUserId })
      }
      emit('submit')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (data: UserDialogOpenData): Promise<void> => {
    await initializeForm(data)
    await dialogRef.value?.handleOpen(data, {
      title: data.type === 'add' ? '添加用户' : '编辑用户',
      width: '60%',
      contentHeight: '70vh',
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
