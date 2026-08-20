<template>
  <div class="business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="ADDRESS DIRECTORY"
      title="客户地址簿"
      description="维护客户常用收发货地址、联系人与地址类型，减少重复录入并提升开单效率。"
      icon="ri:map-pin-user-line"
      :tags="[
        { label: '地址资产', type: 'primary' },
        { label: '快速开单', type: 'success' },
        { label: '到离场围栏', type: 'info' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :api-params="tableApiParams"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 82, showExpand: false }"
      :table-props="{
        emptyText: '暂无客户地址',
        emptyDescription: '可新增常用地址，或调整客户、地址类型、时间和关键字后重新查询。'
      }"
      focusable
    />

    <CustomerAddressDialog ref="dialogRef" @success="handleSaveSuccess" />
    <AddressGeofenceDialog ref="geofenceDialogRef" @success="handleGeofenceSuccess" />
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
  import { canEditField, canViewField, type FieldAccessLevel } from '@/utils/field-permission'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteCustomerAddress,
    deleteCustomerAddressBatch,
    fetchCustomerAddressList,
    fetchCustomerOptions
  } from '@/api/tms'
  import CustomerAddressDialog from './modules/customer-address-dialog.vue'
  import AddressGeofenceDialog from './modules/address-geofence-dialog.vue'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'

  defineOptions({ name: 'TmsCustomerAddress' })

  const { confirmAction } = useArtFeedback()

  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type SearchParams = Api.Tms.BasicData.CustomerAddressSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface AddressDialogExpose {
    handleOpen: (
      row?: CustomerAddress,
      context?: { customerId?: string; customerName?: string }
    ) => Promise<void>
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  interface GeofenceDialogExpose {
    handleOpen: (row: CustomerAddress) => Promise<void>
  }

  interface TableState {
    searchQuery: SearchParams
  }

  const route = useRoute()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<AddressDialogExpose>()
  const geofenceDialogRef = ref<GeofenceDialogExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()
  const addressFieldAccess = ref<Api.Tms.BasicData.CustomerAddressFieldAccessMap>({})

  const fieldAccessRank: Record<FieldAccessLevel, number> = {
    hidden: 0,
    masked: 1,
    read: 2,
    edit: 3
  }

  const mergeAddressFieldAccess = (
    baseAccess: Api.Tms.BasicData.CustomerAddressFieldAccessMap,
    records: CustomerAddress[]
  ): Api.Tms.BasicData.CustomerAddressFieldAccessMap => {
    const result = { ...baseAccess }
    records.forEach((record) => {
      Object.entries(record.fieldAccess ?? {}).forEach(([field, access]) => {
        const key = field as Api.Tms.BasicData.CustomerAddressFieldKey
        const current = result[key] ?? 'hidden'
        if (fieldAccessRank[access] > fieldAccessRank[current]) result[key] = access
      })
    })
    return result
  }

  const routeCustomerId = computed(() => String(route.query.customerId ?? ''))
  const customerName = computed(() => String(route.query.customerName ?? ''))
  const addressTypeOptions = computed(() => getDictMap.value.tmsAddressType ?? [])
  const tableApiParams = computed<Partial<TableParams>>(() => ({
    customerId: routeCustomerId.value || undefined
  }))

  const tableState = reactive<TableState>({
    searchQuery: {
      customerId: routeCustomerId.value,
      addressType: undefined,
      createTimeRange: [],
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : '',
      keyword: ''
    }
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '地址类型',
      key: 'addressType',
      type: 'segment',
      span: 24,
      props: {
        options: [
          { label: '全部', value: undefined },
          ...addressTypeOptions.value.map((item) => ({
            label: item.label,
            value: item.value
          }))
        ]
      }
    },
    {
      label: '客户',
      key: 'customerId',
      type: 'select',
      api: fetchCustomerOptions,
      resultField: 'data',
      labelField: 'customerName',
      valueField: 'id',
      labelFn: (option) => {
        const customer = option as CustomerOption
        return customer.customerCode
          ? `${customer.customerName}（${customer.customerCode}）`
          : customer.customerName
      },
      props: {
        clearable: true,
        filterable: true,
        placeholder: '请选择客户名称或编号'
      }
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
      props: { clearable: true, placeholder: '联系人、电话或详细地址' }
    }
  ])

  const columnsFactory = (): ColumnOption<CustomerAddress>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'addressType',
      label: '地址类型',
      width: 120,
      dict: { code: 'tmsAddressType', display: 'tag' }
    },
    {
      prop: 'customerName',
      label: '客户',
      minWidth: 190,
      formatter: (row) => row.customer?.customerName || customerName.value || '-'
    },
    { prop: 'contactName', label: '联系人', width: 120 },
    ...(canViewField(addressFieldAccess.value, 'contactPhone')
      ? [
          {
            prop: 'contactPhone',
            label: '联系电话',
            width: 150,
            formatter: (row: CustomerAddress) => row.contactPhone || '-'
          } satisfies ColumnOption<CustomerAddress>
        ]
      : []),
    ...(canViewField(addressFieldAccess.value, 'addressDetail')
      ? [
          {
            prop: 'fullAddress',
            label: '详细地址',
            minWidth: 300,
            showOverflowTooltip: true,
            formatter: (row: CustomerAddress) =>
              [row.region, row.addressDetail].filter(Boolean).join(' ') || '-'
          } satisfies ColumnOption<CustomerAddress>
        ]
      : []),
    {
      prop: 'isDefault',
      label: '默认',
      width: 90,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.isDefault) }
    },
    {
      prop: 'geofenceEnabled',
      label: '电子围栏',
      width: 140,
      formatter: (row) => (
        <div class="customer-address-page__geofence-cell">
          <span
            class={['customer-address-page__geofence-dot', { 'is-active': row.geofenceEnabled }]}
          />
          <div>
            <strong>{row.geofenceEnabled ? '已启用' : '未启用'}</strong>
            <small>
              {row.geofenceEnabled ? `${row.geofenceRadiusM ?? '-'} 米` : '不参与定位校验'}
            </small>
          </div>
        </div>
      )
    },
    { prop: 'remark', label: '备注', minWidth: 150, showOverflowTooltip: true },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 164,
      fixed: 'right',
      formatter: (row) => (
        <div class="customer-address-page__operation">
          {canEditField(row.fieldAccess, 'addressDetail') ? (
            <ArtButtonTable
              icon="ri:radar-line"
              permission="TmsCustomerAddress:Geofence"
              label={row.geofenceEnabled ? '查看或修改围栏' : '设置围栏'}
              onClick={() => void geofenceDialogRef.value?.handleOpen(row)}
            />
          ) : null}
          <ArtButtonTable
            type="edit"
            permission="TmsCustomerAddress:Edit"
            onClick={() => openDialog(row)}
          />
          <ArtButtonTable
            type="delete"
            permission="TmsCustomerAddress:Delete"
            onClick={() => handleDelete(row)}
          />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { permission: 'TmsCustomerAddress:Add', type: 'add', onClick: () => openDialog() },
    {
      permission: 'TmsCustomerAddress:Delete',
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 条地址吗？`,
      onClick: async ({ selectedRows }) => {
        const rows = selectedRows as CustomerAddress[]
        if (await inspectDeleteDependencies(rows)) return
        await deleteCustomerAddressBatch(rows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = async (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchCustomerAddressList({
      ...params,
      from,
      to
    })
    addressFieldAccess.value = mergeAddressFieldAccess(result.fieldAccess, result.data ?? [])
    return result
  }

  const openDialog = (row?: CustomerAddress): void => {
    void dialogRef.value?.handleOpen(row, {
      customerId: tableState.searchQuery.customerId ?? undefined,
      customerName: customerName.value ?? undefined
    })
  }

  watch(routeCustomerId, async (value) => {
    tableState.searchQuery.customerId = value
    await nextTick()
    await tableQueryRef.value?.getData()
  })

  watch(
    () => tableState.searchQuery.addressType,
    async () => {
      await nextTick()
      await tableQueryRef.value?.getData()
    },
    { flush: 'post' }
  )

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleGeofenceSuccess = (): void => {
    void tableQueryRef.value?.refreshUpdate()
  }

  const inspectDeleteDependencies = async (rows: CustomerAddress[]): Promise<boolean> => {
    const resources = rows
      .filter((item) => item.id)
      .map((item) => ({
        id: String(item.id),
        label: [item.region, item.addressDetail].filter(Boolean).join(' ') || '未命名地址'
      }))
    if (!resources.length) return false
    return (
      (await deleteGuardRef.value?.inspect({
        resourceType: 'customer_address',
        resourceLabel: '客户地址',
        resources
      })) ?? false
    )
  }

  const handleDeleteGuardCleared = (): void => {
    void tableQueryRef.value?.getData()
  }

  const syncMasterDeleteReturn = (forceRefresh = false): void => {
    if (route.query.resumeMasterDelete !== '1') return
    const recordId = typeof route.query.recordId === 'string' ? route.query.recordId : ''
    const changed = tableState.searchQuery.recordId !== recordId
    Object.assign(tableState.searchQuery, { recordId, keyword: '' })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }

  watch(
    () => route.fullPath,
    () => syncMasterDeleteReturn(),
    { flush: 'post' }
  )
  onActivated(() => syncMasterDeleteReturn(true))

  const handleDelete = async (row: CustomerAddress): Promise<void> => {
    if (!row.id) return
    try {
      if (await inspectDeleteDependencies([row])) return
      await confirmAction(
        `确定删除“${[row.region, row.addressDetail].filter(Boolean).join(' ')}”吗？`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteCustomerAddress(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>

<style scoped lang="scss">
  .customer-address-page {
    &__operation {
      display: inline-flex;
      gap: 8px;
      align-items: center;

      :deep(.art-button-table) {
        margin-right: 0;
      }
    }

    &__geofence-cell {
      display: flex;
      gap: 9px;
      align-items: center;
      min-width: 0;

      > div {
        display: grid;
        min-width: 0;
      }

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 13px;
        color: var(--el-text-color-primary);
      }

      small {
        color: var(--el-text-color-secondary);
      }
    }

    &__geofence-dot {
      flex: 0 0 8px;
      width: 8px;
      height: 8px;
      background: var(--el-color-info-light-5);
      border-radius: 50%;

      &.is-active {
        background: var(--el-color-success);
        box-shadow: 0 0 0 4px var(--el-color-success-light-9);
      }
    }
  }
</style>
