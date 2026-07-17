<template>
  <ArtDialog ref="dialogRef">
    <ElForm ref="formRef" :model="form" :rules="rules" label-width="120px" class="pr-6">
      <ElFormItem v-if="canSelectTenant" label="所属租户" prop="tenantId">
        <ElSelect
          v-model="form.tenantId"
          :disabled="dialogType === 'edit'"
          filterable
          placeholder="请选择所属租户"
          @change="handleTenantChange"
        >
          <ElOption
            v-for="tenant in selectableTenantOptions"
            :key="tenant.id"
            :label="formatTenantOption(tenant)"
            :value="tenant.id"
          />
        </ElSelect>
      </ElFormItem>
      <ElFormItem label="角色名称" prop="roleName">
        <ElInput v-model="form.roleName" placeholder="请输入角色名称" />
      </ElFormItem>
      <ElFormItem label="角色编码" prop="roleCode">
        <ElInput
          v-model="form.roleCode"
          :disabled="isSystemBuiltinRole"
          placeholder="请输入角色编码"
        />
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
        <ElSwitch v-model="form.enabled" :disabled="isSystemBuiltinRole" />
      </ElFormItem>
    </ElForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormInstance, FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
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

  interface Emits {
    (e: 'success'): void
  }

  const emit = defineEmits<Emits>()
  const userStore = useUserStore()
  const { getUserInfo, isSuper } = storeToRefs(userStore)
  const dialogRef = ref<ArtDialogExpose<RoleEditDialogOpenData>>()
  const formRef = ref<FormInstance>()
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
    } else if (!canSelectTenant.value) {
      form.tenantId = currentTenantId.value
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
      if (!canSelectTenant.value) {
        params.tenantId = currentTenantId.value
      }

      if (isDefaultRegisterRole.value) {
        params.roleCode = defaultRegisterRoleCode.value
        params.enabled = true
      }

      if (isSuperRole.value) {
        params.roleCode = superRoleCode.value
        params.enabled = true
      }

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

  const loadTenantOptions = async (): Promise<void> => {
    if (!canSelectTenant.value) return
    const { data } = await fetchGetEnableTenantList()
    tenantOptions.value = data ?? []
  }

  const formatTenantOption = (tenant: TenantListItem): string =>
    tenant.tenantCode ? `${tenant.tenantName}（${tenant.tenantCode}）` : tenant.tenantName

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
