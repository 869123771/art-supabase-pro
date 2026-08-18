<template>
  <ArtDrawer ref="drawerRef" :show-footer="false"
    ><div v-if="run" class="close-detail"
      ><section class="close-detail__summary"
        ><div
          ><small>关账批次</small><strong>{{ run.runNo }}</strong
          ><span>{{
            run.period ? `${run.period.fiscalYear} 年第 ${run.period.periodNo} 期` : '--'
          }}</span></div
        ><ArtDictDisplay
          dict-code="fmsPeriodCloseRunStatus"
          :value="run.status"
          display="tag" /></section
      ><div class="close-detail__counts"
        ><article
          ><span>通过</span><strong>{{ run.passedCount }}</strong></article
        ><article
          ><span>提醒</span><strong>{{ run.warningCount }}</strong></article
        ><article
          ><span>阻断</span><strong>{{ run.blockingCount }}</strong></article
        ></div
      ><ElTable :data="checks" row-key="id"
        ><ElTableColumn prop="checkName" label="检查项目" min-width="170" /><ElTableColumn
          label="结果"
          width="100"
          ><template #default="{ row }"
            ><ArtDictDisplay
              dict-code="fmsPeriodCloseCheckStatus"
              :value="row.status"
              display="tag" /></template></ElTableColumn
        ><ElTableColumn prop="issueCount" label="问题数" width="90" align="right" /><ElTableColumn
          prop="summary"
          label="检查结论"
          min-width="280"
          show-overflow-tooltip
        /><ElTableColumn label="控制级别" width="110"
          ><template #default="{ row }"
            ><ElTag :type="row.isBlocking ? 'danger' : 'info'" effect="plain">{{
              row.isBlocking ? '阻断' : '提醒'
            }}</ElTag></template
          ></ElTableColumn
        ></ElTable
      ></div
    ></ArtDrawer
  >
</template>
<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import { fetchPeriodCloseChecks } from '@/api/fms'
  defineOptions({ name: 'FinancePeriodCloseDetailDrawer' })
  const drawerRef = ref<ArtDrawerExpose>()
  const run = ref<Api.Fms.PeriodCloseRunRecord>()
  const checks = ref<Api.Fms.PeriodCloseCheckRecord[]>([])
  async function handleOpen(row: Api.Fms.PeriodCloseRunRecord) {
    run.value = row
    const { data } = await fetchPeriodCloseChecks(row.id)
    checks.value = data ?? []
    await drawerRef.value?.handleOpen(undefined, {
      title: `关账检查详情 · ${row.runNo}`,
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }
  defineExpose({ handleOpen })
</script>
<style scoped lang="scss">
  .close-detail {
    display: grid;
    gap: 18px;
  }

  .close-detail__summary {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
    padding: 16px;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: var(--el-border-radius-base);
  }

  .close-detail__summary > div {
    display: grid;
    gap: 4px;
  }

  .close-detail small,
  .close-detail span {
    color: var(--el-text-color-secondary);
  }

  .close-detail__counts {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px;
  }

  .close-detail__counts article {
    display: grid;
    gap: 6px;
    padding: 14px;
    background: var(--el-fill-color-lighter);
    border-radius: var(--el-border-radius-base);
  }

  .close-detail__counts strong {
    font-size: 22px;
  }

  @media (width <= 767px) {
    .close-detail__counts {
      grid-template-columns: 1fr;
    }
  }
</style>
