<template>
  <div class="tms-workspace-page art-full-height">
    <CustomerDeleteProcessingNotice
      v-if="deleteContext.active"
      :customer-id="deleteContext.customerId"
      :customer-name="deleteContext.customerName"
      action-hint="已自动定位关联合同；请先按业务规则终止或保留合同。"
    />
    <TmsWorkspaceHeader
      eyebrow="CONTRACT GOVERNANCE"
      title="运输合同"
      description="集中管理承运合同、计费方式、生效周期与审核状态，确保运输合作有据可循。"
      icon="ri:file-shield-2-line"
      :tags="[
        { label: '合同治理', type: 'primary' },
        { label: '周期可追踪', type: 'warning' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        emptyText: '暂无运输合同',
        emptyDescription: '可新增合同，或调整状态、承运商、计费方式和关键字后重新查询。'
      }"
      focusable
    />

    <ContractDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ElMessage, ElTag } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { formatNameCodeOption } from '@/utils/form'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteContract,
    deleteContractBatch,
    exportContractList,
    fetchCarrierOptions,
    fetchContractList,
    importContracts
  } from '@/api/tms'
  import ContractDialog from './modules/contract-dialog.vue'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'
  import CustomerDeleteProcessingNotice from '@/views/tms-transportation/modules/customer-delete-processing-notice.vue'
  import { useCustomerDeleteProcessingContext } from '@/views/tms-transportation/modules/use-customer-delete-processing'

  defineOptions({ name: 'TmsContract' })

  const { confirmAction } = useArtFeedback()

  type Contract = Api.Tms.BasicData.Contract
  type ContractStatus = Api.Tms.BasicData.ContractStatus
  type SearchParams = Api.Tms.BasicData.ContractSearchParams
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type StatusTagType = 'success' | 'warning' | 'danger' | 'info'

  interface ContractDialogExpose {
    handleOpen: (row?: Contract) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
  }

  const router = useRouter()
  const route = useRoute()
  const deleteContext = useCustomerDeleteProcessingContext()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<ContractDialogExpose>()

  const table = reactive<TableGroup>({
    searchQuery: {
      contractStatus: undefined,
      carrierId: typeof route.query.carrierId === 'string' ? route.query.carrierId : '',
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : '',
      billingMethod: '',
      createTimeRange: [],
      keyword: ''
    }
  })

  const statusOptions: Array<{ label: string; value: ContractStatus }> = [
    { label: '草稿', value: 'draft' },
    { label: '待审核', value: 'pending' },
    { label: '已审核', value: 'approved' },
    { label: '已驳回', value: 'rejected' },
    { label: '已终止', value: 'terminated' }
  ]

  const statusMeta: Record<ContractStatus, { label: string; type: StatusTagType }> = {
    draft: { label: '草稿', type: 'info' },
    pending: { label: '待审核', type: 'warning' },
    approved: { label: '已审核', type: 'success' },
    rejected: { label: '已驳回', type: 'danger' },
    terminated: { label: '已终止', type: 'info' }
  }

  const billingMethodOptions = computed(() => getDictMap.value.tmsContractBillingMethod ?? [])
  const billingLabelMap = computed(() => {
    const map = new Map<string, string>()
    billingMethodOptions.value.forEach((item) => {
      if (item.value) map.set(item.value, item.label || item.name || item.value)
    })
    return map
  })
  const billingValueMap = computed(() => {
    const map = new Map<string, string>()
    billingMethodOptions.value.forEach((item) => {
      if (item.value) map.set(item.value, item.value)
      if (item.label) map.set(item.label, item.value)
      if (item.name) map.set(item.name, item.value)
    })
    return map
  })

  const contractExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'contractName', title: '合同名称', required: true },
    { key: 'contractNo', title: '合同编号' },
    { key: 'contractStatus', title: '合同状态', formatter: (value) => formatStatus(value) },
    {
      key: 'carrierName',
      title: '承运商名称',
      required: true,
      formatter: (_value, row) => (row as Contract).carrier?.companyName || ''
    },
    { key: 'contractAmount', title: '合同金额' },
    { key: 'handler', title: '经办人', required: true },
    {
      key: 'signTime',
      title: '签订时间',
      required: true,
      formatter: (value) => formatDateTime(value)
    },
    {
      key: 'billingMethod',
      title: '计费方式',
      required: true,
      formatter: (value) => formatBillingMethod(value)
    },
    { key: 'contactName', title: '联系人姓名' },
    { key: 'waybillNo', title: '运单号' }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '合同状态',
      key: 'contractStatus',
      type: 'select',
      props: { options: statusOptions, clearable: true }
    },
    {
      label: '承运商',
      key: 'carrierId',
      type: 'select',
      api: fetchCarrierOptions,
      resultField: 'data',
      labelField: 'companyName',
      valueField: 'id',
      labelFn: formatCarrierOption,
      props: { clearable: true, filterable: true, placeholder: '请选择承运商' }
    },
    {
      label: '创建日期',
      key: 'createTimeRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至'
      }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '合同名称、编号、联系人、运单号或经办人' }
    }
  ])

  const columnsFactory = (): ColumnOption<Contract>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { prop: 'contractName', label: '合同名称', minWidth: 190, showOverflowTooltip: true },
    { prop: 'contractNo', label: '合同编号', width: 150 },
    {
      prop: 'contractStatus',
      label: '合同状态',
      width: 110,
      formatter: (row) => renderStatus(row.contractStatus)
    },
    {
      prop: 'carrierName',
      label: '承运商名称',
      minWidth: 190,
      showOverflowTooltip: true,
      formatter: (row) => row.carrier?.companyName || '-'
    },
    {
      prop: 'contractAmount',
      label: '合同金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.contractAmount)
    },
    { prop: 'handler', label: '经办人', width: 110 },
    {
      prop: 'signTime',
      label: '签订时间',
      width: 170,
      formatter: (row) => formatDateTime(row.signTime)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonMore
            list={getMoreActions()}
            onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
          />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', onClick: () => openDialog() },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 条合同吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        await deleteContractBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    },
    {
      type: 'import',
      importColumns: contractExcelColumns,
      importTransformer: transformImportRows,
      importApi: async (rows) => {
        await importContracts(rows as Contract[])
      },
      onImportError: () => {
        ElMessage.error('导入文件解析失败')
      }
    },
    {
      type: 'export',
      exportFilename: 'TMS合同资料',
      exportSheetName: '合同管理',
      exportColumns: contractExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportContractList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchContractList({ ...params, from, to })
  }

  function formatCarrierOption(option: Record<string, unknown>): string {
    return formatNameCodeOption(option, 'companyName', 'carrierCode')
  }

  const renderStatus = (status?: ContractStatus) => {
    if (!status) return '-'
    const meta = statusMeta[status] ?? statusMeta.draft
    return <ElTag type={meta.type}>{meta.label}</ElTag>
  }

  const formatStatus = (value: unknown): string => {
    const status = String(value || '') as ContractStatus
    return statusMeta[status]?.label || String(value || '')
  }

  const formatBillingMethod = (value: unknown): string => {
    const key = String(value || '')
    return billingLabelMap.value.get(key) || key
  }

  const formatMoney = (value?: number | null): string => {
    if (value === null || value === undefined || Number.isNaN(Number(value))) return '-'
    return Number(value).toFixed(2)
  }

  const formatDateTime = (value?: unknown): string => {
    if (!value) return '-'
    return formatWithDayjs(String(value), 'YYYY-MM-DD HH:mm:ss') ?? '-'
  }

  const getImportValue = (row: Record<string, unknown>, key: string, title: string): string => {
    return String(row[title] ?? row[key] ?? '').trim()
  }

  const transformImportRows = async (rows: Array<Record<string, unknown>>): Promise<Contract[]> => {
    const { data: carriers } = await fetchCarrierOptions()
    const carrierMap = new Map<string, CarrierOption>()
    ;(carriers ?? []).forEach((carrier) => {
      carrierMap.set(carrier.companyName, carrier)
      if (carrier.carrierCode) carrierMap.set(carrier.carrierCode, carrier)
      if (carrier.carrierCode)
        carrierMap.set(`${carrier.companyName}（${carrier.carrierCode}）`, carrier)
    })

    const statusValueMap = new Map<string, ContractStatus>()
    statusOptions.forEach((item) => {
      statusValueMap.set(item.value, item.value)
      statusValueMap.set(item.label, item.value)
    })

    return rows
      .map((row) => {
        const carrierName = getImportValue(row, 'carrierName', '承运商名称')
        const carrier = carrierMap.get(carrierName)
        return {
          contractNo: getImportValue(row, 'contractNo', '合同编号') || undefined,
          contractName: getImportValue(row, 'contractName', '合同名称'),
          contractStatus:
            statusValueMap.get(getImportValue(row, 'contractStatus', '合同状态')) || 'draft',
          carrierId: carrier?.id || '',
          contactName: getImportValue(row, 'contactName', '联系人姓名') || null,
          waybillNo: getImportValue(row, 'waybillNo', '运单号') || null,
          billingMethod:
            billingValueMap.value.get(getImportValue(row, 'billingMethod', '计费方式')) || '',
          contractAmount: Number(getImportValue(row, 'contractAmount', '合同金额')) || null,
          signTime: getImportValue(row, 'signTime', '签订时间'),
          handler: getImportValue(row, 'handler', '经办人'),
          contractDescription: null,
          attachments: []
        }
      })
      .filter(
        (row) =>
          row.contractName && row.carrierId && row.billingMethod && row.signTime && row.handler
      )
  }

  const openDialog = (row?: Contract): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const openDetail = (row: Contract): void => {
    if (!row.id) return
    void router.push(`/tms-transportation/basic-data/contract-detail/${row.id}`)
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'view',
      label: '查看',
      icon: 'ri:eye-line'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: Contract): void => {
    if (item.key === 'view') {
      openDetail(row)
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

  const handleDelete = async (row: Contract): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除合同“${row.contractName}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteContract(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  const syncMasterDeleteRoute = (forceRefresh = false): void => {
    if (route.query.fromMasterDelete !== '1') return
    const carrierId = typeof route.query.carrierId === 'string' ? route.query.carrierId : ''
    const recordId = typeof route.query.recordId === 'string' ? route.query.recordId : ''
    const changed =
      table.searchQuery.carrierId !== carrierId || table.searchQuery.recordId !== recordId
    Object.assign(table.searchQuery, { carrierId, recordId, keyword: '' })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }

  watch(
    () => route.fullPath,
    () => syncMasterDeleteRoute(),
    { flush: 'post' }
  )
  onActivated(() => syncMasterDeleteRoute(true))
</script>
