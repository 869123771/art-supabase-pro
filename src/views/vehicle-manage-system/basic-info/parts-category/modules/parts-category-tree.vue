<template>
  <ElCard class="parts-category-tree-card art-card-xs flex flex-col h-full mt-0" shadow="never">
    <template #header>
      <div class="tree-toolbar">
        <ElInput v-model="keyword" placeholder="请输入类别名称" clearable @input="debounceFetch" />
        <ElButton type="primary" @click="handleAddRoot">
          <ArtSvgIcon icon="ri:add-fill" />
        </ElButton>
      </div>
    </template>

    <ElScrollbar v-loading="loading">
      <ElTree
        ref="treeRef"
        :data="treeData"
        :props="treeProps"
        node-key="id"
        default-expand-all
        highlight-current
        empty-text="暂无类别"
        @node-click="handleNodeClick"
      >
        <template #default="{ data }">
          <div class="tree-node">
            <div class="label">
              <span class="name">{{ data.categoryName }}</span>
              <ElTag size="small" type="info">{{ data.categoryCode }}</ElTag>
            </div>
            <div class="actions" :class="{ 'is-current': currentId === data.id }">
              <ElButton size="small" circle type="primary" @click.stop="handleAddChild(data)">
                <ArtSvgIcon icon="ri:add-line" />
              </ElButton>
              <ElButton size="small" circle type="success" @click.stop="handleEdit(data)">
                <ArtSvgIcon icon="ri:pencil-line" />
              </ElButton>
              <ElPopconfirm
                title="确定删除该类别及其子类别吗？"
                confirm-button-text="删除"
                cancel-button-text="取消"
                @confirm="handleDelete(data)"
              >
                <template #reference>
                  <ElButton size="small" circle type="danger" @click.stop>
                    <ArtSvgIcon icon="ri:delete-bin-5-line" />
                  </ElButton>
                </template>
              </ElPopconfirm>
            </div>
          </div>
        </template>
      </ElTree>
    </ElScrollbar>
  </ElCard>

  <PartsCategoryDialog ref="dialogRef" @success="handleDialogSuccess" />
</template>

<script setup lang="ts">
  import { debounce } from 'lodash-es'
  import type { ElTree } from 'element-plus'
  import { deletePartsCategory, fetchPartsCategoryTree } from '@/api/vehicle-manage-system'
  import PartsCategoryDialog from './parts-category-dialog.vue'

  type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory

  interface Emits {
    (e: 'tree-node-click', node?: PartsCategory): void
    (e: 'data-change'): void
  }

  interface DialogExpose {
    handleOpen: (row?: PartsCategory, parent?: PartsCategory) => Promise<void>
  }

  const emit = defineEmits<Emits>()

  const treeRef = ref<InstanceType<typeof ElTree>>()
  const dialogRef = ref<DialogExpose>()
  const keyword = ref('')
  const loading = ref(false)
  const treeData = ref<PartsCategory[]>([])
  const currentId = ref<string>()

  const treeProps = {
    children: 'children',
    label: 'categoryName'
  }

  const buildTree = (records: PartsCategory[]): PartsCategory[] => {
    const nodeMap = new Map<string, PartsCategory>()
    const roots: PartsCategory[] = []

    records.forEach((item) => {
      if (!item.id) return
      nodeMap.set(item.id, { ...item, children: [] })
    })

    nodeMap.forEach((node) => {
      if (node.parentId && nodeMap.has(node.parentId)) {
        nodeMap.get(node.parentId)?.children?.push(node)
      } else {
        roots.push(node)
      }
    })

    return roots
  }

  const getCurrentCategory = computed<PartsCategory | undefined>(() => {
    return treeRef.value?.getCurrentNode() as PartsCategory | undefined
  })

  const handleNodeClick = (node: PartsCategory): void => {
    currentId.value = node.id
    emit('tree-node-click', node)
  }

  const refreshTree = async (): Promise<void> => {
    try {
      loading.value = true
      const { data } = await fetchPartsCategoryTree({ categoryName: keyword.value })
      treeData.value = buildTree(data ?? [])
    } finally {
      loading.value = false
    }
  }

  const debounceFetch = debounce(() => {
    void refreshTree()
  }, 400)

  const handleAddRoot = (): void => {
    void dialogRef.value?.handleOpen()
  }

  const handleAddChild = (parent: PartsCategory): void => {
    void dialogRef.value?.handleOpen(undefined, parent)
  }

  const handleEdit = (row: PartsCategory): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleDelete = async (row: PartsCategory): Promise<void> => {
    if (!row.id) return
    await deletePartsCategory(row.id)
    if (currentId.value === row.id) {
      currentId.value = undefined
      emit('tree-node-click', undefined)
    }
    await refreshTree()
    emit('data-change')
  }

  const handleDialogSuccess = async (): Promise<void> => {
    await refreshTree()
    emit('data-change')
  }

  onMounted(() => {
    void refreshTree()
  })

  defineExpose({
    getCurrentCategory,
    refreshTree
  })
</script>

<style scoped lang="scss">
  .parts-category-tree-card {
    :deep(.el-card__header) {
      padding: 12px;
      border-bottom: 0;
    }

    :deep(.el-card__body) {
      flex: 1;
      min-height: 0;
      padding: 0 12px 12px;
    }

    .tree-toolbar {
      display: flex;
      gap: 12px;
    }

    .el-tree {
      height: 100%;

      :deep(.el-tree-node__content) {
        height: 38px;
        margin-top: 2px;
        border-radius: var(--art-control-radius);
      }
    }

    .tree-node {
      position: relative;
      display: flex;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      min-width: 0;
      height: 100%;
      padding-right: 8px;

      .label {
        display: flex;
        column-gap: 8px;
        align-items: center;
        min-width: 0;

        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }

      .actions {
        position: absolute;
        right: 8px;
        display: none;
      }

      &:hover .actions,
      .actions.is-current {
        display: inline-flex;
      }
    }
  }
</style>
