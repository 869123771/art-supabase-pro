<template>
  <ElCard class="tree-card art-card-xs flex flex-col h-full mt-0" shadow="never">
    <template #header>
      <div class="dict-type-tree__header">
        <ElInput
          v-model="tree.keyword"
          placeholder="搜索目录或字典类型"
          clearable
          @input="handleFilter"
        />
        <ElTooltip content="新增根节点" placement="top">
          <ElButton type="primary" @click="handleAdd()">
            <ArtSvgIcon icon="ri:add-fill" />
          </ElButton>
        </ElTooltip>
      </div>
    </template>

    <ElScrollbar v-loading="tree.loading">
      <ElTree
        ref="treeRef"
        :data="tree.data"
        :props="tree.props"
        :filter-node-method="filterNode"
        :draggable="!tree.keyword.trim()"
        :allow-drop="allowDrop"
        :default-expanded-keys="tree.expandedKeys"
        node-key="id"
        highlight-current
        @node-click="handleNodeClick"
        @node-expand="handleNodeExpand"
        @node-collapse="handleNodeCollapse"
        @node-drag-start="handleNodeDragStart"
        @node-drop="handleNodeDrop"
        @node-drag-end="handleNodeDragEnd"
      >
        <template #default="{ data }">
          <div
            class="dict-type-tree__node"
            :class="{
              'is-multi-selected': isNodeSelected(data),
              'is-selectable-leaf': isSelectableLeaf(data)
            }"
          >
            <div class="dict-type-tree__label">
              <ArtSvgIcon
                class="dict-type-tree__node-icon"
                :icon="data.nodeType === 'directory' ? 'ri:folder-3-line' : 'ri:book-2-line'"
              />
              <span>{{ data.name }}</span>
              <ElTag v-if="data.nodeType === 'dictionary'" size="small" type="info">
                {{ data.code }}
              </ElTag>
            </div>

            <div class="dict-type-tree__actions" @click.stop>
              <ElTooltip v-if="data.nodeType === 'directory'" content="新增下级" placement="top">
                <ElButton size="small" circle type="primary" @click="handleAdd(data)">
                  <ArtSvgIcon icon="ri:add-line" />
                </ElButton>
              </ElTooltip>
              <ElTooltip content="编辑" placement="top">
                <ElButton size="small" circle type="success" @click="handleEdit(data)">
                  <ArtSvgIcon icon="ri:pencil-line" />
                </ElButton>
              </ElTooltip>
              <ElTooltip content="删除" placement="top">
                <ElButton size="small" circle type="danger" @click="handleDelete(data)">
                  <ArtSvgIcon icon="ri:delete-bin-5-line" />
                </ElButton>
              </ElTooltip>
            </div>
          </div>
        </template>
      </ElTree>
    </ElScrollbar>
  </ElCard>

  <DictTypeDialog ref="dictTypeDialogRef" @success="handleSuccess" />
</template>

<script setup lang="ts">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ElTree, NodeDropType } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import { cloneDeep } from 'lodash-es'
  import TreeUtils from '@/utils/tree'
  import { deleteDictType, fetchGetDictTypeList, saveDictTypeTreeOrder } from '@/api/data-center'
  import DictTypeDialog from './dict-type-dialog.vue'

  const { confirmAction } = useArtFeedback()

  type DictTypeItem = Api.DataCenter.DictTypeItem
  type AllowDrop = NonNullable<InstanceType<typeof ElTree>['$props']['allowDrop']>

  interface DictTypeDialogExpose {
    handleOpen: (
      data?: DictTypeItem,
      options?: { parentId?: string; treeData: DictTypeItem[] }
    ) => Promise<void>
  }

  interface TreeState {
    keyword: string
    loading: boolean
    data: DictTypeItem[]
    expandedKeys: string[]
    hasInitializedExpandedKeys: boolean
    selectedKeys: string[]
    selectionAnchorKey?: string
    draggingBatchKeys: string[]
    dragSourceData: DictTypeItem[]
    props: {
      children: string
      label: string
      class: (data: unknown) => Record<string, boolean>
    }
  }

  interface ElementTreeNode {
    data?: unknown
    expanded?: boolean
  }

  interface TreeOrderUpdate {
    id: string
    parentId: string | null
    sort: number
  }

  interface FlatDictTypeItem extends DictTypeItem {
    __parentChain?: Array<string | number>
  }

  interface DropSiblingContext {
    siblings: DictTypeItem[]
    targetIndex: number
    parentId: string | null
  }

  const emit = defineEmits<{
    'tree-node-click': [DictTypeItem]
  }>()

  const treeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const treeRef = ref<InstanceType<typeof ElTree>>()
  const dictTypeDialogRef = ref<DictTypeDialogExpose>()
  const tree = reactive<TreeState>({
    keyword: '',
    loading: false,
    data: [],
    expandedKeys: [],
    hasInitializedExpandedKeys: false,
    selectedKeys: [],
    selectionAnchorKey: undefined,
    draggingBatchKeys: [],
    dragSourceData: [],
    props: {
      children: 'children',
      label: 'name',
      class: getNodeClass
    }
  })

  const getCurrentDictType = computed<DictTypeItem | undefined>(() => {
    return (treeRef.value?.getCurrentNode() as DictTypeItem | null | undefined) ?? undefined
  })

  const filterNode = (value: string, rawData: unknown): boolean => {
    const data = rawData as DictTypeItem
    if (!value) return true
    const normalizedKeyword = value.trim().toLowerCase()
    return [data.name, data.code].some((field) =>
      String(field || '')
        .toLowerCase()
        .includes(normalizedKeyword)
    )
  }

  const handleFilter = (value: string): void => {
    treeRef.value?.filter(value)
  }

  function getNodeClass(data: unknown): Record<string, boolean> {
    const node = getDictTypeData(data)

    return {
      'is-multi-selected': isNodeSelected(node),
      'is-selectable-leaf': isSelectableLeaf(node)
    }
  }

  const handleNodeClick = (
    rawData: unknown,
    _node: unknown,
    _nodeInstance: unknown,
    event: MouseEvent
  ): void => {
    const data = getDictTypeData(rawData)
    if (!data) return

    if ((event.ctrlKey || event.metaKey || event.shiftKey) && isSelectableLeaf(data)) {
      handleShortcutSelection(data, event)
    } else if (!event.ctrlKey && !event.metaKey && !event.shiftKey) {
      clearSelectedKeys()
    }

    emit('tree-node-click', data)
  }

  const getNodeKey = (node?: Pick<DictTypeItem, 'id'> | null): string | undefined => {
    return node?.id ? String(node.id) : undefined
  }

  function getDictTypeData(data: unknown): DictTypeItem | undefined {
    if (!data || typeof data !== 'object' || !('nodeType' in data)) return undefined
    return data as DictTypeItem
  }

  function getTreeNodeData(node: unknown): DictTypeItem | undefined {
    if (!node || typeof node !== 'object' || !('data' in node)) return undefined
    return getDictTypeData((node as ElementTreeNode).data)
  }

  function isSelectableLeaf(node?: DictTypeItem | null): boolean {
    return node?.nodeType === 'dictionary' && !node.children?.length
  }

  function isNodeSelected(node?: DictTypeItem | null): boolean {
    const key = getNodeKey(node)
    return Boolean(key && tree.selectedKeys.includes(key))
  }

  function clearSelectedKeys(): void {
    tree.selectedKeys = []
    tree.selectionAnchorKey = undefined
  }

  const getFlatTreeNodes = (nodes: DictTypeItem[] = tree.data): FlatDictTypeItem[] => {
    return treeUtils.treeToList<FlatDictTypeItem>(nodes, {
      includeParentChain: true
    })
  }

  const getVisibleSelectableNodes = (): DictTypeItem[] => {
    const expandedKeySet = new Set(tree.expandedKeys)

    return getFlatTreeNodes()
      .filter((node) =>
        (node.__parentChain ?? []).every((parentKey) => expandedKeySet.has(String(parentKey)))
      )
      .filter(isSelectableLeaf)
  }

  const getOrderedSelectableKeys = (
    keys: string[],
    nodes: DictTypeItem[] = tree.data
  ): string[] => {
    const keySet = new Set(keys)

    return getFlatTreeNodes(nodes)
      .filter(isSelectableLeaf)
      .map(getNodeKey)
      .filter((key): key is string => Boolean(key && keySet.has(key)))
  }

  const replaceSelectedKeys = (keys: string[], anchorKey?: string): void => {
    tree.selectedKeys = Array.from(new Set(keys))
    tree.selectionAnchorKey = anchorKey ?? tree.selectedKeys[tree.selectedKeys.length - 1]
  }

  const handleShortcutSelection = (data: DictTypeItem, event: MouseEvent): void => {
    event.preventDefault()
    const key = getNodeKey(data)
    if (!key) return

    if (event.shiftKey && tree.selectionAnchorKey) {
      const visibleNodes = getVisibleSelectableNodes()
      const visibleKeys = visibleNodes
        .map(getNodeKey)
        .filter((item): item is string => Boolean(item))
      const anchorIndex = visibleKeys.indexOf(tree.selectionAnchorKey)
      const currentIndex = visibleKeys.indexOf(key)

      if (anchorIndex === -1 || currentIndex === -1) {
        replaceSelectedKeys([key], key)
        return
      }

      const [start, end] =
        anchorIndex <= currentIndex ? [anchorIndex, currentIndex] : [currentIndex, anchorIndex]
      const rangeKeys = visibleKeys.slice(start, end + 1)
      replaceSelectedKeys(
        event.ctrlKey || event.metaKey ? [...tree.selectedKeys, ...rangeKeys] : rangeKeys
      )
      return
    }

    if (event.ctrlKey || event.metaKey) {
      replaceSelectedKeys(
        tree.selectedKeys.includes(key)
          ? tree.selectedKeys.filter((selectedKey) => selectedKey !== key)
          : [...tree.selectedKeys, key],
        key
      )
      return
    }

    replaceSelectedKeys([key], key)
  }

  const getRootNodeKeys = (nodes: DictTypeItem[]): string[] => {
    return nodes.map(getNodeKey).filter((key): key is string => Boolean(key))
  }

  const getTreeNodeKeys = (nodes: DictTypeItem[]): Set<string> => {
    return new Set(
      treeUtils
        .treeToList(nodes)
        .map(getNodeKey)
        .filter((key): key is string => Boolean(key))
    )
  }

  const syncExpandedKeysAfterDataLoad = (): void => {
    const availableKeys = getTreeNodeKeys(tree.data)

    if (!tree.hasInitializedExpandedKeys) {
      tree.expandedKeys = getRootNodeKeys(tree.data).filter((key) => availableKeys.has(key))
      tree.hasInitializedExpandedKeys = true
      return
    }

    tree.expandedKeys = tree.expandedKeys.filter((key) => availableKeys.has(key))
  }

  const syncSelectedKeysAfterDataLoad = (): void => {
    const availableKeys = getTreeNodeKeys(tree.data)
    tree.selectedKeys = tree.selectedKeys.filter((key) => availableKeys.has(key))

    if (tree.selectionAnchorKey && !availableKeys.has(tree.selectionAnchorKey)) {
      tree.selectionAnchorKey = tree.selectedKeys[tree.selectedKeys.length - 1]
    }
  }

  const applyExpandedKeys = (): void => {
    const expandedKeySet = new Set(tree.expandedKeys)
    const treeNodes = treeUtils.treeToList(tree.data)

    treeNodes.forEach((node) => {
      const key = getNodeKey(node)
      if (!key) return

      const elTreeNode = treeRef.value?.getNode(key) as unknown as
        { expanded?: boolean } | undefined
      if (elTreeNode) {
        elTreeNode.expanded = expandedKeySet.has(key)
      }
    })
  }

  const handleNodeExpand = (data: DictTypeItem): void => {
    const key = getNodeKey(data)
    if (!key) return

    tree.expandedKeys = Array.from(new Set([...tree.expandedKeys, key]))
  }

  const handleNodeCollapse = (data: DictTypeItem): void => {
    const key = getNodeKey(data)
    if (!key) return

    const descendantKeys = treeUtils
      .getDescendants(tree.data, key, true)
      .map(getNodeKey)
      .filter((itemKey): itemKey is string => Boolean(itemKey))

    const collapsedKeySet = new Set(descendantKeys)
    tree.expandedKeys = tree.expandedKeys.filter((itemKey) => !collapsedKeySet.has(itemKey))
  }

  const allowDrop: AllowDrop = (draggingNode, dropNode, type) => {
    const draggingData = getTreeNodeData(draggingNode)
    const dropData = getTreeNodeData(dropNode)
    if (!draggingData || !dropData) return false

    const batchKeys = getBatchKeysForDragging(draggingData)
    const dropKey = getNodeKey(dropData)

    if (batchKeys.length > 1) {
      if (dropKey && batchKeys.includes(dropKey)) return false
      if (type === 'inner') return dropData.nodeType === 'directory'
      return type === 'prev' || type === 'next'
    }

    if (type !== 'inner') return true
    return dropData.nodeType === 'directory'
  }

  const getBatchKeysForDragging = (data: DictTypeItem): string[] => {
    const key = getNodeKey(data)
    if (!key || !isSelectableLeaf(data) || !tree.selectedKeys.includes(key)) {
      return key ? [key] : []
    }

    return getOrderedSelectableKeys(tree.selectedKeys)
  }

  const getDropSiblingContext = (
    nodes: DictTypeItem[],
    targetNodeKey: string
  ): DropSiblingContext | undefined => {
    const flatTarget = getFlatTreeNodes(nodes).find((node) => getNodeKey(node) === targetNodeKey)
    if (!flatTarget) return undefined

    const parentId = flatTarget.__parentChain?.length
      ? String(flatTarget.__parentChain[flatTarget.__parentChain.length - 1])
      : null
    const siblings = parentId ? (treeUtils.findNode(nodes, parentId)?.children ?? []) : nodes
    const targetIndex = siblings.findIndex((node) => getNodeKey(node) === targetNodeKey)

    if (targetIndex === -1) return undefined

    return {
      siblings,
      targetIndex,
      parentId
    }
  }

  const removeSelectedLeaves = (
    sourceTree: DictTypeItem[],
    selectedKeys: string[]
  ): { nextTree: DictTypeItem[]; movedNodes: DictTypeItem[] } => {
    const orderedKeys = getOrderedSelectableKeys(selectedKeys, sourceTree)
    let nextTree = cloneDeep(sourceTree)
    const movedNodes: DictTypeItem[] = []

    orderedKeys.forEach((key) => {
      const result = treeUtils.removeNode(nextTree, key)
      nextTree = result.tree

      if (result.removed) {
        movedNodes.push(result.removed)
      }
    })

    return {
      nextTree,
      movedNodes
    }
  }

  const moveSelectedLeaves = (
    sourceTree: DictTypeItem[],
    selectedKeys: string[],
    targetNodeKey: string,
    dropType: NodeDropType
  ): DictTypeItem[] => {
    if (selectedKeys.includes(targetNodeKey)) return sourceTree

    const { nextTree, movedNodes } = removeSelectedLeaves(sourceTree, selectedKeys)
    if (!movedNodes.length) return sourceTree

    if (dropType === 'inner') {
      return moveSelectedLeavesToDirectory(nextTree, movedNodes, targetNodeKey) ?? sourceTree
    }

    if (dropType !== 'before' && dropType !== 'after') return sourceTree

    const dropContext = getDropSiblingContext(nextTree, targetNodeKey)
    if (!dropContext) return sourceTree

    const insertIndex =
      dropType === 'before' ? dropContext.targetIndex : dropContext.targetIndex + 1
    movedNodes.forEach((node) => {
      Object.assign(node, {
        parentId: dropContext.parentId
      })
    })
    dropContext.siblings.splice(insertIndex, 0, ...movedNodes)

    return nextTree
  }

  const moveSelectedLeavesToDirectory = (
    nextTree: DictTypeItem[],
    movedNodes: DictTypeItem[],
    targetDirectoryId: string
  ): DictTypeItem[] | undefined => {
    const targetNode = treeUtils.findNode(nextTree, targetDirectoryId)
    if (!targetNode) return undefined

    targetNode.children = targetNode.children ?? []
    movedNodes.forEach((node) => {
      Object.assign(node, {
        parentId: targetDirectoryId
      })
      targetNode.children?.push(node)
    })

    return nextTree
  }

  const buildTreeOrderUpdates = (
    nodes: DictTypeItem[],
    parentId: string | null = null
  ): TreeOrderUpdate[] => {
    const updates: TreeOrderUpdate[] = []

    nodes.forEach((node, index) => {
      if (!node.id) return
      updates.push({
        id: node.id,
        parentId,
        sort: index + 1
      })
      updates.push(...buildTreeOrderUpdates(node.children ?? [], node.id))
    })

    return updates
  }

  const handleNodeDragStart = (draggingNode: unknown): void => {
    const draggingData = getTreeNodeData(draggingNode)
    if (!draggingData) return

    tree.dragSourceData = cloneDeep(tree.data)
    tree.draggingBatchKeys = getBatchKeysForDragging(draggingData)

    if (tree.draggingBatchKeys.length === 1) {
      if (isSelectableLeaf(draggingData)) {
        replaceSelectedKeys(tree.draggingBatchKeys, tree.draggingBatchKeys[0])
      } else {
        clearSelectedKeys()
      }
    }
  }

  const handleNodeDragEnd = (): void => {
    window.setTimeout(() => {
      if (!tree.loading) {
        tree.draggingBatchKeys = []
        tree.dragSourceData = []
      }
    }, 150)
  }

  const handleNodeDrop = async (
    _draggingNode: unknown,
    dropNode: unknown,
    dropType: NodeDropType
  ): Promise<void> => {
    const currentKey = treeRef.value?.getCurrentKey()
    const batchKeys = tree.draggingBatchKeys
    const dragSourceData = tree.dragSourceData
    const dropData = getTreeNodeData(dropNode)
    const dropNodeKey = getNodeKey(dropData)

    try {
      tree.loading = true
      await nextTick()

      if (batchKeys.length > 1 && dropNodeKey) {
        tree.data = moveSelectedLeaves(dragSourceData, batchKeys, dropNodeKey, dropType)
        if (dropType === 'inner') {
          tree.expandedKeys = Array.from(new Set([...tree.expandedKeys, dropNodeKey]))
        }
        replaceSelectedKeys(batchKeys, batchKeys[0])
        await nextTick()
        applyExpandedKeys()
      }

      const updates = buildTreeOrderUpdates(tree.data)
      await saveDictTypeTreeOrder(updates)
      ElMessage.success(
        batchKeys.length > 1 ? `已移动 ${batchKeys.length} 个字典类型` : '目录位置和排序已保存'
      )
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '目录拖拽保存失败')
    } finally {
      tree.draggingBatchKeys = []
      tree.dragSourceData = []
      await handleGetDictTypeList()
      if (currentKey) {
        await nextTick()
        treeRef.value?.setCurrentKey(currentKey)
      }
    }
  }

  const handleAdd = (parent?: DictTypeItem): void => {
    void dictTypeDialogRef.value?.handleOpen(undefined, {
      parentId: parent?.id,
      treeData: tree.data
    })
  }

  const handleEdit = (data: DictTypeItem): void => {
    void dictTypeDialogRef.value?.handleOpen(data, {
      treeData: tree.data
    })
  }

  const handleDelete = async (row: DictTypeItem): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(
        row.nodeType === 'directory'
          ? '确定删除该目录吗？目录下存在子节点时不能删除。'
          : '确定删除该字典类型吗？存在字典项时不能删除。',
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteDictType(row)
      await handleGetDictTypeList()
    } catch {
      // 用户取消或数据库拒绝删除时保留当前树。
    }
  }

  const handleSuccess = async (): Promise<void> => {
    await handleGetDictTypeList()
  }

  const handleGetDictTypeList = async (): Promise<void> => {
    const currentKey = treeRef.value?.getCurrentKey()
    try {
      tree.loading = true
      const { data = [] } = await fetchGetDictTypeList()
      tree.data = treeUtils.listToTree(
        data as DictTypeItem[],
        (a, b) => Number(a.sort || 0) - Number(b.sort || 0)
      )
      syncExpandedKeysAfterDataLoad()
      syncSelectedKeysAfterDataLoad()
      await nextTick()
      applyExpandedKeys()
      if (currentKey) {
        treeRef.value?.setCurrentKey(currentKey)
      }
      treeRef.value?.filter(tree.keyword)
    } finally {
      tree.loading = false
    }
  }

  onMounted(() => {
    void handleGetDictTypeList()
  })

  defineExpose({
    getCurrentDictType
  })
</script>

<style scoped lang="scss">
  .tree-card {
    :deep(.el-card__header) {
      padding: 12px;
      border-bottom: 0;
    }

    :deep(.el-card__body) {
      flex: 1;
      min-height: 0;
      padding: 0 12px 12px;
    }

    :deep(.el-tree-node__content) {
      height: 38px;
      margin-top: 2px;
      border-radius: var(--el-border-radius-base);
    }

    :deep(.el-tree__drop-indicator) {
      z-index: 2;
      height: 2px;
      background-color: var(--el-color-primary);
      box-shadow: 0 0 0 1px var(--el-color-primary-light-7);
    }

    :deep(.el-tree-node.is-multi-selected > .el-tree-node__content) {
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
    }

    :deep(.el-tree-node.is-drop-inner > .el-tree-node__content) {
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-8);
      box-shadow: inset 0 0 0 2px var(--el-color-primary);
    }

    :deep(.el-tree-node.is-drop-inner > .el-tree-node__content .dict-type-tree__node) {
      color: var(--el-color-primary);
      background: transparent;
    }
  }

  .dict-type-tree {
    &__header {
      display: flex;
      gap: 8px;
    }

    &__node {
      display: flex;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      min-width: 0;
      padding-right: 6px;
      border-radius: var(--el-border-radius-base);

      &.is-multi-selected {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &:hover {
        .dict-type-tree__actions {
          display: flex;
        }
      }
    }

    &__label {
      display: flex;
      align-items: center;
      min-width: 0;
      gap: 6px;

      > span {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__node-icon {
      width: 1em;
      height: 1em;
      flex: 0 0 1em;
      font-size: 16px;
    }

    &__actions {
      display: none;
      flex: none;
      align-items: center;

      .el-button + .el-button {
        margin-left: 4px;
      }
    }
  }
</style>
