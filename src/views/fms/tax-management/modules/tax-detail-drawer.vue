<template>
  <ArtDrawer ref="drawerRef" :show-footer="false"
    ><div v-if="period" class="tax-detail"
      ><section class="tax-detail__summary"
        ><div
          ><small>税务期间</small
          ><strong><ArtDictDisplay dict-code="fmsTaxType" :value="period.taxType" /></strong
          ><span>{{
            period.period ? `${period.period.fiscalYear} 年第 ${period.period.periodNo} 期` : '--'
          }}</span></div
        ><ArtDictDisplay
          dict-code="fmsTaxPeriodStatus"
          :value="period.status"
          display="tag" /></section
      ><div class="tax-detail__toolbar"
        ><div><strong>税务台账明细</strong><small>销项、进项与调整项目</small></div
        ><ElButton
          v-if="editable"
          v-auth="'FinanceTaxManagement:Calculate'"
          type="primary"
          @click="dialogRef?.handleOpen(period)"
          >新增明细</ElButton
        ></div
      ><ElTable :data="lines" row-key="id"
        ><ElTableColumn prop="occurredOn" label="日期" width="115" /><ElTableColumn
          prop="sourceType"
          label="来源"
          min-width="110"
        /><ElTableColumn prop="sourceNo" label="来源单号" min-width="140" /><ElTableColumn
          label="方向"
          width="100"
          ><template #default="{ row }"
            ><ArtDictDisplay
              dict-code="fmsTaxLedgerDirection"
              :value="row.direction"
              display="tag" /></template></ElTableColumn
        ><ElTableColumn label="计税金额" min-width="120" align="right"
          ><template #default="{ row }">{{
            formatCurrencyValue(row.taxableAmount)
          }}</template></ElTableColumn
        ><ElTableColumn label="税率" width="100" align="right"
          ><template #default="{ row }">{{
            row.taxRate == null ? '--' : `${(row.taxRate * 100).toFixed(4)}%`
          }}</template></ElTableColumn
        ><ElTableColumn label="税额" min-width="120" align="right"
          ><template #default="{ row }">{{
            formatCurrencyValue(row.taxAmount)
          }}</template></ElTableColumn
        ><ElTableColumn v-if="editable" label="操作" width="110" fixed="right"
          ><template #default="{ row }"
            ><ElButton
              v-auth="'FinanceTaxManagement:Calculate'"
              link
              type="primary"
              @click="editLine(row)"
              >编辑</ElButton
            ><ElButton
              v-auth="'FinanceTaxManagement:Calculate'"
              link
              type="danger"
              @click="remove(row)"
              >删除</ElButton
            ></template
          ></ElTableColumn
        ></ElTable
      ><TaxLedgerDialog ref="dialogRef" @success="reload" /></div
  ></ArtDrawer>
</template>
<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { deleteTaxLedgerLine, fetchTaxLedgerLines } from '@/api/fms'
  import { formatCurrencyValue } from '@/utils/ui'
  import TaxLedgerDialog from './tax-ledger-dialog.vue'
  defineOptions({ name: 'FinanceTaxDetailDrawer' })
  const emit = defineEmits<{ success: [] }>()
  const { hasAuth } = useAuth()
  const { confirmAction } = useArtFeedback()
  const drawerRef = ref<ArtDrawerExpose>()
  const dialogRef = ref<{
    handleOpen: (
      period: Api.Fms.TaxPeriodRecord,
      line?: Api.Fms.TaxLedgerLineRecord
    ) => Promise<void>
  }>()
  const period = ref<Api.Fms.TaxPeriodRecord>()
  const lines = ref<Api.Fms.TaxLedgerLineRecord[]>([])
  const editable = computed(
    () =>
      hasAuth('FinanceTaxManagement:Calculate') &&
      Boolean(period.value && ['draft', 'calculated'].includes(period.value.status))
  )
  async function reload() {
    if (!period.value) return
    const { data } = await fetchTaxLedgerLines(period.value.id)
    lines.value = data ?? []
    emit('success')
  }
  function editLine(rawRow: object): void {
    if (!period.value) return
    void dialogRef.value?.handleOpen(period.value, rawRow as Api.Fms.TaxLedgerLineRecord)
  }

  async function remove(rawRow: object) {
    const row = rawRow as Api.Fms.TaxLedgerLineRecord
    try {
      await confirmAction('确定删除该税务台账明细吗？', '删除税务明细', { type: 'warning' })
      await deleteTaxLedgerLine(row.id)
      await reload()
    } catch {
      /* 用户取消 */
    }
  }
  async function handleOpen(row: Api.Fms.TaxPeriodRecord) {
    period.value = row
    await reload()
    await drawerRef.value?.handleOpen(undefined, {
      title: '税务期间详情',
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }
  defineExpose({ handleOpen })
</script>
<style scoped lang="scss">
  .tax-detail {
    display: grid;
    gap: 18px;
  }

  .tax-detail__summary,
  .tax-detail__toolbar {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
    padding: 16px;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: var(--el-border-radius-base);
  }

  .tax-detail__summary > div,
  .tax-detail__toolbar > div {
    display: grid;
    gap: 4px;
  }

  .tax-detail small,
  .tax-detail span {
    color: var(--el-text-color-secondary);
  }
</style>
