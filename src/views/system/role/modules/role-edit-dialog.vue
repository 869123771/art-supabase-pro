<template>
  <ArtDialog ref="dialogRef" size="md">
    <div v-if="isSystemBuiltinRole" class="role-edit-dialog__notice art-card-xs">
      <span aria-hidden="true"><ArtSvgIcon icon="ri:shield-check-line" /></span>
      <div>
        <strong>系统内置角色</strong>
        <p>角色编码与启用状态受系统保护，仅允许调整名称和描述。</p>
      </div>
    </div>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="rules"
      :span="12"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { addRole, editRole, fetchGetEnableTenantList } from '@/api/system-manage'
  import { uniqueValidator } from '@/utils'
  import { useUserStore } from '@/store/modules/user'
  import { useSystemParam } from '@/hooks'

  type RoleListItem = Api.SystemManage.RoleListItem
  type TenantListItem = Api.SystemManage.TenantListItem
  type DialogType = 'add' | 'edit'

  interface RoleEditDialogOpenData {
    type: DialogType
    roleData?: RoleListItem
  }

  interface ArtFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    validateField: (prop: string) => void
  }

  interface Emits {
    (e: 'success'): void
  }

  const emit = defineEmits<Emits>()
  const userStore = useUserStore()
  const { getUserInfo, isSuper } = storeToRefs(userStore)
  const dialogRef = ref<ArtDialogExpose<RoleEditDialogOpenData>>()
  const formRef = ref<ArtFormExpose>()
  const dialogType = ref<DialogType>('add')
  const currentTenantCode = ref('')
  const tenantOptions = shallowRef<TenantListItem[]>([])
  const {
    defaultRegisterTenantCode,
    defaultRegisterRoleCode,
    superRoleCode,
    loadRoleBuiltinCodes
  } = useSystemParam()

  const normalizeRoleCode = (roleCode?: string): string => String(roleCode ?? '').toUpperCase()
  const canSelectTenant = computed(() => Boolean(isSuper.value))
  const currentTenantId = computed(() => getUserInfo.value.tenantId)
  const selectableTenantOptions = computed(() =>
    tenantOptions.value.filter((tenant): tenant is TenantListItem & { id: string } =>
      Boolean(tenant.id)
    )
  )

  const isDefaultRegisterRole = computed(() => {
    return (
      dialogType.value === 'edit' &&
      currentTenantCode.value.toLowerCase() === defaultRegisterTenantCode.value.toLowerCase() &&
      normalizeRoleCode(form.roleCode) === normalizeRoleCode(defaultRegisterRoleCode.value)
    )
  })

  const isSuperRole = computed(() => {
    return (
      dialogType.value === 'edit' &&
      normalizeRoleCode(form.roleCode) === normalizeRoleCode(superRoleCode.value)
    )
  })

  const isSystemBuiltinRole = computed(() => isDefaultRegisterRole.value || isSuperRole.value)

  const createInitialForm = (): RoleListItem => ({
    id: undefined,
    tenantId: undefined,
    roleName: '',
    roleCode: '',
    description: '',
    enabled: true,
    createBy: undefined
  })

  const form = reactive<RoleListItem>(createInitialForm())

  const rules = computed<FormRules>(() => ({
    tenantId: canSelectTenant.value
      ? [{ required: true, message: '请选择所属租户', trigger: 'change' }]
      : [],
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
          extraWhere: () => ({ tenant_id: form.tenantId }),
          message: '角色编码已存在'
        }),
        trigger: 'change'
      }
    ],
    description: [{ required: true, message: '请输入角色描述', trigger: 'change' }]
  }))

  const formatTenantOption = (tenant: TenantListItem): string =>
    tenant.tenantCode ? `${tenant.tenantName}（${tenant.tenantCode}）` : tenant.tenantName

  const formItems = computed<FormItem[]>(() => [
    {
      label: '角色定义',
      key: 'identitySection',
      type: 'divider',
      span: 24
    },
    {
      label: '所属租户',
      key: 'tenantId',
      type: 'select',
      hidden: !canSelectTenant.value,
      props: {
        disabled: dialogType.value === 'edit',
        filterable: true,
        options: selectableTenantOptions.value.map((tenant) => ({
          label: formatTenantOption(tenant),
          value: tenant.id
        })),
        onChange: handleTenantChange
      },
      help: '角色编码在同一租户内必须唯一。'
    },
    {
      label: '角色名称',
      key: 'roleName',
      type: 'input',
      props: {
        placeholder: '如：财务审核员'
      },
      description: '建议使用能够直接体现职责范围的名称。'
    },
    {
      label: '角色编码',
      key: 'roleCode',
      type: 'input',
      props: {
        disabled: isSystemBuiltinRole.value,
        placeholder: '如：R_FINANCE_AUDITOR'
      },
      help: '建议使用大写字母、数字与下划线，保存后应谨慎修改。'
    },
    {
      label: '描述',
      key: 'description',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 3,
        maxlength: 300,
        showWordLimit: true,
        placeholder: '说明该角色的职责边界和适用成员'
      },
      description: '清晰的职责说明有助于后续权限审计。'
    },
    {
      label: '状态控制',
      key: 'statusSection',
      type: 'divider',
      span: 24
    },
    {
      label: '启用',
      key: 'enabled',
      type: 'switch',
      props: {
        disabled: isSystemBuiltinRole.value
      },
      span: 24,
      description: isSystemBuiltinRole.value
        ? '系统内置角色始终保持启用。'
        : '停用后请同步检查已关联用户的访问安排。'
    }
  ])

  const resetForm = async (): Promise<void> => {
    Object.assign(form, createInitialForm())
    currentTenantCode.value = ''
    await nextTick()
    formRef.value?.clearValidate()
  }

  const initializeForm = async (data: RoleEditDialogOpenData): Promise<void> => {
    await resetForm()
    dialogType.value = data.type

    if (data.roleData) {
      const { id, tenantId, roleName, roleCode, description, enabled, createBy } = data.roleData
      currentTenantCode.value = data.roleData.tenant?.tenantCode ?? ''
      Object.assign(form, {
        id,
        tenantId,
        roleName,
        roleCode,
        description,
        enabled,
        createBy
      })
      return
    }

    if (!canSelectTenant.value) {
      form.tenantId = currentTenantId.value
    }
  }

  const buildRolePayload = (): Omit<RoleListItem, 'id'> => {
    const payload = { ...toRaw(form) }
    delete payload.id

    if (!canSelectTenant.value) {
      payload.tenantId = currentTenantId.value
    }

    if (isDefaultRegisterRole.value) {
      payload.roleCode = defaultRegisterRoleCode.value
      payload.enabled = true
    }

    if (isSuperRole.value) {
      payload.roleCode = superRoleCode.value
      payload.enabled = true
    }

    return payload
  }

  const handleSubmit = async (): Promise<boolean> => {
    if (!formRef.value) return false

    try {
      await formRef.value.validate()
    } catch {
      return false
    }

    try {
      const payload = buildRolePayload()

      if (dialogType.value === 'add') {
        await addRole(payload)
      } else {
        await editRole({ ...payload, id: form.id })
      }
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const loadTenantOptions = async (): Promise<void> => {
    if (!canSelectTenant.value) return
    const { data } = await fetchGetEnableTenantList()
    tenantOptions.value = data ?? []
  }

  const handleTenantChange = (): void => {
    if (form.roleCode) {
      void formRef.value?.validateField('roleCode')
    }
  }

  const handleOpen = async (data: RoleEditDialogOpenData): Promise<void> => {
    await Promise.all([loadRoleBuiltinCodes(), loadTenantOptions()])
    await initializeForm(data)
    await dialogRef.value?.handleOpen(data, {
      title: data.type === 'add' ? '新增角色' : '编辑角色',
      contentMaxHeight: '68vh',
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

<style scoped lang="scss">
  .role-edit-dialog {
    &__notice {
      display: flex;
      align-items: flex-start;
      padding: 12px 14px;
      margin: 4px 16px 0;
      gap: 10px;

      > span {
        display: grid;
        flex: 0 0 32px;
        width: 32px;
        height: 32px;
        font-size: 16px;
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-radius: var(--art-control-radius);
        place-items: center;
      }

      strong {
        font-size: 13px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 2px 0 0;
        font-size: 12px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }
    }
  }
</style>
