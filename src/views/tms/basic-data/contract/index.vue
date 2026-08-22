<template>
  <div class="tms-contract business-workspace-page art-full-height">
    <MasterDeleteProcessingNotice
      v-if="deleteContext.active"
      :customer-id="deleteContext.customerId"
      :customer-name="deleteContext.customerName"
      action-hint="已自动定位关联合同；请先按业务规则终止或保留合同。"
    />
    <BusinessWorkspaceHeader
      eyebrow="CONTRACT GOVERNANCE"
      title="运输合同"
      description="集中管理客户/货主与承运商合同、计费方式、生效周期及审核状态，确保运输合作有据可循。"
      icon="ri:file-shield-2-line"
      :tags="[
        { label: '合同治理', type: 'primary' },
        { label: '周期可追踪', type: 'warning' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      :key="tablePermissionKey"
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: true }"
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
  import { RouterLink } from 'vue-router'
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
  import { canViewField, formatSensitiveNumber } from '@/utils/field-permission'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteContract,
    deleteContractBatch,
    exportContractList,
    fetchCarrierOptions,
    fetchContractList,
    fetchCustomerOptions,
    importContracts
  } from '@/api/tms'
  import ContractDialog from './modules/contract-dialog.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import { useMasterDataDeleteProcessingContext } from '@/hooks/core/useMasterDataDeleteProcessing'
  import { usesCarrierParty } from './modules/contract-business-type'

  defineOptions({ name: 'TmsContract' })

  const { confirmAction } = useArtFeedback()

  type Contract = Api.Tms.BasicData.Contract
  type ContractStatus = Api.Tms.BasicData.ContractStatus
  type ContractBusinessType = Api.Tms.BasicData.ContractBusinessType
  type ContractFieldKey = Api.Tms.BasicData.ContractFieldKey
  type ContractFieldAccessMap = Api.Tms.BasicData.ContractFieldAccessMap
  type SearchParams = Api.Tms.BasicData.ContractSearchParams
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type CustomerOption = Api.Tms.BasicData.CustomerOption
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
  const deleteContext = useMasterDataDeleteProcessingContext()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<ContractDialogExpose>()
  const listFieldAccess = ref<ContractFieldAccessMap>({})
  const currentRows = ref<Contract[]>([])

  const table = reactive<TableGroup>({
    searchQuery: {
      contractStatus: undefined,
      businessContractType: undefined,
      contractCategory: undefined,
      customerId: '',
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
  const contractCategoryOptions = computed(() => getDictMap.value.tmsContractCategory ?? [])
  const businessTypeOptions = computed(() => getDictMap.value.tmsContractBusinessType ?? [])
  const transportModeOptions = computed(() => getDictMap.value.tmsContractTransportMode ?? [])
  const booleanOptions = computed(() => getDictMap.value.commonBoolean ?? [])
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
  const contractCategoryLabelMap = computed(() => createDictLabelMap(contractCategoryOptions.value))
  const businessTypeLabelMap = computed(() => createDictLabelMap(businessTypeOptions.value))
  const transportModeLabelMap = computed(() => createDictLabelMap(transportModeOptions.value))
  const contractCategoryValueMap = computed(() => createDictValueMap(contractCategoryOptions.value))
  const businessTypeValueMap = computed(() => createDictValueMap(businessTypeOptions.value))
  const transportModeValueMap = computed(() => createDictValueMap(transportModeOptions.value))
  const booleanValueMap = computed(() => createDictValueMap(booleanOptions.value))
  const booleanLabelMap = computed(() => createDictLabelMap(booleanOptions.value))

  const contractExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'contractName', title: '合同名称', required: true },
    { key: 'contractNo', title: '合同编号' },
    { key: 'paperContractNo', title: '纸质合同编号' },
    { key: 'mnemonicCode', title: '助记码' },
    { key: 'contractStatus', title: '合同状态', formatter: (value) => formatStatus(value) },
    {
      key: 'businessContractType',
      title: '业务合同分类',
      required: true,
      formatter: (value) => formatDictValue(value, businessTypeLabelMap.value)
    },
    {
      key: 'contractCategory',
      title: '合同类别',
      required: true,
      formatter: (value) => formatDictValue(value, contractCategoryLabelMap.value)
    },
    {
      key: 'transportMode',
      title: '运输方式',
      required: true,
      formatter: (value) => formatDictValue(value, transportModeLabelMap.value)
    },
    {
      key: 'carrierName',
      title: '承运商名称',
      formatter: (_value, row) => (row as Contract).carrier?.companyName || ''
    },
    {
      key: 'customerName',
      title: '客户/货主名称',
      formatter: (_value, row) => (row as Contract).customer?.customerName || ''
    },
    { key: 'contractAmount', title: '合同金额' },
    { key: 'transportUnitPrice', title: '运输单价' },
    { key: 'roadConsumptionRate', title: '路耗标准%' },
    { key: 'lossDeductionPrice', title: '亏扣价' },
    { key: 'agreedTransportQuantity', title: '合同约定运输量' },
    { key: 'handler', title: '经办人', required: true },
    {
      key: 'signTime',
      title: '签订时间',
      required: true,
      formatter: (value) => formatDateTime(value)
    },
    { key: 'effectiveDate', title: '生效日期' },
    { key: 'expiryDate', title: '到期日期' },
    {
      key: 'isCompleted',
      title: '是否完成',
      formatter: (value) =>
        formatDictValue(toBooleanValue(value) ? 'true' : 'false', booleanLabelMap.value)
    },
    {
      key: 'billingMethod',
      title: '计费方式',
      required: true,
      formatter: (value) => formatBillingMethod(value)
    },
    { key: 'contactName', title: '联系人姓名' },
    { key: 'partyContactPhone', title: '相对方联系电话' },
    { key: 'customerSignatory', title: '客户签约人' },
    { key: 'waybillNo', title: '运单号' },
    { key: 'transportRoute', title: '运输路线' },
    { key: 'shipperName', title: '发货方' },
    { key: 'payerName', title: '付款方' },
    { key: 'consigneeName', title: '收货方' },
    { key: 'specialTransportRequirements', title: '运输特殊要求' },
    { key: 'otherDeductionTerms', title: '其他扣款约定' },
    { key: 'contractDescription', title: '合同说明摘要' }
  ]

  const excelSensitiveFieldMap: Partial<Record<string, ContractFieldKey>> = {
    contractAmount: 'contractAmount',
    transportUnitPrice: 'transportUnitPrice',
    roadConsumptionRate: 'roadConsumptionRate',
    lossDeductionPrice: 'lossDeductionPrice',
    partyContactPhone: 'partyContactPhone'
  }

  const shouldDisplaySensitiveField = (field: ContractFieldKey): boolean =>
    canViewField(listFieldAccess.value, field) ||
    currentRows.value.some((row) => canViewField(row.fieldAccess, field))

  const visibleExportColumns = computed(() =>
    contractExcelColumns.filter((column) => {
      const field = excelSensitiveFieldMap[String(column.key)]
      return !field || shouldDisplaySensitiveField(field)
    })
  )

  const tablePermissionKey = computed(() =>
    (['contractAmount', 'partyContactPhone'] as const)
      .map((field) => `${field}:${shouldDisplaySensitiveField(field) ? 'visible' : 'hidden'}`)
      .join('|')
  )

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '合同状态',
      key: 'contractStatus',
      type: 'select',
      props: { options: statusOptions, clearable: true }
    },
    {
      label: '业务分类',
      key: 'businessContractType',
      type: 'select',
      props: { options: businessTypeOptions.value, clearable: true }
    },
    {
      label: '合同类别',
      key: 'contractCategory',
      type: 'select',
      props: { options: contractCategoryOptions.value, clearable: true }
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
      label: '客户/货主',
      key: 'customerId',
      type: 'select',
      api: fetchCustomerOptions,
      resultField: 'data',
      labelField: 'customerName',
      valueField: 'id',
      labelFn: formatCustomerOption,
      props: { clearable: true, filterable: true, placeholder: '请选择客户或货主' }
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
      props: { clearable: true, placeholder: '名称、编号、纸质编号、助记码、联系人或路线' }
    }
  ])

  const columnsFactory = (): ColumnOption<Contract>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    {
      prop: 'contractNo',
      label: '合同编号',
      width: 165,
      formatter: (row) =>
        row.id ? (
          <RouterLink
            class="tms-contract__code-link"
            to={`/tms/basic-data/contract-detail/${row.id}`}
            title={`查看合同 ${row.contractNo || row.contractName} 详情`}
          >
            {row.contractNo || '-'}
          </RouterLink>
        ) : (
          row.contractNo || '-'
        )
    },
    { prop: 'contractName', label: '合同名称', minWidth: 210, showOverflowTooltip: true },
    {
      prop: 'contractStatus',
      label: '合同状态',
      width: 110,
      formatter: (row) => renderStatus(row.contractStatus)
    },
    {
      prop: 'businessContractType',
      label: '业务分类',
      width: 145,
      dict: { code: 'tmsContractBusinessType', display: 'auto' }
    },
    {
      prop: 'partyName',
      label: '合同相对方',
      minWidth: 190,
      showOverflowTooltip: true,
      formatter: (row) => row.customer?.customerName || row.carrier?.companyName || '-'
    },
    ...(shouldDisplaySensitiveField('partyContactPhone')
      ? [
          {
            prop: 'partyContactPhone',
            label: '联系电话',
            width: 145,
            formatter: (row: Contract) => row.partyContactPhone || '-'
          }
        ]
      : []),
    ...(shouldDisplaySensitiveField('contractAmount')
      ? [
          {
            prop: 'contractAmount',
            label: '合同金额',
            width: 130,
            align: 'right' as const,
            formatter: (row: Contract) => formatMoney(row.contractAmount)
          }
        ]
      : []),
    { prop: 'handler', label: '经办人', width: 110 },
    {
      prop: 'expiryDate',
      label: '到期日期',
      width: 120,
      formatter: (row) => row.expiryDate || '-'
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable
            type="edit"
            permission="TmsContract:Edit"
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

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { permission: 'TmsContract:Add', type: 'add', onClick: () => openDialog() },
    {
      permission: 'TmsContract:Delete',
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
      permission: 'TmsContract:Export',
      type: 'export',
      exportFilename: 'TMS合同资料',
      exportSheetName: '合同管理',
      exportColumns: () => visibleExportColumns.value,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportContractList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  const fetchTableData = async (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchContractList({ ...params, from, to })
    listFieldAccess.value = result.fieldAccess
    currentRows.value = result.data
    return result
  }

  function formatCarrierOption(option: Record<string, unknown>): string {
    return formatNameCodeOption(option, 'companyName', 'carrierCode')
  }

  function formatCustomerOption(option: Record<string, unknown>): string {
    return formatNameCodeOption(option, 'customerName', 'customerCode')
  }

  const createDictLabelMap = (options: Api.DataCenter.DictListItem[]): Map<string, string> => {
    const map = new Map<string, string>()
    options.forEach((item) => {
      if (item.value) map.set(item.value, item.label || item.name || item.value)
    })
    return map
  }

  const createDictValueMap = (options: Api.DataCenter.DictListItem[]): Map<string, string> => {
    const map = new Map<string, string>()
    options.forEach((item) => {
      if (item.value) map.set(item.value, item.value)
      if (item.label) map.set(item.label, item.value)
      if (item.name) map.set(item.name, item.value)
    })
    return map
  }

  const formatDictValue = (value: unknown, labels: Map<string, string>): string => {
    const key = String(value ?? '')
    return labels.get(key) || key
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

  const formatMoney = (value?: Api.Tms.BasicData.SensitiveNumber): string =>
    formatSensitiveNumber(value)

  const formatDateTime = (value?: unknown): string => {
    if (!value) return '-'
    return formatWithDayjs(String(value), 'YYYY-MM-DD HH:mm:ss') ?? '-'
  }

  const getImportValue = (row: Record<string, unknown>, key: string, title: string): string => {
    return String(row[title] ?? row[key] ?? '').trim()
  }

  const parseImportNumber = (
    row: Record<string, unknown>,
    key: string,
    title: string
  ): number | null => {
    const rawValue = getImportValue(row, key, title)
    if (!rawValue) return null
    const value = Number(rawValue)
    return Number.isFinite(value) ? value : null
  }

  const toBooleanValue = (value: unknown): boolean => {
    if (typeof value === 'boolean') return value
    const normalized = String(value ?? '').trim()
    return booleanValueMap.value.get(normalized) === 'true' || normalized === 'true'
  }

  const transformImportRows = async (rows: Array<Record<string, unknown>>): Promise<Contract[]> => {
    const [{ data: carriers }, { data: customers }] = await Promise.all([
      fetchCarrierOptions(),
      fetchCustomerOptions()
    ])
    const carrierMap = new Map<string, CarrierOption>()
    ;(carriers ?? []).forEach((carrier) => {
      carrierMap.set(carrier.companyName, carrier)
      if (carrier.carrierCode) carrierMap.set(carrier.carrierCode, carrier)
      if (carrier.carrierCode)
        carrierMap.set(`${carrier.companyName}（${carrier.carrierCode}）`, carrier)
    })
    const customerMap = new Map<string, CustomerOption>()
    ;(customers ?? []).forEach((customer) => {
      customerMap.set(customer.customerName, customer)
      if (customer.customerCode) customerMap.set(customer.customerCode, customer)
      if (customer.customerCode)
        customerMap.set(`${customer.customerName}（${customer.customerCode}）`, customer)
    })

    const statusValueMap = new Map<string, ContractStatus>()
    statusOptions.forEach((item) => {
      statusValueMap.set(item.value, item.value)
      statusValueMap.set(item.label, item.value)
    })

    return rows
      .map((row) => {
        const carrierName = getImportValue(row, 'carrierName', '承运商名称')
        const customerName = getImportValue(row, 'customerName', '客户/货主名称')
        const carrier = carrierMap.get(carrierName)
        const customer = customerMap.get(customerName)
        const importedBusinessType = businessTypeValueMap.value.get(
          getImportValue(row, 'businessContractType', '业务合同分类')
        )
        const businessContractType: ContractBusinessType =
          importedBusinessType === 'customer' || importedBusinessType === 'carrier'
            ? importedBusinessType
            : customer
              ? 'carrier'
              : 'customer'
        return {
          contractNo: getImportValue(row, 'contractNo', '合同编号') || undefined,
          contractName: getImportValue(row, 'contractName', '合同名称'),
          paperContractNo: getImportValue(row, 'paperContractNo', '纸质合同编号') || null,
          mnemonicCode: getImportValue(row, 'mnemonicCode', '助记码') || null,
          contractStatus:
            statusValueMap.get(getImportValue(row, 'contractStatus', '合同状态')) || 'draft',
          businessContractType,
          contractCategory:
            contractCategoryValueMap.value.get(
              getImportValue(row, 'contractCategory', '合同类别')
            ) || 'annual_framework',
          transportMode:
            transportModeValueMap.value.get(getImportValue(row, 'transportMode', '运输方式')) ||
            'road',
          carrierId: usesCarrierParty(businessContractType) ? carrier?.id || null : null,
          customerId: usesCarrierParty(businessContractType) ? null : customer?.id || null,
          contactName: getImportValue(row, 'contactName', '联系人姓名') || null,
          customerSignatory: getImportValue(row, 'customerSignatory', '客户签约人') || null,
          waybillNo: getImportValue(row, 'waybillNo', '运单号') || null,
          billingMethod:
            billingValueMap.value.get(getImportValue(row, 'billingMethod', '计费方式')) || '',
          contractAmount: parseImportNumber(row, 'contractAmount', '合同金额'),
          transportUnitPrice: parseImportNumber(row, 'transportUnitPrice', '运输单价'),
          roadConsumptionRate: parseImportNumber(row, 'roadConsumptionRate', '路耗标准%'),
          lossDeductionPrice: parseImportNumber(row, 'lossDeductionPrice', '亏扣价'),
          agreedTransportQuantity: parseImportNumber(
            row,
            'agreedTransportQuantity',
            '合同约定运输量'
          ),
          signTime: getImportValue(row, 'signTime', '签订时间'),
          effectiveDate: getImportValue(row, 'effectiveDate', '生效日期') || null,
          expiryDate: getImportValue(row, 'expiryDate', '到期日期') || null,
          isCompleted: toBooleanValue(getImportValue(row, 'isCompleted', '是否完成')),
          handler: getImportValue(row, 'handler', '经办人'),
          transportRoute: getImportValue(row, 'transportRoute', '运输路线') || null,
          shipperName: getImportValue(row, 'shipperName', '发货方') || null,
          payerName: getImportValue(row, 'payerName', '付款方') || null,
          consigneeName: getImportValue(row, 'consigneeName', '收货方') || null,
          specialTransportRequirements:
            getImportValue(row, 'specialTransportRequirements', '运输特殊要求') || null,
          otherDeductionTerms: getImportValue(row, 'otherDeductionTerms', '其他扣款约定') || null,
          contractDescription: getImportValue(row, 'contractDescription', '合同说明摘要') || null,
          transportDetails: [],
          attachments: []
        }
      })
      .filter(
        (row) =>
          row.contractName &&
          (usesCarrierParty(row.businessContractType) ? row.carrierId : row.customerId) &&
          row.billingMethod &&
          row.signTime &&
          row.handler
      )
  }

  const openDialog = (row?: Contract): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const openDetail = (row: Contract): void => {
    if (!row.id) return
    void router.push(`/tms/basic-data/contract-detail/${row.id}`)
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    { auth: 'TmsContract:View', key: 'view', label: '查看', icon: 'ri:eye-line' },
    {
      auth: 'TmsContract:Delete',
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
    if (route.query.fromMasterDelete !== '1' && route.query.fromCustomerDelete !== '1') return
    const carrierId = typeof route.query.carrierId === 'string' ? route.query.carrierId : ''
    const customerId = typeof route.query.customerId === 'string' ? route.query.customerId : ''
    const recordId = typeof route.query.recordId === 'string' ? route.query.recordId : ''
    const changed =
      table.searchQuery.carrierId !== carrierId ||
      table.searchQuery.customerId !== customerId ||
      table.searchQuery.recordId !== recordId
    Object.assign(table.searchQuery, { carrierId, customerId, recordId, keyword: '' })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }

  watch(
    () => route.fullPath,
    () => syncMasterDeleteRoute(),
    { flush: 'post' }
  )
  onActivated(() => syncMasterDeleteRoute(true))
</script>

<style scoped lang="scss">
  .tms-contract {
    :deep(.tms-contract__code-link) {
      display: inline-block;
      max-width: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
      font-weight: 600;
      vertical-align: middle;
      color: var(--el-color-primary);
      white-space: nowrap;
      text-decoration: none;

      &:hover {
        color: var(--el-color-primary-dark-2);
        text-decoration: underline;
        text-underline-offset: 3px;
      }

      &:focus-visible {
        outline: 2px solid var(--el-color-primary);
        outline-offset: 2px;
        border-radius: var(--el-border-radius-small);
      }
    }
  }
</style>
