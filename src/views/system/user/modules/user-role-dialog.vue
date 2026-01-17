<template>
  <ElDialog
    v-model="dialog.visible"
    title="赋予角色"
    width="50%"
    align-center
    destroy-on-close
    @close="handleClose"
  >
    <ArtForm
      class="pr-4"
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="24"
      :gutter="20"
      label-width="80px"
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
  import ArtForm, { FormItem } from '@/components/core/forms/art-form/index.vue'
  import { cloneDeep, isEmpty } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { editUser, fetchGetEnableRoleList } from '@/api/system-manage'

  import UserListItem = Api.SystemManage.UserListItem
  import RoleListItem = Api.SystemManage.RoleListItem
  import DictListItem = Api.DataCenter.DictListItem

  const emits = defineEmits(['success'])

  const dialog = ref({
    visible: false,
    loading: false
  })

  const dataDefault = {
    userRoles: []
  }
  const form = ref({
    data: cloneDeep(dataDefault) as Pick<UserListItem, 'userRoles' | 'id'>,
    items: computed<FormItem[]>(() => {
      return [
        {
          label: '角色',
          key: 'userRoles',
          type: 'select',
          props: {
            multiple: true,
            options: select.value?.roles ?? []
          }
        }
      ]
    }),
    rules: computed<FormRules>(() => {
      return {}
    })
  })

  const select = ref({
    roles: [] as DictListItem[]
  })

  const handleResetFields = () => {
    form.value.data = cloneDeep(dataDefault)
  }

  const handleOpen = (data: UserListItem = {} as UserListItem) => {
    dialog.value = {
      ...unref(dialog),
      visible: true
    }
    if (!isEmpty(data)) {
      const { id, userRoles = [] } = data
      form.value.data = {
        userRoles,
        id
      }
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
    try {
      dialog.value.loading = true
      const { data } = form.value

      const params = {
        ...data
      }
      await editUser(params as UserListItem)
      emits('success')
      handleClose()
    } finally {
      dialog.value.loading = false
    }
  }

  const handleGetRoles = async () => {
    const { data } = await fetchGetEnableRoleList()
    select.value = {
      ...unref(select),
      roles: (data as RoleListItem[]).map(({ roleCode, roleName }) => {
        return {
          label: roleName,
          value: roleCode
        }
      }) as DictListItem[]
    }
  }

  onMounted(() => {
    handleGetRoles()
  })

  defineExpose({
    handleOpen
  })
</script>

<style scoped lang="scss"></style>
