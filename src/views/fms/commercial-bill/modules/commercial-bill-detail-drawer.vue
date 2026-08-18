<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <template v-if="bill">
      <div class="commercial-bill-detail">
        <section class="commercial-bill-detail__summary">
          <div>
            <span>票据编号</span>
            <strong translate="no">{{ bill.billNo }}</strong>
            <small>{{ bill.externalBillNo || '未登记票面号码' }}</small>
          </div>
          <ElTag :type="dictTagType('fmsBillStatus', bill.status)" effect="light">
            {{ dictLabel('fmsBillStatus', bill.status) }}
          </ElTag>
        </section>

        <ArtDescriptions :data="bill" :items="detailItems" :columns="2" />

        <section class="commercial-bill-detail__events">
          <div class="commercial-bill-detail__section-title">
            <div>
              <strong>流转记录</strong>
              <small>票据每一次状态变化均保留操作时间、金额与业务依据</small>
            </div>
          </div>
          <ElTimeline v-if="events.length">
            <ElTimelineItem
              v-for="event in events"
              :key="event.id"
              :timestamp="formatWithDayjs(event.createTime, 'YYYY-MM-DD HH:mm') || '--'"
              placement="top"
              :type="event.eventType === 'cancelled' ? 'danger' : 'primary'"
            >
              <div class="commercial-bill-detail__event-card">
                <strong>{{ dictLabel('fmsBillEventType', event.eventType) }}</strong>
                <span>{{ formatCurrencyValue(event.amount, bill.currencyCode) }}</span>
                <small>{{
                  event.counterpartyName || event.referenceNo || event.remark || '系统登记'
                }}</small>
              </div>
            </ElTimelineItem>
          </ElTimeline>
          <ElEmpty v-else description="草稿尚未产生流转记录" :image-size="72" />
        </section>
      </div>
    </template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { storeToRefs } from 'pinia'
  import type { TagProps } from 'element-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import { fetchCommercialBillEvents } from '@/api/fms'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceCommercialBillDetailDrawer' })

  type Bill = Api.Fms.CommercialBillRecord

  const { getDictMap } = storeToRefs(useUserStore())
  const drawerRef = ref<ArtDrawerExpose<Bill>>()
  const bill = ref<Bill>()
  const events = ref<Api.Fms.CommercialBillEventRecord[]>([])

  function dictLabel(code: keyof typeof getDictMap.value, value: string): string {
    return getDictMap.value[code]?.find((item) => item.value === value)?.label ?? value
  }

  function dictTagType(code: keyof typeof getDictMap.value, value: string): TagProps['type'] {
    return (getDictMap.value[code]?.find((item) => item.value === value)?.tagType ||
      'info') as TagProps['type']
  }

  const detailItems = computed<ArtDescriptionItem<Bill>[]>(() => {
    if (!bill.value) return []
    return [
      { key: 'direction', label: '票据方向', field: 'direction', dictCode: 'fmsBillDirection' },
      { key: 'billType', label: '票据类型', field: 'billType', dictCode: 'fmsBillType' },
      { key: 'drawerName', label: '出票人', field: 'drawerName' },
      { key: 'payeeName', label: '收款人', field: 'payeeName' },
      { key: 'acceptorName', label: '承兑人', field: 'acceptorName' },
      { key: 'counterpartyName', label: '往来单位', field: 'counterpartyName' },
      { key: 'issueDate', label: '出票日期', field: 'issueDate', format: 'date' },
      { key: 'dueDate', label: '到期日期', field: 'dueDate', format: 'date' },
      { key: 'faceAmount', label: '票面金额', field: 'faceAmount', format: 'money' },
      { key: 'settledAmount', label: '已结金额', field: 'settledAmount', format: 'money' },
      {
        key: 'transferable',
        label: '允许背书',
        field: 'transferable',
        formatter: (_value, row) => (row.transferable ? '允许' : '禁止')
      },
      { key: 'sourceNo', label: '来源单号', field: 'sourceNo', copyable: true },
      { key: 'remark', label: '备注', field: 'remark', span: 2 }
    ]
  })

  async function handleOpen(row: Bill): Promise<void> {
    bill.value = row
    events.value = []
    await drawerRef.value?.handleOpen(row, {
      title: `票据详情 · ${row.billNo}`,
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: async () => {
        const { data } = await fetchCommercialBillEvents(row.id)
        events.value = data ?? []
      },
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .commercial-bill-detail {
    display: grid;
    gap: 18px;

    &__summary {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      padding: 18px;
      background: linear-gradient(135deg, var(--el-color-primary-light-9), transparent);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > div {
        display: grid;
        gap: 4px;
      }

      span,
      small {
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 20px;
      }
    }

    &__events {
      padding: 18px;
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__section-title {
      margin-bottom: 18px;

      > div {
        display: grid;
        gap: 4px;
      }

      small {
        color: var(--el-text-color-secondary);
      }
    }

    &__event-card {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 4px 16px;
      padding: 12px 14px;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);

      small {
        grid-column: 1 / -1;
        color: var(--el-text-color-secondary);
      }
    }
  }
</style>
