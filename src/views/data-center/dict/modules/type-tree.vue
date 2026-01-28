<template>
  <ElCard class="tree-card art-card-xs flex flex-col h-full mt-0" shadow="never">
    <template #header>
      <div class="flex gap-3">
        <ElInput v-model="tree.name" placeholder="输入名称" @input="debounceFetch" clearable>
        </ElInput>
        <ElButton type="primary" @click="handleAdd">
          <ArtSvgIcon icon="ri:add-fill" />
        </ElButton>
      </div>
    </template>

    <ElScrollbar v-loading="tree.loading">
      <ElTree
        ref="treeRef"
        :data="tree.data"
        :props="tree.props"
        node-key="id"
        default-expand-all
        highlight-current
        @node-click="handleNodeClick"
      >
        <template #default="{ data }">
          <div class="tree-node">
            <div class="label">
              {{ data.name ?? 'unknown' }}
            </div>
            <div class="do" :class="{ '!inline-block': treeRef?.getCurrentKey?.() === data.id }">
              <ElTag type="primary" class="mr-2">
                {{ data.code }}
              </ElTag>
              <ElButton size="small" circle type="success" @click.stop="handleEdit(data)">
                <ArtSvgIcon icon="ri:pencil-line" />
              </ElButton>
              <ElPopconfirm
                title="是否删除数据？"
                confirm-button-text="确认"
                cancel-button-text="取消"
                @confirm.stop="handleDelete(data)"
              >
                <template #reference>
                  <ElButton size="small" circle type="danger">
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
  <DictTypeDialog ref="dictTypeDialogRef" @success="handleSuccess" />
</template>

<script setup lang="ts">
  import DictTypeDialog from './dict-type-dialog.vue'
  import { deleteDictType, fetchGetDictTypeList } from '@/api/data-center'
  import { debounce } from 'lodash-es'

  const emits = defineEmits(['tree-node-click'])
  type DictListItem = Api.DataCenter.DictListItem

  const debounceFetch = debounce(() => handleNameChange(), 500)
  const dictTypeDialogRef = ref()
  const treeRef = ref()
  const tree = ref({
    name: '',
    data: [],
    loading: false,
    props: {
      children: 'children',
      label: 'name'
    }
  })

  const getCurrentDictType = computed(() => treeRef.value?.getCurrentNode() ?? {})

  const handleNodeClick = (data: any) => {
    emits('tree-node-click', data)
  }

  const handleDelete = async (row: DictListItem) => {
    await deleteDictType({ id: row?.id } as DictListItem)
    await handleGetDictTypeList()
  }
  const handleEdit = async (data: DictListItem) => {
    dictTypeDialogRef.value.handleOpen(data)
  }
  const handleAdd = async () => {
    dictTypeDialogRef.value.handleOpen()
  }

  const handleSuccess = () => {
    handleGetDictTypeList()
  }

  const handleNameChange = () => {
    handleGetDictTypeList()
  }
  const handleGetDictTypeList = async () => {
    try {
      tree.value.loading = true
      const { name } = unref(tree)
      const params = {
        name
      }
      const { data } = await fetchGetDictTypeList(params as DictListItem)
      tree.value = {
        ...unref(tree),
        data
      }
    } finally {
      tree.value.loading = false
    }
  }
  onMounted(() => {
    handleGetDictTypeList()
  })

  defineExpose({
    getCurrentDictType
  })
</script>

<style scoped lang="scss">
  .el-card {
    :deep(.el-card__header) {
      border-bottom: 0;
      padding: 12px;
    }
    :deep(.el-card__body) {
      flex: 1;
      padding: 0 12px;
      min-height: 0;
    }
    .el-tree {
      height: 100%;
      :deep(.el-tree-node__content) {
        margin-top: 0.125rem;
        height: 35px;
        border-radius: 0.25rem;
      }

      .tree-node {
        position: relative;
        height: 100%;
        width: 100%;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding-right: 0.5rem;

        .label {
          height: 100%;
          display: flex;
          align-items: center;
          column-gap: 0.375rem;
        }
        .do {
          position: absolute;
          right: 0.75rem;
          display: none;
        }
      }

      .tree-node:hover .do {
        display: inline-block;
      }
    }
  }
</style>
