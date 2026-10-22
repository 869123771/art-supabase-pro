<template>
  <ArtPermissionGuard :permission="permissions.View" :resource-name="title">
    <div class="business-workspace-page art-full-height min-w-0">
      <BusinessWorkspaceHeader
        :title="title"
        :description="
          kind === 'purpose'
            ? '维护付款业务与应收、应付核销属性；已引用用途的关键属性不可改变。'
            : '维护现金、票据和汇兑等结算类别，控制付款账户与手续费适用范围。'
        "
        icon="ri:bank-card-line"
        density="compact"
        ><template #actions><BusinessTableWorkspaceActions :table="tableRef" /></template
      ></BusinessWorkspaceHeader>
      <ArtTableQuery
        ref="tableRef"
        :api-fn="fetchRows"
        :columns-factory="columnsFactory"
        :search-items="[
          {
            key: 'keyword',
            label: '查询条件',
            type: 'input',
            props: { placeholder: '编码、名称', clearable: true }
          }
        ]"
        :header-actions="[
          { type: 'add', permission: permissions.Add, onClick: () => editorRef?.open() }
        ]"
        header-actions-placement="workspace"
        focusable
      />
      <ReferenceEditor ref="editorRef" :kind="kind" @success="tableRef?.refreshData()" />
    </div>
  </ArtPermissionGuard>
</template>
<script setup lang="tsx">
  import { ElTag } from 'element-plus'
  import { useTenantScopeStore } from '@/store/modules/tenant-scope'
  import { formatTenantLabel } from '@/utils/tenant-display'
  import {
    fetchPayableReferences,
    type PayableReference,
    type PayableReferenceKind
  } from '@/api/payable-reference'
  import ArtTableQuery from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessTableRowActions from '@/components/business/business-table-row-actions/index.vue'
  import ReferenceEditor from './modules/reference-editor.vue'
  import type { ColumnOption } from '@/types'
  const props = defineProps<{
    kind: Exclude<PayableReferenceKind, 'scheme'>
    permissions: { View: string; Add: string; Edit: string }
  }>()
  const tenantScope = useTenantScopeStore()
  const title = computed(() => (props.kind === 'purpose' ? '付款用途' : '结算方式'))
  const tableRef = ref<InstanceType<typeof ArtTableQuery>>()
  const editorRef = ref<InstanceType<typeof ReferenceEditor>>()
  const labels: Record<string, string> = {
    purchase: '采购付款',
    advance: '预付款',
    other: '其他付款',
    sales_refund: '销售退款',
    other_refund: '其他退款',
    cash: '现金',
    cheque: '支票',
    remittance: '汇兑',
    bill: '非支票票据',
    virtual: '虚拟结算'
  }
  async function fetchRows(params: { keyword?: string; current?: number; size?: number }) {
    const rows = (await fetchPayableReferences(props.kind)).filter(
      (row) => !params.keyword || `${row.code} ${row.name}`.includes(params.keyword)
    )
    const size = params.size || 20
    const start = ((params.current || 1) - 1) * size
    return { data: rows.slice(start, start + size), total: rows.length }
  }
  const columnsFactory = (): ColumnOption<PayableReference>[] => [
    ...(tenantScope.isAllTenants
      ? [
          {
            prop: 'tenant',
            label: '所属租户',
            minWidth: 190,
            formatter: (row: PayableReference) => formatTenantLabel(row)
          }
        ]
      : []),
    { prop: 'code', label: '编码', minWidth: 150 },
    { prop: 'name', label: '名称', minWidth: 200 },
    ...(props.kind === 'purpose'
      ? [
          {
            prop: 'businessType',
            label: '付款业务类型',
            minWidth: 150,
            formatter: (row: PayableReference) => labels[row.businessType || ''] || '—'
          },
          {
            prop: 'payableWriteoff',
            label: '参与应付核销',
            width: 145,
            formatter: (row: PayableReference) => (row.payableWriteoff ? '是' : '否')
          },
          {
            prop: 'receivableWriteoff',
            label: '参与应收核销',
            width: 145,
            formatter: (row: PayableReference) => (row.receivableWriteoff ? '是' : '否')
          }
        ]
      : [
          {
            prop: 'category',
            label: '类别',
            minWidth: 160,
            formatter: (row: PayableReference) => labels[row.category || ''] || '—'
          }
        ]),
    { prop: 'description', label: '描述', minWidth: 240 },
    {
      prop: 'enabled',
      label: '状态',
      width: 100,
      formatter: (row) => (
        <ElTag type={row.enabled ? 'success' : 'info'}>{row.enabled ? '启用' : '停用'}</ElTag>
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 80,
      fixed: 'right',
      formatter: (row) => (
        <BusinessTableRowActions>
          <ArtButtonTable
            type="edit"
            label="编辑"
            permission={props.permissions.Edit}
            onClick={() => editorRef.value?.open(row)}
          />
        </BusinessTableRowActions>
      )
    }
  ]
</script>
