<template>
  <ArtDialog ref="dialogRef" :loading="contentLoading">
    <div class="role-permission-dialog">
      <section class="role-permission-dialog__context art-card-xs">
        <div class="role-permission-dialog__context-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:shield-user-line" />
        </div>
        <div class="role-permission-dialog__context-copy">
          <div>
            <strong>{{ roleData?.roleName || '未选择角色' }}</strong>
            <span>{{ roleData?.roleCode }}</span>
          </div>
          <p>勾选该角色可访问的菜单与按钮权限，保存后对关联用户生效。</p>
        </div>
        <span class="role-permission-dialog__selection-count">已选 {{ selectedCount }} 项</span>
      </section>

      <div class="role-permission-dialog__toolbar">
        <ElInput
          v-model="permissionKeyword"
          placeholder="搜索菜单或按钮权限"
          clearable
          @input="handlePermissionFilter"
        >
          <template #prefix>
            <ArtSvgIcon icon="ri:search-line" />
          </template>
        </ElInput>
        <span>支持展开目录后精细配置按钮权限</span>
      </div>

      <ElTree
        v-if="menuList.length"
        ref="treeRef"
        class="role-permission-dialog__tree"
        :data="menuList"
        show-checkbox
        :check-strictly="!isCascadeCheck"
        :filter-node-method="filterMenuNode"
        node-key="id"
        :default-expand-all="isExpandAll"
        :default-checked-keys="[]"
        :props="defaultProps"
        @check="handleTreeCheck"
      >
        <template #default="{ data }">
          <div class="role-permission-dialog__node">
            <ArtSvgIcon
              class="role-permission-dialog__node-icon"
              :icon="data.isAuth ? 'ri:key-2-line' : 'ri:menu-line'"
            />
            <span>{{ data.isAuth ? data.label : defaultProps.label(data) }}</span>
            <ElTag v-if="data.isAuth" size="small" type="info" effect="plain">按钮</ElTag>
          </div>
        </template>
      </ElTree>

      <ElEmpty v-else-if="!contentLoading" :image-size="72" description="暂无可配置的菜单权限" />
    </div>

    <template #footer="{ loading, api }">
      <div class="role-permission-dialog__footer">
        <ElTooltip content="开启后，选择父菜单会联动其下级菜单与按钮权限" placement="top">
          <ElCheckbox
            v-model="isCascadeCheck"
            :disabled="contentLoading"
            @change="handleCascadeCheckChange"
          >
            父子关联
          </ElCheckbox>
        </ElTooltip>
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
  const permissionKeyword = ref('')
  const selectedCount = ref(0)

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
    permissionKeyword.value = ''
    selectedCount.value = 0
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
    handleTreeCheck()
  }

  const handleTreeCheck = (): void => {
    const allKeys = getAllMenuKeys()
    isSelectAll.value = getCheckedKeys.value.length === allKeys.length && allKeys.length > 0
    selectedCount.value = getSelectedMenuIds().length
  }

  const filterMenuNode = (value: string, data: Record<string, unknown>): boolean => {
    if (!value.trim()) return true
    const keyword = value.trim().toLowerCase()
    const label = data.isAuth ? String(data.label ?? '') : defaultProps.label(data)
    return label.toLowerCase().includes(keyword)
  }

  const handlePermissionFilter = (value: string): void => {
    treeRef.value?.filter(value)
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
      title: '配置菜单权限',
      size: 'md',
      contentHeight: '66vh',
      dialogProps: {
        class: 'el-dialog-border',
        bodyClass: 'role-permission-dialog-shell'
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
  :global(.role-permission-dialog-shell) {
    overflow-x: hidden;
  }

  .role-permission-dialog {
    min-width: 0;

    &__context {
      display: flex;
      min-width: 0;
      align-items: center;
      padding: 12px 14px;
      margin-bottom: 12px;
      gap: 10px;
    }

    &__context-icon {
      display: grid;
      flex: 0 0 38px;
      width: 38px;
      height: 38px;
      font-size: 18px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--art-control-radius);
      place-items: center;
    }

    &__context-copy {
      min-width: 0;

      > div {
        display: flex;
        min-width: 0;
        align-items: center;
        gap: 8px;

        strong {
          overflow: hidden;
          font-size: 15px;
          color: var(--el-text-color-primary);
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        span {
          flex: none;
          padding: 1px 7px;
          font-size: 11px;
          color: var(--el-text-color-secondary);
          background: var(--el-fill-color-light);
          border-radius: 999px;
        }
      }

      p {
        margin: 3px 0 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__selection-count {
      flex: none;
      padding: 3px 9px;
      font-size: 12px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 999px;
    }

    &__toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 10px 12px;
      margin-bottom: 8px;
      background: var(--el-fill-color-extra-light);
      border-radius: var(--el-border-radius-base);
      gap: 12px;

      .el-input {
        width: min(320px, 100%);
      }

      > span {
        font-size: 11px;
        color: var(--el-text-color-placeholder);
        text-align: right;
      }
    }

    &__tree {
      padding: 2px 6px 12px;

      :deep(.el-tree-node__content) {
        min-height: 36px;
        border-radius: var(--el-border-radius-base);
      }
    }

    &__node {
      display: flex;
      min-width: 0;
      align-items: center;
      gap: 7px;

      > span {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__node-icon {
      flex: 0 0 16px;
      font-size: 16px;
      color: var(--el-text-color-secondary);
    }

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

    @media (width <= 640px) {
      &__context {
        align-items: flex-start;
        flex-wrap: wrap;
      }

      &__selection-count {
        margin-left: 48px;
      }

      &__toolbar {
        align-items: stretch;
        flex-direction: column;

        .el-input {
          width: 100%;
        }

        > span {
          text-align: left;
        }
      }

      &__footer {
        align-items: stretch;
        flex-direction: column;
      }

      &__footer-actions {
        flex-wrap: wrap;
      }
    }
  }
</style>
