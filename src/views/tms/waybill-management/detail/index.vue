<template>
  <ArtPageShell
    class="waybill-detail"
    :loading="detail.loading"
    loading-mode="skeleton"
    :error="detail.error"
    :empty="detail.loaded && !detail.data"
    empty-text="暂无运单详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.waybillNo || '运单详情'"
      :subtitle="routeSubtitle"
      show-back
      @back="goBack"
    >
      <template #status>
        <ArtDictDisplay
          v-if="detail.data"
          dict-code="tmsWaybillStatus"
          :value="detail.data.status"
          display="tag"
        />
      </template>
      <template #meta>
        <div v-if="detail.data" class="waybill-detail__header-meta">
          <span
            ><ArtSvgIcon icon="ri:steering-2-line" aria-hidden="true" />{{
              detail.data.driver?.driverName || '未分配司机'
            }}</span
          >
          <span
            ><ArtSvgIcon icon="ri:truck-line" aria-hidden="true" />{{
              detail.data.vehicle?.plateNo || '未分配车辆'
            }}</span
          >
          <span
            ><ArtSvgIcon icon="ri:time-line" aria-hidden="true" />更新于
            {{ formatDateTime(detail.data.updateTime) }}</span
          >
        </div>
      </template>
      <ElButton v-if="detail.data?.orderId" @click="openOrderDetail">
        <ArtSvgIcon icon="ri:file-list-3-line" aria-hidden="true" />
        查看订单
      </ElButton>
    </ArtPageHeader>

    <section v-if="detail.data" class="waybill-detail__overview art-card-xs">
      <div v-for="item in overviewItems" :key="item.label" class="waybill-detail__metric">
        <span :class="`is-${item.tone}`"><ArtSvgIcon :icon="item.icon" aria-hidden="true" /></span>
        <div
          ><small>{{ item.label }}</small
          ><strong>{{ item.value }}</strong
          ><p>{{ item.description }}</p></div
        >
      </div>
    </section>

    <section v-if="detail.data" class="waybill-detail__journey art-card-xs">
      <div class="waybill-detail__journey-heading">
        <div>
          <strong>运输进度</strong>
          <span>{{ journeySummary }}</span>
        </div>
        <div class="waybill-detail__journey-legend">
          <span><i class="is-done"></i>已完成</span>
          <span><i class="is-current"></i>当前节点</span>
          <span><i></i>待执行</span>
        </div>
      </div>
      <div class="waybill-detail__journey-scroll">
        <ol class="waybill-detail__journey-track">
          <li
            v-for="(node, index) in journeyNodes"
            :key="node.key"
            :class="{ 'is-done': node.done, 'is-current': node.current }"
          >
            <div class="waybill-detail__journey-node">
              <span><ArtSvgIcon :icon="node.icon" aria-hidden="true" /></span>
              <div>
                <strong>{{ node.label }}</strong>
                <small :class="{ 'is-planned': node.metaLabel }">
                  <span v-if="node.metaLabel">{{ node.metaLabel }}</span>
                  {{ node.metaValue }}
                </small>
              </div>
            </div>
            <i v-if="index < journeyNodes.length - 1"></i>
          </li>
        </ol>
      </div>
    </section>

    <section v-if="detail.data" class="waybill-detail__workspace">
      <ElTabs v-model="detail.activeTab" class="waybill-detail__tabs">
        <ElTabPane label="业务总览" name="overview">
          <WaybillInfoPanel :waybill="detail.data" @open-order="openOrderDetail" />
        </ElTabPane>
        <ElTabPane name="tracking">
          <template #label>
            <span class="waybill-detail__tab-label"
              >运单跟踪<ElBadge :value="detail.data.events.length" :max="99"
            /></span>
          </template>
          <WaybillTrackingPanel :waybill="detail.data" />
        </ElTabPane>
        <ElTabPane name="operations" lazy>
          <template #label>
            <span class="waybill-detail__tab-label"
              >装卸作业<ElBadge
                v-if="detail.data.cargoOperations.length"
                :value="detail.data.cargoOperations.length"
                :max="99"
            /></span>
          </template>
          <WaybillOperationPanel :waybill="detail.data" />
        </ElTabPane>
        <ElTabPane name="documents" lazy>
          <template #label>
            <span class="waybill-detail__tab-label"
              >单证影像<ElBadge v-if="evidenceCount" :value="evidenceCount" :max="99"
            /></span>
          </template>
          <WaybillDocumentPanel :waybill="detail.data" />
        </ElTabPane>
        <ElTabPane label="轨迹和定位" name="route" lazy>
          <WaybillRoutePanel :waybill="detail.data" />
        </ElTabPane>
      </ElTabs>
    </section>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import type { UnwrapNestedRefs } from 'vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtPageHeader from '@/components/core/layouts/art-page-header/index.vue'
  import ArtPageShell from '@/components/core/layouts/art-page-shell/index.vue'
  import { fetchWaybillDetail } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'
  import WaybillDocumentPanel from './modules/waybill-document-panel.vue'
  import WaybillInfoPanel from './modules/waybill-info-panel.vue'
  import WaybillOperationPanel from './modules/waybill-operation-panel.vue'
  import WaybillRoutePanel from './modules/waybill-route-panel.vue'
  import WaybillTrackingPanel from './modules/waybill-tracking-panel.vue'

  defineOptions({ name: 'TmsWaybillDetail' })

  type DetailTab = 'overview' | 'tracking' | 'operations' | 'documents' | 'route'

  interface DetailGroup {
    activeTab: DetailTab
    data?: Api.Tms.Waybill.WaybillDetailRecord
    error: Error | null
    loaded: boolean
    loading: boolean
  }

  interface OverviewItem {
    label: string
    value: string
    description: string
    icon: string
    tone: 'primary' | 'success' | 'warning' | 'info'
  }

  interface JourneyNode {
    key: string
    label: string
    icon: string
    time?: string | null
    metaLabel?: string
    metaValue: string
    done: boolean
    current: boolean
  }

  const route = useRoute()
  const router = useRouter()
  const detail: UnwrapNestedRefs<DetailGroup> = reactive<DetailGroup>({
    activeTab: normalizeTab(route.query.tab),
    data: undefined,
    error: null,
    loaded: false,
    loading: false
  })

  const routeSubtitle = computed(() => {
    const data = detail.data
    return data
      ? [data.originCity, data.destinationCity].filter(Boolean).join(' → ') || '运输执行详情'
      : '运输执行详情'
  })

  const journeyNodes = computed<JourneyNode[]>(() => {
    const data = detail.data
    if (!data) return []
    const definitions = [
      { key: 'accepted', label: '接单', icon: 'ri:hand-coin-line', time: data.acceptedAt },
      { key: 'loaded', label: '装货', icon: 'ri:archive-stack-line', time: data.loadedAt },
      { key: 'departed', label: '发车', icon: 'ri:truck-line', time: data.departedAt },
      { key: 'arrived', label: '到达', icon: 'ri:map-pin-2-line', time: data.arrivedAt },
      { key: 'unloaded', label: '卸货', icon: 'ri:inbox-unarchive-line', time: data.unloadedAt },
      {
        key: 'signed',
        label: '签收',
        icon: 'ri:quill-pen-line',
        time: data.execution?.signedAt || data.order?.signedAt || findEventTime(data, 'signed')
      },
      { key: 'completed', label: '完成', icon: 'ri:checkbox-circle-line', time: data.completedAt }
    ]
    const doneIndexes = definitions.flatMap((item, index) => (item.time ? [index] : []))
    const currentIndex = doneIndexes.at(-1) ?? 0
    return definitions.map((item, index) => {
      const fallback = getJourneyFallback(item.key, data)
      return {
        ...item,
        metaLabel: item.time ? undefined : fallback.label,
        metaValue: item.time ? formatDateTime(item.time) : fallback.value,
        done: Boolean(item.time),
        current: index === currentIndex && data.status !== 'cancelled'
      }
    })
  })

  const journeySummary = computed(() => {
    const data = detail.data
    if (!data) return ''
    if (data.status === 'cancelled') return `运单已于 ${formatDateTime(data.cancelledAt)} 取消`
    const completed = journeyNodes.value.filter((item) => item.done).length
    return `已完成 ${completed}/${journeyNodes.value.length} 个关键节点 · 全流程操作可追溯`
  })

  const evidenceCount = computed(() => (detail.data ? countEvidence(detail.data) : 0))

  const overviewItems = computed<OverviewItem[]>(() => {
    const data = detail.data
    if (!data) return []
    const latestEvent = data.events[0]
    return [
      {
        label: '当前节点',
        value: getLatestEventLabel(latestEvent?.eventType, data.status),
        description: latestEvent ? formatDateTime(latestEvent.eventTime) : '暂无节点时间',
        icon: 'ri:route-line',
        tone: 'primary'
      },
      {
        label: '司机端记录',
        value: `${data.events.filter(isDriverEvent).length} 条`,
        description: '司机端操作已纳入统一审计',
        icon: 'ri:smartphone-line',
        tone: 'success'
      },
      {
        label: '作业凭证',
        value: `${countEvidence(data)} 份`,
        description: '现场照片、磅单、回单及签名',
        icon: 'ri:image-2-line',
        tone: 'warning'
      },
      {
        label: '定位节点',
        value: `${countLocations(data)} 个`,
        description: '地址端点、签到和运输事件位置',
        icon: 'ri:map-pin-line',
        tone: 'info'
      }
    ]
  })

  onMounted(() => {
    void loadDetail()
  })
  watch(
    () => route.params.id,
    () => {
      void loadDetail()
    }
  )
  watch(
    () => detail.activeTab,
    (tab) => {
      if (route.query.tab === tab) return
      void router.replace({ query: { ...route.query, tab } })
    }
  )

  async function loadDetail(): Promise<void> {
    const waybillId = String(route.params.id || '')
    if (!waybillId) {
      Object.assign(detail, { error: new Error('缺少运单标识'), loaded: true })
      return
    }
    detail.loading = true
    detail.error = null
    try {
      const { data } = await fetchWaybillDetail(waybillId)
      detail.data = data ?? undefined
    } catch (error) {
      detail.error = error instanceof Error ? error : new Error('运单详情加载失败，请稍后重试')
    } finally {
      detail.loaded = true
      detail.loading = false
    }
  }

  function normalizeTab(value: unknown): DetailTab {
    const normalized = String(value) === 'info' ? 'overview' : String(value)
    return ['overview', 'tracking', 'operations', 'documents', 'route'].includes(normalized)
      ? (normalized as DetailTab)
      : 'overview'
  }

  function getLatestEventLabel(eventType: string | undefined, status: string): string {
    const labels: Record<string, string> = {
      created: '运单创建',
      accepted: '已接单',
      loading_checked_in: '装货签到',
      loaded: '已装货',
      departed: '运输中',
      arrived: '已到达',
      unloaded: '已卸货',
      signed: '已签收',
      completed: '已完成',
      cancelled: '已取消'
    }
    return labels[eventType || ''] || labels[status] || status || '-'
  }

  function countEvidence(data: Api.Tms.Waybill.WaybillDetailRecord): number {
    const execution = data.execution
    const urls = [
      ...data.proofs.map((proof) => proof.fileUrl),
      ...data.pickupPhotos,
      ...data.deliveryPhotos,
      ...data.receiptAttachments,
      ...(data.order?.imageUrls ?? []),
      ...(data.order?.receiptImageUrls ?? []),
      ...data.cargoOperations.flatMap((operation) => [
        ...operation.photoUrls,
        ...operation.weighbridgeTicketUrls
      ]),
      ...(execution?.departurePhotoUrls ?? []),
      ...(execution?.receiptUrls ?? []),
      ...(execution?.signatureUrls ?? []),
      ...(execution?.returnPhotoUrls ?? [])
    ]
    return new Set(urls.filter(Boolean)).size
  }

  function findEventTime(
    data: Api.Tms.Waybill.WaybillDetailRecord,
    eventType: string
  ): string | null {
    return data.events.find((event) => event.eventType === eventType)?.eventTime ?? null
  }

  function getJourneyFallback(
    key: string,
    data: Api.Tms.Waybill.WaybillDetailRecord
  ): { label?: string; value: string } {
    if (data.status === 'cancelled') return { value: '流程已终止' }
    const plans: Record<string, string | null | undefined> = {
      loaded: data.plannedLoadTime,
      unloaded: data.plannedUnloadTime
    }
    return plans[key] ? { label: '计划', value: formatDateTime(plans[key]) } : { value: '待执行' }
  }

  function countLocations(data: Api.Tms.Waybill.WaybillDetailRecord): number {
    return (
      data.cargoOperations.length +
      data.events.filter((event) => event.longitude != null && event.latitude != null).length +
      (data.shipperLongitude != null && data.shipperLatitude != null ? 1 : 0) +
      (data.receiverLongitude != null && data.receiverLatitude != null ? 1 : 0)
    )
  }

  function isDriverEvent(event: Api.Tms.Waybill.WaybillEventRecord): boolean {
    return (
      event.payload.source === 'driver' ||
      Boolean(event.operatorName && event.operatorName === detail.data?.driver?.driverName)
    )
  }

  function openOrderDetail(): void {
    if (!detail.data?.orderId) return
    void router.push({ name: 'TmsOrderDetail', params: { id: detail.data.orderId } })
  }

  function goBack(): void {
    void router.back()
  }

  function formatDateTime(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm') || '-'
  }
</script>

<style scoped lang="scss">
  .waybill-detail {
    min-height: 100%;
    padding: 12px 16px 18px;
    font-size: var(--art-font-size-body);
    line-height: var(--art-line-height-body);
    background: var(--art-main-bg-color);

    :deep(strong) {
      font-weight: 600;
    }

    :deep(small) {
      font-size: var(--art-font-size-caption);
      line-height: 18px;
    }

    &__header-meta {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-3);
    }

    &__header-meta span {
      display: inline-flex;
      gap: 5px;
      align-items: center;
    }

    &__overview {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 0;
      padding: 0;
      margin-top: var(--art-space-3);
      overflow: hidden;
    }

    &__journey {
      min-width: 0;
      padding: var(--art-space-4);
      margin-top: var(--art-space-3);
    }

    &__journey-heading {
      display: flex;
      gap: var(--art-space-4);
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: var(--art-space-4);

      > div:first-child {
        display: grid;
        gap: 4px;
      }

      span {
        color: var(--el-text-color-secondary);
      }
    }

    &__journey-legend {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-3);

      > span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        white-space: nowrap;
      }

      i {
        width: 8px;
        height: 8px;
        background: var(--el-border-color);
        border-radius: 50%;

        &.is-done {
          background: var(--el-color-success);
        }

        &.is-current {
          background: var(--el-color-primary);
          box-shadow: 0 0 0 3px var(--el-color-primary-light-8);
        }
      }
    }

    &__journey-scroll {
      padding-bottom: 2px;
      overflow-x: auto;
      scrollbar-width: thin;
    }

    &__journey-track {
      display: flex;
      align-items: center;
      min-width: 1160px;
      padding: 0;
      margin: 0;
      list-style: none;

      > li {
        display: flex;
        flex: 1;
        align-items: center;
        min-width: 0;

        > i {
          flex: 1;
          min-width: 20px;
          height: 2px;
          margin-inline: var(--art-space-2);
          background: var(--el-border-color-lighter);
        }

        &.is-done > i {
          background: var(--el-color-success-light-5);
        }
      }
    }

    &__journey-node {
      display: flex;
      gap: var(--art-space-2);
      align-items: center;
      min-width: 158px;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 36px;
        height: 36px;
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color-lighter);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: 50%;
      }

      > div {
        display: grid;
        gap: 3px;
        min-width: 0;
      }

      small {
        display: inline-flex;
        gap: 4px;
        align-items: center;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-secondary);
        white-space: nowrap;

        > span {
          padding: 1px 5px;
          font-size: 10px;
          line-height: 16px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 999px;
        }
      }
    }

    &__journey-track > li.is-done &__journey-node > span {
      color: var(--el-color-success);
      background: var(--el-color-success-light-9);
      border-color: var(--el-color-success-light-7);
    }

    &__journey-track > li.is-current &__journey-node > span {
      color: white;
      background: var(--el-color-primary);
      border-color: var(--el-color-primary);
      box-shadow: 0 0 0 4px var(--el-color-primary-light-9);
    }

    &__metric {
      display: flex;
      gap: var(--art-space-3);
      min-width: 0;
      padding: var(--art-space-4);
      border-right: 1px solid var(--el-border-color-lighter);

      &:last-child {
        border-right: 0;
      }

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 42px;
        height: 42px;
        font-size: 20px;
        border-radius: var(--el-border-radius-base);
      }

      > span.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      > span.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      > span.is-warning {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }

      > span.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }

      > div {
        display: grid;
        gap: 2px;
        min-width: 0;
      }

      small,
      p {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 17px;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }

      p {
        margin: 0;
        font-size: 11px;
      }
    }

    &__workspace {
      margin-top: var(--art-space-3);
    }

    &__tabs {
      :deep(.el-tabs__header) {
        padding: 0 var(--art-space-4);
        margin: 0;
        background: var(--el-bg-color);
        border-radius: var(--el-border-radius-base) var(--el-border-radius-base) 0 0;
      }

      :deep(.el-tabs__item) {
        height: 52px;
        font-size: 14px;
      }

      :deep(.el-tabs__content) {
        padding-top: var(--art-space-3);
      }
    }

    &__tab-label {
      display: inline-flex;
      gap: var(--art-space-2);
      align-items: center;
    }
  }

  @media (width <= 1100px) {
    .waybill-detail {
      &__overview {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__metric:nth-child(2) {
        border-right: 0;
      }

      &__metric:nth-child(-n + 2) {
        border-bottom: 1px solid var(--el-border-color-lighter);
      }
    }
  }

  @media (width <= 640px) {
    .waybill-detail {
      padding-inline: 10px;

      &__overview {
        grid-template-columns: 1fr;
      }

      &__metric {
        border-right: 0;
        border-bottom: 1px solid var(--el-border-color-lighter);
      }

      &__metric:last-child {
        border-bottom: 0;
      }

      &__tabs :deep(.el-tabs__header) {
        padding-inline: var(--art-space-2);
      }

      &__tabs :deep(.el-tabs__item) {
        padding-inline: var(--art-space-3);
      }

      &__journey-heading {
        flex-direction: column;
      }
    }
  }
</style>
