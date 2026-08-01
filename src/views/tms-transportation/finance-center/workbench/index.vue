<template>
  <div class="finance-workbench">
    <FinanceMetricGrid :items="metrics" />

    <div class="finance-workbench__content">
      <section class="art-card-xs finance-workbench__panel">
        <ArtSectionTitle>待办任务</ArtSectionTitle>
        <ElTable :data="workbenchTasks" table-layout="fixed">
          <ElTableColumn prop="title" label="任务" min-width="160" />
          <ElTableColumn prop="count" label="数量" width="85">
            <template #default="{ row }">{{ row.count }} 项</template>
          </ElTableColumn>
          <ElTableColumn prop="amount" label="涉及金额" min-width="130" align="right">
            <template #default="{ row }">{{ formatMoney(row.amount) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="urgency" label="优先级" width="90">
            <template #default="{ row }">
              <ElTag :type="urgencyType(row.urgency)">{{ row.urgency }}</ElTag>
            </template>
          </ElTableColumn>
        </ElTable>
      </section>

      <section class="art-card-xs finance-workbench__panel">
        <ArtSectionTitle>本月经营概览</ArtSectionTitle>
        <div class="finance-workbench__progress-list">
          <div
            v-for="item in progressItems"
            :key="item.label"
            class="finance-workbench__progress-item"
          >
            <div
              ><span>{{ item.label }}</span
              ><strong>{{ item.value }}</strong></div
            >
            <ElProgress :percentage="item.percent" :stroke-width="10" :color="item.color" />
          </div>
        </div>
      </section>
    </div>

    <section class="art-card-xs finance-workbench__panel">
      <ArtSectionTitle>结算提醒</ArtSectionTitle>
      <ElAlert
        title="有 3 份客户对账单已超过约定回款日，请优先跟进。"
        type="warning"
        show-icon
        :closable="false"
      />
      <ElAlert
        title="有 2 笔承运商付款尚未关联对账单，建议完成核销。"
        type="info"
        show-icon
        :closable="false"
      />
    </section>
  </div>
</template>

<script setup lang="ts">
  import type { TagProps } from 'element-plus'
  import { formatMoney, workbenchTasks } from '../modules/finance-scaffold-data'
  import type { FinanceMetric } from '../modules/finance-types'
  import FinanceMetricGrid from '../modules/finance-metric-grid.vue'

  defineOptions({ name: 'TmsFinanceWorkbench' })

  const metrics: FinanceMetric[] = [
    {
      label: '客户应收余额',
      value: '¥1,286,500.00',
      trend: '较上月 +8.6%',
      icon: 'ri:funds-line',
      tone: 'primary'
    },
    {
      label: '承运商应付余额',
      value: '¥786,300.00',
      trend: '本周待付 ¥116,900',
      icon: 'ri:bank-card-line',
      tone: 'warning'
    },
    {
      label: '本月已回款',
      value: '¥968,000.00',
      trend: '回款率 73.4%',
      icon: 'ri:money-cny-circle-line',
      tone: 'success'
    },
    {
      label: '本月运输毛利',
      value: '¥326,800.00',
      trend: '综合毛利率 21.7%',
      icon: 'ri:line-chart-line',
      tone: 'danger'
    }
  ]
  const progressItems = [
    { label: '客户回款完成率', value: '73.4%', percent: 73.4, color: 'var(--el-color-success)' },
    { label: '承运商付款完成率', value: '61.8%', percent: 61.8, color: 'var(--el-color-warning)' },
    { label: '发票匹配完成率', value: '82.5%', percent: 82.5, color: 'var(--el-color-primary)' },
    { label: '费用审核完成率', value: '89.2%', percent: 89.2, color: 'var(--el-color-success)' }
  ]

  function urgencyType(value: string): TagProps['type'] {
    if (value === '紧急') return 'danger'
    if (value === '关注') return 'warning'
    return 'info'
  }
</script>

<style scoped lang="scss">
  .finance-workbench {
    display: grid;
    gap: 12px;

    &__content {
      display: grid;
      grid-template-columns: 1.35fr 1fr;
      gap: 12px;
    }
    &__panel {
      padding: 18px;
    }
    &__progress-list {
      display: grid;
      gap: 22px;
      margin-top: 18px;
    }
    &__progress-item {
      display: grid;
      gap: 8px;

      div {
        display: flex;
        justify-content: space-between;
        color: var(--el-text-color-regular);
      }
    }

    .el-alert + .el-alert {
      margin-top: 10px;
    }
  }

  @media (width <= 900px) {
    .finance-workbench__content {
      grid-template-columns: 1fr;
    }
  }
</style>
