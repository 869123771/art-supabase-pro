<template>
  <div class="business-workspace-page art-full-height fms-accounting-page voucher-template-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="VOUCHER STANDARDIZATION"
      title="凭证模板"
      description="沉淀高频经济业务的科目、借贷方向和核算维度，套用后仍须核对、审核并过账。"
      icon="ri:file-copy-2-line"
      :tags="[
        { label: '标准分录', type: 'primary' },
        { label: '快速制单', type: 'success' },
        { label: '不绕过审核', type: 'info' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户凭证模板；新增、编辑和删除模板仅平台超级管理员可执行。"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="table.headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 88, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无凭证模板',
        emptyDescription: '为当前账套新增常用凭证模板，统一会计处理口径。'
      }"
      focusable
    />

    <VoucherTemplateDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElTag } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import { useUserStore } from '@/store/modules/user'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import {
    deleteVoucherTemplate,
    fetchAccountSetOptions,
    fetchAuxiliaryItemList,
    fetchCurrencyList,
    fetchSubjectList,
    fetchVoucherTemplateList
  } from '@/api/fms'
  import VoucherTemplateDialog from './modules/voucher-template-dialog.vue'

  defineOptions({ name: 'FinanceVoucherTemplate' })

  type Template = Api.Fms.VoucherTemplateRecord
  type SearchParams = Api.Fms.VoucherTemplateSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogContext {
    accountSet: Api.Fms.AccountSetOption
    subjects: Api.Fms.SubjectRecord[]
    currencies: Api.Fms.CurrencyRecord[]
    auxiliaryItems: Api.Fms.AuxiliaryItemRecord[]
  }

  interface DialogExpose {
    handleOpen: (context: DialogContext, row?: Template) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    accountSetOptions: Api.Fms.AccountSetOption[]
  }

  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const { confirmDelete } = useArtFeedback()
  const { ensureAccountSet } = useFinanceAccountSetPrerequisite()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const entryContext = shallowRef<DialogContext>()

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      accountSetId: '',
      voucherType: '',
      isEnabled: '',
      keyword: ''
    },
    accountSetOptions: [],
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '账套',
        key: 'accountSetId',
        type: 'select',
        props: {
          options: table.accountSetOptions,
          filterable: true,
          clearable: true,
          placeholder: '全部可查看账套',
          onChange: () => {
            entryContext.value = undefined
          }
        }
      },
      {
        label: '凭证类型',
        key: 'voucherType',
        type: 'select',
        props: {
          options: (getDictMap.value.fmsVoucherType ?? []).filter(
            (item) => item.value !== 'reversal'
          ),
          clearable: true
        }
      },
      {
        label: '启用状态',
        key: 'isEnabled',
        type: 'select',
        props: {
          options: (getDictMap.value.commonBoolean ?? []).map((item) => ({
            ...item,
            value: item.value === 'true'
          })),
          clearable: true
        }
      },
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '模板编码、名称或摘要' }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() =>
      isPlatformSuper.value
        ? [
            {
              type: 'add',
              label: '新增模板',
              onClick: () => void openDialog()
            }
          ]
        : []
    )
  })

  const columnsFactory = (): ColumnOption<Template>[] => [
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'templateCode',
      label: '模板编码',
      width: 180,
      formatter: (row) => <span class="voucher-template-page__code">{row.templateCode}</span>
    },
    { prop: 'templateName', label: '模板名称', minWidth: 210, showOverflowTooltip: true },
    {
      prop: 'voucherType',
      label: '凭证类型',
      width: 120,
      dict: { code: 'fmsVoucherType', display: 'text' }
    },
    { prop: 'summary', label: '默认摘要', minWidth: 230, showOverflowTooltip: true },
    { prop: 'sort', label: '排序', width: 80, align: 'center' },
    {
      prop: 'isEnabled',
      label: '状态',
      width: 90,
      formatter: (row) => (
        <ElTag type={row.isEnabled ? 'success' : 'info'}>{row.isEnabled ? '启用' : '停用'}</ElTag>
      )
    },
    { prop: 'updateBy', label: '最后维护人', minWidth: 150, showOverflowTooltip: true },
    {
      prop: 'operation',
      label: '操作',
      width: 140,
      fixed: 'right',
      formatter: (row) =>
        isPlatformSuper.value ? (
          <div class="voucher-template-page__actions">
            <ElButton link type="primary" onClick={() => void openDialog(row)}>
              编辑
            </ElButton>
            <ElButton link type="danger" onClick={() => void handleDelete(row)}>
              删除
            </ElButton>
          </div>
        ) : (
          <span>只读</span>
        )
    }
  ]

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchVoucherTemplateList({ ...params, from, to })
  }

  async function loadEntryContext(): Promise<DialogContext | undefined> {
    const accountSet = table.accountSetOptions.find(
      (item) => item.value === table.searchQuery.accountSetId
    )
    if (!accountSet) return undefined
    if (entryContext.value?.accountSet.value === accountSet.value) return entryContext.value
    const [subjectResult, currencyResult, auxiliaryResult] = await Promise.all([
      fetchSubjectList(accountSet.value),
      fetchCurrencyList(accountSet.value),
      fetchAuxiliaryItemList(accountSet.value)
    ])
    entryContext.value = {
      accountSet,
      subjects: subjectResult.data ?? [],
      currencies: currencyResult.data ?? [],
      auxiliaryItems: auxiliaryResult.data ?? []
    }
    return entryContext.value
  }

  async function openDialog(row?: Template): Promise<void> {
    if (
      !(await ensureAccountSet({
        actionLabel: row ? '编辑凭证模板' : '新增凭证模板',
        available: Boolean(row?.accountSetId || table.searchQuery.accountSetId)
      }))
    )
      return
    const context = await loadEntryContext()
    if (context) await dialogRef.value?.handleOpen(context, row)
  }

  async function handleDelete(row: Template): Promise<void> {
    try {
      await confirmDelete(`确定删除凭证模板 ${row.templateCode} · ${row.templateName} 吗？`)
      await deleteVoucherTemplate(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  function handleSaveSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  async function loadAccountSets(): Promise<void> {
    const { data } = await fetchAccountSetOptions({ from: 0, to: 999 })
    table.accountSetOptions = data ?? []
    if (!table.searchQuery.accountSetId && table.accountSetOptions.length) {
      table.searchQuery.accountSetId = table.accountSetOptions[0].value
      await nextTick()
      await tableQueryRef.value?.getData()
    }
  }

  onMounted(() => void loadAccountSets())
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .voucher-template-page {
    @include accounting.accounting-workspace-layout;

    &__code {
      font-weight: 600;
      font-variant-numeric: tabular-nums;
      color: var(--el-color-primary);
    }

    &__actions {
      display: flex;
      align-items: center;
    }
  }
</style>
