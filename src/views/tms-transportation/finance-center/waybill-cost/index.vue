<template>
  <div class="tms-workspace-page art-full-height">
    <TmsWorkspaceHeader
      eyebrow="COST GOVERNANCE"
      title="运单成本"
      description="归集运单成本项目、承运商费用与审核状态，为利润核算和结算付款建立可靠依据。"
      icon="ri:funds-box-line"
      :tags="[
        { label: '成本台账', type: 'primary' },
        { label: '审核闭环', type: 'warning' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无运单成本',
        emptyDescription: '可新增成本记录，或调整运单号、状态、费用类型和日期后查询。'
      }"
      focusable
    />

    <WaybillCostDialog ref="dialogRef" @success="handleSaveSuccess" />
    <WaybillCostAuditDrawer ref="auditDrawerRef" />
    <WorkflowBusinessHistoryDrawer ref="approvalHistoryRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElImage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExcelColumn,
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteWaybillCost,
    exportWaybillCostList,
    fetchWaybillCostList,
    reviewWaybillCost,
    submitWaybillCost,
    voidWaybillCost
  } from '@/api/tms'
  import WaybillCostDialog from './modules/waybill-cost-dialog.vue'
  import WaybillCostAuditDrawer from './modules/waybill-cost-audit-drawer.vue'
  import WorkflowBusinessHistoryDrawer from '@/components/business/workflow-business-history/workflow-business-history-drawer.vue'
  import type { WorkflowBusinessHistoryDrawerExpose } from '@/components/business/workflow-business-history/types'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'

  defineOptions({ name: 'TmsWaybillCost' })

  type WaybillCost = Api.Tms.Finance.WaybillCostRecord
  type SearchParams = Api.Tms.Finance.WaybillCostSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: WaybillCost) => Promise<void>
  }

  interface AuditDrawerExpose {
    handleOpen: (data: { costId: string; waybillNo: string }) => Promise<void>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const { promptReason, confirmAction } = useArtFeedback()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const auditDrawerRef = ref<AuditDrawerExpose>()
  const approvalHistoryRef = ref<WorkflowBusinessHistoryDrawerExpose>()
  const searchQuery = reactive<SearchParams>({
    keyword: '',
    costType: '',
    auditStatus: '',
    occurredOnRange: []
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '费用类型',
      key: 'costType',
      type: 'select',
      props: {
        options: getDictMap.value.tmsWaybillCostType ?? [],
        clearable: true
      }
    },
    {
      label: '审核状态',
      key: 'auditStatus',
      type: 'select',
      props: {
        options: getDictMap.value.tmsCostAuditStatus ?? [],
        clearable: true
      }
    },
    {
      label: '发生日期',
      key: 'occurredOnRange',
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
      props: {
        clearable: true,
        placeholder: '运单号、收款方、填报人或部门'
      }
    }
  ])

  const formatMoney = (value?: number | null): string =>
    `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`

  const columnsFactory = (): ColumnOption<WaybillCost>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'waybillNo',
      label: '运单号',
      width: 175,
      formatter: (row) => row.waybill?.waybillNo || '-'
    },
    {
      prop: 'route',
      label: '运输路线',
      minWidth: 190,
      showOverflowTooltip: true,
      formatter: (row) =>
        [row.waybill?.originCity, row.waybill?.destinationCity].filter(Boolean).join(' → ') || '-'
    },
    {
      prop: 'costType',
      label: '费用类型',
      width: 125,
      dict: { code: 'tmsWaybillCostType', display: 'tag' }
    },
    { prop: 'payeeName', label: '收款方', minWidth: 160, showOverflowTooltip: true },
    { prop: 'occurredOn', label: '发生日期', width: 110 },
    {
      prop: 'amount',
      label: '费用金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.amount)
    },
    {
      prop: 'reporterNameSnapshot',
      label: '填报人',
      width: 132,
      showOverflowTooltip: true,
      formatter: (row) => row.reporterNameSnapshot || row.createBy || '-'
    },
    {
      prop: 'reporterDepartmentSnapshot',
      label: '填报人所属部门',
      minWidth: 160,
      showOverflowTooltip: true,
      formatter: (row) => row.reporterDepartmentSnapshot || '-'
    },
    {
      prop: 'attachments',
      label: '图片凭证',
      width: 144,
      formatter: (row) => {
        const urls = row.attachments ?? []
        if (!urls.length) return '-'
        return (
          <div class="waybill-cost__evidence">
            {urls.slice(0, 3).map((url, index) => (
              <ElImage
                key={url}
                src={url}
                previewSrcList={urls}
                initialIndex={index}
                previewTeleported
                fit="cover"
                class="waybill-cost__evidence-image"
              />
            ))}
            {urls.length > 3 ? <span>+{urls.length - 3}</span> : null}
          </div>
        )
      }
    },
    {
      prop: 'auditStatus',
      label: '审核状态',
      width: 110,
      dict: { code: 'tmsCostAuditStatus', display: 'tag' }
    },
    { prop: 'remark', label: '费用说明', minWidth: 180, showOverflowTooltip: true },
    {
      prop: 'reviewRemark',
      label: '审核意见',
      minWidth: 160,
      showOverflowTooltip: true
    },
    {
      prop: 'updateTime',
      label: '更新时间',
      width: 165,
      formatter: (row) => formatWithDayjs(row.updateTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 360,
      fixed: 'right',
      formatter: (row) => {
        if (row.auditStatus === 'draft' || row.auditStatus === 'rejected') {
          return (
            <div class="flex items-center">
              <ElButton link type="primary" onClick={() => void openApprovalHistory(row)}>
                审批记录
              </ElButton>
              <ElButton link type="primary" onClick={() => void handleAiAudit(row)}>
                AI 审核
              </ElButton>
              <ElButton link type="primary" onClick={() => void dialogRef.value?.handleOpen(row)}>
                编辑
              </ElButton>
              <ElButton link type="primary" onClick={() => void handleSubmitReview(row)}>
                提交审核
              </ElButton>
              <ElButton link type="danger" onClick={() => void handleDelete(row)}>
                删除
              </ElButton>
            </div>
          )
        }
        if (row.auditStatus === 'pending_review') {
          return (
            <div class="flex items-center">
              <ElButton link type="primary" onClick={() => void openApprovalHistory(row)}>
                审批记录
              </ElButton>
              <ElButton link type="primary" onClick={() => void handleAiAudit(row)}>
                AI 审核
              </ElButton>
              <ElButton link type="success" onClick={() => void handleApprove(row)}>
                审核通过
              </ElButton>
              <ElButton link type="danger" onClick={() => void handleReject(row)}>
                驳回
              </ElButton>
            </div>
          )
        }
        if (row.auditStatus === 'approved') {
          return (
            <div class="flex items-center">
              <ElButton link type="primary" onClick={() => void openApprovalHistory(row)}>
                审批记录
              </ElButton>
              <ElButton link type="primary" onClick={() => void handleAiAudit(row)}>
                AI 复核
              </ElButton>
              <ElButton link type="danger" onClick={() => void handleVoid(row)}>
                作废
              </ElButton>
            </div>
          )
        }
        return (
          <div class="flex items-center">
            <ElButton link type="primary" onClick={() => void openApprovalHistory(row)}>
              审批记录
            </ElButton>
            <ElButton link type="primary" onClick={() => void handleAiAudit(row)}>
              AI 复核
            </ElButton>
          </div>
        )
      }
    }
  ]

  const excelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'waybill.waybillNo', title: '运单号' },
    { key: 'costType', title: '费用类型' },
    { key: 'payeeName', title: '收款方' },
    { key: 'occurredOn', title: '发生日期' },
    { key: 'amount', title: '费用金额' },
    { key: 'reporterNameSnapshot', title: '填报人' },
    { key: 'reporterDepartmentSnapshot', title: '填报人所属部门' },
    { key: 'attachments', title: '图片凭证' },
    { key: 'auditStatus', title: '审核状态' },
    { key: 'remark', title: '费用说明' },
    { key: 'reviewRemark', title: '审核意见' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '登记费用',
      onClick: () => void dialogRef.value?.handleOpen()
    },
    {
      type: 'export',
      exportFilename: 'TMS运单费用',
      exportSheetName: '运单费用',
      exportColumns: excelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportWaybillCostList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchWaybillCostList({ ...params, from, to })
  }

  const handleSaveSuccess = (type: 'add' | 'edit'): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleAiAudit = async (row: WaybillCost): Promise<void> => {
    if (!row.id) return
    await auditDrawerRef.value?.handleOpen({
      costId: row.id,
      waybillNo: row.waybill?.waybillNo || '未编号运单'
    })
  }

  const openApprovalHistory = async (row: WaybillCost): Promise<void> => {
    if (!row.id) return
    await approvalHistoryRef.value?.handleOpen({
      businessType: 'tms_waybill_cost',
      businessId: row.id,
      businessTitle: row.waybill?.waybillNo || '运单费用'
    })
  }

  const handleSubmitReview = async (row: WaybillCost): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction('提交后业务字段将锁定，确定提交审核吗？', '提交审核', {
        type: 'warning',
        confirmButtonText: '提交',
        cancelButtonText: '取消'
      })
      await submitWaybillCost(row.id)
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  const handleApprove = async (row: WaybillCost): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction('审核通过后，该费用会立即计入运单利润。', '审核通过', {
        type: 'success',
        confirmButtonText: '通过',
        cancelButtonText: '取消'
      })
      await reviewWaybillCost({ id: row.id, auditStatus: 'approved' })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  const handleReject = async (row: WaybillCost): Promise<void> => {
    if (!row.id) return
    try {
      const reason = await promptReason('请填写驳回原因', '驳回费用', {
        confirmButtonText: '确认驳回',
        emptyMessage: '驳回原因不能为空',
        placeholder: '请说明费用被驳回的原因'
      })
      await reviewWaybillCost({
        id: row.id,
        auditStatus: 'rejected',
        reviewRemark: reason
      })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  const handleVoid = async (row: WaybillCost): Promise<void> => {
    if (!row.id) return
    try {
      const reason = await promptReason('作废后该费用将从利润中扣除，请填写作废原因', '作废费用', {
        confirmButtonText: '确认作废',
        emptyMessage: '作废原因不能为空',
        placeholder: '请说明费用作废的原因'
      })
      await voidWaybillCost(row.id, reason)
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  const handleDelete = async (row: WaybillCost): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction('仅草稿或已驳回费用可删除，删除后无法恢复。', '删除费用', {
        type: 'warning',
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteWaybillCost(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消时无需提示。
    }
  }
</script>

<style scoped lang="scss">
  :deep(.waybill-cost__evidence) {
    display: flex;
    gap: 4px;
    align-items: center;

    > span {
      font-size: 12px;
      color: var(--art-text-gray-500);
    }
  }

  :deep(.waybill-cost__evidence-image) {
    width: 30px;
    height: 30px;
    overflow: hidden;
    cursor: zoom-in;
    border: 1px solid var(--art-border-dashed-color);
    border-radius: var(--el-border-radius-small);
  }
</style>
