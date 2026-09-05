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
        <span class="role-permission-dialog__selection-count">
          已选 {{ selectedCount }} / {{ permissionCount }} 项
        </span>
      </section>

      <div class="role-permission-dialog__toolbar">
        <ElInput
          v-model="permissionKeyword"
          placeholder="搜索菜单、按钮或权限标识"
          clearable
          @input="handlePermissionFilter"
        >
          <template #prefix>
            <ArtSvgIcon icon="ri:search-line" />
          </template>
        </ElInput>
        <span v-if="permissionKeyword.trim()">找到 {{ matchedCount }} 个匹配项</span>
        <span v-else>搜索会自动展开匹配路径</span>
      </div>

      <div
        v-if="menuList.length"
        ref="treeViewportRef"
        class="role-permission-dialog__tree-viewport"
      >
        <ElTreeV2
          ref="treeRef"
          class="role-permission-dialog__tree"
          :data="menuList"
          :height="treeHeight"
          :item-size="TREE_ROW_HEIGHT"
          :default-expanded-keys="initialExpandedKeys"
          show-checkbox
          :check-strictly="!isCascadeCheck"
          :filter-method="filterMenuNode"
          :props="treeProps"
          @check="handleTreeCheck"
          @node-expand="handleNodeExpand"
          @node-collapse="handleNodeCollapse"
        >
          <template #default="{ data }">
            <div class="role-permission-dialog__node" :title="data.displayLabel">
              <ArtSvgIcon
                class="role-permission-dialog__node-icon"
                :icon="getNodeIcon(data.type)"
              />
              <span>{{ data.displayLabel }}</span>
              <ElTag v-if="data.type === 'button'" size="small" type="info" effect="plain">
                按钮
              </ElTag>
              <span v-if="data.type === 'button'" class="role-permission-dialog__node-code">
                {{ data.name }}
              </span>
            </div>
          </template>
        </ElTreeV2>
      </div>

      <ArtAsyncState
        v-else-if="!contentLoading"
        class="role-permission-dialog__state"
        :error="loadError ? '菜单权限加载失败，请稍后重试' : null"
        :empty="!loadError"
        empty-text="暂无可配置的菜单权限"
        :empty-image-size="72"
        :min-height="240"
        @retry="loadPermission"
      />
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
          <ElTooltip content="作用于全部权限，不受当前搜索条件影响" placement="top">
            <ElButton @click="toggleSelectAll">
              {{ isSelectAll ? '取消全选' : '全部选择' }}
            </ElButton>
          </ElTooltip>
          <ElButton
            type="primary"
            :loading="loading"
            :disabled="contentLoading"
            @click="api.handleConfirm"
          >
            保存权限
          </ElButton>
        </div>
      </div>
    </template>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import ArtAsyncState from '@/components/core/feedback/art-async-state/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import { ElTreeV2, type TreeV2Instance } from 'element-plus'
  import { formatMenuTitle } from '@/utils/router'
  import TreeUtils from '@utils/tree'
  import { omit, uniq } from 'lodash-es'
  import { useDebounceFn, useElementSize } from '@vueuse/core'
  import type { AppRouteRecord } from '@/types'
  import {
    fetchGetEnableMenuList,
    getCurrentRoleMenus,
    saveRoleMenuList
  } from '@/api/system-manage'

  type RoleListItem = Api.SystemManage.RoleListItem
  type TreeKey = string | number
  type PermissionTreeNode = Omit<AppRouteRecord, 'children' | 'id'> & {
    id: string
    children?: PermissionTreeNode[]
    displayLabel: string
    searchText: string
  }

  interface Emits {
    (e: 'success'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<RoleListItem>>()
  const treeRef = ref<TreeV2Instance>()
  const treeViewportRef = ref<HTMLElement>()
  const roleData = shallowRef<RoleListItem>()
  const menuList = ref<PermissionTreeNode[]>([])
  const contentLoading = ref(false)
  const loadError = ref(false)
  const isExpandAll = ref(false)
  const isSelectAll = ref(false)
  const isCascadeCheck = ref(false)
  const permissionKeyword = ref('')
  const selectedCount = ref(0)
  const initialExpandedKeys = ref<TreeKey[]>([])
  const manualExpandedKeys = new Set<TreeKey>()
  const TREE_ROW_HEIGHT = 40
  const { height: viewportHeight } = useElementSize(treeViewportRef)
  const treeHeight = computed(() => Math.max(Math.floor(viewportHeight.value), 1))

  const treeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children',
    deepClone: false
  })

  const treeProps = {
    children: 'children',
    label: 'displayLabel',
    value: 'id'
  }

  const flatMenuList = computed(() =>
    treeUtils.treeToList(menuList.value, {
      includeDepth: true,
      includeParentChain: true
    })
  )
  const getCheckedKeys = (): TreeKey[] => treeRef.value?.getCheckedKeys() ?? []
  const getHalfCheckedKeys = (): TreeKey[] => treeRef.value?.getHalfCheckedKeys() ?? []

  const getNodeLabel = (data: AppRouteRecord): string =>
    formatMenuTitle(data.meta?.title ?? '') || data.name || '未命名权限'

  const getNodeIcon = (type?: string): string => {
    if (type === 'button') return 'ri:key-2-line'
    if (type === 'folder') return 'ri:folder-3-line'
    return 'ri:menu-line'
  }

  const toPermissionNode = (data: AppRouteRecord): PermissionTreeNode | null => {
    if (!data.id) return null
    const displayLabel = getNodeLabel(data)
    return {
      ...omit(data, ['children']),
      id: data.id,
      displayLabel,
      searchText: `${displayLabel} ${data.name} ${data.path ?? ''}`.toLowerCase()
    }
  }

  const getAllMenuKeys = (): TreeKey[] => {
    return flatMenuList.value
      .map((item) => item.id)
      .filter(
        (id): id is NonNullable<typeof id> => typeof id === 'string' || typeof id === 'number'
      )
  }

  const getExpandableMenuKeys = (): TreeKey[] =>
    uniq(
      flatMenuList.value
        .map((item) => item.parentId)
        .filter((parentId): parentId is string => typeof parentId === 'string')
    )

  const permissionCount = computed(() => getAllMenuKeys().length)
  const matchedCount = computed(() => {
    const keyword = permissionKeyword.value.trim().toLowerCase()
    if (!keyword) return permissionCount.value
    return flatMenuList.value.filter((item) => item.searchText.includes(keyword)).length
  })

  const resetPermission = (): void => {
    treeRef.value?.setCheckedKeys([])
    roleData.value = undefined
    menuList.value = []
    isExpandAll.value = false
    isSelectAll.value = false
    isCascadeCheck.value = false
    permissionKeyword.value = ''
    selectedCount.value = 0
    loadError.value = false
    initialExpandedKeys.value = []
    manualExpandedKeys.clear()
  }

  const loadPermission = async (): Promise<void> => {
    if (!roleData.value?.id) return

    contentLoading.value = true
    loadError.value = false
    try {
      const [menuResult, roleMenuResult] = await Promise.all([
        fetchGetEnableMenuList(),
        getCurrentRoleMenus({ id: roleData.value.id } as AppRouteRecord)
      ])
      if (menuResult.error || roleMenuResult.error) {
        loadError.value = true
        menuList.value = []
        return
      }

      const menus = menuResult.data ?? []
      const roleMenus = roleMenuResult.data ?? []
      const permissionNodes = (menus ?? [])
        .map(toPermissionNode)
        .filter((item): item is PermissionTreeNode => item !== null)
      menuList.value = treeUtils.listToTree(permissionNodes)
      initialExpandedKeys.value = menuList.value.map((item) => item.id)
      initialExpandedKeys.value.forEach((key) => manualExpandedKeys.add(key))
      await nextTick()
      const menuIds = roleMenus.map((item: { menuId: TreeKey }) => item.menuId)
      treeRef.value?.setCheckedKeys(menuIds)
      await nextTick()
      handleTreeCheck()
    } catch {
      loadError.value = true
      menuList.value = []
    } finally {
      contentLoading.value = false
      await nextTick()
      treeRef.value?.scrollTo(0)
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

    const shouldExpand = !isExpandAll.value
    const expandedKeys = shouldExpand ? getExpandableMenuKeys() : initialExpandedKeys.value
    tree.setExpandedKeys(expandedKeys)
    manualExpandedKeys.clear()
    expandedKeys.forEach((key) => manualExpandedKeys.add(key))
    isExpandAll.value = shouldExpand
  }

  const toggleSelectAll = async (): Promise<void> => {
    const tree = treeRef.value
    if (!tree) return

    tree.setCheckedKeys(isSelectAll.value ? [] : getAllMenuKeys())
    await nextTick()
    handleTreeCheck()
  }

  const handleTreeCheck = (): void => {
    const allKeys = getAllMenuKeys()
    isSelectAll.value = getCheckedKeys().length === allKeys.length && allKeys.length > 0
    selectedCount.value = getSelectedMenuIds().length
  }

  const filterMenuNode = (value: string, data: Record<string, unknown>): boolean => {
    if (!value.trim()) return true
    const keyword = value.trim().toLowerCase()
    return typeof data.searchText === 'string' && data.searchText.includes(keyword)
  }

  const applyPermissionFilter = useDebounceFn((value: string): void => {
    const tree = treeRef.value
    if (!tree) return

    tree.filter(value)
    tree.scrollTo(0)
    if (!value.trim()) {
      tree.setExpandedKeys([...manualExpandedKeys])
    }
  }, 120)

  const handlePermissionFilter = (value: string): void => {
    void applyPermissionFilter(value)
  }

  const handleNodeExpand = (data: Record<string, unknown>): void => {
    if (typeof data.id === 'string' || typeof data.id === 'number') {
      manualExpandedKeys.add(data.id)
    }
  }

  const handleNodeCollapse = (data: Record<string, unknown>): void => {
    if (typeof data.id === 'string' || typeof data.id === 'number') {
      manualExpandedKeys.delete(data.id)
    }
    isExpandAll.value = false
  }

  const getSelectedMenuIds = (): TreeKey[] => {
    if (!isCascadeCheck.value) {
      return getCheckedKeys()
    }

    return uniq([...getCheckedKeys(), ...getHalfCheckedKeys()])
  }

  const handleCascadeCheckChange = async (): Promise<void> => {
    const tree = treeRef.value
    if (!tree) return

    const checkedKeys = getCheckedKeys()
    await nextTick()
    tree.setCheckedKeys(checkedKeys)
    await nextTick()
    handleTreeCheck()
  }

  const handleOpen = async (data: RoleListItem): Promise<void> => {
    resetPermission()
    roleData.value = data
    await dialogRef.value?.handleOpen(data, {
      title: '配置菜单权限',
      subtitle: `为“${data.roleName}”配置可访问的菜单和操作权限`,
      size: 'lg',
      contentHeight: 'min(68vh, 640px)',
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

  :global(.role-permission-dialog-shell .art-dialog__scrollbar),
  :global(.role-permission-dialog-shell .art-dialog__scrollbar > .el-scrollbar__wrap),
  :global(
    .role-permission-dialog-shell .art-dialog__scrollbar > .el-scrollbar__wrap > .el-scrollbar__view
  ),
  :global(.role-permission-dialog-shell .art-dialog__content) {
    height: 100%;
  }

  :global(.role-permission-dialog-shell .art-overlay-loading),
  :global(.role-permission-dialog-shell .art-overlay-loading__content) {
    height: 100%;
  }

  .role-permission-dialog {
    display: flex;
    flex-direction: column;
    min-width: 0;
    height: 100%;

    &__context {
      display: flex;
      gap: 10px;
      align-items: center;
      min-width: 0;
      padding: 12px 14px;
      margin-bottom: 12px;
    }

    &__context-icon {
      display: grid;
      flex: 0 0 38px;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 18px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--art-control-radius);
    }

    &__context-copy {
      min-width: 0;

      > div {
        display: flex;
        gap: 8px;
        align-items: center;
        min-width: 0;

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 15px;
          color: var(--el-text-color-primary);
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
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      padding: 10px 12px;
      margin-bottom: 8px;
      background: var(--el-fill-color-extra-light);
      border-radius: var(--el-border-radius-base);

      .el-input {
        width: min(320px, 100%);
      }

      > span {
        font-size: 11px;
        color: var(--el-text-color-placeholder);
        text-align: right;
      }
    }

    &__tree-viewport {
      flex: 1;
      width: 100%;
      min-height: 0;
      overflow: hidden;
    }

    &__state {
      flex: 1;
    }

    &__tree {
      width: 100%;
      padding: 2px 6px 0;

      :deep(.el-tree-node__content) {
        min-height: 40px;
        border-radius: var(--el-border-radius-base);
      }
    }

    &__node {
      display: flex;
      gap: 7px;
      align-items: center;
      min-width: 0;

      > span {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__node-code {
      min-width: 0;
      margin-left: auto;
      font-family: var(--art-font-family-mono, ui-monospace, SFMono-Regular, Consolas, monospace);
      font-size: 11px;
      color: var(--el-text-color-placeholder);
    }

    &__node-icon {
      flex: 0 0 16px;
      font-size: 16px;
      color: var(--el-text-color-secondary);
    }

    &__footer {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
    }

    &__footer-actions {
      display: flex;
      align-items: center;
      justify-content: flex-end;
    }

    @media (width <= 640px) {
      &__context {
        flex-wrap: wrap;
        align-items: flex-start;
      }

      &__selection-count {
        margin-left: 48px;
      }

      &__toolbar {
        flex-direction: column;
        align-items: stretch;

        .el-input {
          width: 100%;
        }

        > span {
          text-align: left;
        }
      }

      &__footer {
        flex-direction: column;
        align-items: stretch;
      }

      &__footer-actions {
        flex-wrap: wrap;
      }
    }
  }
</style>
