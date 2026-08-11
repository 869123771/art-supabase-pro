<template>
  <div class="tms-workspace-page art-full-height">
    <TmsWorkspaceHeader
      eyebrow="客户主数据"
      title="客户资料"
      description="统一维护客户主体、行业等级、结算联系人与业务状态，为开单和对账提供可信主数据。"
      icon="ri:user-star-line"
      :tags="[
        { label: '客户主数据', type: 'primary' },
        { label: '业务可用性', type: 'success' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: true }"
      :table-props="{
        emptyText: '暂无客户资料',
        emptyDescription: '可新增客户，或调整客户等级、行业、状态和关键字后重新查询。'
      }"
      focusable
    />

    <CustomerDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ElButton, ElMessage, ElMessageBox, ElScrollbar, ElTag } from 'element-plus'
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
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import {
    cleanupCustomerDeleteSafeDependencies,
    deleteCustomer,
    deleteCustomerBatch,
    exportCustomerList,
    fetchCustomerDeleteDependencyDetails,
    fetchCustomerDeleteSafeCleanupCandidates,
    fetchCustomerList,
    importCustomers
  } from '@/api/tms'
  import type {
    CustomerDeleteDependencyCode,
    CustomerDeleteDependencyDetail,
    CustomerDeleteSafeCleanupCandidate,
    CustomerDeleteSafeCleanupCode
  } from '@/api/tms'
  import CustomerDialog from './modules/customer-dialog.vue'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'

  defineOptions({ name: 'TmsCustomer' })

  const { confirmAction } = useArtFeedback()

  type Customer = Api.Tms.BasicData.Customer
  type SearchParams = Api.Tms.BasicData.CustomerSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface CustomerDialogExpose {
    handleOpen: (row?: Customer) => Promise<void>
  }

  interface CustomerDeleteDependencyMeta {
    action: string
    actionLabel: string
    label: string
    order: number
    routeName: string
    unit: string
  }

  interface CustomerDeleteBlockerItem extends CustomerDeleteDependencyMeta {
    affectedCustomerNames: string[]
    count: number
    dependencyCode: CustomerDeleteDependencyCode
    records: CustomerDeleteDependencyDetail[]
  }

  const router = useRouter()
  const route = useRoute()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<CustomerDialogExpose>()

  const customerDeleteDependencyMeta: Record<
    CustomerDeleteDependencyCode,
    CustomerDeleteDependencyMeta
  > = {
    cash_allocation: {
      label: '收款核销分配',
      unit: '条',
      action: '请到“收付款管理”查看并撤销核销；历史核销记录本身不支持直接物理删除。',
      actionLabel: '去处理核销',
      routeName: 'TmsCashTransaction',
      order: 1
    },
    cash_transaction: {
      label: '收付款流水',
      unit: '笔',
      action: '收付款流水属于财务历史，可作废但不直接物理删除；如需保留历史，建议停用客户。',
      actionLabel: '去查看流水',
      routeName: 'TmsCashTransaction',
      order: 2
    },
    customer_statement: {
      label: '客户对账单',
      unit: '张',
      action: '无核销关系的草稿可一键清理；审核后或已作废记录应保留，并改为停用客户。',
      actionLabel: '去处理对账单',
      routeName: 'TmsCustomerSettlement',
      order: 3
    },
    customer_statement_item: {
      label: '客户对账明细',
      unit: '条',
      action: '明细随对应草稿对账单一并删除，无需单独处理。',
      actionLabel: '去对应对账单',
      routeName: 'TmsCustomerSettlement',
      order: 4
    },
    invoice: {
      label: '客户发票',
      unit: '张',
      action: '草稿发票可一键清理；已复核、已开具或已作废发票属于财务历史，应保留。',
      actionLabel: '去处理发票',
      routeName: 'TmsInvoiceManagement',
      order: 5
    },
    contract: {
      label: '运输合同',
      unit: '份',
      action: '合同属于经营与审批历史，应先终止或保留合同，并改为停用客户。',
      actionLabel: '去处理合同',
      routeName: 'TmsContract',
      order: 6
    },
    customer_price: {
      label: '客户价格方案',
      unit: '条',
      action: '报价配置可一键清理，也可以到“客户报价”逐条确认后删除。',
      actionLabel: '去删除报价',
      routeName: 'TmsCustomerPrice',
      order: 7
    }
  }

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      customerLevel: '',
      industry: '',
      enabled: undefined,
      createTimeRange: [],
      customerId: typeof route.query.customerId === 'string' ? route.query.customerId : '',
      keyword: ''
    }
  })

  const customerLevelOptions = computed(() => getDictMap.value.tmsCustomerLevel ?? [])
  const customerIndustryOptions = computed(() => getDictMap.value.tmsCustomerIndustry ?? [])
  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const customerExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'customerCode', title: '客户编号' },
    { key: 'customerName', title: '客户名称', required: true },
    { key: 'industry', title: '所属行业' },
    { key: 'customerLevel', title: '客户级别' },
    { key: 'contactName', title: '联系人' },
    { key: 'contactPhone', title: '手机号码' },
    { key: 'region', title: '区域' },
    { key: 'addressDetail', title: '公司地址' },
    { key: 'postalCode', title: '邮编' },
    { key: 'remark', title: '备注' }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '客户级别',
      key: 'customerLevel',
      type: 'select',
      props: { options: customerLevelOptions.value, clearable: true }
    },
    {
      label: '所属行业',
      key: 'industry',
      type: 'select',
      props: { options: customerIndustryOptions.value, clearable: true }
    },
    {
      label: '客户状态',
      key: 'enabled',
      type: 'select',
      props: { options: commonBooleanOptions.value, clearable: true }
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
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '客户名称、编号、联系人或电话' }
    }
  ])

  const columnsFactory = (): ColumnOption<Customer>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    { prop: 'customerCode', label: '客户编号', width: 140 },
    { prop: 'customerName', label: '客户名称', minWidth: 190, showOverflowTooltip: true },
    {
      prop: 'industry',
      label: '所属行业',
      width: 130,
      dict: { code: 'tmsCustomerIndustry', display: 'text' }
    },
    {
      prop: 'customerLevel',
      label: '客户级别',
      width: 120,
      formatter: (row) =>
        row.customerLevel ? (
          <ArtDictDisplay dictCode="tmsCustomerLevel" value={row.customerLevel} display="tag" />
        ) : (
          <span class="text-g-400">—</span>
        )
    },
    {
      prop: 'tags',
      label: '客户标签',
      minWidth: 200,
      formatter: (row) => (
        <div class="flex flex-wrap gap-1">
          {(row.tags?.length ? row.tags : ['']).map((tag) => (
            <ArtDictDisplay
              key={tag || 'empty'}
              dictCode="tmsCustomerTag"
              value={tag}
              display={tag ? 'tag' : 'text'}
            />
          ))}
        </div>
      )
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 96,
      formatter: (row) => (
        <ElTag type={row.enabled ? 'success' : 'info'} effect="light" size="small">
          {row.enabled ? '启用' : '停用'}
        </ElTag>
      )
    },
    { prop: 'contactName', label: '联系人', width: 110 },
    {
      prop: 'contactPhone',
      label: '手机号码',
      width: 140,
      formatter: (row) => maskPhone(row.contactPhone)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 138,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable
            type="view"
            icon="ri:map-pin-line"
            onClick={() => openAddressManage(row)}
          />
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
      type: 'import',
      importColumns: customerExcelColumns,
      importApi: async (rows) => {
        await importCustomers(rows as Customer[])
      },
      onImportError: () => {
        ElMessage.error('导入文件解析失败')
      }
    },
    {
      type: 'export',
      exportFilename: 'TMS客户资料',
      exportSheetName: '客户管理',
      exportColumns: customerExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCustomerList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 个客户吗？客户地址会一并删除，历史订单会解除客户关联；存在财务或价格资料时将无法删除。`,
      onClick: async ({ selectedRows }) => {
        const customers = selectedRows as Customer[]
        await executeCustomerDelete(customers)
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCustomerList({ ...params, from, to })
  }

  const openDialog = (row?: Customer): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const openAddressManage = (row: Customer): void => {
    if (!row.id) return
    void router.push({
      name: 'TmsCustomerAddress',
      query: {
        customerId: row.id,
        customerName: row.customerName
      }
    })
  }

  const maskPhone = (phone?: string | null): string => {
    const value = String(phone ?? '').trim()
    if (!value) return '—'
    if (value.length <= 7) return `${value.slice(0, 2)}***${value.slice(-2)}`
    return `${value.slice(0, 3)}****${value.slice(-4)}`
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'delete',
      label: '删除客户',
      icon: 'ri:delete-bin-5-line',
      color: 'var(--el-color-danger)'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: Customer): void => {
    if (item.key === 'delete') void handleDelete(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Customer): Promise<void> => {
    if (!row.id) return
    try {
      if (await showCustomerDeleteBlockersIfNeeded([row])) return
      await confirmAction(
        `确定删除客户“${row.customerName}”吗？客户地址会一并删除，历史订单会解除客户关联。若需保留业务历史，建议改为停用客户。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await executeCustomerDelete([row], false)
    } catch (error) {
      if (!isFeedbackCancel(error)) await handleCustomerDeleteError(error, [row])
    }
  }

  const getCustomerDeleteBlockerItems = (
    dependencies: CustomerDeleteDependencyDetail[],
    customers: Customer[]
  ): CustomerDeleteBlockerItem[] => {
    const customerNameMap = new Map(customers.map((item) => [String(item.id), item.customerName]))
    const grouped = new Map<
      CustomerDeleteDependencyCode,
      { customerNames: Set<string>; records: CustomerDeleteDependencyDetail[] }
    >()
    dependencies.forEach((dependency) => {
      const current = grouped.get(dependency.dependencyCode) ?? {
        customerNames: new Set<string>(),
        records: []
      }
      current.records.push(dependency)
      const customerName = customerNameMap.get(dependency.customerId)
      if (customerName) current.customerNames.add(customerName)
      grouped.set(dependency.dependencyCode, current)
    })

    return Array.from(grouped.entries())
      .map(([dependencyCode, value]) => ({
        dependencyCode,
        ...customerDeleteDependencyMeta[dependencyCode],
        count: value.records.length,
        affectedCustomerNames: Array.from(value.customerNames),
        records: value.records
      }))
      .sort((left, right) => left.order - right.order)
  }

  const formatAffectedCustomers = (names: string[]): string => {
    const displayed = names.slice(0, 3)
    return `${displayed.join('、')}${names.length > displayed.length ? ` 等 ${names.length} 个客户` : ''}`
  }

  const dependencyStatusLabelMap: Record<string, string> = {
    active: '当前生效',
    reversed: '已撤销',
    inactive: '已失效',
    pending_allocation: '待核销',
    partially_allocated: '部分核销',
    fully_allocated: '已核销',
    draft: '草稿',
    pending: '待审核',
    approved: '已审核',
    rejected: '已驳回',
    terminated: '已终止',
    pending_review: '待审核',
    confirmed: '已确认',
    issued: '已开具',
    certified: '已认证',
    voided: '已作废'
  }

  const formatDependencyStatus = (status?: string | null): string =>
    status ? dependencyStatusLabelMap[status] || status : ''

  const formatDependencyAmount = (amount?: number | null): string =>
    `¥${Number(amount ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`

  const safeCleanupLabelMap: Record<CustomerDeleteSafeCleanupCode, string> = {
    customer_price: '客户报价',
    customer_statement: '草稿对账单',
    invoice: '草稿发票'
  }

  const getSafeCleanupCandidateKey = (
    dependencyCode: CustomerDeleteDependencyCode,
    recordId: string
  ): string => `${dependencyCode}:${recordId}`

  const isSafeCleanupRecord = (
    record: CustomerDeleteDependencyDetail,
    candidateKeys: Set<string>
  ): boolean => {
    if (record.dependencyCode === 'customer_statement_item') {
      return candidateKeys.has(getSafeCleanupCandidateKey('customer_statement', record.targetId))
    }
    return candidateKeys.has(getSafeCleanupCandidateKey(record.dependencyCode, record.recordId))
  }

  const formatSafeCleanupSummary = (candidates: CustomerDeleteSafeCleanupCandidate[]): string => {
    const counts = candidates.reduce<Partial<Record<CustomerDeleteSafeCleanupCode, number>>>(
      (summary, candidate) => {
        summary[candidate.dependencyCode] = (summary[candidate.dependencyCode] ?? 0) + 1
        return summary
      },
      {}
    )
    return (Object.entries(counts) as Array<[CustomerDeleteSafeCleanupCode, number]>)
      .map(([code, count]) => `${safeCleanupLabelMap[code]} ${count} 项`)
      .join('、')
  }

  const handleSafeCleanup = async (
    customers: Customer[],
    candidates: CustomerDeleteSafeCleanupCandidate[]
  ): Promise<void> => {
    const customerIds = customers.map((item) => String(item.id)).filter(Boolean)
    if (!customerIds.length || !candidates.length) return
    ElMessageBox.close()
    await nextTick()
    try {
      await confirmAction(
        `将永久删除 ${formatSafeCleanupSummary(candidates)}。该操作不会删除收付款流水、核销记录及已生效票据，是否继续？`,
        '一键清理确认',
        {
          type: 'warning',
          confirmButtonText: `确认清理 ${candidates.length} 项`,
          cancelButtonText: '取消',
          confirmButtonClass: 'el-button--danger',
          closeOnClickModal: false
        }
      )
      const results = await cleanupCustomerDeleteSafeDependencies(customerIds)
      const deletedCount = results.reduce((total, item) => total + item.deletedCount, 0)
      if (!deletedCount) {
        ElMessage.warning('资料状态已发生变化，本次没有可安全清理的记录')
        await showCustomerDeleteBlockersIfNeeded(customers)
        return
      }
      const stillBlocked = await showCustomerDeleteBlockersIfNeeded(customers)
      if (!stillBlocked) {
        ElMessage.success(`已安全清理 ${deletedCount} 项资料，现在可以重新删除客户`)
      } else {
        ElMessage.success(`已安全清理 ${deletedCount} 项资料，其余财务历史仍需保留`)
      }
    } catch (error) {
      if (!isFeedbackCancel(error)) {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '安全清理失败，请稍后重试'))
      }
    }
  }

  const openCustomerDeleteDependency = (
    item: CustomerDeleteBlockerItem,
    record: CustomerDeleteDependencyDetail,
    customers: Customer[]
  ): void => {
    const customer = customers.find((candidate) => String(candidate.id) === record.customerId)
    ElMessageBox.close()
    void router.push({
      name: item.routeName,
      query: {
        fromCustomerDelete: '1',
        customerId: record.customerId,
        customerName: customer?.customerName,
        recordId: record.targetId,
        recordNo: record.recordNo,
        dependencyCode: item.dependencyCode
      }
    })
  }

  const showCustomerDeleteBlockers = async (
    dependencies: CustomerDeleteDependencyDetail[],
    cleanupCandidates: CustomerDeleteSafeCleanupCandidate[],
    customers: Customer[]
  ): Promise<void> => {
    const blockerItems = getCustomerDeleteBlockerItems(dependencies, customers)
    const cleanupCandidateKeys = new Set(
      cleanupCandidates.map((candidate) =>
        getSafeCleanupCandidateKey(candidate.dependencyCode, candidate.recordId)
      )
    )
    const customerLabel =
      customers.length === 1
        ? `客户“${customers[0].customerName}”`
        : `选中的 ${customers.length} 个客户`
    try {
      await confirmAction(
        <div class="customer-delete-blockers">
          <div class="customer-delete-blockers__lead">
            <p>{customerLabel}仍被以下业务资料引用。点击具体记录可直接打开并精确过滤。</p>
            {cleanupCandidates.length ? (
              <ElButton
                type="danger"
                plain
                onClick={() => void handleSafeCleanup(customers, cleanupCandidates)}
              >
                <i class="ri:delete-bin-5-line" aria-hidden="true" />
                一键清理可删除项（{cleanupCandidates.length}）
              </ElButton>
            ) : null}
          </div>
          <ElScrollbar maxHeight="430px">
            <div class="customer-delete-blockers__list">
              {blockerItems.map((item, index) => (
                <div key={item.dependencyCode} class="customer-delete-blockers__item">
                  <span class="customer-delete-blockers__index">{index + 1}</span>
                  <div class="customer-delete-blockers__content">
                    <div class="customer-delete-blockers__title">
                      <strong>{item.label}</strong>
                      <ElTag type="warning" effect="light" size="small">
                        {item.count} {item.unit}
                      </ElTag>
                    </div>
                    <p>{item.action}</p>
                    {customers.length > 1 && item.affectedCustomerNames.length ? (
                      <small>涉及：{formatAffectedCustomers(item.affectedCustomerNames)}</small>
                    ) : null}
                    <div class="customer-delete-blockers__records">
                      {item.records.map((record) => (
                        <div key={record.recordId} class="customer-delete-blockers__record">
                          <div class="customer-delete-blockers__record-copy">
                            <strong>{record.recordNo || '未编号记录'}</strong>
                            <span>
                              {record.recordSummary ? `${record.recordSummary} · ` : ''}
                              {formatDependencyStatus(record.recordStatus) || '待处理'}
                              {record.recordAmount !== null && record.recordAmount !== undefined
                                ? ` · ${formatDependencyAmount(record.recordAmount)}`
                                : ''}
                            </span>
                          </div>
                          <div class="customer-delete-blockers__record-actions">
                            <ElTag
                              type={
                                isSafeCleanupRecord(record, cleanupCandidateKeys)
                                  ? 'success'
                                  : 'info'
                              }
                              effect="light"
                              size="small"
                            >
                              {isSafeCleanupRecord(record, cleanupCandidateKeys)
                                ? '可一键清理'
                                : '需保留/处理'}
                            </ElTag>
                            <ElButton
                              link
                              type="primary"
                              onClick={() => openCustomerDeleteDependency(item, record, customers)}
                            >
                              {item.actionLabel}
                              <i class="ri:arrow-right-s-line" aria-hidden="true" />
                            </ElButton>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </ElScrollbar>
          <div class="customer-delete-blockers__tip">
            <i class="ri:information-line" aria-hidden="true" />
            <span>处理页会作为顶部任务标签打开。完成后点击“返回客户管理”，再重新删除该客户。</span>
          </div>
        </div>,
        {
          title: '暂时无法删除客户',
          type: undefined,
          confirmButtonText: '我知道了',
          showCancelButton: false,
          closeOnClickModal: false,
          customClass: 'customer-delete-blocker-message-box'
        }
      )
    } catch {
      // 关闭说明弹窗无需继续处理。
    }
  }

  const showCustomerDeleteBlockersIfNeeded = async (customers: Customer[]): Promise<boolean> => {
    const customerIds = customers.map((item) => String(item.id)).filter(Boolean)
    const [dependencies, cleanupCandidates] = await Promise.all([
      fetchCustomerDeleteDependencyDetails(customerIds),
      fetchCustomerDeleteSafeCleanupCandidates(customerIds)
    ])
    if (!dependencies.length) return false
    await showCustomerDeleteBlockers(dependencies, cleanupCandidates, customers)
    return true
  }

  const isFeedbackCancel = (error: unknown): boolean => error === 'cancel' || error === 'close'

  const isForeignKeyViolation = (error: unknown): boolean => {
    if (!error || typeof error !== 'object') return false
    const record = error as { code?: unknown; message?: unknown }
    if (record.code === '23503') return true
    const message = typeof record.message === 'string' ? record.message : ''
    return /23503|foreign key|violates foreign key constraint/i.test(message)
  }

  const handleCustomerDeleteError = async (
    error: unknown,
    customers: Customer[]
  ): Promise<void> => {
    if (isForeignKeyViolation(error)) {
      try {
        if (await showCustomerDeleteBlockersIfNeeded(customers)) return
      } catch {
        ElMessage.error('客户仍被业务资料引用，但暂时无法获取引用明细，请刷新后重试')
        return
      }
    }
    ElMessage.error(getFriendlySupabaseErrorMessage(error, '客户删除失败，请稍后重试'))
  }

  const executeCustomerDelete = async (
    customers: Customer[],
    checkDependencies = true
  ): Promise<void> => {
    const customerIds = customers.map((item) => String(item.id)).filter(Boolean)
    if (!customerIds.length) return
    try {
      if (checkDependencies && (await showCustomerDeleteBlockersIfNeeded(customers))) return
      if (customerIds.length === 1) await deleteCustomer(customerIds[0])
      else await deleteCustomerBatch(customerIds)
      ElMessage.success(
        customerIds.length === 1 ? '客户已删除' : `已删除 ${customerIds.length} 个客户`
      )
      await tableQueryRef.value?.refreshRemove()
    } catch (error) {
      await handleCustomerDeleteError(error, customers)
    }
  }

  const syncCustomerDeleteReturn = async (forceRefresh = false): Promise<void> => {
    const customerId = typeof route.query.customerId === 'string' ? route.query.customerId : ''
    const changed = tableState.searchQuery.customerId !== customerId
    if (!customerId && !changed) return
    tableState.searchQuery.customerId = customerId
    if (customerId) tableState.searchQuery.keyword = ''
    if (changed || forceRefresh) {
      await nextTick()
      await tableQueryRef.value?.getData()
    }
    if (route.query.resumeCustomerDelete !== '1') return
    const customerName =
      typeof route.query.customerName === 'string' ? route.query.customerName : ''
    ElMessage.info(
      customerName
        ? `已返回并定位客户“${customerName}”，处理完全部前置资料后可重新删除`
        : '已返回客户管理，请重新检查并删除客户'
    )
    const query = { ...route.query }
    delete query.resumeCustomerDelete
    await router.replace({ name: 'TmsCustomer', query })
  }

  watch(
    () => route.fullPath,
    () => void syncCustomerDeleteReturn(),
    { flush: 'post' }
  )

  onActivated(() => void syncCustomerDeleteReturn(true))
</script>

<style lang="scss">
  .customer-delete-blocker-message-box {
    width: min(720px, calc(100vw - 32px));

    .customer-delete-blockers {
      &__lead {
        display: flex;
        gap: 12px;
        align-items: center;
        justify-content: space-between;
        margin: 0 0 12px;
        line-height: 1.6;
        color: var(--el-text-color-primary);

        p {
          margin: 0;
        }

        .el-button {
          flex: none;

          i {
            margin-right: 4px;
          }
        }
      }

      &__list {
        display: grid;
        gap: 8px;
        padding-right: 8px;
      }

      &__item {
        display: flex;
        gap: 10px;
        align-items: flex-start;
        padding: 10px 12px;
        background: var(--el-fill-color-light);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      &__index {
        display: inline-flex;
        flex: 0 0 22px;
        align-items: center;
        justify-content: center;
        width: 22px;
        height: 22px;
        font-size: 12px;
        font-weight: 700;
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-radius: 50%;
      }

      &__content {
        flex: 1;
        min-width: 0;

        p,
        small {
          display: block;
          margin: 4px 0 0;
          line-height: 1.5;
          color: var(--el-text-color-secondary);
        }
      }

      &__title {
        display: flex;
        gap: 8px;
        align-items: center;
        justify-content: space-between;
      }

      &__tip {
        display: flex;
        gap: 6px;
        align-items: flex-start;
        padding: 10px 12px;
        margin-top: 12px;
        line-height: 1.5;
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-radius: var(--el-border-radius-base);

        i {
          flex: none;
          margin-top: 2px;
          font-size: 16px;
        }
      }

      &__records {
        display: grid;
        gap: 6px;
        padding-top: 8px;
        margin-top: 8px;
        border-top: 1px dashed var(--el-border-color);
      }

      &__record {
        display: flex;
        gap: 12px;
        align-items: center;
        justify-content: space-between;
        min-width: 0;
        padding: 7px 8px;
        background: var(--el-bg-color);
        border-radius: var(--el-border-radius-small);

        .el-button {
          flex: none;

          i {
            margin-left: 2px;
            font-size: 16px;
          }
        }
      }

      &__record-copy {
        display: grid;
        min-width: 0;

        strong,
        span {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        strong {
          font-size: 13px;
          color: var(--el-text-color-primary);
        }

        span {
          margin-top: 2px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }

      &__record-actions {
        display: inline-flex;
        flex: none;
        gap: 8px;
        align-items: center;
      }

      @media (width <= 600px) {
        &__lead {
          flex-direction: column;
          align-items: stretch;

          .el-button {
            width: 100%;
          }
        }

        &__record {
          flex-direction: column;
          align-items: flex-start;
        }

        &__record-actions {
          justify-content: space-between;
          width: 100%;
        }
      }
    }
  }
</style>
