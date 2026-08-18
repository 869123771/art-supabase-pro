<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <div class="depreciation-workbench">
      <section class="depreciation-workbench__controls">
        <ElSelect
          v-model="accountSetId"
          filterable
          placeholder="选择账套"
          :no-data-text="ACCOUNTING_SELECT_EMPTY_TEXT.accountSet"
          @change="loadPeriods"
          ><ElOption
            v-for="item in accountSetOptions"
            :key="item.value"
            :label="item.label"
            :value="item.value"
        /></ElSelect>
        <ElSelect
          v-model="periodId"
          placeholder="选择开放期间"
          :disabled="!accountSetId"
          :no-data-text="
            accountSetId
              ? ACCOUNTING_SELECT_EMPTY_TEXT.openAccountingPeriod
              : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
          "
          ><ElOption
            v-for="item in periodOptions"
            :key="item.value"
            :label="item.label"
            :value="item.value"
        /></ElSelect>
        <ElButton type="primary" :disabled="!periodId" @click="calculate">计算本期折旧</ElButton>
      </section>
      <ElTable :data="runs" row-key="id" @row-click="selectRun">
        <ElTableColumn prop="runNo" label="批次号" min-width="150" />
        <ElTableColumn label="期间" min-width="120"
          ><template #default="{ row }">{{
            row.period ? `${row.period.fiscalYear}-${row.period.periodNo}` : '--'
          }}</template></ElTableColumn
        >
        <ElTableColumn prop="assetCount" label="资产数" width="90" />
        <ElTableColumn label="折旧金额" min-width="130" align="right"
          ><template #default="{ row }">{{
            formatCurrencyValue(row.totalAmount)
          }}</template></ElTableColumn
        >
        <ElTableColumn label="状态" width="100"
          ><template #default="{ row }"
            ><ArtDictDisplay
              dict-code="fmsDepreciationRunStatus"
              :value="row.status"
              display="tag" /></template
        ></ElTableColumn>
        <ElTableColumn label="操作" width="130" fixed="right"
          ><template #default="{ row }"
            ><ElButton
              v-if="row.status === 'calculated'"
              link
              type="primary"
              @click.stop="postRun(row)"
              >确认折旧</ElButton
            ></template
          ></ElTableColumn
        >
      </ElTable>
      <section v-if="selectedRun" class="depreciation-workbench__lines">
        <strong>{{ selectedRun.runNo }} · 折旧明细</strong>
        <ElTable :data="lines" size="small" max-height="300">
          <ElTableColumn label="资产" min-width="190"
            ><template #default="{ row }"
              >{{ row.asset?.assetNo }} · {{ row.asset?.assetName }}</template
            ></ElTableColumn
          >
          <ElTableColumn label="期初累计" min-width="120" align="right"
            ><template #default="{ row }">{{
              formatCurrencyValue(row.openingAccumulatedDepreciation)
            }}</template></ElTableColumn
          >
          <ElTableColumn label="本期折旧" min-width="120" align="right"
            ><template #default="{ row }">{{
              formatCurrencyValue(row.depreciationAmount)
            }}</template></ElTableColumn
          >
          <ElTableColumn label="期末累计" min-width="120" align="right"
            ><template #default="{ row }">{{
              formatCurrencyValue(row.closingAccumulatedDepreciation)
            }}</template></ElTableColumn
          >
        </ElTable>
      </section>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { formatCurrencyValue } from '@/utils/ui'
  import { ACCOUNTING_SELECT_EMPTY_TEXT } from '../../modules/accounting-select-text'
  import {
    actAssetDepreciationRun,
    calculateAssetDepreciation,
    fetchAccountingPeriodList,
    fetchAccountSetOptions,
    fetchAssetDepreciationLines,
    fetchAssetDepreciationRuns
  } from '@/api/fms'
  defineOptions({ name: 'FinanceAssetDepreciationDrawer' })
  const emit = defineEmits<{ success: [] }>()
  const { confirmAction } = useArtFeedback()
  const drawerRef = ref<ArtDrawerExpose>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const periodOptions = ref<Array<{ label: string; value: string }>>([])
  const accountSetId = ref('')
  const periodId = ref('')
  const runs = ref<Api.Fms.AssetDepreciationRunRecord[]>([])
  const selectedRun = ref<Api.Fms.AssetDepreciationRunRecord>()
  const lines = ref<Api.Fms.AssetDepreciationLineRecord[]>([])
  async function loadPeriods(): Promise<void> {
    periodId.value = ''
    periodOptions.value = []
    if (!accountSetId.value) return
    const { data } = await fetchAccountingPeriodList(accountSetId.value)
    periodOptions.value = (data ?? [])
      .filter((item) => item.status === 'open')
      .map((item) => ({
        label: `${item.fiscalYear} 年第 ${item.periodNo} 期（${item.startDate} 至 ${item.endDate}）`,
        value: item.id
      }))
    periodId.value = periodOptions.value[0]?.value ?? ''
    await loadRuns()
  }
  async function loadRuns(): Promise<void> {
    const { data } = await fetchAssetDepreciationRuns(accountSetId.value)
    runs.value = data ?? []
  }
  async function selectRun(rawRow: object): Promise<void> {
    const row = rawRow as Api.Fms.AssetDepreciationRunRecord
    selectedRun.value = row
    const { data } = await fetchAssetDepreciationLines(row.id)
    lines.value = data ?? []
  }
  async function calculate(): Promise<void> {
    await calculateAssetDepreciation(periodId.value)
    await loadRuns()
    emit('success')
  }
  async function postRun(rawRow: object): Promise<void> {
    const row = rawRow as Api.Fms.AssetDepreciationRunRecord
    try {
      await confirmAction(
        `确认批次 ${row.runNo} 的折旧金额 ${formatCurrencyValue(row.totalAmount)} 吗？`,
        '确认本期折旧',
        { type: 'warning', confirmButtonText: '确认并入账' }
      )
      await actAssetDepreciationRun(row.id, 'post')
      await loadRuns()
      emit('success')
    } catch {
      /* 用户取消 */
    }
  }
  async function handleOpen(currentAccountSetId?: string): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    accountSetId.value = currentAccountSetId || accountSetOptions.value[0]?.value || ''
    await loadPeriods()
    await drawerRef.value?.handleOpen(undefined, {
      title: '固定资产折旧管理',
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }
  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .depreciation-workbench {
    display: grid;
    gap: 18px;
  }

  .depreciation-workbench__controls {
    display: grid;
    grid-template-columns: minmax(220px, 1fr) minmax(260px, 1.3fr) auto;
    gap: 12px;
    padding: 16px;
    background: var(--el-fill-color-lighter);
    border-radius: var(--el-border-radius-base);
  }

  .depreciation-workbench__lines {
    display: grid;
    gap: 12px;
    padding: 16px;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: var(--el-border-radius-base);
  }

  @media (width <= 767px) {
    .depreciation-workbench__controls {
      grid-template-columns: 1fr;
    }
  }
</style>
