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
        node-key="id"
        default-expand-all
        highlight-current
        @node-click="handleNodeClick"
        @node-drop="handleNodeDrop"
      >
        <template #default="{ data }">
          <div class="dict-type-tree__node">
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
  import type { ElTree } from 'element-plus'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import TreeUtils from '@/utils/tree'
  import { deleteDictType, fetchGetDictTypeList, saveDictTypeTreeOrder } from '@/api/data-center'
  import DictTypeDialog from './dict-type-dialog.vue'

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
    props: {
      children: string
      label: string
    }
  }

  interface TreeOrderUpdate {
    id: string
    parentId: string | null
    sort: number
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
    props: {
      children: 'children',
      label: 'name'
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

  const handleNodeClick = (data: DictTypeItem): void => {
    emit('tree-node-click', data)
  }

  const allowDrop: AllowDrop = (_draggingNode, dropNode, type) => {
    if (type !== 'inner') return true
    return (dropNode.data as DictTypeItem).nodeType === 'directory'
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

  const handleNodeDrop = async (): Promise<void> => {
    const currentKey = treeRef.value?.getCurrentKey()

    try {
      tree.loading = true
      await nextTick()
      const updates = buildTreeOrderUpdates(tree.data)
      await saveDictTypeTreeOrder(updates)
      ElMessage.success('目录位置和排序已保存')
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '目录拖拽保存失败')
    } finally {
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
      await ElMessageBox.confirm(
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
      ) as DictTypeItem[]
      await nextTick()
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
