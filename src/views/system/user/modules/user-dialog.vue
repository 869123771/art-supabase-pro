<template>
  <ArtDialog ref="dialogRef" size="lg">
    <div class="user-dialog">
      <section class="user-dialog__context">
        <div class="user-dialog__context-icon" aria-hidden="true">
          <ArtSvgIcon :icon="isEdit ? 'ri:user-settings-line' : 'ri:user-add-line'" />
        </div>
        <div>
          <strong>{{ contextTitle }}</strong>
          <p>{{ contextDescription }}</p>
        </div>
        <ElTag
          :type="isCurrentUser ? 'warning' : isEdit ? 'primary' : 'success'"
          effect="light"
          round
        >
          {{ isCurrentUser ? '当前账号' : isEdit ? '编辑资料' : '新增账号' }}
        </ElTag>
      </section>

      <ElAlert
        v-if="isCurrentUser"
        class="user-dialog__notice"
        title="正在维护当前登录账号，保存后的昵称与头像可能立即同步到导航栏。"
        type="warning"
        :closable="false"
        show-icon
      />

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
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { useI18n } from 'vue-i18n'
  import { cloneDeep, omit } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import {
    addUser,
    editUser,
    fetchGetEnableOrganizationTree,
    fetchGetEnableTenantList
  } from '@/api/system-manage'
  import { useSystemParam } from '@/hooks'

  type UserListItem = Api.SystemManage.UserListItem
  type SaveType = 'add' | 'edit'

  interface Emits {
    (e: 'success', type: SaveType): void
  }

  interface ArtFormExpose {
    validate: () => Promise<boolean | void>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<void>
  }

  const emit = defineEmits<Emits>()
  const userStore = useUserStore()
  const { getDictMap, getUserInfo, isSuper } = storeToRefs(userStore)
  const { t } = useI18n()
  const {
    passwordMinLength,
    loadPasswordPolicy,
    getPasswordMinLengthMessage,
    getPasswordComplexityMessage,
    validatePasswordComplexity
  } = useSystemParam()
  const dialogRef = ref<ArtDialogExpose<Partial<UserListItem> | undefined>>()
  const formRef = ref<ArtFormExpose>()

  const createInitialForm = (): UserListItem => ({
    id: undefined,
    tenantId: undefined,
    organizationId: null,
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
  const isCurrentUser = computed(
    () => isEdit.value && getUserInfo.value.email === formData.value.userEmail
  )
  const isProtectedSuperUser = computed(
    () =>
      isEdit.value &&
      (String(formData.value.userEmail ?? '').toLowerCase() === '869123771@qq.com' ||
        Boolean(formData.value.userRoles?.includes('R_SUPER')))
  )
  const canSelectTenant = computed(() => Boolean(isSuper.value))
  const currentTenantId = computed(() => getUserInfo.value.tenantId)
  const contextTitle = computed(() =>
    isEdit.value ? '维护用户资料与访问状态' : '创建新的登录账号'
  )
  const contextDescription = computed(() =>
    isEdit.value
      ? '账号邮箱保持锁定；租户归属与状态调整会影响访问范围，角色授权请通过专用入口维护。'
      : '完成身份、登录凭据和联系信息后，再按职责分配角色权限。'
  )

  const rules = computed<FormRules>(() => ({
    tenantId: canSelectTenant.value
      ? [{ required: true, message: '请选择所属租户', trigger: 'change' }]
      : [],
    userName: [{ min: 2, max: 20, message: '长度在 2 到 20 个字符', trigger: 'change' }],
    userPhone: [{ pattern: /^1[3-9]\d{9}$/, message: '请输入正确的手机号格式', trigger: 'change' }],
    userEmail: [{ required: true, type: 'email', message: '请输入正确的邮箱', trigger: 'change' }],
    password: [
      { required: true, validator: validatePassword, trigger: 'change' },
      {
        min: passwordMinLength.value,
        message: getPasswordMinLengthMessage(t),
        trigger: 'change'
      }
    ],
    confirmPassword: [{ required: true, validator: validateConfirmPassword, trigger: 'change' }]
  }))

  const formItems = computed<FormItem[]>(() => [
    {
      label: '基本身份',
      key: 'identitySection',
      type: 'divider',
      span: 24
    },
    {
      label: '头像',
      key: 'avatar',
      span: 24
    },
    {
      label: '所属租户',
      key: 'tenantId',
      type: 'select',
      span: 24,
      hidden: !canSelectTenant.value,
      api: fetchGetEnableTenantList,
      resultField: 'data',
      labelField: 'tenantName',
      valueField: 'id',
      labelFn: (item) => `${item.tenantName}（${item.tenantCode}）`,
      props: {
        placeholder: '请选择所属租户',
        filterable: true,
        disabled: isProtectedSuperUser.value,
        onChange: handleTenantChange
      }
    },
    {
      label: '所属组织',
      key: 'organizationId',
      type: 'treeSelect',
      span: 24,
      api: fetchGetEnableOrganizationTree,
      immediate: false,
      beforeFetch: () => ({ tenantId: formData.value.tenantId }),
      resultField: 'data',
      labelField: 'organizationName',
      valueField: 'id',
      labelFn: (item) => `${item.organizationName}（${item.organizationCode}）`,
      childrenField: 'children',
      props: {
        disabled: !formData.value.tenantId,
        clearable: true,
        checkStrictly: true,
        defaultExpandAll: true,
        renderAfterExpand: false,
        placeholder: formData.value.tenantId ? '请选择所属组织' : '请先选择租户'
      },
      description: '用户归属组织决定组织治理视图；角色权限仍通过角色分配独立控制。'
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
      label: '登录与联系',
      key: 'contactSection',
      type: 'divider',
      span: 24
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
      props: {
        placeholder: '请输入邮箱',
        clearable: true,
        disabled: isEdit.value
      },
      description: isEdit.value ? '登录邮箱已锁定，如需变更请通过账号迁移流程处理。' : undefined
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
      label: '账号属性',
      key: 'attributeSection',
      type: 'divider',
      span: 24
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
        options: getDictMap.value.status ?? [],
        disabled: isProtectedSuperUser.value
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

    if (!validatePasswordComplexity(value)) {
      callback(new Error(getPasswordComplexityMessage(t)))
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
    } else if (!canSelectTenant.value) {
      formData.value.tenantId = currentTenantId.value
    }
  }

  const handleTenantChange = (): void => {
    formData.value.organizationId = null
    void formRef.value?.reloadOptions('organizationId')
  }

  const handleSubmit = async (): Promise<boolean> => {
    if (!formRef.value) return false

    try {
      await formRef.value.validate()
    } catch {
      return false
    }

    try {
      const rawForm = toRaw(formData.value)
      const { id, userEmail, password, authUserId } = rawForm
      const rest = omit(rawForm, [
        'id',
        'authUserId',
        'userEmail',
        'password',
        'tenant',
        'organization',
        'createBy',
        'createTime',
        'updateBy',
        'updateTime'
      ])
      const params: UserListItem = {
        userEmail,
        password,
        ...rest
      }
      if (!canSelectTenant.value) {
        params.tenantId = currentTenantId.value
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
      title: isEdit.value ? '编辑用户' : '新增用户',
      contentMaxHeight: '70vh',
      loading: true,
      onOpen: async (_data, api) => {
        try {
          await Promise.all([loadPasswordPolicy(), formRef.value?.reloadOptions('organizationId')])
          if (formData.value.password) {
            await formRef.value?.validate()
          }
        } finally {
          api.setLoading(false)
        }
      },
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

<style scoped lang="scss">
  .user-dialog {
    display: grid;
    gap: 16px;
    min-width: 0;

    &__context {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 12px;
      align-items: center;
      padding: 14px 16px;
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: var(--custom-radius);

      > div:nth-child(2) {
        min-width: 0;
      }

      strong {
        display: block;
        margin-bottom: 3px;
        font-size: 14px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__context-icon {
      display: grid;
      place-items: center;
      width: 38px;
      height: 38px;
      color: var(--el-color-primary);
      background: var(--el-bg-color);
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 19px;
        height: 19px;
      }
    }

    &__notice {
      align-items: flex-start;

      :deep(.el-alert__content) {
        min-width: 0;
      }

      :deep(.el-alert__title) {
        line-height: 1.6;
      }
    }

    @media (width <= 640px) {
      &__context {
        grid-template-columns: auto minmax(0, 1fr);

        > :deep(.el-tag) {
          grid-column: 2;
          justify-self: start;
        }
      }
    }
  }
</style>
