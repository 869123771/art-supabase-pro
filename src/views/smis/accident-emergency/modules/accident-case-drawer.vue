<template>
  <ArtDrawer ref="drawerRef" :show-footer="false" show-fullscreen-button>
    <ArtAsyncState
      :loading="state.loading"
      :error="state.error"
      :empty="!state.row"
      @retry="reload"
    >
      <div v-if="state.row" class="accident-case-detail">
        <section class="accident-case-detail__hero art-card-xs">
          <div
            ><span>{{ state.row.caseNo }}</span
            ><h3>{{ state.row.caseTitle }}</h3
            ><p v-if="canViewAccidentField(state.row, 'incidentLocation')">
              {{ state.row.location || '未登记地点' }}
            </p></div
          >
          <ArtDictDisplay
            dict-code="smisAccidentCaseStatus"
            :value="state.row.status"
            display="tag"
          />
        </section>
        <section class="accident-case-detail__section art-card-xs">
          <ArtSectionTitle :show-line="false">事件与调查信息</ArtSectionTitle>
          <dl>
            <div
              ><dt>发生时间</dt><dd>{{ formatWithDayjs(state.row.occurredAt) }}</dd></div
            >
            <div
              ><dt>严重程度</dt><dd>{{ severityLabel(state.row.severity) }}</dd></div
            >
            <div
              ><dt>关联风险点</dt><dd>{{ state.row.riskPoint?.riskPointName || '--' }}</dd></div
            >
            <div v-if="canViewAccidentField(state.row, 'caseParticipants')"
              ><dt>调查负责人</dt><dd>{{ userName(state.row.investigatorUser) }}</dd></div
            >
            <div v-if="canViewAccidentField(state.row, 'casualtyAndLoss')"
              ><dt>伤亡人数</dt><dd>{{ formatSensitiveCount(state.row.casualties) }}</dd></div
            >
            <div v-if="canViewAccidentField(state.row, 'casualtyAndLoss')"
              ><dt>经济损失</dt><dd>{{ formatSensitiveMoney(state.row.economicLoss) }}</dd></div
            >
            <div v-if="canViewAccidentField(state.row, 'investigationDetails')" class="is-wide"
              ><dt>事件描述</dt><dd>{{ state.row.description || '--' }}</dd></div
            >
            <div v-if="canViewAccidentField(state.row, 'investigationDetails')" class="is-wide"
              ><dt>即时处置</dt><dd>{{ state.row.immediateActions || '--' }}</dd></div
            >
            <div v-if="canViewAccidentField(state.row, 'investigationDetails')" class="is-wide"
              ><dt>原因分析</dt><dd>{{ state.row.causeAnalysis || '--' }}</dd></div
            >
            <div v-if="canViewAccidentField(state.row, 'investigationDetails')" class="is-wide"
              ><dt>纠正措施</dt><dd>{{ state.row.correctiveActions || '--' }}</dd></div
            >
          </dl>
        </section>
        <SmisAttachmentEvidence
          v-if="
            canViewAccidentField(state.row, 'caseEvidence') &&
            (state.row.attachmentRefs?.length ?? 0) > 0
          "
          :model-value="state.row.attachmentRefs ?? []"
          readonly
          title="事故上报附件"
        />
        <section class="accident-case-detail__section art-card-xs">
          <ArtSectionTitle :show-line="false">处理时间线</ArtSectionTitle>
          <ElTimeline v-if="state.events.length">
            <ElTimelineItem
              v-for="event in state.events"
              :key="event.id"
              :timestamp="formatWithDayjs(event.createTime) || undefined"
              placement="top"
            >
              <div class="accident-case-detail__event"
                ><strong>{{ actionLabel(event.action) }}</strong
                ><small v-if="canViewAccidentField(state.row, 'caseParticipants')">
                  {{ userName(event.actorUser) }}
                </small>
                <p v-if="canViewAccidentField(state.row, 'investigationDetails')">
                  {{ event.comment || '未填写说明' }}
                </p>
                <SmisAttachmentEvidence
                  v-if="
                    canViewAccidentField(state.row, 'caseEvidence') &&
                    (event.attachmentRefs?.length ?? 0) > 0
                  "
                  :model-value="event.attachmentRefs ?? []"
                  readonly
                  title="本次处理附件"
                />
              </div>
            </ElTimelineItem>
          </ElTimeline>
          <ArtEmptyState
            v-else
            compact
            title="暂无处理记录"
            description="上报与每次状态流转都会自动留痕。"
          />
        </section>
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import SmisAttachmentEvidence from '@/views/smis/components/smis-attachment-evidence.vue'
  import { fetchAccidentCaseDetail, fetchAccidentCaseEventList } from '@/api/smis'
  import { formatSensitiveNumber } from '@/utils/field-permission'
  import { formatWithDayjs } from '@/utils/time'
  import { canViewAccidentField } from './accident-field-access'

  defineOptions({ name: 'SmisAccidentCaseDrawer' })
  type Row = Api.Smis.AccidentEmergency.AccidentCaseRecord
  type Event = Api.Smis.AccidentEmergency.AccidentCaseEventRecord
  const drawerRef = ref<ArtDrawerExpose<Row>>()
  const state = reactive<{
    loading: boolean
    error: Error | string | null
    row: Row | null
    events: Event[]
  }>({ loading: false, error: null, row: null, events: [] })
  const userName = (user?: Api.Smis.AccidentEmergency.UserRef | null) =>
    user?.nickName || user?.userName || user?.userEmail || '--'
  const severityLabel = (value: Row['severity']) =>
    ({ slight: '轻微', general: '一般', major: '较大', critical: '重大' })[value]
  const actionLabel = (action: Event['action']) =>
    ({
      report: '事件上报',
      investigate: '立案调查',
      rectify: '进入整改',
      close: '结案',
      cancel: '作废'
    })[action]
  const formatSensitiveCount = (value?: number | string | null): string =>
    formatSensitiveNumber(value, { maximumFractionDigits: 0 })
  const formatSensitiveMoney = (value?: number | string | null): string => {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥ ${formatted}`
  }
  const reload = async (): Promise<void> => {
    if (!state.row?.id) return
    state.loading = true
    state.error = null
    try {
      const [detail, events] = await Promise.all([
        fetchAccidentCaseDetail(state.row.id),
        fetchAccidentCaseEventList(state.row.id)
      ])
      state.row = detail.data
      state.events = events.data ?? []
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('处理记录加载失败')
    } finally {
      state.loading = false
    }
  }
  const handleOpen = async (row: Row): Promise<void> => {
    state.row = structuredClone(toRaw(row))
    state.events = []
    await drawerRef.value?.handleOpen(row, { title: '事故事件档案', size: 'min(800px, 94vw)' })
    await reload()
  }
  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .accident-case-detail {
    display: grid;
    gap: 12px;
    min-width: 0;
  }

  .accident-case-detail__hero {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
    padding: 18px;
  }

  .accident-case-detail__hero span,
  .accident-case-detail__hero p,
  .accident-case-detail__event small {
    color: var(--art-text-gray-600);
  }

  .accident-case-detail__hero h3 {
    margin: 6px 0;
    font-size: 20px;
  }

  .accident-case-detail__section {
    padding: 18px;
  }

  .accident-case-detail dl {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px 20px;
    margin: 16px 0 0;
  }

  .accident-case-detail dl .is-wide {
    grid-column: 1 / -1;
  }

  .accident-case-detail dt {
    margin-bottom: 5px;
    font-size: 13px;
    color: var(--art-text-gray-600);
  }

  .accident-case-detail dd {
    margin: 0;
    line-height: 1.6;
    overflow-wrap: anywhere;
  }

  .accident-case-detail__event {
    display: grid;
    gap: 4px;
  }

  .accident-case-detail__event p {
    margin: 0;
    line-height: 1.6;
  }

  @media (width <= 640px) {
    .accident-case-detail__hero {
      flex-direction: column;
    }

    .accident-case-detail dl {
      grid-template-columns: 1fr;
    }

    .accident-case-detail dl .is-wide {
      grid-column: auto;
    }
  }
</style>
