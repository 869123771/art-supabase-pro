<template>
  <ArtDrawer ref="drawerRef">
    <ArtAsyncState
      :loading="state.loading"
      loading-mode="skeleton"
      :error="state.error"
      :empty="!state.riskPoint"
      empty-text="暂无风险档案"
      @retry="retryLoad"
    >
      <div v-if="state.riskPoint" class="smis-risk-profile">
        <section class="smis-risk-profile__overview">
          <article class="smis-risk-profile__identity art-card-xs">
            <div class="smis-risk-profile__identity-main">
              <span>{{ state.riskPoint.riskPointNo }}</span>
              <strong>{{ state.riskPoint.riskPointName }}</strong>
              <p>
                {{ state.riskPoint.site?.siteName || '--' }} ·
                {{ state.riskPoint.area?.areaName || '--' }}
              </p>
            </div>
            <ArtDictDisplay
              v-if="state.riskPoint.currentRiskLevel"
              dict-code="smisRiskLevel"
              :value="state.riskPoint.currentRiskLevel"
              display="tag"
            />
            <ElTag v-else type="info">待评估</ElTag>
          </article>

          <article class="smis-risk-profile__metric art-card-xs">
            <ArtSvgIcon icon="ri:alert-line" />
            <div
              ><strong>{{ state.hazards.length }}</strong
              ><span>危险源</span></div
            >
          </article>
          <article class="smis-risk-profile__metric art-card-xs">
            <ArtSvgIcon icon="ri:file-list-3-line" />
            <div
              ><strong>{{ state.assessments.length }}</strong
              ><span>评估版本</span></div
            >
          </article>
          <article class="smis-risk-profile__metric art-card-xs">
            <ArtSvgIcon icon="ri:shield-check-line" />
            <div
              ><strong>{{ measureCount }}</strong
              ><span>当前措施</span></div
            >
          </article>
        </section>

        <ElTabs v-model="state.activeTab" class="smis-risk-profile__tabs">
          <ElTabPane name="hazards" :label="`危险源辨识（${state.hazards.length}）`">
            <section class="smis-risk-profile__section art-card-xs">
              <div class="smis-risk-profile__section-header">
                <div>
                  <ArtSectionTitle :show-line="false">危险源清单</ArtSectionTitle>
                  <p>统一维护风险点下的人、物、环境和管理危险因素。</p>
                </div>
                <ElButton v-if="canAddHazard" type="primary" @click="openHazardDialog()">
                  <ArtSvgIcon icon="ri:add-line" />
                  新增危险源
                </ElButton>
              </div>

              <ArtTable
                :data="state.hazards"
                :columns="hazardColumns"
                :pagination="false"
                height="380px"
                row-key="id"
                empty-text="暂无危险源"
                empty-description="先辨识危险源，再创建 LEC 评估版本。"
                border
              />
            </section>
          </ElTabPane>

          <ElTabPane name="assessments" :label="`LEC 评估（${state.assessments.length}）`">
            <section class="smis-risk-profile__assessment-toolbar art-card-xs">
              <div class="smis-risk-profile__version-select">
                <span>评估版本</span>
                <ElSelect
                  v-model="state.selectedAssessmentId"
                  placeholder="请选择评估版本"
                  :disabled="state.assessments.length === 0"
                  @change="handleAssessmentChange"
                >
                  <ElOption
                    v-for="assessment in state.assessments"
                    :key="assessment.id"
                    :label="getAssessmentOptionLabel(assessment)"
                    :value="assessment.id!"
                  />
                </ElSelect>
              </div>
              <ElButton
                v-if="canAssess"
                type="primary"
                :disabled="state.riskPoint.status !== 'active'"
                :title="
                  state.riskPoint.status === 'active'
                    ? '创建新的评估版本'
                    : '只有启用状态的风险点可以创建评估'
                "
                @click="openAssessmentDialog()"
              >
                <ArtSvgIcon icon="ri:add-line" />
                创建评估版本
              </ElButton>
            </section>

            <ArtAsyncState
              :loading="state.assessmentLoading"
              loading-mode="skeleton"
              :empty="!selectedAssessment"
              empty-text="暂无评估版本"
              empty-description="创建评估版本后，为危险源录入 LEC 分值和管控措施。"
            >
              <template v-if="selectedAssessment">
                <section class="smis-risk-profile__assessment-head art-card-xs">
                  <div class="smis-risk-profile__assessment-summary">
                    <div class="smis-risk-profile__assessment-title">
                      <strong>V{{ selectedAssessment.versionNo }}</strong>
                      <ArtDictDisplay
                        dict-code="smisAssessmentStatus"
                        :value="selectedAssessment.status"
                        display="tag"
                      />
                      <ArtDictDisplay
                        v-if="selectedAssessment.maxRiskLevel"
                        dict-code="smisRiskLevel"
                        :value="selectedAssessment.maxRiskLevel"
                        display="tag"
                      />
                    </div>
                    <p>{{ selectedAssessment.assessmentSummary || '未填写本版本评估说明' }}</p>
                    <div class="smis-risk-profile__assessment-meta">
                      <span>评估日期 {{ selectedAssessment.assessmentDate }}</span>
                      <span>评估人 {{ getUserName(selectedAssessment.assessorUser) }}</span>
                      <span>最高 D 值 {{ selectedAssessment.maxRiskScore ?? '--' }}</span>
                    </div>
                  </div>

                  <div class="smis-risk-profile__assessment-actions">
                    <ElButton
                      v-if="canEditSelectedAssessment"
                      @click="openAssessmentDialog(selectedAssessment)"
                    >
                      编辑信息
                    </ElButton>
                    <ElButton
                      v-if="canEditSelectedAssessment"
                      type="primary"
                      :disabled="state.items.length === 0"
                      @click="submitAssessment"
                    >
                      提交评估
                    </ElButton>
                    <ElButton
                      v-if="canAssess && selectedAssessment.status === 'submitted'"
                      @click="withdrawAssessment"
                    >
                      撤回草稿
                    </ElButton>
                    <ElButton
                      v-if="canActivate && selectedAssessment.status === 'submitted'"
                      type="success"
                      @click="activateAssessment"
                    >
                      评估生效
                    </ElButton>
                    <ElButton
                      v-if="canEditSelectedAssessment"
                      type="danger"
                      plain
                      @click="removeAssessment"
                    >
                      删除草稿
                    </ElButton>
                  </div>
                </section>

                <ElAlert
                  v-if="selectedAssessment.status === 'draft' && itemsWithoutMeasures > 0"
                  :title="`还有 ${itemsWithoutMeasures} 个评估项未配置管控措施，暂不能提交。`"
                  type="warning"
                  :closable="false"
                  show-icon
                />

                <section class="smis-risk-profile__section art-card-xs">
                  <div class="smis-risk-profile__section-header">
                    <div>
                      <ArtSectionTitle :show-line="false">LEC 评估明细</ArtSectionTitle>
                      <p>分值和危险源描述均按当前版本固化，后续修改主档不会影响历史。</p>
                    </div>
                    <ElButton
                      v-if="canEditSelectedAssessment"
                      type="primary"
                      :disabled="availableHazards.length === 0"
                      :title="
                        availableHazards.length
                          ? '新增 LEC 评估项'
                          : '所有已启用危险源均已纳入本版本'
                      "
                      @click="openAssessmentItemDialog()"
                    >
                      <ArtSvgIcon icon="ri:add-line" />
                      新增评估项
                    </ElButton>
                  </div>

                  <ArtEmptyState
                    v-if="state.items.length === 0"
                    title="暂无 LEC 评估项"
                    description="从已辨识危险源中选择对象，录入 L、E、C 分值。"
                    size="compact"
                    :visual-size="76"
                  />

                  <div v-else class="smis-risk-profile__item-list">
                    <article
                      v-for="item in state.items"
                      :key="item.id"
                      class="smis-risk-profile__item-card"
                    >
                      <header class="smis-risk-profile__item-header">
                        <div class="smis-risk-profile__item-identity">
                          <span>{{ item.hazardSource?.sourceNo || '危险源' }}</span>
                          <strong>{{
                            item.hazardNameSnapshot || item.hazardSource?.hazardName
                          }}</strong>
                          <p>{{ item.hazardDescriptionSnapshot || '未填写危险源描述' }}</p>
                        </div>
                        <div class="smis-risk-profile__score">
                          <span>L {{ item.likelihood }}</span>
                          <span>E {{ item.exposure }}</span>
                          <span>C {{ item.consequence }}</span>
                          <strong>D {{ item.riskScore }}</strong>
                          <ArtDictDisplay
                            dict-code="smisRiskLevel"
                            :value="item.riskLevel"
                            display="tag"
                          />
                        </div>
                        <div
                          v-if="canEditSelectedAssessment"
                          class="smis-risk-profile__item-actions"
                        >
                          <ElButton link type="primary" @click="openAssessmentItemDialog(item)">
                            编辑
                          </ElButton>
                          <ElButton link type="danger" @click="removeAssessmentItem(item)">
                            删除
                          </ElButton>
                        </div>
                      </header>

                      <div v-if="item.evaluationNote" class="smis-risk-profile__note">
                        <span>评估说明</span>
                        <p>{{ item.evaluationNote }}</p>
                      </div>

                      <div class="smis-risk-profile__measure-head">
                        <div>
                          <strong>管控措施</strong>
                          <span>共 {{ item.controlMeasures?.length ?? 0 }} 条</span>
                        </div>
                        <ElButton
                          v-if="canEditSelectedAssessment"
                          link
                          type="primary"
                          @click="openControlMeasureDialog(item)"
                        >
                          新增措施
                        </ElButton>
                      </div>
                      <ArtTable
                        :data="item.controlMeasures ?? []"
                        :columns="measureColumns"
                        :pagination="false"
                        height="auto"
                        row-key="id"
                        empty-text="暂无管控措施"
                        empty-description="每项评估至少需要一条措施后才能提交。"
                        border
                      />
                    </article>
                  </div>
                </section>

                <section class="smis-risk-profile__section art-card-xs">
                  <ArtSectionTitle>流转记录</ArtSectionTitle>
                  <ArtEmptyState
                    v-if="state.events.length === 0"
                    title="暂无流转记录"
                    description="提交、撤回和生效操作会在此形成审计记录。"
                    size="compact"
                    :visual-size="68"
                  />
                  <ElTimeline v-else>
                    <ElTimelineItem
                      v-for="event in state.events"
                      :key="event.id"
                      :timestamp="formatWithDayjs(event.createTime, 'YYYY-MM-DD HH:mm') ?? '--'"
                      placement="top"
                    >
                      <div class="smis-risk-profile__event">
                        <div>
                          <strong>{{ getUserName(event.actorUser) }}</strong>
                          <span>将评估状态变更为</span>
                          <ArtDictDisplay
                            dict-code="smisAssessmentStatus"
                            :value="event.toStatus"
                            display="tag"
                          />
                        </div>
                        <p v-if="event.comment">{{ event.comment }}</p>
                      </div>
                    </ElTimelineItem>
                  </ElTimeline>
                </section>
              </template>
            </ArtAsyncState>
          </ElTabPane>
        </ElTabs>
      </div>
    </ArtAsyncState>

    <template #footer="{ api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
    </template>
  </ArtDrawer>

  <HazardSourceDialog ref="hazardDialogRef" @success="handleHazardSaved" />
  <RiskAssessmentDialog ref="assessmentDialogRef" @success="handleAssessmentSaved" />
  <RiskAssessmentItemDialog ref="assessmentItemDialogRef" @success="reloadAssessmentDetails" />
  <ControlMeasureDialog ref="controlMeasureDialogRef" @success="reloadAssessmentDetails" />
</template>

<script setup lang="tsx">
  import { ElButton } from 'element-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { formatWithDayjs } from '@/utils/time'
  import {
    deleteControlMeasure,
    deleteHazardSource,
    deleteRiskAssessment,
    deleteRiskAssessmentItem,
    fetchHazardSourceList,
    fetchRiskAssessmentEventList,
    fetchRiskAssessmentItemList,
    fetchRiskAssessmentList,
    transitionRiskAssessment
  } from '@/api/smis'
  import HazardSourceDialog from './hazard-source-dialog.vue'
  import RiskAssessmentDialog from './risk-assessment-dialog.vue'
  import RiskAssessmentItemDialog from './risk-assessment-item-dialog.vue'
  import ControlMeasureDialog from './control-measure-dialog.vue'

  defineOptions({ name: 'SmisRiskAssessmentDrawer' })

  type RiskPoint = Api.Smis.RiskControl.RiskPointRecord
  type HazardSource = Api.Smis.RiskControl.HazardSourceRecord
  type RiskAssessment = Api.Smis.RiskControl.RiskAssessmentRecord
  type RiskAssessmentItem = Api.Smis.RiskControl.RiskAssessmentItemRecord
  type ControlMeasure = Api.Smis.RiskControl.ControlMeasureRecord
  type UserSummary = RiskAssessment['assessorUser']

  interface DrawerState {
    riskPoint?: RiskPoint
    hazards: HazardSource[]
    assessments: RiskAssessment[]
    selectedAssessmentId: string
    items: RiskAssessmentItem[]
    events: Api.Smis.RiskControl.RiskAssessmentEventRecord[]
    activeTab: 'hazards' | 'assessments'
    loading: boolean
    assessmentLoading: boolean
    error: Error | null
  }

  interface HazardDialogExpose {
    handleOpen: (data: { riskPointId: string; row?: HazardSource }) => Promise<void>
  }

  interface AssessmentDialogExpose {
    handleOpen: (data: { riskPointId: string; row?: RiskAssessment }) => Promise<void>
  }

  interface AssessmentItemDialogExpose {
    handleOpen: (data: {
      assessmentId: string
      hazards: HazardSource[]
      row?: RiskAssessmentItem
    }) => Promise<void>
  }

  interface ControlMeasureDialogExpose {
    handleOpen: (data: { assessmentItemId: string; row?: ControlMeasure }) => Promise<void>
  }

  const emit = defineEmits<{ changed: [] }>()
  const { hasAuth } = useAuth()
  const { confirmAction, confirmDelete, promptReason } = useArtFeedback()
  const drawerRef = ref<ArtDrawerExpose<RiskPoint>>()
  const hazardDialogRef = ref<HazardDialogExpose>()
  const assessmentDialogRef = ref<AssessmentDialogExpose>()
  const assessmentItemDialogRef = ref<AssessmentItemDialogExpose>()
  const controlMeasureDialogRef = ref<ControlMeasureDialogExpose>()
  let assessmentRequestId = 0

  const state = reactive<DrawerState>({
    riskPoint: undefined,
    hazards: [],
    assessments: [],
    selectedAssessmentId: '',
    items: [],
    events: [],
    activeTab: 'hazards',
    loading: false,
    assessmentLoading: false,
    error: null
  })

  const canAddHazard = computed(() => hasAuth('SmisRiskPoint:Add'))
  const canEditHazard = computed(() => hasAuth('SmisRiskPoint:Edit'))
  const canDeleteHazard = computed(() => hasAuth('SmisRiskPoint:Delete'))
  const canAssess = computed(() => hasAuth('SmisRiskPoint:Assess'))
  const canActivate = computed(() => hasAuth('SmisRiskPoint:ActivateAssessment'))
  const selectedAssessment = computed(() =>
    state.assessments.find((item) => item.id === state.selectedAssessmentId)
  )
  const canEditSelectedAssessment = computed(
    () => canAssess.value && selectedAssessment.value?.status === 'draft'
  )
  const measureCount = computed(() =>
    state.items.reduce((total, item) => total + (item.controlMeasures?.length ?? 0), 0)
  )
  const itemsWithoutMeasures = computed(
    () => state.items.filter((item) => !item.controlMeasures?.length).length
  )
  const availableHazards = computed(() => {
    const usedIds = new Set(state.items.map((item) => item.hazardSourceId))
    return state.hazards.filter((item) => item.enabled && item.id && !usedIds.has(item.id))
  })

  const hazardColumns = computed<ColumnOption<HazardSource>[]>(() => [
    { prop: 'sourceNo', label: '编号', width: 132 },
    { prop: 'hazardName', label: '危险源名称', minWidth: 180 },
    { prop: 'accidentType', label: '事故类型', width: 120 },
    { prop: 'possibleConsequence', label: '可能后果', minWidth: 190 },
    {
      prop: 'enabled',
      label: '状态',
      width: 86,
      formatter: (row) => (
        <ArtDictDisplay dictCode="commonBoolean" value={String(row.enabled)} display="tag" />
      )
    },
    ...(canEditHazard.value || canDeleteHazard.value
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 112,
            fixed: 'right' as const,
            formatter: (row: HazardSource) => (
              <div class="flex">
                {canEditHazard.value ? (
                  <ElButton link type="primary" onClick={() => openHazardDialog(row)}>
                    编辑
                  </ElButton>
                ) : null}
                {canDeleteHazard.value ? (
                  <ElButton link type="danger" onClick={() => void removeHazard(row)}>
                    删除
                  </ElButton>
                ) : null}
              </div>
            )
          } satisfies ColumnOption<HazardSource>
        ]
      : [])
  ])

  const measureColumns = computed<ColumnOption<ControlMeasure>[]>(() => [
    {
      prop: 'measureType',
      label: '类型',
      width: 110,
      dict: { code: 'smisControlMeasureType', display: 'text' }
    },
    { prop: 'measureContent', label: '措施内容', minWidth: 220 },
    {
      prop: 'responsibleUser',
      label: '责任人',
      width: 110,
      formatter: (row) => getUserName(row.responsibleUser)
    },
    { prop: 'targetDate', label: '目标日期', width: 112 },
    {
      prop: 'status',
      label: '状态',
      width: 92,
      dict: { code: 'smisControlMeasureStatus', display: 'tag' }
    },
    ...(canEditSelectedAssessment.value
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 112,
            fixed: 'right' as const,
            formatter: (row: ControlMeasure) => (
              <div class="flex">
                <ElButton link type="primary" onClick={() => openControlMeasureDialogByRow(row)}>
                  编辑
                </ElButton>
                <ElButton link type="danger" onClick={() => void removeControlMeasure(row)}>
                  删除
                </ElButton>
              </div>
            )
          } satisfies ColumnOption<ControlMeasure>
        ]
      : [])
  ])

  function getUserName(user: UserSummary | undefined | null): string {
    return user?.nickName || user?.userName || user?.userEmail || '--'
  }

  function getAssessmentOptionLabel(assessment: RiskAssessment): string {
    const statusLabel: Record<Api.Smis.RiskControl.RiskAssessmentStatus, string> = {
      draft: '草稿',
      submitted: '已提交',
      effective: '已生效',
      superseded: '已被替代'
    }
    return `V${assessment.versionNo} · ${assessment.assessmentDate} · ${statusLabel[assessment.status]}`
  }

  async function loadAssessmentDetails(assessmentId: string): Promise<void> {
    const requestId = ++assessmentRequestId
    if (!assessmentId) {
      state.items = []
      state.events = []
      return
    }
    state.assessmentLoading = true
    try {
      const [itemResult, eventResult] = await Promise.all([
        fetchRiskAssessmentItemList(assessmentId),
        fetchRiskAssessmentEventList(assessmentId)
      ])
      if (requestId !== assessmentRequestId) return
      state.items = itemResult.data ?? []
      state.events = eventResult.data ?? []
    } finally {
      if (requestId === assessmentRequestId) state.assessmentLoading = false
    }
  }

  async function loadProfile(preferredAssessmentId?: string): Promise<void> {
    const riskPoint = state.riskPoint
    if (!riskPoint?.id) return
    state.error = null
    try {
      const [hazardResult, assessmentResult] = await Promise.all([
        fetchHazardSourceList(riskPoint.id),
        fetchRiskAssessmentList(riskPoint.id)
      ])
      state.hazards = hazardResult.data ?? []
      state.assessments = assessmentResult.data ?? []
      const preferred = state.assessments.find((item) => item.id === preferredAssessmentId)
      const effective = state.assessments.find((item) => item.status === 'effective')
      state.selectedAssessmentId = preferred?.id || effective?.id || state.assessments[0]?.id || ''
      await loadAssessmentDetails(state.selectedAssessmentId)
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('风险档案加载失败，请稍后重试')
    }
  }

  function retryLoad(): void {
    void loadProfile(state.selectedAssessmentId)
  }

  function handleAssessmentChange(value: string): void {
    void loadAssessmentDetails(value)
  }

  function openHazardDialog(row?: HazardSource): void {
    if (!state.riskPoint?.id) return
    void hazardDialogRef.value?.handleOpen({ riskPointId: state.riskPoint.id, row })
  }

  async function handleHazardSaved(): Promise<void> {
    if (!state.riskPoint?.id) return
    const result = await fetchHazardSourceList(state.riskPoint.id)
    state.hazards = result.data ?? []
  }

  async function removeHazard(row: HazardSource): Promise<void> {
    if (!row.id) return
    try {
      await confirmDelete(`确定删除危险源“${row.hazardName}”吗？已被评估引用时系统会阻止删除。`)
      await deleteHazardSource(row.id)
      await handleHazardSaved()
    } catch {
      // 用户取消或数据库引用约束阻止时，不重复提示。
    }
  }

  function openAssessmentDialog(row?: RiskAssessment): void {
    if (!state.riskPoint?.id) return
    void assessmentDialogRef.value?.handleOpen({ riskPointId: state.riskPoint.id, row })
  }

  async function handleAssessmentSaved(assessmentId?: string): Promise<void> {
    await loadProfile(assessmentId || state.selectedAssessmentId)
    state.activeTab = 'assessments'
  }

  function openAssessmentItemDialog(row?: RiskAssessmentItem): void {
    const assessmentId = selectedAssessment.value?.id
    if (!assessmentId) return
    const hazards = row
      ? state.hazards.filter(
          (item) =>
            item.enabled &&
            (item.id === row.hazardSourceId ||
              !state.items.some((existing) => existing.hazardSourceId === item.id))
        )
      : availableHazards.value
    void assessmentItemDialogRef.value?.handleOpen({ assessmentId, hazards, row })
  }

  async function removeAssessmentItem(row: RiskAssessmentItem): Promise<void> {
    if (!row.id) return
    try {
      await confirmDelete(
        `确定删除“${row.hazardNameSnapshot || '该危险源'}”的 LEC 评估和全部管控措施吗？`
      )
      await deleteRiskAssessmentItem(row.id)
      await reloadAssessmentDetails()
    } catch {
      // 用户取消时无需提示。
    }
  }

  function openControlMeasureDialog(item: RiskAssessmentItem): void {
    if (!item.id) return
    void controlMeasureDialogRef.value?.handleOpen({ assessmentItemId: item.id })
  }

  function openControlMeasureDialogByRow(row: ControlMeasure): void {
    void controlMeasureDialogRef.value?.handleOpen({
      assessmentItemId: row.assessmentItemId,
      row
    })
  }

  async function removeControlMeasure(row: ControlMeasure): Promise<void> {
    if (!row.id) return
    try {
      await confirmDelete(`确定删除管控措施“${row.measureContent}”吗？`)
      await deleteControlMeasure(row.id)
      await reloadAssessmentDetails()
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function reloadAssessmentDetails(): Promise<void> {
    if (state.selectedAssessmentId) await loadAssessmentDetails(state.selectedAssessmentId)
  }

  async function submitAssessment(): Promise<void> {
    const assessment = selectedAssessment.value
    if (!assessment?.id) return
    try {
      await confirmAction(
        `确定提交 V${assessment.versionNo} 评估吗？提交后评估明细和管控措施将被冻结。`,
        '提交评估',
        { confirmButtonText: '提交评估', type: 'warning' }
      )
      await transitionRiskAssessment(assessment.id, 'submit')
      await loadProfile(assessment.id)
    } catch {
      // 用户取消或提交前置条件不满足时，不重复提示。
    }
  }

  async function withdrawAssessment(): Promise<void> {
    const assessment = selectedAssessment.value
    if (!assessment?.id) return
    try {
      await confirmAction(
        `确定将 V${assessment.versionNo} 撤回为草稿吗？撤回后可继续修改。`,
        '撤回评估',
        { confirmButtonText: '撤回草稿', type: 'warning' }
      )
      await transitionRiskAssessment(assessment.id, 'withdraw')
      await loadProfile(assessment.id)
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function activateAssessment(): Promise<void> {
    const assessment = selectedAssessment.value
    if (!assessment?.id) return
    try {
      const reason = await promptReason(
        `V${assessment.versionNo} 生效后将成为风险点当前等级，原生效版本会自动转为“已被替代”。`,
        '评估生效确认',
        {
          confirmButtonText: '确认生效',
          placeholder: '请填写复核结论或生效依据',
          emptyMessage: '请填写复核结论'
        }
      )
      await transitionRiskAssessment(assessment.id, 'activate', reason)
      await loadProfile(assessment.id)
      emit('changed')
    } catch {
      // 用户取消或数据库状态约束阻止时，不重复提示。
    }
  }

  async function removeAssessment(): Promise<void> {
    const assessment = selectedAssessment.value
    if (!assessment?.id) return
    try {
      await confirmDelete(`确定删除 V${assessment.versionNo} 草稿及其全部评估项和管控措施吗？`)
      await deleteRiskAssessment(assessment.id)
      await loadProfile()
    } catch {
      // 用户取消或非草稿状态阻止时，不重复提示。
    }
  }

  async function handleOpen(row: RiskPoint): Promise<void> {
    Object.assign(state, {
      riskPoint: row,
      hazards: [],
      assessments: [],
      selectedAssessmentId: '',
      items: [],
      events: [],
      activeTab: 'hazards',
      loading: true,
      assessmentLoading: false,
      error: null
    })
    await drawerRef.value?.handleOpen(row, {
      title: `风险档案 · ${row.riskPointName}`,
      subtitle: `${row.riskPointNo} · 危险源辨识、LEC 评估与管控措施`,
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      scrollbarAlways: true,
      onOpen: async (_data, api) => {
        try {
          await loadProfile()
        } finally {
          state.loading = false
          api.setLoading(false)
        }
      },
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .smis-risk-profile {
    min-width: 0;

    &__overview {
      display: grid;
      grid-template-columns: minmax(280px, 2fr) repeat(3, minmax(120px, 1fr));
      gap: var(--art-space-3);
      margin: var(--art-space-4) 0 var(--art-space-5);
    }

    &__identity,
    &__metric {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      min-width: 0;
      padding: var(--art-space-4);
    }

    &__identity {
      justify-content: space-between;
    }

    &__identity-main {
      display: grid;
      min-width: 0;

      span,
      p {
        margin: 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 18px;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    &__metric {
      > svg {
        flex: none;
        width: 24px;
        height: 24px;
        color: var(--el-color-primary);
      }

      div {
        display: grid;
      }

      strong {
        font-size: 20px;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-primary);
      }

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__tabs {
      min-width: 0;
    }

    &__section,
    &__assessment-toolbar,
    &__assessment-head {
      min-width: 0;
      padding: var(--art-space-4);
      margin-bottom: var(--art-space-4);
    }

    &__section-header,
    &__assessment-toolbar,
    &__assessment-head,
    &__item-header,
    &__measure-head {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      justify-content: space-between;
    }

    &__section-header {
      margin-bottom: var(--art-space-4);

      .art-section-title {
        margin-bottom: 0;
      }

      p {
        margin: 2px 0 0 11px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__version-select {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      min-width: 0;

      > span {
        flex: none;
        font-size: 13px;
        font-weight: 600;
        color: var(--el-text-color-primary);
      }

      .el-select {
        width: min(360px, 50vw);
      }
    }

    &__assessment-head {
      align-items: flex-start;
    }

    &__assessment-summary {
      display: grid;
      gap: var(--art-space-2);
      min-width: 0;

      > p {
        max-width: 720px;
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-regular);
        overflow-wrap: anywhere;
      }
    }

    &__assessment-title,
    &__assessment-meta,
    &__assessment-actions,
    &__score,
    &__item-actions {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-2);
      align-items: center;
    }

    &__assessment-title strong {
      font-size: 22px;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-primary);
    }

    &__assessment-meta {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    &__assessment-actions {
      justify-content: flex-end;
    }

    &__item-list {
      display: grid;
      gap: var(--art-space-4);
    }

    &__item-card {
      min-width: 0;
      padding: var(--art-space-4);
      background: var(--art-gray-100);
      border-radius: var(--el-border-radius-base);
    }

    &__item-header {
      align-items: flex-start;
      padding-bottom: var(--art-space-3);
      border-bottom: 1px solid var(--el-border-color-lighter);
    }

    &__item-identity {
      display: grid;
      flex: 1;
      min-width: 0;

      span,
      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }

      strong {
        color: var(--el-text-color-primary);
      }

      p {
        overflow-wrap: anywhere;
      }
    }

    &__score {
      justify-content: flex-end;
      font-size: 12px;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-secondary);

      strong {
        font-size: 16px;
        color: var(--el-text-color-primary);
      }
    }

    &__note {
      display: grid;
      gap: var(--art-space-1);
      padding: var(--art-space-3) 0;

      span {
        font-size: 12px;
        font-weight: 600;
        color: var(--el-text-color-secondary);
      }

      p {
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-regular);
        overflow-wrap: anywhere;
      }
    }

    &__measure-head {
      margin: var(--art-space-3) 0 var(--art-space-2);

      > div {
        display: flex;
        gap: var(--art-space-2);
        align-items: baseline;

        strong {
          color: var(--el-text-color-primary);
        }

        span {
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__event {
      display: grid;
      gap: var(--art-space-1);

      > div {
        display: flex;
        flex-wrap: wrap;
        gap: var(--art-space-2);
        align-items: center;
      }

      p {
        margin: 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 1100px) {
      &__overview {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      &__identity {
        grid-column: 1 / -1;
      }
    }

    @media (width <= 760px) {
      &__overview {
        grid-template-columns: 1fr;
      }

      &__identity {
        grid-column: auto;
      }

      &__section-header,
      &__assessment-toolbar,
      &__assessment-head,
      &__item-header {
        flex-direction: column;
        align-items: stretch;
      }

      &__version-select {
        flex-direction: column;
        align-items: stretch;

        .el-select {
          width: 100%;
        }
      }

      &__assessment-actions,
      &__score {
        justify-content: flex-start;
      }
    }
  }
</style>
