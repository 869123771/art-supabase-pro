<template>
  <ArtDialog ref="dialogRef">
    <ArtForm
      ref="formRef"
      v-model="formData"
      class="pr-4"
      :items="formItems"
      :rules="rules"
      :span="24"
      :gutter="20"
      label-width="80px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { cloneDeep } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { editUser, fetchGetEnableRoleList } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'

  type UserListItem = Api.SystemManage.UserListItem
  type UserRoleFormData = Pick<UserListItem, 'userRoles' | 'id' | 'tenantId'>

  interface Emits {
    (e: 'success'): void
  }

  const emit = defineEmits<Emits>()
  const userStore = useUserStore()
  const { getUserInfo, isSuper } = storeToRefs(userStore) as Record<string, any>
  const dialogRef = ref<ArtDialogExpose<UserListItem>>()
  const formRef = ref()
  const rules: FormRules = {}

  const createInitialForm = (): UserRoleFormData => ({
    userRoles: []
  })

  const formData = ref<UserRoleFormData>(createInitialForm())
  const currentTenantId = computed(() => getUserInfo.value.tenantId)
  const roleQueryTenantId = computed(() =>
    isSuper.value ? formData.value.tenantId : currentTenantId.value
  )

  const formItems = computed<FormItem[]>(() => [
    {
      label: '角色',
      key: 'userRoles',
      type: 'select',
      api: fetchGetEnableRoleList,
      params: {
        tenantId: roleQueryTenantId.value
      },
      shouldFetch: (params) => Boolean(params?.tenantId),
      resultField: 'data',
      labelField: 'roleName',
      valueField: 'roleCode',
      props: {
        multiple: true,
        filterable: true,
        collapseTags: true,
        collapseTagsTooltip: true,
        maxCollapseTags: 3,
        disabled: !roleQueryTenantId.value,
        placeholder: roleQueryTenantId.value ? '请选择角色' : '当前用户未绑定租户'
      }
    }
  ])

  const resetForm = async (): Promise<void> => {
    formData.value = cloneDeep(createInitialForm())
    await nextTick()
    formRef.value?.ref?.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const params = { ...formData.value } as UserListItem
      if (!isSuper.value) {
        params.tenantId = currentTenantId.value
      }
      await editUser(params)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (data: UserListItem): Promise<void> => {
    await resetForm()
    const { id, userRoles, tenantId } = data
    formData.value = {
      id,
      userRoles,
      tenantId: isSuper.value ? tenantId : currentTenantId.value
    }
    await dialogRef.value?.handleOpen(data, {
      title: '赋予角色',
      width: '50%',
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
