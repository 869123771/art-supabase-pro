<template>
  <ArtDialog ref="dialogRef" :loading="contentLoading">
    <ElTree
      ref="treeRef"
      :data="menuList"
      show-checkbox
      :check-strictly="!isCascadeCheck"
      node-key="id"
      :default-expand-all="isExpandAll"
      :default-checked-keys="[]"
      :props="defaultProps"
      @check="handleTreeCheck"
    >
      <template #default="{ data }">
        <div class="flex items-center">
          <span v-if="data.isAuth">{{ data.label }}</span>
          <span v-else>{{ defaultProps.label(data) }}</span>
        </div>
      </template>
    </ElTree>

    <template #footer="{ loading, api }">
      <div class="role-permission-dialog__footer">
        <ElCheckbox
          v-model="isCascadeCheck"
          :disabled="contentLoading"
          @change="handleCascadeCheckChange"
        >
          父子关联
        </ElCheckbox>
        <div class="role-permission-dialog__footer-actions">
          <ElButton @click="toggleExpandAll">
            {{ isExpandAll ? '全部收起' : '全部展开' }}
          </ElButton>
          <ElButton @click="toggleSelectAll">
            {{ isSelectAll ? '取消全选' : '全部选择' }}
          </ElButton>
          <ElButton
            type="primary"
            :loading="loading"
            :disabled="contentLoading"
            @click="api.handleConfirm"
          >
            保存
          </ElButton>
        </div>
      </div>
    </template>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import { formatMenuTitle } from '@/utils/router'
  import TreeUtils from '@utils/tree'
  import type { AppRouteRecord } from '@/types'
  import {
    fetchGetEnableMenuList,
    getCurrentRoleMenus,
    saveRoleMenuList
  } from '@/api/system-manage'

  type RoleListItem = Api.SystemManage.RoleListItem
  type TreeKey = string | number
  type TreeStoreNode = { expanded: boolean }

  interface Emits {
    (e: 'success'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<RoleListItem>>()
  const treeRef = ref()
  const roleData = shallowRef<RoleListItem>()
  const menuList = ref<AppRouteRecord[]>([])
  const contentLoading = ref(false)
  const isExpandAll = ref(true)
  const isSelectAll = ref(false)
  const isCascadeCheck = ref(false)

  const treeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children',
    deepClone: true
  })

  const getCheckedKeys = computed<TreeKey[]>(() => treeRef.value?.getCheckedKeys() ?? [])
  const getHalfCheckedKeys = computed<TreeKey[]>(() => treeRef.value?.getHalfCheckedKeys() ?? [])

  const defaultProps = {
    children: 'children',
    label: (data: Record<string, unknown>) => {
      const meta = data.meta as AppRouteRecord['meta'] | undefined
      return formatMenuTitle(meta?.title ?? '') || String(data.label ?? '')
    }
  }

  const getAllMenuKeys = (): TreeKey[] => {
    const list = treeUtils.treeToList(menuList.value, {
      includeDepth: true,
      includeParentChain: true
    })
    return (list ?? [])
      .map((item) => item.id)
      .filter(
        (id): id is NonNullable<typeof id> => typeof id === 'string' || typeof id === 'number'
      )
  }

  const resetPermission = (): void => {
    treeRef.value?.setCheckedKeys([])
    roleData.value = undefined
    menuList.value = []
    isExpandAll.value = true
    isSelectAll.value = false
    isCascadeCheck.value = false
  }

  const loadPermission = async (): Promise<void> => {
    if (!roleData.value?.id) return

    contentLoading.value = true
    try {
      const [{ data: menus }, { data: roleMenus }] = await Promise.all([
        fetchGetEnableMenuList(),
        getCurrentRoleMenus({ id: roleData.value.id } as AppRouteRecord)
      ])
      menuList.value = treeUtils.listToTree(menus ?? []) as AppRouteRecord[]
      await nextTick()
      const menuIds = (roleMenus ?? []).map((item: { menuId: TreeKey }) => item.menuId)
      treeRef.value?.setCheckedKeys(menuIds)
      handleTreeCheck()
    } finally {
      contentLoading.value = false
    }
  }

  const savePermission = async (): Promise<boolean> => {
    if (!roleData.value?.id) return false

    try {
      const menuIds = getSelectedMenuIds()
      const { error } = await saveRoleMenuList({
        p_role_id: roleData.value.id,
        p_menu_ids: menuIds.filter((key): key is string => typeof key === 'string')
      })
      if (error) return false

      emit('success')
      return true
    } catch {
      return false
    }
  }

  const toggleExpandAll = (): void => {
    const tree = treeRef.value
    if (!tree) return

    Object.values(tree.store.nodesMap).forEach((node) => {
      const storeNode = node as TreeStoreNode
      storeNode.expanded = !isExpandAll.value
    })
    isExpandAll.value = !isExpandAll.value
  }

  const toggleSelectAll = (): void => {
    const tree = treeRef.value
    if (!tree) return

    tree.setCheckedKeys(isSelectAll.value ? [] : getAllMenuKeys())
    isSelectAll.value = !isSelectAll.value
  }

  const handleTreeCheck = (): void => {
    const allKeys = getAllMenuKeys()
    isSelectAll.value = getCheckedKeys.value.length === allKeys.length && allKeys.length > 0
  }

  const getSelectedMenuIds = (): TreeKey[] => {
    if (!isCascadeCheck.value) {
      return getCheckedKeys.value
    }

    return [...new Set([...getCheckedKeys.value, ...getHalfCheckedKeys.value])]
  }

  const handleCascadeCheckChange = async (): Promise<void> => {
    const tree = treeRef.value
    if (!tree) return

    const checkedKeys = getCheckedKeys.value
    await nextTick()
    tree.setCheckedKeys(checkedKeys)
    handleTreeCheck()
  }

  const handleOpen = async (data: RoleListItem): Promise<void> => {
    resetPermission()
    roleData.value = data
    await dialogRef.value?.handleOpen(data, {
      title: '菜单权限',
      width: '520px',
      contentHeight: '70vh',
      dialogProps: {
        class: 'el-dialog-border'
      },
      onOpen: loadPermission,
      onConfirm: savePermission,
      onReset: resetPermission
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>

<style scoped lang="scss">
  .role-permission-dialog {
    &__footer {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }

    &__footer-actions {
      display: flex;
      align-items: center;
      justify-content: flex-end;
    }
  }
</style>
