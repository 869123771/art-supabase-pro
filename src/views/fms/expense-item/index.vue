<template>
  <div class="business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="EXPENSE TAXONOMY"
      title="费用项目"
      description="用树形项目统一承运、在途和其他运单费用口径，业务表单只能选择可记账的末级项目。"
      icon="ri:node-tree"
      :tags="[
        { label: '树形结构', type: 'primary' },
        { label: '统一费用口径', type: 'success' }
      ]"
    />

    <ArtTableQuery
      ref="tableRef"
      v-model="search"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 8, labelWidth: 86, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        defaultExpandAll: true,
        treeProps: { children: 'children' },
        tableLayout: 'fixed',
        emptyText: '暂无费用项目',
        emptyDescription: '可先新增一级分组，再为分组添加可记账的末级费用项目。'
      }"
      focusable
    />

    <ExpenseItemDialog ref="dialogRef" @success="handleSaved" />
  </div>
</template>

<script setup lang="tsx">
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import type { ColumnOption } from '@/types'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import { deleteExpenseItem, fetchExpenseItemTree } from '@/api/fms'
  import { fetchGetTenantList } from '@/api/system-manage'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import ExpenseItemDialog from './modules/expense-item-dialog.vue'

  defineOptions({ name: 'FinanceExpenseItem' })

  type ExpenseItem = Api.Fms.ExpenseItem
  type SearchParams = Api.Fms.ExpenseItemSearchParams

  interface DialogExpose {
    handleOpen: (row?: ExpenseItem, parent?: ExpenseItem) => Promise<void>
  }

  const { confirmAction } = useArtFeedback()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const search = ref<SearchParams>({ keyword: '', tenantId: undefined, isEnabled: undefined })
  const tenantOptions = ref<Array<{ label: string; value: string }>>([])

  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const searchItems = computed<SearchFormItem[]>(() => [
    ...(isPlatformSuper.value
      ? [
          {
            label: '所属租户',
            key: 'tenantId',
            type: 'select' as const,
            props: {
              clearable: true,
              filterable: true,
              options: tenantOptions.value,
              placeholder: '全部租户'
            }
          }
        ]
      : []),
    {
      label: '启用状态',
      key: 'isEnabled',
      type: 'select',
      props: { options: commonBooleanOptions.value, clearable: true }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '项目编码、名称或备注' }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', label: '新增一级项目', onClick: () => openDialog() }
  ])

  const fetchTableData = async (params: SearchParams) => {
    const result = await fetchExpenseItemTree(params)
    return { ...result, total: result.data?.length ?? 0 }
  }

  const columnsFactory = (): ColumnOption<ExpenseItem>[] => [
    { prop: 'itemName', label: '费用项目', minWidth: 220, fixed: 'left' },
    ...(isPlatformSuper.value
      ? [
          {
            prop: 'tenant',
            label: '所属租户',
            minWidth: 190,
            formatter: (row: ExpenseItem) => (
              <div class="expense-item-tenant">
                <strong title={row.tenant?.tenantName || '未识别租户'}>
                  {row.tenant?.tenantName || '未识别租户'}
                </strong>
                <small title={row.tenant?.tenantCode || row.tenantId || '--'} translate="no">
                  {row.tenant?.tenantCode || row.tenantId || '--'}
                </small>
              </div>
            )
          } satisfies ColumnOption<ExpenseItem>
        ]
      : []),
    { prop: 'itemCode', label: '项目编码', width: 170 },
    {
      prop: 'businessCategory',
      label: '业务分类',
      width: 150,
      dict: { code: 'tmsWaybillCostType', display: 'tag' },
      formatter: (row) => (row.isSelectable ? row.businessCategory || '--' : '分组')
    },
    {
      prop: 'isSelectable',
      label: '可记账',
      width: 95,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.isSelectable) }
    },
    {
      prop: 'reimbursementAllowed',
      label: '可报销',
      width: 95,
      dict: {
        code: 'commonBoolean',
        display: 'tag',
        value: (row) => String(row.reimbursementAllowed)
      }
    },
    {
      prop: 'isEnabled',
      label: '启用状态',
      width: 105,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.isEnabled) }
    },
    { prop: 'sort', label: '排序', width: 80, align: 'center' },
    { prop: 'remark', label: '备注', minWidth: 180, showOverflowTooltip: true },
    {
      prop: 'operation',
      label: '操作',
      width: 150,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonMore
            list={moreActions}
            onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
          />
        </div>
      )
    }
  ]

  const moreActions: ButtonMoreItem[] = [
    { key: 'addChild', label: '新增下级', icon: 'ri:add-line' },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-line',
      color: 'var(--el-color-danger)'
    }
  ]

  function openDialog(row?: ExpenseItem, parent?: ExpenseItem): void {
    void dialogRef.value?.handleOpen(row, parent)
  }

  function handleMoreAction(item: ButtonMoreItem, row: ExpenseItem): void {
    if (item.key === 'addChild') openDialog(undefined, row)
    if (item.key === 'delete') void handleDelete(row)
  }

  async function handleDelete(row: ExpenseItem): Promise<void> {
    if (!row.id) return
    const tenantContext = isPlatformSuper.value ? `所属租户：${resolveTenantLabel(row)}。` : ''
    try {
      await confirmAction(
        `确定删除费用项目“${row.itemName}”吗？${tenantContext}删除后不可撤销；存在下级项目或费用引用时系统会阻止删除。`,
        '删除费用项目',
        {
          type: 'warning',
          confirmButtonText: '确认删除',
          cancelButtonText: '取消',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteExpenseItem(row.id)
      await tableRef.value?.refreshRemove()
    } catch {
      // 用户取消或业务约束阻止删除时，不重复提示。
    }
  }

  function handleSaved(type: 'add' | 'edit'): void {
    void (type === 'add' ? tableRef.value?.refreshCreate() : tableRef.value?.refreshUpdate())
  }

  function resolveTenantLabel(row: ExpenseItem): string {
    const tenantName = row.tenant?.tenantName?.trim()
    const tenantCode = row.tenant?.tenantCode?.trim()
    if (tenantName && tenantCode) return `${tenantName}（${tenantCode}）`
    return tenantName || tenantCode || row.tenantId || '未识别租户'
  }

  async function loadTenantOptions(): Promise<void> {
    if (!isPlatformSuper.value) return
    const { data } = await fetchGetTenantList({ from: 0, to: 999 })
    tenantOptions.value = (data ?? [])
      .filter((tenant) => tenant.id)
      .map((tenant) => ({
        label: `${tenant.tenantName}（${tenant.tenantCode}）`,
        value: String(tenant.id)
      }))
  }

  onMounted(() => void loadTenantOptions())
</script>

<style scoped lang="scss">
  :deep(.expense-item-tenant) {
    min-width: 0;

    strong,
    small {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      margin-top: 3px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }
</style>
