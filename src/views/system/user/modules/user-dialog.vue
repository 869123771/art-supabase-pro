<template>
  <ArtDialog ref="dialogRef">
    <ArtForm
      ref="formRef"
      v-model="formData"
      :items="formItems"
      :rules="rules"
      :span="12"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
      :validate-on-rule-change="false"
    >
      <template #avatar>
        <ArtUploadImage v-model="formData.avatar" />
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { useI18n } from 'vue-i18n'
  import { cloneDeep } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import { addUser, editUser } from '@/api/system-manage'

  type UserListItem = Api.SystemManage.UserListItem
  type SaveType = 'add' | 'edit'

  interface Emits {
    (e: 'success', type: SaveType): void
  }

  interface ArtFormExpose {
    validate: () => Promise<boolean | void>
    clearValidate: () => void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore()) as Record<string, any>
  const { t } = useI18n()
  const dialogRef = ref<ArtDialogExpose<Partial<UserListItem> | undefined>>()
  const formRef = ref<ArtFormExpose>()

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

  const formData = ref<UserListItem>(createInitialForm())
  const isEdit = computed(() => !!formData.value.id)

  const rules = computed<FormRules>(() => ({
    userName: [{ min: 2, max: 20, message: '长度在 2 到 20 个字符', trigger: 'change' }],
    userPhone: [{ pattern: /^1[3-9]\d{9}$/, message: '请输入正确的手机号格式', trigger: 'change' }],
    userEmail: [{ required: true, type: 'email', message: '请输入正确的邮箱', trigger: 'change' }],
    password: [
      { required: true, validator: validatePassword, trigger: 'change' },
      { min: 6, message: t('register.rule.passwordLength'), trigger: 'change' }
    ],
    confirmPassword: [{ required: true, validator: validateConfirmPassword, trigger: 'change' }]
  }))

  const formItems = computed<FormItem[]>(() => [
    {
      label: '图像',
      key: 'avatar',
      span: 24
    },
    {
      label: '用户名',
      key: 'userName',
      type: 'input',
      props: { placeholder: '请输入用户名', clearable: true }
    },
    {
      label: '昵称',
      key: 'nickName',
      type: 'input',
      props: { placeholder: '请输入昵称', clearable: true }
    },
    {
      label: '手机号',
      key: 'userPhone',
      type: 'input',
      props: { placeholder: '请输入手机号', clearable: true, maxlength: 11 }
    },
    {
      label: '邮箱',
      key: 'userEmail',
      type: 'input',
      hidden: isEdit.value,
      props: { placeholder: '请输入邮箱', clearable: true }
    },
    {
      label: '密码',
      key: 'password',
      type: 'input',
      hidden: isEdit.value,
      props: {
        placeholder: '请输入密码',
        type: 'password',
        autocomplete: 'off',
        showPassword: true
      }
    },
    {
      label: '确认密码',
      key: 'confirmPassword',
      type: 'input',
      hidden: isEdit.value,
      props: {
        placeholder: '请再次输入密码',
        type: 'password',
        autocomplete: 'off',
        showPassword: true
      }
    },
    {
      label: '性别',
      key: 'userGender',
      type: 'select',
      props: {
        placeholder: '请选择性别',
        options: getDictMap.value.sex ?? []
      }
    },
    {
      label: '用户类型',
      key: 'userType',
      type: 'radioGroup',
      hidden: isEdit.value,
      props: {
        optionType: 'button',
        options: getDictMap.value.userType ?? []
      }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        placeholder: '请输入备注',
        type: 'textarea',
        rows: 3
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
    }
  ])

  function validatePassword(_rule: unknown, value: string, callback: (error?: Error) => void) {
    if (isEdit.value) {
      callback()
      return
    }

    if (!value) {
      callback(new Error(t('register.placeholder.password')))
      return
    }

    callback()
  }

  function validateConfirmPassword(
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) {
    if (isEdit.value) {
      callback()
      return
    }

    if (!value) {
      callback(new Error(t('register.rule.confirmPasswordRequired')))
      return
    }

    if (value !== formData.value.password) {
      callback(new Error(t('register.rule.passwordMismatch')))
      return
    }
    callback()
  }

  const resetForm = async (): Promise<void> => {
    formData.value = cloneDeep(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const initializeForm = async (row?: Partial<UserListItem>): Promise<void> => {
    await resetForm()

    if (row?.id) {
      formData.value = {
        ...formData.value,
        ...cloneDeep(row)
      }
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
      const { id, userEmail, password, authUserId, ...rest } = toRaw(formData.value)
      const params: UserListItem = {
        userEmail,
        password,
        ...rest
      }

      if (!isEdit.value) {
        await addUser(params)
        emit('success', 'add')
      } else {
        await editUser({ ...params, id, authUserId })
        emit('success', 'edit')
      }
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Partial<UserListItem>): Promise<void> => {
    await initializeForm(row)
    await dialogRef.value?.handleOpen(row, {
      title: isEdit.value ? '编辑用户' : '添加用户',
      width: '60%',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleSubmit,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
