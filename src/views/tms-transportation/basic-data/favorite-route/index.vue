<template>
  <div class="tms-workspace-page favorite-route-page art-full-height">
    <TmsWorkspaceHeader
      eyebrow="ROUTE LIBRARY"
      title="常用线路"
      description="沉淀客户高频装卸路线，统一地址、里程与计划时长口径，为开单、报价和调度提供可复用线路资产。"
      icon="ri:route-line"
      :tags="[
        { label: '线路资产', type: 'primary' },
        { label: '地址簿联动', type: 'success' },
        { label: '快速开单', type: 'info' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 8, labelWidth: 82, showExpand: false }"
      :table-props="{
        emptyText: '暂无常用线路',
        emptyDescription: '新增一条高频装卸线路，后续开单、报价与调度可直接复用。'
      }"
      focusable
    />

    <FavoriteRouteDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    deleteFavoriteRoute,
    deleteFavoriteRouteBatch,
    fetchCustomerOptions,
    fetchFavoriteRouteList
  } from '@/api/tms'
  import FavoriteRouteDialog from './modules/favorite-route-dialog.vue'

  defineOptions({ name: 'TmsFavoriteRoute' })

  type FavoriteRoute = Api.Tms.BasicData.FavoriteRoute
  type FavoriteRouteSearchParams = Api.Tms.BasicData.FavoriteRouteSearchParams
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type TableParams = FavoriteRouteSearchParams &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableGroup {
    searchQuery: FavoriteRouteSearchParams
  }

  interface DialogExpose {
    handleOpen: (row?: FavoriteRoute) => Promise<void>
  }

  const { confirmAction } = useArtFeedback()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const table = reactive<TableGroup>({ searchQuery: { keyword: '', customerId: undefined } })

  const searchItems: SearchFormItem[] = [
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '线路名称或备注' }
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
      props: { filterable: true, clearable: true, placeholder: '请选择客户' }
    },
    {
      label: '线路状态',
      key: 'enabled',
      type: 'segment',
      props: {
        options: [
          { label: '全部', value: undefined },
          { label: '启用', value: true },
          { label: '停用', value: false }
        ]
      }
    }
  ]

  const getFullAddress = (address?: Api.Tms.BasicData.CustomerAddress | null): string =>
    [address?.region, address?.addressDetail].filter(Boolean).join(' ') || '-'

  const formatDuration = (minutes?: number | null): string => {
    if (!minutes) return '-'
    const hours = Math.floor(minutes / 60)
    const remainder = minutes % 60
    if (!hours) return `${remainder} 分钟`
    return remainder ? `${hours} 小时 ${remainder} 分钟` : `${hours} 小时`
  }

  const columnsFactory = (): ColumnOption<FavoriteRoute>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'routeName',
      label: '线路名称',
      minWidth: 190,
      formatter: (row) => (
        <div class="favorite-route-page__route-name">
          <span>
            <ArtSvgIcon icon="ri:route-line" />
          </span>
          <div>
            <strong title={row.routeName}>{row.routeName}</strong>
            <small>{row.customer?.customerName || '未关联客户'}</small>
          </div>
        </div>
      )
    },
    {
      prop: 'routeEndpoints',
      label: '装卸线路',
      minWidth: 360,
      formatter: (row) => (
        <div class="favorite-route-page__endpoints">
          <div>
            <span class="is-origin">装</span>
            <strong title={getFullAddress(row.originAddress)}>
              {getFullAddress(row.originAddress)}
            </strong>
          </div>
          <i aria-hidden="true" />
          <div>
            <span class="is-destination">卸</span>
            <strong title={getFullAddress(row.destinationAddress)}>
              {getFullAddress(row.destinationAddress)}
            </strong>
          </div>
        </div>
      )
    },
    {
      prop: 'distanceKm',
      label: '参考里程',
      width: 120,
      formatter: (row) => (row.distanceKm ? `${Number(row.distanceKm).toFixed(2)} km` : '-')
    },
    {
      prop: 'estimatedMinutes',
      label: '预计时长',
      width: 140,
      formatter: (row) => formatDuration(row.estimatedMinutes)
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 90,
      formatter: (row) => (
        <ArtDictDisplay dictCode="commonBoolean" value={String(row.enabled)} display="tag" />
      )
    },
    {
      prop: 'updateTime',
      label: '最近更新',
      width: 168,
      formatter: (row) => formatWithDayjs(row.updateTime, 'YYYY-MM-DD HH:mm') || '-'
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="favorite-route-page__operation">
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonTable type="delete" onClick={() => void handleDelete(row)} />
        </div>
      )
    }
  ]

  const headerActions: ArtTableQueryHeaderAction[] = [
    { type: 'add', label: '新增线路', onClick: () => openDialog() },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 条常用线路吗？`,
      onClick: async ({ selectedRows }) => {
        const ids = (selectedRows as FavoriteRoute[])
          .map((row) => String(row.id ?? ''))
          .filter(Boolean)
        if (!ids.length) {
          ElMessage.warning('请选择要删除的线路')
          return
        }
        await deleteFavoriteRouteBatch(ids)
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchFavoriteRouteList({ ...params, from, to })
  }

  const openDialog = (row?: FavoriteRoute): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: FavoriteRoute): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除常用线路“${row.routeName}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteFavoriteRoute(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>

<style scoped lang="scss">
  .favorite-route-page {
    :deep(.favorite-route-page__route-name) {
      display: flex;
      gap: 10px;
      align-items: center;
      min-width: 0;

      > span {
        display: grid;
        flex: 0 0 34px;
        place-items: center;
        width: 34px;
        height: 34px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

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

      small {
        margin-top: 2px;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.favorite-route-page__endpoints) {
      display: grid;
      grid-template-columns: minmax(0, 1fr);
      gap: 4px;
      min-width: 0;

      > div {
        display: flex;
        gap: 8px;
        align-items: center;
        min-width: 0;

        span {
          display: grid;
          flex: 0 0 22px;
          place-items: center;
          width: 22px;
          height: 22px;
          font-size: 11px;
          font-weight: 700;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 50%;

          &.is-destination {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }
        }

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 500;
          white-space: nowrap;
        }
      }

      > i {
        width: 1px;
        height: 6px;
        margin-left: 10px;
        background: var(--el-border-color);
      }
    }

    :deep(.favorite-route-page__operation) {
      display: inline-flex;
      gap: 8px;
      align-items: center;

      .art-button-table {
        margin-right: 0;
      }
    }
  }
</style>
