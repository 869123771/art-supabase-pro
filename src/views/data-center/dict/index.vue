<!-- 左树右表示例页面 -->
<template>
  <div class="art-full-height">
    <div class="box-border flex gap-4 h-full max-md:block max-md:gap-0 max-md:h-auto">
      <div class="flex-shrink-0 w-58 h-full max-md:w-full max-md:h-auto max-md:mb-5">
        <TypeTree ref="typeTreeRef" @tree-node-click="getData" />
      </div>

      <div class="flex flex-col flex-grow min-w-0">
        <DictSearch v-model="form" @search="getData" />

        <ElCard class="flex flex-col flex-1 min-h-0 art-table-card" shadow="never">
          <ArtTableHeader v-model:columns="columnChecks" :loading="loading" @refresh="refreshData">
            <template #left>
              <ElSpace wrap>
                <ElButton @click="handleAdd" v-ripple type="primary" plain>新增 </ElButton>
                <ElButton
                  :disabled="isEmpty(tableSelections)"
                  @click="handleDeleteBatch"
                  v-ripple
                  type="danger"
                  plain
                  >删除
                </ElButton>
              </ElSpace>
            </template>
          </ArtTableHeader>

          <ArtTable
            table-layout="fixed"
            ref="artTableRef"
            rowKey="id"
            :loading="loading"
            :data="data as Record<string, any>[]"
            :columns="columns"
            :pagination="pagination"
            @pagination:size-change="handleSizeChange"
            @pagination:current-change="handleCurrentChange"
          >
          </ArtTable>
        </ElCard>
      </div>
    </div>
    <DictDialog ref="dictDialogRef" @success="getData"></DictDialog>
  </div>
</template>

<script setup lang="tsx">
  import { useTable } from '@/hooks/core/useTable'
  import DictSearch from './modules/dict-search.vue'
  import TypeTree from './modules/type-tree.vue'
  import DictDialog from './modules/dict-dialog.vue'
  import { fetchGetDictListByTypeId, deleteDict, deleteDictBatch } from '@/api/data-center'
  import { isEmpty } from 'lodash-es'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ElMessageBox, ElTag } from 'element-plus'
  import { useUserStore } from '@/store/modules/user'
  import type { TagProps } from 'element-plus'
  import { ColumnOption } from '@/types'
  const { getDictLabelByValue } = useUserStore()

  defineOptions({ name: 'dict' })

  type DictListItem = Api.DataCenter.DictListItem

  const artTableRef = ref()
  const typeTreeRef = ref()
  const dictDialogRef = ref()

  // 表单搜索初始值
  const form = ref<Partial<DictListItem>>({
    label: '',
    code: '',
    i18nScope: '',
    status: ''
  })

  const {
    data,
    columns,
    columnChecks,
    loading,
    pagination,
    getData,
    refreshData,
    handleSizeChange,
    handleCurrentChange
  } = useTable({
    core: {
      apiFn: () => handleGetDictListByTypeId(),
      immediate: false,
      apiParams: {
        current: 1,
        size: 20
      },
      columnsFactory: (): ColumnOption[] => [
        {
          type: 'selection'
        },
        {
          prop: 'label',
          label: '字典名称'
        },
        {
          prop: 'code',
          label: '字典编码'
        },
        {
          prop: 'value',
          label: '字典值'
        },
        {
          prop: 'i18n',
          label: '国际化'
        },
        {
          prop: 'i18nScope',
          label: '国际化范围',
          formatter: (row: DictListItem) => {
            const colorMap: Record<string, TagProps['type']> = {
              '1': 'primary',
              '2': 'danger'
            }
            const tagType = colorMap[String(row.i18nScope)] ?? 'info'
            return (
              <ElTag type={tagType}>
                <span>{getDictLabelByValue('i18nScope', row?.i18nScope || '')}</span>
              </ElTag>
            )
          }
        },
        {
          prop: 'status',
          label: '状态',
          formatter: (row: DictListItem) => {
            const colorMap: Record<string, TagProps['type']> = {
              '1': 'success',
              '2': 'danger'
            }
            const tagType = colorMap[String(row.status)] ?? 'info'
            return (
              <ElTag type={tagType}>
                <span>{getDictLabelByValue('status', row.status)}</span>
              </ElTag>
            )
          }
        },
        {
          prop: 'color',
          label: '文字颜色'
        },
        {
          prop: 'sort',
          label: '排序'
        },
        {
          prop: 'operation',
          label: '操作',
          width: 120,
          fixed: 'right', // 固定列
          formatter: (row: DictListItem) =>
            h('div', [
              h(ArtButtonTable, {
                type: 'edit',
                onClick: () => handleEdit(row)
              }),
              h(ArtButtonTable, {
                type: 'delete',
                onClick: () => handleDelete(row)
              })
            ])
        }
      ]
    }
  })

  const tableSelections = computed(() => {
    const { elTableRef = null } = artTableRef.value ?? {}
    return elTableRef?.getSelectionRows() ?? []
  })

  const handleAdd = () => {
    const currentDictType = typeTreeRef.value.getCurrentDictType
    if (isEmpty(currentDictType)) {
      return ElMessage.warning('请选择字典类型')
    }
    dictDialogRef.value.handleOpen({
      typeId: currentDictType.id,
      dictTypeName: currentDictType.name
    })
  }
  const handleEdit = (row: DictListItem) => {
    const currentDictType = typeTreeRef.value.getCurrentDictType
    dictDialogRef.value.handleOpen({
      ...row,
      dictTypeName: currentDictType.name
    })
  }

  const handleDeleteBatch = () => {
    const ids: string[] = tableSelections.value?.map((item: DictListItem) => item.id)
    ElMessageBox.confirm(`确定要删除选中字典项吗？`, '删除字典项', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'error'
    }).then(async () => {
      await deleteDictBatch(ids)
      await getData()
    })
  }
  const handleDelete = (row: DictListItem) => {
    ElMessageBox.confirm(`确定要删除该字典项吗？`, '删除字典项', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'error'
    }).then(async () => {
      await deleteDict(row)
      await getData()
    })
  }

  const handleGetDictListByTypeId = async () => {
    const currentDictType = typeTreeRef.value.getCurrentDictType
    if (isEmpty(currentDictType)) {
      return false
    }
    const params: Partial<DictListItem> = {
      typeId: currentDictType.id,
      ...form.value
    }
    return await fetchGetDictListByTypeId(params as DictListItem)
  }
</script>

<style scoped></style>
