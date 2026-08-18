<template>
  <div class="business-workspace-page art-full-height fms-accounting-page fixed-asset-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="FIXED ASSET LEDGER"
      title="固定资产"
      description="以资产卡片为核心管理类别、转固、使用状态、月度折旧和处置，关键动作自动进入凭证生成队列。"
      icon="ri:building-2-line"
      :tags="[
        { label: '一卡一档', type: 'primary' },
        { label: '月度折旧', type: 'success' },
        { label: '处置留痕', type: 'warning' }
      ]"
      :metrics="metrics"
    />

    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户资产台账；类别、卡片、折旧和处置仅平台超级管理员可维护。"
    />

    <ArtTableQuery
      ref="tableRef"
      v-model="table.search"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 8, labelWidth: 82, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无固定资产',
        emptyDescription: isPlatformSuper
          ? '先建立资产类别，再新增资产卡片。'
          : '当前租户暂无资产卡片。'
      }"
      focusable
    />

    <FixedAssetDialog ref="dialogRef" @success="handleSaved" />
    <AssetCategoryDialog ref="categoryDialogRef" @success="handleCategorySaved" />
    <AssetDepreciationDrawer ref="depreciationRef" @success="refreshAll" />
  </div>
</template>

<script setup lang="tsx">
  import { storeToRefs } from 'pinia'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import { ACCOUNTING_SELECT_EMPTY_TEXT } from '../modules/accounting-select-text'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    actFixedAsset,
    deleteFixedAsset,
    fetchAccountSetOptions,
    fetchAssetCategoryList,
    fetchFixedAssetList,
    fetchFixedAssetSummary
  } from '@/api/fms'
  import FixedAssetDialog from './modules/fixed-asset-dialog.vue'
  import AssetCategoryDialog from './modules/asset-category-dialog.vue'
  import AssetDepreciationDrawer from './modules/asset-depreciation-drawer.vue'

  defineOptions({ name: 'FinanceFixedAsset' })

  type Asset = Api.Fms.FixedAssetRecord
  type SearchParams = Api.Fms.FixedAssetSearchParams
  type TableParams = SearchParams & { current: number; size: number }

  const emptySummary = (): Api.Fms.FixedAssetSummary => ({
    categoryCount: 0,
    assetCount: 0,
    activeCount: 0,
    originalValue: 0,
    netValue: 0,
    periodDepreciation: 0
  })

  const { confirmAction, promptReason } = useArtFeedback()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<{ handleOpen: (row?: Asset) => Promise<void> }>()
  const categoryDialogRef = ref<{ handleOpen: () => Promise<void> }>()
  const depreciationRef = ref<{ handleOpen: (accountSetId?: string) => Promise<void> }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const categoryOptions = ref<Array<{ label: string; value: string }>>([])
  const summary = ref<Api.Fms.FixedAssetSummary>(emptySummary())
  const table = reactive<{ search: SearchParams }>({
    search: { accountSetId: undefined, keyword: '' }
  })

  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'category',
      label: '资产类别',
      value: summary.value.categoryCount,
      description: '启用中的类别',
      icon: 'ri:folder-chart-line',
      tone: 'primary'
    },
    {
      key: 'asset',
      label: '资产卡片',
      value: summary.value.assetCount,
      description: `${summary.value.activeCount} 项使用中`,
      icon: 'ri:building-2-line',
      tone: 'success'
    },
    {
      key: 'original',
      label: '资产原值',
      value: formatCurrencyValue(summary.value.originalValue),
      description: '全部资产口径',
      icon: 'ri:money-cny-box-line',
      tone: 'warning'
    },
    {
      key: 'net',
      label: '资产净值',
      value: formatCurrencyValue(summary.value.netValue),
      description: '扣除累计折旧与减值',
      icon: 'ri:line-chart-line',
      tone: 'info'
    }
  ])

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      props: {
        options: accountSetOptions.value,
        clearable: false,
        filterable: true,
        placeholder: '选择核算账套',
        noDataText: ACCOUNTING_SELECT_EMPTY_TEXT.accountSet
      }
    },
    {
      label: '资产类别',
      key: 'categoryId',
      type: 'select',
      props: {
        options: categoryOptions.value,
        clearable: true,
        placeholder: '全部类别',
        disabled: !table.search.accountSetId,
        noDataText: table.search.accountSetId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.assetCategory
          : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
      }
    },
    {
      label: '资产状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsAssetStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '资产编号、名称或序列号' }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    isPlatformSuper.value
      ? [
          { type: 'add', label: '新建资产', onClick: () => void dialogRef.value?.handleOpen() },
          {
            key: 'category',
            label: '资产类别',
            icon: 'ri:folder-add-line',
            onClick: () => void categoryDialogRef.value?.handleOpen()
          },
          {
            key: 'depreciation',
            label: '折旧管理',
            icon: 'ri:calendar-todo-line',
            onClick: () => void depreciationRef.value?.handleOpen(table.search.accountSetId)
          }
        ]
      : []
  )

  function columnsFactory(): ColumnOption<Asset>[] {
    return [
      { prop: 'assetNo', label: '资产编号', minWidth: 160, fixed: 'left' },
      { prop: 'assetName', label: '资产名称', minWidth: 180, showOverflowTooltip: true },
      {
        prop: 'category',
        label: '资产类别',
        minWidth: 140,
        formatter: (row) => row.category?.categoryName || '--'
      },
      {
        prop: 'originalValue',
        label: '原值',
        minWidth: 130,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.originalValue)
      },
      {
        prop: 'accumulatedDepreciation',
        label: '累计折旧',
        minWidth: 130,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.accumulatedDepreciation)
      },
      {
        prop: 'usefulLifeMonths',
        label: '使用寿命',
        width: 110,
        formatter: (row) => `${row.depreciatedMonths}/${row.usefulLifeMonths} 月`
      },
      {
        prop: 'location',
        label: '存放地点',
        minWidth: 140,
        formatter: (row) => row.location || '--',
        showOverflowTooltip: true
      },
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'fmsAssetStatus', display: 'tag' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: isPlatformSuper.value ? 150 : 70,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            {isPlatformSuper.value && row.status === 'draft' ? (
              <ArtButtonTable type="edit" onClick={() => void dialogRef.value?.handleOpen(row)} />
            ) : null}
            {isPlatformSuper.value && getActionItems(row).length ? (
              <ArtButtonMore
                list={getActionItems(row)}
                onClick={(item: ButtonMoreItem) => void handleAction(item, row)}
              />
            ) : null}
          </div>
        )
      }
    ]
  }

  function getActionItems(row: Asset): ButtonMoreItem[] {
    if (row.status === 'draft')
      return [
        {
          key: 'activate',
          label: '确认转固',
          icon: 'ri:checkbox-circle-line',
          color: 'var(--el-color-success)'
        },
        {
          key: 'delete',
          label: '删除草稿',
          icon: 'ri:delete-bin-line',
          color: 'var(--el-color-danger)'
        }
      ]
    if (row.status === 'active')
      return [
        {
          key: 'suspend',
          label: '暂停折旧',
          icon: 'ri:pause-circle-line',
          color: 'var(--el-color-warning)'
        },
        {
          key: 'dispose',
          label: '资产处置',
          icon: 'ri:delete-bin-6-line',
          color: 'var(--el-color-danger)'
        }
      ]
    if (row.status === 'suspended')
      return [
        {
          key: 'resume',
          label: '恢复使用',
          icon: 'ri:play-circle-line',
          color: 'var(--el-color-success)'
        },
        {
          key: 'dispose',
          label: '资产处置',
          icon: 'ri:delete-bin-6-line',
          color: 'var(--el-color-danger)'
        }
      ]
    return []
  }

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchFixedAssetList({ ...params, from, to })
  }

  async function loadCategories(): Promise<void> {
    if (!table.search.accountSetId) return void (categoryOptions.value = [])
    const { data } = await fetchAssetCategoryList(table.search.accountSetId)
    categoryOptions.value = (data ?? [])
      .filter((item) => item.isEnabled)
      .map((item) => ({ label: `${item.categoryName}（${item.categoryCode}）`, value: item.id }))
  }

  async function loadSummary(): Promise<void> {
    if (!table.search.accountSetId) return void (summary.value = emptySummary())
    const { data } = await fetchFixedAssetSummary(table.search.accountSetId)
    summary.value = data ?? emptySummary()
  }

  async function handleAction(item: ButtonMoreItem, row: Asset): Promise<void> {
    try {
      if (item.key === 'delete') {
        await confirmAction(`确定删除资产草稿“${row.assetName}”吗？`, '删除资产', {
          type: 'warning',
          confirmButtonText: '确认删除'
        })
        await deleteFixedAsset(row.id)
      } else if (item.key === 'dispose') {
        const reason = await promptReason('请填写资产处置原因。', '资产处置', {
          confirmButtonText: '确认处置',
          emptyMessage: '处置原因不能为空'
        })
        await actFixedAsset(row.id, 'dispose', { reason, amount: 0 })
      } else {
        await confirmAction(`确定执行“${item.label}”吗？`, item.label, {
          type: 'warning',
          confirmButtonText: item.label
        })
        await actFixedAsset(row.id, item.key as Api.Fms.FixedAssetAction)
      }
      await refreshAll()
    } catch {
      // 用户取消或业务约束阻止时保持当前列表。
    }
  }

  async function refreshAll(): Promise<void> {
    await Promise.all([tableRef.value?.refreshUpdate(), loadSummary(), loadCategories()])
  }

  async function handleSaved(): Promise<void> {
    await refreshAll()
  }
  async function handleCategorySaved(): Promise<void> {
    await loadCategories()
  }

  watch(
    () => table.search.accountSetId,
    async () => {
      table.search.categoryId = undefined
      await Promise.all([loadCategories(), loadSummary()])
    }
  )

  onMounted(async () => {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    table.search.accountSetId = accountSetOptions.value[0]?.value
    await Promise.all([loadCategories(), loadSummary()])
    await tableRef.value?.getData()
  })
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .fixed-asset-page {
    @include accounting.accounting-workspace-layout;
  }
</style>
