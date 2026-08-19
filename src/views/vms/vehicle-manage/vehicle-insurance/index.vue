<template>
  <div class="vehicle-insurance-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="INSURANCE COMPLIANCE"
      title="车辆保险"
      description="集中管理商业险与交强险保单、保费和到期信息，持续掌握车队保险覆盖情况。"
      icon="ri:shield-check-line"
      :tags="[
        { label: '双险协同', type: 'primary' },
        { label: '到期可追踪', type: 'info' }
      ]"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 110 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无车辆保险记录',
        emptyDescription: '可新增保单，或调整车辆、保单号和到期日期后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />

    <VehicleInsuranceDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessage } from 'element-plus'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import {
    deleteVehicleInsurance,
    deleteVehicleInsuranceBatch,
    exportVehicleInsuranceList,
    fetchVehicleInsuranceList
  } from '@/api/vms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import VehicleInsuranceDialog from './modules/vehicle-insurance-dialog.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'

  defineOptions({ name: 'VehicleInsurance' })

  const { confirmAction } = useArtFeedback()

  type VehicleInsurance = Api.Vms.VehicleManage.VehicleInsurance
  type SearchParams = Api.Vms.VehicleManage.VehicleInsuranceSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: VehicleInsurance) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<VehicleInsurance>[]
  }

  const router = useRouter()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const overview = reactive<{ total: number; rows: VehicleInsurance[] }>({ total: 0, rows: [] })
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '保险记录',
      value: overview.total,
      description: '当前筛选条件下的保单记录',
      icon: 'ri:file-list-3-line'
    },
    {
      label: '本页双险完整',
      value: overview.rows.filter((row) => row.commercialPolicyNo && row.compulsoryPolicyNo).length,
      description: '商业险与交强险均已登记',
      icon: 'ri:shield-star-line',
      tone: 'success'
    },
    {
      label: '本页保单待补',
      value: overview.rows.filter((row) => !row.commercialPolicyNo || !row.compulsoryPolicyNo)
        .length,
      description: '至少缺少一个险种的保单号',
      icon: 'ri:file-warning-line',
      tone: 'warning'
    }
  ])

  const createInitialSearch = (): SearchParams => ({
    companyName: '',
    plateNo: '',
    commercialPolicyNo: '',
    compulsoryPolicyNo: '',
    commercialExpireDateRange: [],
    compulsoryExpireDateRange: [],
    createTimeRange: []
  })

  const dateRangeProps = {
    type: 'daterange',
    valueFormat: 'YYYY-MM-DD',
    startPlaceholder: '开始日期',
    endPlaceholder: '结束日期',
    class: '!w-full'
  }

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: createInitialSearch(),
    searchItems: computed<SearchFormItem[]>(() => [
      { label: '所属公司', key: 'companyName', type: 'input' },
      { label: '车牌号', key: 'plateNo', type: 'input' },
      { label: '商业险保单号', key: 'commercialPolicyNo', type: 'input' },
      { label: '交强险保单号', key: 'compulsoryPolicyNo', type: 'input' },
      {
        label: '商业险到期',
        key: 'commercialExpireDateRange',
        type: 'date',
        props: dateRangeProps
      },
      {
        label: '交强险到期',
        key: 'compulsoryExpireDateRange',
        type: 'date',
        props: dateRangeProps
      },
      { label: '创建时间', key: 'createTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        permission: 'VehicleInsurance:Add',
        onClick: () => openDialog()
      },
      {
        type: 'export',
        permission: 'VehicleInsurance:Export',
        exportFilename: '车辆保险',
        exportSheetName: '车辆保险',
        exportColumns: insuranceExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportVehicleInsuranceList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      },
      {
        type: 'delete',
        permission: 'VehicleInsurance:Delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定删除选中的 ${selectedCount} 条车辆保险记录吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows.map((row) => row.id).filter(Boolean)
          await deleteVehicleInsuranceBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'companyName', label: '所属公司', minWidth: 150 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      {
        label: '商业险',
        children: [
          { prop: 'commercialPolicyNo', label: '保单号', minWidth: 150 },
          { prop: 'commercialCompanyName', label: '保险公司', minWidth: 150 },
          { prop: 'commercialInsureDate', label: '投保日期', width: 120 },
          {
            prop: 'commercialPremium',
            label: '投保金额',
            width: 120,
            formatter: (row: VehicleInsurance) => formatMoney(row.commercialPremium)
          },
          { prop: 'commercialExpireDate', label: '到期日期', width: 120 }
        ]
      },
      {
        label: '交强险',
        children: [
          { prop: 'compulsoryPolicyNo', label: '保单号', minWidth: 150 },
          { prop: 'compulsoryCompanyName', label: '保险公司', minWidth: 150 },
          { prop: 'compulsoryInsureDate', label: '投保日期', width: 120 },
          {
            prop: 'compulsoryPremium',
            label: '投保金额',
            width: 120,
            formatter: (row: VehicleInsurance) => formatMoney(row.compulsoryPremium)
          },
          { prop: 'compulsoryExpireDate', label: '到期日期', width: 120 }
        ]
      },
      {
        prop: 'createTime',
        label: '创建时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.createTime)
      },
      { prop: 'createBy', label: '创建人', width: 130 },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="edit"
              permission="VehicleInsurance:Edit"
              onClick={() => openDialog(row)}
            />
            <ArtButtonMore
              list={getMoreActions()}
              onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
            />
          </div>
        )
      }
    ]
  })

  const insuranceExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'commercialPolicyNo', title: '商业险保单号', required: true },
    { key: 'commercialCompanyName', title: '商业险保险公司' },
    { key: 'commercialInsureDate', title: '商业险投保日期' },
    { key: 'commercialPremium', title: '商业险投保金额' },
    { key: 'commercialExpireDate', title: '商业险到期日期' },
    { key: 'compulsoryPolicyNo', title: '交强险保单号', required: true },
    { key: 'compulsoryCompanyName', title: '交强险保险公司' },
    { key: 'compulsoryInsureDate', title: '交强险投保日期' },
    { key: 'compulsoryPremium', title: '交强险投保金额' },
    { key: 'compulsoryExpireDate', title: '交强险到期日期' },
    { key: 'remark', title: '备注' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchVehicleInsuranceList({ ...params, from, to })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as VehicleInsurance[]
    overview.total = response.total ?? rows.length
  }

  const openDialog = (row?: VehicleInsurance): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const viewDetail = (row: VehicleInsurance): void => {
    if (!row.id) return
    void router.push(`/vms/vehicle-manage/vehicle-insurance-detail/${row.id}`)
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'view',
      label: '查看',
      icon: 'ri:eye-line',
      auth: 'VehicleInsurance:View'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      auth: 'VehicleInsurance:Delete',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: VehicleInsurance): void => {
    if (item.key === 'view') {
      viewDetail(row)
      return
    }
    if (item.key === 'delete') {
      void handleDelete(row)
    }
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: VehicleInsurance): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(`确定删除车辆“${row.plateNo}”的保险记录吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteVehicleInsurance(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  const formatMoney = (value?: number | null): string => {
    if (value === undefined || value === null) return '--'
    return `${Number(value).toFixed(2)} 元`
  }

  onErrorCaptured((error) => {
    ElMessage.error(getFriendlySupabaseErrorMessage(error, '车辆保险页面异常'))
    return false
  })
</script>

<style scoped lang="scss">
  .vehicle-insurance-page {
    gap: 12px;
    min-width: 0;
  }
</style>
