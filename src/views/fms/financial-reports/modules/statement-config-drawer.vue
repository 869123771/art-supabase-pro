<template>
  <ArtDrawer ref="drawerRef" size="xl" :show-footer="false">
    <div class="statement-config-drawer">
      <section class="statement-config-drawer__summary">
        <div>
          <span>报表类型</span>
          <strong>{{ statementTypeLabel }}</strong>
        </div>
        <div>
          <span>项目总数</span>
          <strong>{{ items.length }}</strong>
        </div>
        <div>
          <span>直接取数行</span>
          <strong>{{ mappingItemCount }}</strong>
        </div>
        <div>
          <span>公式 / 标题行</span>
          <strong>{{ formulaItemCount }} / {{ labelItemCount }}</strong>
        </div>
      </section>

      <section class="statement-config-drawer__panel">
        <header>
          <div>
            <h3>账套报表项目</h3>
            <p>项目结构决定报表展示，科目映射与公式关系决定可审计取数口径。</p>
          </div>
          <div v-if="canEditBaseRules" class="statement-config-drawer__actions">
            <ElButton :loading="loading" @click="initializeItems">
              <ArtSvgIcon icon="ri:magic-line" />
              初始化标准项目
            </ElButton>
            <ElButton type="primary" @click="openItemDialog()">
              <ArtSvgIcon icon="ri:add-line" />
              新增项目
            </ElButton>
          </div>
        </header>

        <ElTable
          v-loading="loading"
          :data="items"
          row-key="id"
          border
          table-layout="fixed"
          max-height="calc(100vh - 320px)"
          empty-text="当前账套尚未初始化报表项目"
        >
          <ElTableColumn label="项目" min-width="260" fixed="left">
            <template #default="{ row }">
              <div
                class="statement-config-drawer__item"
                :style="{ paddingLeft: `${Math.max(row.itemLevel - 1, 0) * 14}px` }"
              >
                <strong>{{ row.itemName }}</strong>
                <small translate="no">{{ row.itemCode }} · 行次 {{ row.lineNo }}</small>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="计算方式" width="120">
            <template #default="{ row }">
              <ElTag :type="calculationTag(row.calculationMethod)" effect="plain">
                {{ dictLabel('fmsStatementCalculationMethod', row.calculationMethod) }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="行样式" width="105">
            <template #default="{ row }">
              {{ dictLabel('fmsStatementDisplayStyle', row.displayStyle) }}
            </template>
          </ElTableColumn>
          <ElTableColumn
            v-if="statementType === 'cash_flow_statement'"
            label="流量方向"
            width="105"
          >
            <template #default="{ row }">
              {{ dictLabel('fmsCashFlowDirection', row.cashFlowDirection) || '--' }}
            </template>
          </ElTableColumn>
          <ElTableColumn v-if="canViewRules" label="规则数" width="90" align="right">
            <template #default="{ row }">
              {{ row.calculationMethod === 'label' ? '--' : (row.ruleCount ?? '--') }}
            </template>
          </ElTableColumn>
          <ElTableColumn label="状态" width="84" align="center">
            <template #default="{ row }">
              <ElTag :type="row.isEnabled ? 'success' : 'info'" effect="plain">
                {{ row.isEnabled ? '启用' : '停用' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn v-if="canViewRules" label="操作" width="180" fixed="right">
            <template #default="{ row }">
              <div class="statement-config-drawer__row-actions">
                <ArtButtonTable
                  v-if="canEditRowRules(row)"
                  type="edit"
                  @click="openItemDialog(row)"
                />
                <ArtButtonTable
                  v-if="canConfigureRule(row) && canReadRowRules(row)"
                  :type="canEditRowRules(row) ? 'edit' : 'view'"
                  :label="ruleActionLabel(row)"
                  @click="openRuleDialog(row)"
                />
              </div>
            </template>
          </ElTableColumn>
        </ElTable>
      </section>
    </div>

    <StatementItemDialog ref="itemDialogRef" @success="handleConfigurationSaved" />
    <StatementRuleDialog ref="ruleDialogRef" @success="handleConfigurationSaved" />
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { storeToRefs } from 'pinia'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import StatementItemDialog from './statement-item-dialog.vue'
  import StatementRuleDialog from './statement-rule-dialog.vue'
  import {
    fetchFinancialStatementItems,
    fetchSubjectList,
    initializeFinancialStatementItems
  } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { canEditField, getFieldAccess, mergeFieldAccessMaps } from '@/utils/field-permission'

  defineOptions({ name: 'FinanceStatementConfigDrawer' })

  type Item = Api.Fms.FinancialStatementItemRecord

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const { hasAuth } = useAuth()
  const { confirmAction } = useArtFeedback()
  const canEditConfigButton = computed(() => hasAuth('FinanceFinancialReports:EditConfig'))
  const drawerRef = ref<ArtDrawerExpose>()
  const itemDialogRef = ref<InstanceType<typeof StatementItemDialog>>()
  const ruleDialogRef = ref<InstanceType<typeof StatementRuleDialog>>()
  const accountSetId = ref('')
  const statementType = ref<Api.Fms.FinancialStatementType>('balance_sheet')
  const items = ref<Item[]>([])
  const subjects = ref<Api.Fms.SubjectRecord[]>([])
  const listFieldAccess = ref<Api.Fms.FinancialReportFieldAccessMap>({})
  const loading = ref(false)

  const statementTypeLabel = computed(() =>
    dictLabel('fmsFinancialStatementType', statementType.value)
  )
  const mappingItemCount = computed(
    () => items.value.filter((item) => item.calculationMethod === 'mapping').length
  )
  const formulaItemCount = computed(
    () => items.value.filter((item) => item.calculationMethod === 'formula').length
  )
  const labelItemCount = computed(
    () => items.value.filter((item) => item.calculationMethod === 'label').length
  )
  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(listFieldAccess.value, ...items.value.map((item) => item.fieldAccess))
  )
  const canViewRules = computed(
    () => getFieldAccess(effectiveFieldAccess.value, 'reportRules') !== 'hidden'
  )
  const canEditBaseRules = computed(
    () => canEditConfigButton.value && canEditField(listFieldAccess.value, 'reportRules')
  )

  function dictLabel(code: string, value: unknown): string {
    if (value === null || value === undefined || value === '') return ''
    return (
      (getDictMap.value[code] ?? []).find((item) => String(item.value) === String(value))?.label ??
      String(value)
    )
  }

  function calculationTag(method: Api.Fms.FinancialStatementCalculationMethod) {
    if (method === 'formula') return 'success'
    if (method === 'label') return 'info'
    return 'primary'
  }

  function canConfigureRule(row: unknown): boolean {
    const item = row as Item
    if (item.calculationMethod === 'formula') return true
    return item.calculationMethod === 'mapping' && item.statementType !== 'cash_flow_statement'
  }

  function canReadRowRules(row: unknown): boolean {
    const item = row as Item
    return ['read', 'edit'].includes(getFieldAccess(item.fieldAccess, 'reportRules'))
  }

  function canEditRowRules(row: unknown): boolean {
    const item = row as Item
    return canEditConfigButton.value && canEditField(item.fieldAccess, 'reportRules')
  }

  function ruleActionLabel(row: unknown): string {
    const item = row as Item
    const action = item.calculationMethod === 'formula' ? '公式' : '科目映射'
    return `${canEditRowRules(item) ? '配置' : '查看'}${action}`
  }

  async function loadConfiguration(): Promise<void> {
    if (!accountSetId.value) return
    loading.value = true
    try {
      const [itemResult, subjectResult] = await Promise.all([
        fetchFinancialStatementItems(accountSetId.value, statementType.value),
        fetchSubjectList(accountSetId.value)
      ])
      items.value = itemResult.data ?? []
      listFieldAccess.value = itemResult.fieldAccess
      subjects.value = subjectResult.data ?? []
    } finally {
      loading.value = false
    }
  }

  async function initializeItems(): Promise<void> {
    if (!canEditBaseRules.value || !accountSetId.value) return
    await confirmAction(
      '系统将补齐企业会计准则通用报表项目、合计公式和现金流方向；已有同编码项目不会重复创建。',
      '初始化标准财务报表',
      { type: 'warning', confirmButtonText: '确认初始化', cancelButtonText: '取消' }
    )
    await initializeFinancialStatementItems(accountSetId.value)
    await handleConfigurationSaved()
  }

  function openItemDialog(row?: unknown): void {
    const item = row as Item | undefined
    if (!(item ? canEditRowRules(item) : canEditBaseRules.value)) return
    void itemDialogRef.value?.handleOpen(accountSetId.value, statementType.value, items.value, item)
  }

  function openRuleDialog(row: unknown): void {
    const item = row as Item
    if (!canReadRowRules(item)) return
    void ruleDialogRef.value?.handleOpen(item, items.value, subjects.value, canEditRowRules(item))
  }

  async function handleConfigurationSaved(): Promise<void> {
    await loadConfiguration()
    emit('success')
  }

  async function handleOpen(
    targetAccountSetId: string,
    targetStatementType: Api.Fms.FinancialStatementType
  ): Promise<void> {
    accountSetId.value = targetAccountSetId
    statementType.value = targetStatementType
    await drawerRef.value?.handleOpen(undefined, {
      title: '财务报表取数口径',
      subtitle: `${statementTypeLabel.value} · 账套级配置`,
      contentHeight: 'calc(100vh - 116px)',
      onOpen: loadConfiguration,
      drawerProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .statement-config-drawer {
    display: grid;
    gap: var(--art-space-4);

    &__summary {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: var(--art-space-3);

      > div {
        display: flex;
        flex-direction: column;
        gap: 6px;
        min-width: 0;
        padding: var(--art-space-3) var(--art-space-4);
        background: var(--el-fill-color-light);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      span {
        font-size: 12px;
        color: var(--art-text-gray-600);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 18px;
        color: var(--art-text-gray-900);
        white-space: nowrap;
      }
    }

    &__panel {
      min-width: 0;
      padding: var(--art-space-4);
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > header {
        display: flex;
        gap: var(--art-space-4);
        align-items: flex-start;
        justify-content: space-between;
        margin-bottom: var(--art-space-4);

        h3,
        p {
          margin: 0;
        }

        h3 {
          font-size: 16px;
          color: var(--art-text-gray-900);
        }

        p {
          margin-top: 5px;
          font-size: 13px;
          line-height: 1.5;
          color: var(--art-text-gray-600);
        }
      }
    }

    &__actions,
    &__row-actions {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-2);
      align-items: center;
    }

    &__item {
      display: flex;
      flex-direction: column;
      gap: 3px;
      min-width: 0;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        color: var(--art-text-gray-900);
      }

      small {
        color: var(--art-text-gray-600);
      }
    }
  }

  @media (width <= 900px) {
    .statement-config-drawer__summary {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (width <= 640px) {
    .statement-config-drawer {
      &__summary {
        grid-template-columns: 1fr;
      }

      &__panel > header {
        flex-direction: column;
        align-items: stretch;
      }
    }
  }
</style>
