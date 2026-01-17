<template>
  <ElDialog
    v-model="visible"
    title="菜单权限"
    width="520px"
    align-center
    class="el-dialog-border"
    @close="handleClose"
  >
    <ElScrollbar height="70vh" v-loading="loading">
      <ElTree
        ref="treeRef"
        :data="menuList"
        show-checkbox
        check-strictly
        node-key="id"
        :default-expand-all="isExpandAll"
        :default-checked-keys="[]"
        :props="defaultProps"
        @check="handleTreeCheck"
      >
        <template #default="{ data }">
          <div style="display: flex; align-items: center">
            <span v-if="data.isAuth">
              {{ data.label }}
            </span>
            <span v-else>{{ defaultProps.label(data) }}</span>
          </div>
        </template>
      </ElTree>
    </ElScrollbar>
    <template #footer>
      <ElButton @click="outputSelectedData">获取选中数据</ElButton>

      <ElButton @click="toggleExpandAll">{{ isExpandAll ? '全部收起' : '全部展开' }}</ElButton>
      <ElButton @click="toggleSelectAll">{{ isSelectAll ? '取消全选' : '全部选择' }}</ElButton>
      <ElButton type="primary" @click="savePermission" :loading="loading">保存</ElButton>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import { formatMenuTitle } from '@/utils/router'
  import TreeUtils from '@utils/tree'
  import type { AppRouteRecord } from '@/types'
  import {
    fetchGetEnableMenuList,
    getCurrentRoleMenus,
    saveRoleMenuList
  } from '@/api/system-manage'

  type RoleListItem = Api.SystemManage.RoleListItem

  interface Props {
    modelValue: boolean
    roleData?: RoleListItem
  }

  interface Emits {
    (e: 'update:modelValue', value: boolean): void
    (e: 'success'): void
  }

  const props = withDefaults(defineProps<Props>(), {
    modelValue: false,
    roleData: undefined
  })

  const emit = defineEmits<Emits>()

  const treeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children',
    deepClone: true
  })

  const loading = ref<boolean>(false)
  const menuList = ref<AppRouteRecord[]>([])
  const treeRef = ref()
  const isExpandAll = ref(true)
  const isSelectAll = ref(false)

  /**
   * 弹窗显示状态双向绑定
   */
  const visible = computed({
    get: () => props.modelValue,
    set: (value) => emit('update:modelValue', value)
  })

  const getCheckedKeys = computed(() => {
    const tree = treeRef.value
    if (!tree) return

    return tree.getCheckedKeys()
  })
  /**
   * 树形组件配置
   */
  const defaultProps = {
    children: 'children',
    label: (data: any) => formatMenuTitle(data.meta?.title) || data.label || ''
  }

  /**
   * 监听弹窗打开，初始化权限数据
   */
  watch(
    () => props.modelValue,
    async (newVal) => {
      if (newVal && props.roleData) {
        await handleGetMenuList()
        await handleSetCurrentRoleMenus()
        // TODO: 根据角色加载对应的权限数据
        console.log('设置权限:', props.roleData)
      }
    }
  )

  /**
   * 关闭弹窗并清空选中状态
   */
  const handleClose = () => {
    visible.value = false
    treeRef.value?.setCheckedKeys([])
  }

  /**
   * 保存权限配置
   */
  const savePermission = async () => {
    try {
      loading.value = true
      const checkedKeys = getCheckedKeys.value
      const params = {
        p_role_id: props.roleData?.id,
        p_menu_ids: checkedKeys
      }
      const { error } = await saveRoleMenuList(params)
      if (!error) {
        emit('success')
        handleClose()
      }
    } finally {
      loading.value = false
    }
  }

  /**
   * 切换全部展开/收起状态
   */
  const toggleExpandAll = () => {
    const tree = treeRef.value
    if (!tree) return

    const nodes = tree.store.nodesMap
    // 这里保留 any，因为 Element Plus 的内部节点类型较复杂
    Object.values(nodes).forEach((node: any) => {
      node.expanded = !isExpandAll.value
    })

    isExpandAll.value = !isExpandAll.value
  }

  /**
   * 切换全选/取消全选状态
   */
  const toggleSelectAll = () => {
    const tree = treeRef.value
    if (!tree) return

    if (!isSelectAll.value) {
      const allKeys = treeUtils
        .treeToList(menuList.value, { includeDepth: true, includeParentChain: true })
        ?.map((item: any) => item.id)
      tree.setCheckedKeys(allKeys)
    } else {
      tree.setCheckedKeys([])
    }

    isSelectAll.value = !isSelectAll.value
  }

  /**
   * 处理树节点选中状态变化
   * 同步更新全选按钮状态
   */
  const handleTreeCheck = () => {
    const checkedKeys = getCheckedKeys.value
    const allKeys = treeUtils
      .treeToList(menuList.value, { includeDepth: true, includeParentChain: true })
      ?.map((item: any) => item.id)

    isSelectAll.value = checkedKeys.length === allKeys.length && allKeys.length > 0
  }

  /**
   * 输出选中的权限数据到控制台
   * 用于调试和查看当前选中的权限配置
   */
  const outputSelectedData = () => {
    const tree = treeRef.value
    if (!tree) return

    const selectedData = {
      checkedKeys: tree.getCheckedKeys(),
      halfCheckedKeys: tree.getHalfCheckedKeys(),
      checkedNodes: tree.getCheckedNodes(),
      halfCheckedNodes: tree.getHalfCheckedNodes(),
      totalChecked: tree.getCheckedKeys().length,
      totalHalfChecked: tree.getHalfCheckedKeys().length
    }

    console.log('=== 选中的权限数据 ===', selectedData)
    ElMessage.success(`已输出选中数据到控制台，共选中 ${selectedData.totalChecked} 个节点`)
  }

  const handleGetMenuList = async () => {
    try {
      loading.value = true
      const { data } = await fetchGetEnableMenuList()
      menuList.value = treeUtils.listToTree(data) as AppRouteRecord[]
    } finally {
      loading.value = false
    }
  }

  const handleSetCurrentRoleMenus = async () => {
    try {
      loading.value = true
      const params = {
        id: props.roleData?.id
      }
      const { data } = await getCurrentRoleMenus(params)
      if (data) {
        const menuIds = (data || []).map((r: any) => r.menuId)
        treeRef.value?.setCheckedKeys(menuIds)
      }
    } finally {
      loading.value = false
    }
  }
</script>
