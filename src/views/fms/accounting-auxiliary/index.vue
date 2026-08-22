<template>
  <div
    class="business-workspace-page art-full-height fms-accounting-page accounting-auxiliary-page"
    :class="{ 'is-focus-mode': focusMode }"
  >
    <BusinessWorkspaceHeader
      v-show="!focusMode"
      density="compact"
      eyebrow="财务基础 · 核算维度"
      title="辅助核算"
      description="统一客户、承运商、部门、员工、项目等核算维度，并与现有业务主数据保持同源。"
      icon="ri:git-branch-line"
      :tags="[
        { label: '业务主数据同步', type: 'primary' },
        { label: '租户账套隔离', type: 'success' },
        { label: '维度停用留痕', type: 'info' }
      ]"
      :metrics="metrics"
    >
      <template #actions>
        <BusinessWorkspaceFocusToggle v-model="focusMode" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtPageSection
      v-show="!focusMode"
      title="核算范围"
      subtitle="客户、承运商、部门和员工以现有业务档案为权威来源"
      class="accounting-workspace-scope-section"
    >
      <div class="accounting-auxiliary-page__scope">
        <span>当前账套</span>
        <ElSelect
          v-model="scope.accountSetId"
          aria-label="当前账套"
          filterable
          :loading="scope.loading"
          placeholder="请选择账套"
          @change="handleAccountSetChange"
        >
          <ElOption
            v-for="item in scope.options"
            :key="item.value"
            :label="item.label"
            :value="item.value"
          />
        </ElSelect>
      </div>
      <AccountingSetupGuide
        :loading="scope.loading"
        :has-account-set="scope.options.length > 0"
        :can-configure="hasAuth('FinanceAccountSet:Add')"
        @configure="goToAccountSet"
      />
    </ArtPageSection>

    <div class="accounting-auxiliary-page__workspace" :class="{ 'is-focused': focusMode }">
      <ArtPageSection
        title="核算维度"
        subtitle="选择维度后查看其核算项目"
        class="accounting-auxiliary-page__types accounting-workspace-fill-section"
      >
        <template #actions>
          <ElButton
            v-auth="'FinanceAccountingAuxiliary:AddType'"
            type="primary"
            @click="openTypeDialog()"
          >
            <ArtSvgIcon icon="ri:add-line" />新增维度
          </ElButton>
        </template>

        <ArtAsyncState
          class="accounting-workspace-content-state"
          :class="{ 'is-empty': workspace.types.length === 0 }"
          :loading="workspace.loading"
          :empty-image-size="68"
          :min-height="150"
          :error="workspace.error"
          :empty="workspace.types.length === 0"
          empty-text="暂无辅助核算维度"
          empty-description="创建账套时会自动生成客户、承运商、部门、员工和项目维度。"
          @retry="loadWorkspace"
        >
          <ElScrollbar class="accounting-auxiliary-page__type-scrollbar">
            <div class="accounting-auxiliary-page__type-list">
              <div
                v-for="item in workspace.types"
                :key="item.id"
                class="accounting-auxiliary-page__type-card"
                :class="{ 'is-active': item.id === workspace.selectedTypeId }"
              >
                <button
                  type="button"
                  class="accounting-auxiliary-page__type-select"
                  :aria-label="`选择核算维度${item.typeName}`"
                  :aria-pressed="item.id === workspace.selectedTypeId"
                  @click="selectType(item.id)"
                >
                  <span class="accounting-auxiliary-page__type-icon">
                    <ArtSvgIcon :icon="sourceIcon(item.sourceType)" />
                  </span>
                  <span class="accounting-auxiliary-page__type-content">
                    <strong>{{ item.typeName }}</strong>
                    <small>{{ item.typeCode }}</small>
                  </span>
                  <span class="accounting-auxiliary-page__type-meta">
                    <span
                      v-if="item.id === workspace.selectedTypeId"
                      class="accounting-auxiliary-page__selected-badge"
                    >
                      <ArtSvgIcon icon="ri:check-line" />已选
                    </span>
                    <ArtDictDisplay
                      v-else
                      dict-code="fmsAuxiliarySourceType"
                      :value="item.sourceType"
                      display="text"
                    />
                    <ElTag size="small" :type="item.isEnabled ? 'success' : 'info'">
                      {{ item.isEnabled ? '启用' : '停用' }}
                    </ElTag>
                  </span>
                </button>
                <ArtButtonMore
                  class="accounting-auxiliary-page__type-more"
                  :list="getTypeActions(item)"
                  @click="handleTypeAction($event, item)"
                />
              </div>
            </div>
          </ElScrollbar>
        </ArtAsyncState>
      </ArtPageSection>

      <ArtPageSection
        title="核算项目"
        :subtitle="
          selectedType ? `${selectedType.typeName} · ${sourceDescription}` : '请先选择核算维度'
        "
        class="accounting-auxiliary-page__items accounting-workspace-fill-section"
      >
        <template #actions>
          <BusinessWorkspaceFocusToggle v-if="focusMode" v-model="focusMode" />
          <ElButton
            v-if="hasAuth('FinanceAccountingAuxiliary:Sync') && canSync"
            :loading="workspace.syncing"
            @click="handleSync"
          >
            <ArtSvgIcon icon="ri:refresh-line" />同步主数据
          </ElButton>
          <ElButton
            v-if="hasAuth('FinanceAccountingAuxiliary:Add') && canMaintainItems"
            type="primary"
            @click="openItemDialog()"
          >
            <ArtSvgIcon icon="ri:add-line" />新增项目
          </ElButton>
        </template>

        <ArtSearchBar
          v-model="itemFilterForm"
          class="accounting-auxiliary-page__item-search"
          :items="itemSearchItems"
          :span="8"
          :gutter="12"
          label-position="left"
          label-width="76px"
          :show-expand="false"
          :button-left-limit="0"
          @search="applyItemFilters"
          @reset="resetItemFilters"
        />

        <ArtAsyncState
          class="accounting-workspace-content-state"
          :class="{ 'is-empty': filteredItems.length === 0 }"
          :loading="workspace.itemLoading"
          :empty-image-size="72"
          :min-height="160"
          :error="workspace.itemError"
          :empty="filteredItems.length === 0"
          empty-text="暂无辅助核算项目"
          :empty-description="
            canSync ? '点击“同步主数据”从现有业务档案生成核算项目。' : '可新增手工核算项目。'
          "
          @retry="loadItems"
        >
          <ArtTable
            :data="filteredItems"
            :columns="columns"
            :pagination="false"
            table-layout="fixed"
            empty-text="暂无辅助核算项目"
          />
        </ArtAsyncState>
      </ArtPageSection>
    </div>

    <AuxiliaryTypeDialog ref="typeDialogRef" @success="loadWorkspace" />
    <AuxiliaryItemDialog ref="itemDialogRef" @success="loadItems" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElTag } from 'element-plus'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import AccountingSetupGuide from '../modules/accounting-setup-guide.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtSearchBar, {
    type SearchFormItem
  } from '@/components/core/forms/art-search-bar/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import type { ColumnOption } from '@/types'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import {
    deleteAuxiliaryType,
    fetchAccountSetOptions,
    fetchAuxiliaryItemList,
    fetchAuxiliaryTypeList,
    setAuxiliaryItemEnabled,
    syncAuxiliaryItems
  } from '@/api/fms'
  import BusinessWorkspaceFocusToggle from '@/components/business/business-workspace-focus-toggle/index.vue'
  import { useWorkspaceFocus } from '@/hooks/core/useWorkspaceFocus'
  import AuxiliaryTypeDialog from './modules/auxiliary-type-dialog.vue'
  import AuxiliaryItemDialog from './modules/auxiliary-item-dialog.vue'

  defineOptions({ name: 'FinanceAccountingAuxiliary' })

  type AuxiliaryType = Api.Fms.AuxiliaryTypeRecord
  type AuxiliaryItem = Api.Fms.AuxiliaryItemRecord

  interface ScopeGroup {
    accountSetId: string
    loading: boolean
    options: Api.Fms.AccountSetOption[]
  }

  interface WorkspaceGroup {
    loading: boolean
    error: string
    types: AuxiliaryType[]
    selectedTypeId: string
    itemLoading: boolean
    itemError: string
    items: AuxiliaryItem[]
    syncing: boolean
  }

  interface ItemFilter extends Record<string, unknown> {
    keyword: string
    enabled?: boolean
  }

  interface AuxiliaryTypeDialogExpose {
    handleOpen: (accountSet: Api.Fms.AccountSetOption, row?: AuxiliaryType) => Promise<void>
  }

  interface AuxiliaryItemDialogExpose {
    handleOpen: (
      accountSet: Api.Fms.AccountSetOption,
      type: AuxiliaryType,
      row?: AuxiliaryItem
    ) => Promise<void>
  }

  const { confirmAction } = useArtFeedback()
  const { focusMode } = useWorkspaceFocus()
  const { ensureAccountSet, goToAccountSet } = useFinanceAccountSetPrerequisite()
  const { hasAuth } = useAuth()
  const typeDialogRef = ref<AuxiliaryTypeDialogExpose>()
  const itemDialogRef = ref<AuxiliaryItemDialogExpose>()
  const scope = reactive<ScopeGroup>({ accountSetId: '', loading: true, options: [] })
  const workspace = reactive<WorkspaceGroup>({
    loading: false,
    error: '',
    types: [],
    selectedTypeId: '',
    itemLoading: false,
    itemError: '',
    items: [],
    syncing: false
  })
  const itemFilterForm = ref<ItemFilter>(createDefaultItemFilter())
  const appliedItemFilter = reactive<ItemFilter>(createDefaultItemFilter())
  const itemSearchItems: SearchFormItem[] = [
    {
      label: '核算项目',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '搜索项目编码或名称' }
    },
    {
      label: '项目状态',
      key: 'enabled',
      type: 'select',
      props: {
        clearable: true,
        placeholder: '全部状态',
        options: [
          { label: '启用', value: true },
          { label: '停用', value: false }
        ]
      }
    }
  ]

  const currentAccountSet = computed(() =>
    scope.options.find((item) => item.value === scope.accountSetId)
  )
  const selectedType = computed(() =>
    workspace.types.find((item) => item.id === workspace.selectedTypeId)
  )
  const canSync = computed(
    () =>
      Boolean(selectedType.value) &&
      !['manual', 'project'].includes(selectedType.value?.sourceType ?? '')
  )
  const canMaintainItems = computed(
    () =>
      Boolean(selectedType.value) &&
      ['manual', 'project'].includes(selectedType.value?.sourceType ?? '')
  )
  const sourceDescription = computed(() =>
    canSync.value ? '由业务主数据同步，名称和状态以源档案为准' : '由财务手工维护'
  )
  const filteredItems = computed(() => {
    const keyword = appliedItemFilter.keyword.trim().toLowerCase()
    return workspace.items.filter((item) => {
      const matched =
        !keyword ||
        item.itemCode.toLowerCase().includes(keyword) ||
        item.itemName.toLowerCase().includes(keyword)
      return (
        matched &&
        (appliedItemFilter.enabled === undefined || item.isEnabled === appliedItemFilter.enabled)
      )
    })
  })

  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'types',
      label: '核算维度',
      value: workspace.types.length,
      description: '当前账套维度数量',
      icon: 'ri:git-branch-line'
    },
    {
      key: 'items',
      label: '核算项目',
      value: workspace.items.length,
      description: selectedType.value?.typeName ?? '请选择核算维度',
      icon: 'ri:list-check-3',
      tone: 'success'
    },
    {
      key: 'enabled',
      label: '启用项目',
      value: workspace.items.filter((item) => item.isEnabled).length,
      description: '可用于凭证和期初余额',
      icon: 'ri:checkbox-circle-line',
      tone: 'warning'
    },
    {
      key: 'linked',
      label: '业务关联',
      value: workspace.items.filter((item) => item.externalEntityId).length,
      description: '与业务主数据保持同源',
      icon: 'ri:links-line',
      tone: 'info'
    }
  ])

  const columns: ColumnOption<AuxiliaryItem>[] = [
    {
      prop: 'itemCode',
      label: '项目编码',
      minWidth: 150,
      formatter: (row) => <strong class="accounting-auxiliary-page__code">{row.itemCode}</strong>
    },
    { prop: 'itemName', label: '项目名称', minWidth: 180, showOverflowTooltip: true },
    {
      prop: 'externalEntityId',
      label: '数据来源',
      width: 120,
      formatter: (row) => (
        <ElTag type={row.externalEntityId ? 'primary' : 'info'}>
          {row.externalEntityId ? '业务同步' : '手工维护'}
        </ElTag>
      )
    },
    { prop: 'sort', label: '排序', width: 80, align: 'center' },
    {
      prop: 'isEnabled',
      label: '状态',
      width: 90,
      formatter: (row) => (
        <ElTag type={row.isEnabled ? 'success' : 'info'}>{row.isEnabled ? '启用' : '停用'}</ElTag>
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 150,
      fixed: 'right',
      formatter: (row) => {
        if (row.externalEntityId)
          return <span class="accounting-auxiliary-page__readonly">源数据维护</span>
        return (
          <div class="accounting-auxiliary-page__actions">
            <ArtButtonTable
              type="edit"
              permission="FinanceAccountingAuxiliary:Edit"
              onClick={() => openItemDialog(row)}
            />
            {hasAuth('FinanceAccountingAuxiliary:Toggle') ? (
              <ElButton
                link
                type={row.isEnabled ? 'danger' : 'success'}
                onClick={() => toggleItem(row)}
              >
                {row.isEnabled ? '停用' : '启用'}
              </ElButton>
            ) : null}
          </div>
        )
      }
    }
  ]

  function sourceIcon(sourceType: Api.Fms.AuxiliarySourceType): string {
    return {
      manual: 'ri:edit-line',
      customer: 'ri:user-star-line',
      carrier: 'ri:truck-line',
      department: 'ri:organization-chart',
      employee: 'ri:team-line',
      project: 'ri:briefcase-4-line'
    }[sourceType]
  }

  function createDefaultItemFilter(): ItemFilter {
    return { keyword: '', enabled: undefined }
  }

  function getTypeActions(row: AuxiliaryType): ButtonMoreItem[] {
    const actions: ButtonMoreItem[] = [
      {
        key: 'edit',
        label: '编辑维度',
        icon: 'ri:edit-line',
        auth: 'FinanceAccountingAuxiliary:EditType'
      }
    ]
    if (!row.isSystem && row.sourceType === 'manual') {
      actions.push({
        key: 'delete',
        label: '删除维度',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)',
        auth: 'FinanceAccountingAuxiliary:DeleteType'
      })
    }
    return actions
  }

  function handleTypeAction(action: ButtonMoreItem, row: AuxiliaryType): void {
    if (action.key === 'edit') {
      void openTypeDialog(row)
      return
    }
    if (action.key === 'delete') void handleDeleteType(row)
  }

  function applyItemFilters(params: Record<string, unknown>): void {
    appliedItemFilter.keyword = typeof params.keyword === 'string' ? params.keyword : ''
    appliedItemFilter.enabled = typeof params.enabled === 'boolean' ? params.enabled : undefined
  }

  function resetItemFilters(): void {
    itemFilterForm.value = createDefaultItemFilter()
    Object.assign(appliedItemFilter, createDefaultItemFilter())
  }

  async function loadItems(): Promise<void> {
    if (!scope.accountSetId || !workspace.selectedTypeId) {
      workspace.items = []
      return
    }
    workspace.itemLoading = true
    workspace.itemError = ''
    try {
      const result = await fetchAuxiliaryItemList(scope.accountSetId, workspace.selectedTypeId)
      workspace.items = result.data ?? []
    } catch (error) {
      workspace.itemError = error instanceof Error ? error.message : '辅助核算项目加载失败'
    } finally {
      workspace.itemLoading = false
    }
  }

  async function loadWorkspace(): Promise<void> {
    if (!scope.accountSetId) return
    workspace.loading = true
    workspace.error = ''
    try {
      const result = await fetchAuxiliaryTypeList(scope.accountSetId)
      workspace.types = result.data ?? []
      if (!workspace.types.some((item) => item.id === workspace.selectedTypeId)) {
        workspace.selectedTypeId = workspace.types[0]?.id ?? ''
      }
      await loadItems()
    } catch (error) {
      workspace.error = error instanceof Error ? error.message : '辅助核算维度加载失败'
    } finally {
      workspace.loading = false
    }
  }

  function selectType(id: string): void {
    workspace.selectedTypeId = id
    resetItemFilters()
    void loadItems()
  }

  function handleAccountSetChange(): void {
    Object.assign(workspace, { selectedTypeId: '', items: [] })
    resetItemFilters()
    void loadWorkspace()
  }

  async function openTypeDialog(row?: AuxiliaryType): Promise<void> {
    if (
      !(await ensureAccountSet({
        actionLabel: row ? '编辑核算维度' : '新增核算维度',
        available: Boolean(currentAccountSet.value)
      }))
    )
      return
    await typeDialogRef.value?.handleOpen(currentAccountSet.value!, row)
  }

  async function handleDeleteType(row: AuxiliaryType): Promise<void> {
    await confirmAction(
      `确定删除手工维度“${row.typeName}（${row.typeCode}）”吗？仅未被会计科目和核算项目引用的维度可以删除。`,
      '删除辅助核算维度',
      {
        type: 'warning',
        confirmButtonText: '确认删除',
        cancelButtonText: '取消'
      }
    )
    await deleteAuxiliaryType(row.id)
    await loadWorkspace()
  }

  async function openItemDialog(row?: AuxiliaryItem): Promise<void> {
    if (!currentAccountSet.value || !selectedType.value) return
    await itemDialogRef.value?.handleOpen(currentAccountSet.value, selectedType.value, row)
  }

  async function handleSync(): Promise<void> {
    if (!selectedType.value) return
    workspace.syncing = true
    try {
      await syncAuxiliaryItems(scope.accountSetId, selectedType.value.id)
      await loadItems()
    } finally {
      workspace.syncing = false
    }
  }

  async function toggleItem(row: AuxiliaryItem): Promise<void> {
    await confirmAction(
      `确定${row.isEnabled ? '停用' : '启用'}项目“${row.itemCode} ${row.itemName}”吗？`,
      `${row.isEnabled ? '停用' : '启用'}辅助核算项目`
    )
    await setAuxiliaryItemEnabled(row.id, !row.isEnabled)
    await loadItems()
  }

  async function loadAccountSets(): Promise<void> {
    scope.loading = true
    try {
      const result = await fetchAccountSetOptions({ from: 0, to: 999 })
      scope.options = result.data ?? []
      if (!scope.accountSetId && scope.options.length) {
        scope.accountSetId = scope.options[0].value
        await loadWorkspace()
      }
    } finally {
      scope.loading = false
    }
  }

  onMounted(loadAccountSets)
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .accounting-auxiliary-page {
    @include accounting.accounting-workspace-layout;

    &.is-focus-mode {
      gap: 0;
    }

    &__scope,
    &__actions {
      display: flex;
      gap: 10px;
      align-items: center;
    }

    &__scope {
      display: flex;
      flex-direction: column;
      gap: 6px;
      align-items: stretch;
      max-width: 560px;

      > span {
        flex: none;
        font-size: 12px;
        font-weight: 600;
        line-height: 18px;
        color: var(--el-text-color-regular);
      }

      :deep(.el-select) {
        flex: 1;
      }
    }

    &__workspace {
      display: grid;
      flex: 1;
      grid-template-columns: minmax(300px, 340px) minmax(0, 1fr);
      gap: 12px;
      min-height: 0;

      &.is-focused {
        height: 100%;
      }
    }

    &__types,
    &__items {
      min-width: 0;
      min-height: 0;
    }

    &__type-scrollbar {
      height: min(480px, calc(100vh - 360px));
      min-height: 220px;
    }

    &__type-list {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding-right: 4px;
    }

    &__type-card {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 4px;
      align-items: center;
      width: 100%;
      padding: 6px;
      color: var(--art-text-gray-800);
      text-align: left;
      background: var(--art-main-bg-color);
      border: 1px solid var(--art-border-dashed-color);
      border-radius: var(--el-border-radius-base);
      transition:
        color 0.18s ease,
        background-color 0.18s ease,
        border-color 0.18s ease,
        box-shadow 0.18s ease;

      &:hover,
      &:focus-within,
      &.is-active {
        color: var(--theme-color);
        outline: none;
        background: color-mix(in srgb, var(--theme-color) 11%, var(--art-main-bg-color));
      }

      &.is-active {
        border-color: color-mix(in srgb, var(--theme-color) 62%, var(--el-border-color));
        box-shadow: inset 3px 0 0 var(--theme-color);
      }
    }

    &__type-select {
      display: grid;
      grid-template-columns: 40px minmax(0, 1fr) auto;
      gap: 10px;
      align-items: center;
      min-width: 0;
      padding: 4px 2px 4px 4px;
      color: inherit;
      text-align: left;
      touch-action: manipulation;
      cursor: pointer;
      background: transparent;
      border: 0;
      border-radius: var(--el-border-radius-small);

      &:focus-visible {
        outline: 2px solid color-mix(in srgb, var(--theme-color) 55%, transparent);
        outline-offset: 1px;
      }
    }

    :global([data-box-mode='border-mode']) &__type-card:hover,
    :global([data-box-mode='border-mode']) &__type-card:focus-within,
    :global([data-box-mode='border-mode']) &__type-card.is-active {
      border-color: color-mix(in srgb, var(--theme-color) 55%, var(--el-border-color));
      box-shadow:
        inset 3px 0 0 var(--theme-color),
        inset 0 0 0 1px color-mix(in srgb, var(--theme-color) 20%, transparent);
    }

    :global([data-box-mode='shadow-mode']) &__type-card:hover,
    :global([data-box-mode='shadow-mode']) &__type-card:focus-within,
    :global([data-box-mode='shadow-mode']) &__type-card.is-active {
      border-color: transparent;
      box-shadow:
        inset 3px 0 0 var(--theme-color),
        0 8px 20px color-mix(in srgb, var(--theme-color) 16%, transparent);
    }

    &__type-icon {
      display: grid;
      place-items: center;
      width: 40px;
      height: 40px;
      font-size: 20px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, transparent);
      border-radius: var(--el-border-radius-base);
    }

    &__type-card.is-active &__type-icon {
      color: #fff;
      background: var(--theme-color);
    }

    &__type-content,
    &__type-meta {
      display: flex;
      flex-direction: column;
      min-width: 0;
    }

    &__type-content {
      gap: 3px;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        color: var(--art-text-gray-500);
      }
    }

    &__type-meta {
      gap: 5px;
      align-items: flex-end;
      font-size: 12px;
      white-space: nowrap;
    }

    &__selected-badge {
      display: inline-flex;
      gap: 3px;
      align-items: center;
      font-weight: 650;
      color: var(--theme-color);
      white-space: nowrap;
    }

    &__type-more {
      flex: none;
    }

    &__item-search {
      margin-bottom: 12px;
    }

    &__code {
      font-variant-numeric: tabular-nums;
      color: var(--theme-color);
    }

    &__readonly {
      color: var(--art-text-gray-500);
    }
  }

  @media only screen and (width <= 980px) {
    .accounting-auxiliary-page {
      &__workspace {
        grid-template-columns: 1fr;
      }

      &__type-scrollbar {
        height: auto;
        min-height: 0;
        max-height: 300px;
      }
    }
  }

  @media only screen and (width <= 640px) {
    .accounting-auxiliary-page {
      &__scope {
        flex-direction: column;
        align-items: stretch;

        :deep(.el-select) {
          width: 100%;
        }
      }
    }
  }
</style>
