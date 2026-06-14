<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 8, labelWidth: 90 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <PartsDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage, ElMessageBox, ElTag } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import TreeUtils from '@/utils/tree'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteParts,
    deletePartsBatch,
    exportPartsList,
    fetchPartsCategoryTree,
    fetchPartsList,
    importParts
  } from '@/api/vehicle-mgt-sys'
  import PartsDialog from './modules/parts-dialog.vue'

  defineOptions({ name: 'VehicleParts' })

  type Parts = Api.VehicleMgtSys.BasicInfo.Parts
  type SearchParams = Api.VehicleMgtSys.BasicInfo.PartsSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory

  interface DialogExpose {
    handleOpen: (row?: Parts) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore) as Record<string, any>
  const categoryTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const searchQuery = ref<SearchParams>({
    partName: '',
    partCode: '',
    categoryId: undefined,
    brand: '',
    status: undefined
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '零部件名称',
      key: 'partName',
      type: 'input'
    },
    {
      label: '零部件编码',
      key: 'partCode',
      type: 'input'
    },
    {
      label: '零部件类别',
      key: 'categoryId',
      type: 'treeSelect',
      api: fetchPartsCategoryTree,
      afterFetch: (result: unknown) => {
        const records = (result as { data?: PartsCategory[] })?.data ?? []
        return categoryTreeUtils.listToTree(records) as PartsCategory[]
      },
      labelField: 'categoryName',
      valueField: 'id',
      childrenField: 'children',
      props: {
        checkStrictly: true,
        renderAfterExpand: false
      }
    },
    {
      label: '品牌',
      key: 'brand',
      type: 'input'
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.status ?? []
      }
    }
  ])

  const partsExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'partName', title: '零部件名称', required: true },
    { key: 'partCode', title: '零部件编码', required: true },
    { key: 'categoryId', title: '类别ID' },
    { key: 'categoryName', title: '类别名称' },
    { key: 'brand', title: '品牌' },
    { key: 'model', title: '型号' },
    { key: 'unit', title: '单位' },
    { key: 'isConsumable', title: '是否易损/耗件' },
    { key: 'warrantyMileage', title: '质保里程' },
    { key: 'warrantyDuration', title: '质保时长（月）' },
    { key: 'serviceLife', title: '使用年限（年）' },
    { key: 'serviceMileage', title: '使用里程' },
    { key: 'manufacturer', title: '生产厂商' },
    { key: 'supplierId', title: '供应厂商ID' },
    { key: 'supplierName', title: '供应厂商' },
    { key: 'supplierContact', title: '供应商联系人' },
    { key: 'status', title: '状态' },
    { key: 'remark', title: '备注' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      onClick: () => openDialog()
    },
    {
      type: 'import',
      importColumns: partsExcelColumns,
      importApi: async (rows) => {
        await importParts(rows as Parts[])
      },
      onImportError: handleImportError
    },
    {
      type: 'export',
      exportFilename: '零部件',
      exportSheetName: '零部件',
      exportColumns: partsExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportPartsList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
      }
    },
    {
      type: 'delete',
      content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
        `确定删除选中的 ${selectedCount} 个零部件吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const ids = selectedRows
          .map((row) => row.id)
          .filter((id): id is string => typeof id === 'string')
        await deletePartsBatch(ids)
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })

    return fetchPartsList({
      ...params,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<Parts>[] => [
    {
      type: 'selection',
      width: 50,
      fixed: 'left',
      reserveSelection: true
    },
    {
      type: 'globalIndex',
      label: '序号',
      width: 80
    },
    {
      prop: 'partName',
      label: '零部件名称',
      minWidth: 180
    },
    {
      prop: 'partCode',
      label: '零部件编码',
      minWidth: 160
    },
    {
      prop: 'categoryName',
      label: '类别',
      minWidth: 140,
      formatter: (row) => row.categoryName || '-'
    },
    {
      prop: 'brandModel',
      label: '品牌 / 型号',
      minWidth: 170,
      formatter: (row) => [row.brand, row.model].filter(Boolean).join(' / ') || '-'
    },
    {
      prop: 'unit',
      label: '单位',
      width: 90
    },
    {
      prop: 'supplierName',
      label: '供应厂商',
      minWidth: 160,
      formatter: (row) => row.supplierName || '-'
    },
    {
      prop: 'isConsumable',
      label: '易损/耗件',
      width: 110,
      formatter: (row) => (
        <ElTag type={row.isConsumable ? 'warning' : 'info'}>{row.isConsumable ? '是' : '否'}</ElTag>
      )
    },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      formatter: (row) => {
        const status = row.status || '1'
        const tag = userStore.getDictTagByValue('status', status)

        return <ElTag type={tag.type}>{tag.label}</ElTag>
      }
    },
    {
      prop: 'remark',
      label: '备注',
      minWidth: 180
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
        </div>
      )
    }
  ]

  const openDialog = (row?: Parts): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Parts): Promise<void> => {
    if (!row.id) return

    try {
      await ElMessageBox.confirm(
        `确定删除零部件“${row.partName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteParts(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需额外提示。
    }
  }

  const handleImportError = (): void => {
    ElMessage.error('导入文件解析失败')
  }
</script>
