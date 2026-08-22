<template>
  <FinanceAccountingWorkspaceShell
    class="accounting-subject-page"
    :class="{ 'is-focus-mode': focusMode }"
  >
    <BusinessWorkspaceHeader
      v-show="!focusMode"
      density="compact"
      eyebrow="财务基础 · 科目体系"
      title="会计科目"
      description="按账套维护最多十级的企业会计科目体系，统一科目类别、余额方向及外币、数量和现金流核算属性。"
      icon="ri:node-tree"
      :tags="[
        { label: '十级科目', type: 'primary' },
        { label: '余额方向继承', type: 'success' },
        { label: '停用留痕', type: 'info' }
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
      subtitle="切换账套后，科目树与统计口径同步刷新"
      class="accounting-workspace-scope-section"
    >
      <div class="accounting-subject-page__scope">
        <div class="accounting-subject-page__selector">
          <span>当前账套</span>
          <ElSelect
            v-model="state.accountSetId"
            aria-label="当前账套"
            filterable
            placeholder="请选择账套"
            :loading="state.accountSetLoading"
            @change="handleAccountSetChange"
          >
            <ElOption
              v-for="item in state.accountSetOptions"
              :key="item.value"
              :label="item.label"
              :value="item.value"
            />
          </ElSelect>
        </div>
      </div>
      <AccountingSetupGuide
        :loading="state.accountSetLoading"
        :has-account-set="state.accountSetOptions.length > 0"
        :can-configure="hasAuth('FinanceAccountSet:Add')"
        @configure="goToAccountSet"
      />
    </ArtPageSection>

    <section
      v-if="currentAccountSet && state.readiness && !state.readiness.foundationReady"
      v-show="!focusMode"
      class="accounting-subject-page__readiness"
      aria-labelledby="accounting-readiness-title"
    >
      <span class="accounting-subject-page__readiness-icon" aria-hidden="true">
        <ArtSvgIcon icon="ri:settings-4-line" />
      </span>
      <div class="accounting-subject-page__readiness-copy">
        <strong id="accounting-readiness-title">当前账套尚未完成核算初始化</strong>
        <p>{{ readinessDescription }}</p>
      </div>
      <ElButton
        v-if="hasAuth('FinanceAccountingSubject:Initialize')"
        type="primary"
        :loading="state.initializing"
        @click="initializeFoundation"
      >
        <ArtSvgIcon icon="ri:magic-line" />补齐核算基础
      </ElButton>
      <ElTag v-else type="warning">请联系管理员授权或初始化</ElTag>
    </section>

    <div class="accounting-subject-page__workspace" :class="{ 'is-focused': focusMode }">
      <ArtSearchBar
        v-model="filterForm"
        :items="searchItems"
        :span="8"
        :gutter="16"
        label-position="left"
        label-width="76px"
        :show-expand="false"
        :button-left-limit="0"
        @search="applyFilters"
        @reset="resetFilters"
      />

      <ArtPageSection
        title="科目体系"
        :subtitle="
          currentAccountSet
            ? `${currentAccountSet.label} · 下级科目继承上级类别与余额方向`
            : '请先选择账套'
        "
        class="accounting-subject-page__table-section accounting-workspace-fill-section"
      >
        <template #actions>
          <BusinessWorkspaceFocusToggle v-if="focusMode" v-model="focusMode" />
          <ElButton v-auth="'FinanceAccountingSubject:Add'" type="primary" @click="openDialog()">
            <ArtSvgIcon icon="ri:add-line" />新增科目
          </ElButton>
        </template>

        <ArtAsyncState
          class="accounting-workspace-content-state"
          :class="{
            'is-empty': !state.loading && !state.error && filteredSubjects.length === 0
          }"
          :loading="state.loading"
          :empty-image-size="72"
          :min-height="160"
          :error="state.error"
          :empty="!state.loading && !state.error && filteredSubjects.length === 0"
          empty-text="暂无会计科目"
          :empty-description="
            currentAccountSet ? '当前账套尚未维护符合条件的会计科目。' : '请选择一个可查看的账套。'
          "
          @retry="loadSubjects"
        >
          <ArtTable
            :data="filteredSubjects"
            :columns="columns"
            :pagination="false"
            row-key="id"
            default-expand-all
            table-layout="fixed"
            :tree-props="{ children: 'children' }"
            empty-text="暂无会计科目"
          />
        </ArtAsyncState>
      </ArtPageSection>
    </div>

    <SubjectDialog ref="dialogRef" @success="loadSubjects" />
  </FinanceAccountingWorkspaceShell>
</template>

<script setup lang="tsx">
  import { ElButton, ElTag } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessWorkspaceFocusToggle from '@/components/business/business-workspace-focus-toggle/index.vue'
  import { useWorkspaceFocus } from '@/hooks/core/useWorkspaceFocus'
  import AccountingSetupGuide from '../modules/accounting-setup-guide.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSearchBar, {
    type SearchFormItem
  } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ColumnOption } from '@/types'
  import TreeUtils from '@/utils/tree'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchAccountingReadiness,
    fetchAccountSetOptions,
    fetchAuxiliaryTypeList,
    fetchSubjectList,
    initializeAccountingDefaults,
    setSubjectEnabled
  } from '@/api/fms'
  import SubjectDialog from './modules/subject-dialog.vue'

  defineOptions({ name: 'FinanceAccountingSubject' })

  type Subject = Api.Fms.SubjectRecord
  type AccountSetOption = {
    label: string
    value: string
    status: Api.Fms.AccountSetStatus
    tenantId: string
  }

  interface SubjectDialogExpose {
    handleOpen: (
      accountSet: AccountSetOption,
      subjects: Subject[],
      auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[],
      row?: Subject
    ) => Promise<void>
  }

  interface SubjectFilter extends Record<string, unknown> {
    keyword: string
    category?: Api.Fms.SubjectCategory
  }

  const { confirmAction } = useArtFeedback()
  const { focusMode } = useWorkspaceFocus()
  const { ensureAccountSet, goToAccountSet } = useFinanceAccountSetPrerequisite()
  const { getDictMap } = storeToRefs(useUserStore())
  const { hasAuth } = useAuth()
  const dialogRef = ref<SubjectDialogExpose>()
  const subjectTree = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const state = reactive({
    accountSetId: '',
    accountSetLoading: true,
    accountSetOptions: [] as AccountSetOption[],
    loading: false,
    error: '',
    initializing: false,
    readiness: null as Api.Fms.AccountingReadiness | null,
    subjects: [] as Subject[],
    auxiliaryTypes: [] as Api.Fms.AuxiliaryTypeRecord[]
  })
  const filterForm = ref<SubjectFilter>(createDefaultFilter())
  const appliedFilter = reactive<SubjectFilter>(createDefaultFilter())

  const categoryOptions = computed(() => getDictMap.value.fmsSubjectCategory ?? [])
  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '会计科目',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '搜索科目编码或名称' }
    },
    {
      label: '科目类别',
      key: 'category',
      type: 'select',
      props: { clearable: true, placeholder: '全部类别', options: categoryOptions.value }
    }
  ])

  const currentAccountSet = computed(() =>
    state.accountSetOptions.find((item) => item.value === state.accountSetId)
  )

  const readinessDescription = computed(() => {
    const readiness = state.readiness
    if (!readiness) return ''
    const items: string[] = []
    if (readiness.missingSubjectCodes.length) {
      items.push(`缺少 ${readiness.missingSubjectCodes.length} 个核心明细科目`)
    }
    if (readiness.missingPostingRuleCodes.length) {
      items.push(`缺少 ${readiness.missingPostingRuleCodes.length} 套自动制证规则`)
    }
    if (!readiness.statementItemCount || !readiness.statementMappingCount) {
      items.push('财务报表项目与科目映射未完成')
    }
    if (!readiness.openPeriodCount) items.push('没有开放的会计期间')
    return `${items.join('；')}。补齐操作只新增缺失项，不覆盖已有科目、规则和报表配置。`
  })

  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const subjects = state.subjects
    return [
      {
        key: 'total',
        label: '科目总数',
        value: subjects.length,
        description: '当前账套完整科目体系',
        icon: 'ri:node-tree'
      },
      {
        key: 'enabled',
        label: '启用科目',
        value: subjects.filter((item) => item.isEnabled).length,
        description: '可用于凭证分录',
        icon: 'ri:checkbox-circle-line',
        tone: 'success'
      },
      {
        key: 'detail',
        label: '明细科目',
        value: countLeafSubjects(subjects),
        description: '当前无下级的末级科目',
        icon: 'ri:list-check-3',
        tone: 'warning'
      },
      {
        key: 'foreign',
        label: '外币核算',
        value: subjects.filter((item) => item.allowForeignCurrency).length,
        description: '需要记录原币金额',
        icon: 'ri:exchange-dollar-line',
        tone: 'info'
      }
    ]
  })

  const filteredSubjects = computed<Subject[]>(() => {
    const keyword = appliedFilter.keyword.trim().toLowerCase()
    const list = state.subjects.filter((item) => {
      const keywordMatched =
        !keyword ||
        item.subjectCode.toLowerCase().includes(keyword) ||
        item.subjectName.toLowerCase().includes(keyword)
      return keywordMatched && (!appliedFilter.category || item.category === appliedFilter.category)
    })
    return subjectTree.listToTree(list, (left, right) =>
      (left as Subject).subjectCode.localeCompare((right as Subject).subjectCode)
    ) as Subject[]
  })

  const columns: ColumnOption<Subject>[] = [
    {
      prop: 'subjectCode',
      label: '科目编码',
      minWidth: 180,
      formatter: (row) => <span class="accounting-subject-page__code">{row.subjectCode}</span>
    },
    { prop: 'subjectName', label: '科目名称', minWidth: 180, showOverflowTooltip: true },
    {
      prop: 'category',
      label: '类别',
      width: 120,
      dict: { code: 'fmsSubjectCategory', display: 'auto' }
    },
    {
      prop: 'balanceDirection',
      label: '余额方向',
      width: 100,
      dict: { code: 'fmsBalanceDirection', display: 'auto' }
    },
    { prop: 'level', label: '级次', width: 78, align: 'center' },
    {
      prop: 'attributes',
      label: '核算属性',
      minWidth: 210,
      formatter: (row) => (
        <div class="accounting-subject-page__attributes">
          {row.allowQuantity && <ElTag size="small">数量</ElTag>}
          {row.allowForeignCurrency && (
            <ElTag size="small" type="success">
              外币
            </ElTag>
          )}
          {row.cashFlowRequired && (
            <ElTag size="small" type="warning">
              现金流
            </ElTag>
          )}
          {(row.auxiliaryConfigs ?? []).map((config) => (
            <ElTag key={config.auxiliaryTypeId} size="small" type="info">
              {config.auxiliaryType?.typeName ?? '辅助核算'}
            </ElTag>
          ))}
          {!row.allowQuantity && !row.allowForeignCurrency && !row.cashFlowRequired && (
            <span>{row.auxiliaryConfigs?.length ? '' : '—'}</span>
          )}
        </div>
      )
    },
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
      formatter: (row) => (
        <div class="accounting-subject-page__actions">
          <ArtButtonTable
            type="edit"
            permission="FinanceAccountingSubject:Edit"
            onClick={() => openDialog(row)}
          />
          {hasAuth('FinanceAccountingSubject:Toggle') ? (
            <ElButton
              link
              type={row.isEnabled ? 'danger' : 'success'}
              onClick={() => toggleEnabled(row)}
            >
              {row.isEnabled ? '停用' : '启用'}
            </ElButton>
          ) : null}
        </div>
      )
    }
  ]

  function countLeafSubjects(subjects: Subject[]): number {
    const tree = subjectTree.listToTree(subjects)
    let count = 0
    subjectTree.traverse<Subject>(tree, (node) => {
      if (!node.children?.length) count += 1
    })
    return count
  }

  function createDefaultFilter(): SubjectFilter {
    return { keyword: '', category: undefined }
  }

  function applyFilters(params: Record<string, unknown>): void {
    appliedFilter.keyword = typeof params.keyword === 'string' ? params.keyword : ''
    appliedFilter.category =
      typeof params.category === 'string' ? (params.category as Api.Fms.SubjectCategory) : undefined
  }

  function resetFilters(): void {
    filterForm.value = createDefaultFilter()
    Object.assign(appliedFilter, createDefaultFilter())
  }

  async function loadSubjects(): Promise<void> {
    if (!state.accountSetId) {
      state.subjects = []
      return
    }
    state.loading = true
    state.error = ''
    try {
      const [subjectResult, auxiliaryResult, readinessResult] = await Promise.all([
        fetchSubjectList(state.accountSetId),
        fetchAuxiliaryTypeList(state.accountSetId),
        fetchAccountingReadiness(state.accountSetId)
      ])
      state.subjects = subjectResult.data ?? []
      state.auxiliaryTypes = auxiliaryResult.data ?? []
      state.readiness = readinessResult.data ?? null
    } catch (error) {
      state.error = error instanceof Error ? error.message : '会计科目加载失败'
    } finally {
      state.loading = false
    }
  }

  async function initializeFoundation(): Promise<void> {
    if (!currentAccountSet.value || state.initializing) return
    try {
      await confirmAction(
        `将为“${currentAccountSet.value.label}”补齐核心会计科目、默认自动制证规则和财务报表映射。已有配置不会被覆盖。`,
        '补齐核算基础',
        {
          type: 'warning',
          confirmButtonText: '确认补齐',
          cancelButtonText: '暂不处理'
        }
      )
      state.initializing = true
      await initializeAccountingDefaults(currentAccountSet.value.value)
      await loadSubjects()
    } catch {
      // 用户取消或数据库业务约束阻止时，不重复提示。
    } finally {
      state.initializing = false
    }
  }

  function handleAccountSetChange(): void {
    resetFilters()
    void loadSubjects()
  }

  async function openDialog(row?: Subject): Promise<void> {
    if (
      !(await ensureAccountSet({
        actionLabel: row ? '编辑会计科目' : '新增会计科目',
        available: Boolean(currentAccountSet.value)
      }))
    )
      return
    await dialogRef.value?.handleOpen(
      currentAccountSet.value!,
      state.subjects,
      state.auxiliaryTypes,
      row
    )
  }

  async function toggleEnabled(row: Subject): Promise<void> {
    await confirmAction(
      `确定${row.isEnabled ? '停用' : '启用'}科目“${row.subjectCode} ${row.subjectName}”吗？`,
      `${row.isEnabled ? '停用' : '启用'}会计科目`,
      { confirmButtonText: row.isEnabled ? '确认停用' : '确认启用' }
    )
    await setSubjectEnabled(row.id, !row.isEnabled)
    await loadSubjects()
  }

  async function loadAccountSets(): Promise<void> {
    state.accountSetLoading = true
    try {
      const result = await fetchAccountSetOptions({ from: 0, to: 999 })
      state.accountSetOptions = result.data ?? []
      if (!state.accountSetId && state.accountSetOptions.length) {
        state.accountSetId = state.accountSetOptions[0].value
        await loadSubjects()
      }
    } finally {
      state.accountSetLoading = false
    }
  }

  onMounted(loadAccountSets)
</script>

<style scoped lang="scss">
  .accounting-subject-page {
    &.is-focus-mode {
      gap: 0;
    }

    &__selector,
    &__actions,
    &__attributes {
      display: flex;
      gap: 10px;
      align-items: center;
    }

    &__scope {
      max-width: 560px;
    }

    &__selector {
      flex-direction: column;
      gap: 6px;
      align-items: stretch;
      min-width: 0;

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

    &__table-section {
      flex: 1;
      min-height: 0;
    }

    &__workspace {
      display: flex;
      flex: 1;
      flex-direction: column;
      gap: 16px;
      min-width: 0;
      min-height: 0;

      &.is-focused {
        height: 100%;
      }
    }

    &__readiness {
      display: grid;
      grid-template-columns: 40px minmax(0, 1fr) auto;
      gap: 12px;
      align-items: center;
      padding: 12px 14px;
      color: var(--el-text-color-regular);
      background: color-mix(in srgb, var(--el-color-warning) 7%, var(--default-box-color));
      border: 1px solid color-mix(in srgb, var(--el-color-warning) 28%, var(--el-border-color));
      border-radius: var(--el-border-radius-base);
    }

    &__readiness-icon {
      display: grid;
      place-items: center;
      width: 40px;
      height: 40px;
      font-size: 19px;
      color: var(--el-color-warning-dark-2);
      background: color-mix(in srgb, var(--el-color-warning) 14%, transparent);
      border-radius: var(--el-border-radius-base);
    }

    &__readiness-copy {
      min-width: 0;

      strong {
        display: block;
        margin-bottom: 2px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
      }
    }

    &__code {
      font-weight: 700;
      font-variant-numeric: tabular-nums;
      color: var(--art-primary);
    }

    &__attributes {
      flex-wrap: wrap;
      gap: 6px;
    }

    &__readonly {
      color: var(--art-text-gray-500);
    }
  }

  @media only screen and (width <= 720px) {
    .accounting-subject-page {
      &__selector {
        width: 100%;
      }

      &__readiness {
        grid-template-columns: 40px minmax(0, 1fr);

        :deep(.el-button),
        :deep(.el-tag) {
          grid-column: 1 / -1;
          width: 100%;
        }
      }
    }
  }
</style>
