<template>
  <ArtDrawer ref="drawerRef">
    <ArtAsyncState
      :loading="state.loading"
      loading-mode="skeleton"
      :error="state.error"
      :empty="!state.row"
      empty-text="暂无隐患详情"
      @retry="reload"
    >
      <div v-if="state.row" class="smis-danger-detail">
        <section class="smis-danger-detail__hero art-card-xs">
          <div>
            <span>{{ state.row.dangerNo }}</span>
            <h3>{{ state.row.dangerTitle }}</h3>
            <p>{{ state.row.riskPoint?.riskPointName || '--' }}</p>
          </div>
          <div class="smis-danger-detail__tags">
            <ArtDictDisplay
              dict-code="smisRiskLevel"
              :value="state.row.dangerLevel"
              display="tag"
            />
            <ArtDictDisplay
              dict-code="smisHiddenDangerStatus"
              :value="state.row.status"
              display="tag"
            />
          </div>
        </section>

        <section class="smis-danger-detail__section art-card-xs">
          <ArtSectionTitle :show-line="false">隐患与整改要求</ArtSectionTitle>
          <dl>
            <div
              ><dt>隐患描述</dt><dd>{{ state.row.dangerDescription }}</dd></div
            >
            <div
              ><dt>整改要求</dt
              ><dd>{{ state.row.rectificationRequirement || '待指派时明确' }}</dd></div
            >
            <div
              ><dt>责任人</dt><dd>{{ userName(state.row.responsibleUser) }}</dd></div
            >
            <div
              ><dt>整改期限</dt
              ><dd>{{ formatWithDayjs(state.row.rectificationDeadline ?? undefined) }}</dd></div
            >
            <div
              ><dt>关联危险源</dt><dd>{{ state.row.hazardSource?.hazardName || '--' }}</dd></div
            >
            <div
              ><dt>来源检查任务</dt><dd>{{ state.row.task?.taskNo || '现场直接上报' }}</dd></div
            >
          </dl>
        </section>

        <SmisAttachmentEvidence
          v-if="state.row.attachmentRefs.length"
          :model-value="state.row.attachmentRefs"
          title="隐患上报附件"
          description="现场上报时保存的原始证据。"
          readonly
        />

        <section class="smis-danger-detail__section art-card-xs">
          <ArtSectionTitle :show-line="false">治理时间线</ArtSectionTitle>
          <ElTimeline v-if="state.events.length">
            <ElTimelineItem
              v-for="event in state.events"
              :key="event.id"
              :timestamp="formatWithDayjs(event.createTime) || undefined"
              placement="top"
            >
              <div class="smis-danger-detail__event">
                <strong>{{ actionLabel(event.action) }}</strong>
                <span>{{ userName(event.actorUser) }}</span>
                <p>{{ event.comment || '未填写补充说明' }}</p>
                <SmisAttachmentEvidence
                  v-if="event.attachmentRefs.length"
                  :model-value="event.attachmentRefs"
                  title="本次处理附件"
                  description="随状态流转归档的整改或复查证据。"
                  readonly
                />
              </div>
            </ElTimelineItem>
          </ElTimeline>
          <ArtEmptyState
            v-else
            title="暂无治理记录"
            description="隐患上报和每次状态流转都会自动留痕。"
          />
        </section>

        <section class="smis-danger-detail__section art-card-xs">
          <ArtSectionTitle :show-line="false">流程审批历程</ArtSectionTitle>
          <WorkflowBusinessHistory
            business-type="smis_hidden_danger"
            :business-id="state.row.id!"
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
  import WorkflowBusinessHistory from '@/components/business/workflow-business-history/index.vue'
  import { fetchHiddenDangerEventList } from '@/api/smis'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'SmisHiddenDangerDrawer' })
  type Danger = Api.Smis.InspectionControl.HiddenDangerRecord
  type Event = Api.Smis.InspectionControl.HiddenDangerEventRecord
  const drawerRef = ref<ArtDrawerExpose<Danger>>()
  const state = reactive<{
    loading: boolean
    error: string | Error | null
    row: Danger | null
    events: Event[]
  }>({
    loading: false,
    error: null,
    row: null,
    events: []
  })

  const userName = (
    user?: { nickName?: string | null; userName?: string | null; userEmail: string } | null
  ) => user?.nickName || user?.userName || user?.userEmail || '--'
  const actionLabel = (action: Event['action']): string =>
    ({
      report: '隐患上报',
      assign: '指派整改',
      submit_review: '提交复查',
      reject: '复查退回',
      close: '复查销号',
      cancel: '隐患作废',
      workflow_started: '发起流程审批',
      workflow_approved: '流程审批通过并销号',
      workflow_rejected: '流程审批驳回',
      workflow_withdrawn: '流程审批撤回',
      workflow_cancelled: '流程审批终止'
    })[action]

  const reload = async (): Promise<void> => {
    if (!state.row?.id) return
    state.loading = true
    state.error = null
    try {
      const response = await fetchHiddenDangerEventList(state.row.id)
      state.events = response.data ?? []
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('隐患治理记录加载失败')
    } finally {
      state.loading = false
    }
  }
  const handleOpen = async (row: Danger): Promise<void> => {
    state.row = structuredClone(toRaw(row))
    state.events = []
    await drawerRef.value?.handleOpen(row, { title: '隐患治理档案', size: 'min(760px, 92vw)' })
    await reload()
  }
  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .smis-danger-detail {
    display: grid;
    gap: 12px;
    min-width: 0;

    &__hero {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      padding: 18px;

      span,
      p {
        color: var(--art-text-gray-600);
      }

      h3 {
        margin: 6px 0;
        font-size: 20px;
        line-height: 1.35;
      }
    }

    &__tags {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }

    &__section {
      padding: 18px;
    }

    dl {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px 20px;
      margin: 16px 0 0;
    }

    dl div {
      min-width: 0;
    }

    dt {
      margin-bottom: 5px;
      font-size: 13px;
      color: var(--art-text-gray-600);
    }

    dd {
      margin: 0;
      line-height: 1.6;
      overflow-wrap: anywhere;
    }

    &__event {
      display: grid;
      gap: 4px;
    }

    &__event span {
      font-size: 13px;
      color: var(--art-text-gray-600);
    }

    &__event p {
      margin: 0;
      line-height: 1.6;
    }
  }

  @media (width <= 640px) {
    .smis-danger-detail__hero {
      flex-direction: column;
    }

    .smis-danger-detail dl {
      grid-template-columns: 1fr;
    }
  }
</style>
