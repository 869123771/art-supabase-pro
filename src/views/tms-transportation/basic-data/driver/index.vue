<template>
  <div class="tms-workspace-page art-full-height">
    <CustomerDeleteProcessingNotice
      v-if="deleteContext.active"
      :customer-id="deleteContext.customerId"
      :customer-name="deleteContext.customerName"
      action-hint="已自动定位关联司机；请先调整归属或处理司机资料。"
    />
    <TmsWorkspaceHeader
      eyebrow="DRIVER ROSTER"
      title="司机资料"
      description="统一维护司机归属、从业类型、证照与可用状态，为车辆调度提供清晰的人力视图。"
      icon="ri:steering-2-line"
      :tags="[
        { label: '司机名册', type: 'primary' },
        { label: '调度可用', type: 'success' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :immediate="tableImmediate"
      :table-props="{
        emptyText: '暂无司机资料',
        emptyDescription: '可新增司机，或调整承运商、司机类型、状态和关键字后重新查询。'
      }"
      focusable
    />

    <DriverDialog ref="dialogRef" @success="handleSaveSuccess" />
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleDeleteGuardCleared" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import { RouterLink } from 'vue-router'
  import {
    deleteDriver,
    deleteDriverBatch,
    fetchCarrierDetail,
    fetchCarrierOptions,
    fetchDriverList
  } from '@/api/tms'
  import DriverDialog from './modules/driver-dialog.vue'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'
  import CustomerDeleteProcessingNotice from '@/views/tms-transportation/modules/customer-delete-processing-notice.vue'
  import { useCustomerDeleteProcessingContext } from '@/views/tms-transportation/modules/use-customer-delete-processing'

  defineOptions({ name: 'TmsDriver' })

  const { confirmAction } = useArtFeedback()

  type Driver = Api.Tms.BasicData.Driver
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type SearchParams = Api.Tms.BasicData.DriverSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DriverDialogExpose {
    handleOpen: (row?: Driver) => Promise<void>
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const route = useRoute()
  const deleteContext = useCustomerDeleteProcessingContext()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DriverDialogExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()
  const initialCarrierId = String(route.query.carrierId || '')
  const initialRecordId = String(route.query.recordId || '')
  const tableImmediate = !initialCarrierId && !initialRecordId

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      carrierId: initialCarrierId,
      recordId: initialRecordId,
      driverType: undefined,
      gender: '',
      enabled: undefined,
      createTimeRange: [],
      keyword: ''
    }
  })

  onMounted(async () => {
    if (!initialCarrierId && !initialRecordId) return
    await nextTick()
    await tableQueryRef.value?.getData()
  })

  watch(
    () => route.fullPath,
    async () => {
      const carrierId = String(route.query.carrierId || '')
      const recordId = String(route.query.recordId || '')
      if (
        tableState.searchQuery.carrierId === carrierId &&
        tableState.searchQuery.recordId === recordId
      ) {
        return
      }
      Object.assign(tableState.searchQuery, { carrierId, recordId, keyword: '' })
      await nextTick()
      await tableQueryRef.value?.getData()
    },
    { flush: 'post' }
  )

  onActivated(() => void tableQueryRef.value?.getData())

  const genderOptions = computed(() => getDictMap.value.sex ?? [])
  const driverTypeOptions = computed(() => getDictMap.value.tmsDriverType ?? [])
  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const withSelectedCarrierOption = async (result: unknown) => {
    const carrierResult = result as Awaited<ReturnType<typeof fetchCarrierOptions>>
    const selectedCarrierId = tableState.searchQuery.carrierId
    const options = carrierResult.data ?? []

    if (!selectedCarrierId || options.some((option) => option.id === selectedCarrierId)) {
      return carrierResult
    }

    const detailResult = await fetchCarrierDetail(selectedCarrierId)
    const carrier = detailResult.data
    if (!carrier?.id) return carrierResult

    return {
      ...carrierResult,
      data: [carrier as CarrierOption, ...options]
    }
  }

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '所属承运商',
      key: 'carrierId',
      type: 'select',
      api: fetchCarrierOptions,
      afterFetch: withSelectedCarrierOption,
      resultField: 'data',
      labelField: 'companyName',
      valueField: 'id',
      labelFn: (option) => {
        const carrier = option as CarrierOption
        return carrier.carrierCode
          ? `${carrier.companyName}（${carrier.carrierCode}）`
          : carrier.companyName
      },
      props: {
        clearable: true,
        filterable: true,
        placeholder: '请选择承运商'
      }
    },
    {
      label: '性别',
      key: 'gender',
      type: 'select',
      props: { options: genderOptions.value, clearable: true }
    },
    {
      label: '司机类型',
      key: 'driverType',
      type: 'select',
      props: { options: driverTypeOptions.value, clearable: true }
    },
    {
      label: '状态',
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
      props: {
        clearable: true,
        placeholder: '姓名、手机号、身份证号或家庭住址'
      }
    }
  ])

  const columnsFactory = (): ColumnOption<Driver>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'driverName',
      label: '姓名',
      minWidth: 120,
      showOverflowTooltip: true
    },
    {
      prop: 'carrierName',
      label: '所属承运商',
      minWidth: 210,
      showOverflowTooltip: true,
      formatter: (row) => row.carrier?.companyName || '-'
    },
    {
      prop: 'driverType',
      label: '司机类型',
      width: 100,
      dict: { code: 'tmsDriverType', display: 'tag' }
    },
    {
      prop: 'assignedVehicles',
      label: '车牌号',
      minWidth: 240,
      formatter: (row) => renderAssignedVehicles(row)
    },
    { prop: 'phone', label: '手机号码', width: 150 },
    {
      prop: 'gender',
      label: '性别',
      width: 90,
      dict: { code: 'sex', display: 'text' }
    },
    {
      prop: 'licenseType',
      label: '驾照类型',
      width: 100,
      dict: { code: 'tmsDriverLicenseType', display: 'text' }
    },
    {
      prop: 'licenseExpireDate',
      label: '驾照日期',
      width: 130,
      formatter: (row) => row.licenseExpireDate || '-'
    },
    {
      prop: 'homeAddress',
      label: '家庭住址',
      minWidth: 260,
      showOverflowTooltip: true,
      formatter: (row) => row.homeAddress || '-'
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 90,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.enabled) }
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
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

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', onClick: () => openDialog() },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 个司机吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const rows = selectedRows as Driver[]
        if (await inspectDeleteDependencies(rows)) return
        await deleteDriverBatch(rows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchDriverList({ ...params, from, to })
  }

  const renderAssignedVehicles = (row: Driver) => {
    const vehicles = row.assignedVehicles ?? []
    if (!vehicles.length) return <span class="tms-driver__vehicle-empty">-</span>

    return (
      <div
        class="tms-driver__vehicle-links"
        title={vehicles
          .map((vehicle) => vehicle.plateNo)
          .filter(Boolean)
          .join('、')}
      >
        {vehicles.map((vehicle) => (
          <RouterLink
            key={vehicle.id}
            class="tms-driver__vehicle-link"
            to={{
              path: `/vehicle-manage-system/vehicle-archive-detail/${vehicle.id}`
            }}
            title={`查看车辆 ${vehicle.plateNo} 详情`}
          >
            {vehicle.plateNo}
          </RouterLink>
        ))}
      </div>
    )
  }

  const openDialog = (row?: Driver): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const inspectDeleteDependencies = async (rows: Driver[]): Promise<boolean> => {
    const resources = rows
      .filter((item) => item.id)
      .map((item) => ({ id: String(item.id), label: item.driverName }))
    if (!resources.length) return false
    return (
      (await deleteGuardRef.value?.inspect({
        resourceType: 'driver',
        resourceLabel: '司机',
        resources
      })) ?? false
    )
  }

  const handleDeleteGuardCleared = (): void => {
    void tableQueryRef.value?.getData()
  }

  const handleDelete = async (row: Driver): Promise<void> => {
    if (!row.id) return
    try {
      if (await inspectDeleteDependencies([row])) return
      await confirmAction(`确定删除司机“${row.driverName}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteDriver(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示
    }
  }
</script>

<style lang="scss">
  .tms-driver {
    &__vehicle-links {
      display: flex;
      gap: 4px;
      align-items: center;
      min-width: 0;
      padding: 4px 0;
      overflow: hidden;
      white-space: nowrap;
    }

    &__vehicle-link {
      flex: none;
      max-width: 112px;
      padding: 1px 3px;
      overflow: hidden;
      text-overflow: ellipsis;
      font-weight: 700;
      line-height: 20px;
      color: var(--el-color-primary);
      white-space: nowrap;
      text-decoration: none;
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--el-border-radius-small);

      &:hover {
        color: var(--el-color-primary-dark-2);
        background: var(--el-color-primary-light-8);
        border-color: var(--el-color-primary-light-5);
      }

      &:focus-visible {
        outline: 2px solid var(--el-color-primary);
        outline-offset: 2px;
        border-radius: var(--el-border-radius-small);
      }
    }

    &__vehicle-empty {
      color: var(--el-text-color-placeholder);
    }
  }
</style>
