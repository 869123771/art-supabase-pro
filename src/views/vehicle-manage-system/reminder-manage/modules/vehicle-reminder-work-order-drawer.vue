<template>
  <ArtDrawer ref="drawerRef">
    <div class="reminder-work-order">
      <section class="reminder-work-order__summary art-card-xs">
        <header class="reminder-work-order__summary-header">
          <div class="reminder-work-order__identity">
            <span class="reminder-work-order__identity-icon" aria-hidden="true">
              <ArtSvgIcon icon="ri:alarm-warning-line" />
            </span>
            <div>
              <span class="reminder-work-order__eyebrow">车辆到期提醒</span>
              <h3>{{ state.openData?.row.plateNo || '--' }} · {{ state.openData?.sourceLabel }}</h3>
              <p>处理车辆到期风险，所有状态变更均记录操作人与时间。</p>
            </div>
          </div>
          <ArtDictDisplay
            v-if="state.workOrder"
            dict-code="vehicleReminderWorkOrderStatus"
            :value="state.workOrder.status"
            display="tag"
          />
        </header>

        <div class="reminder-work-order__facts">
          <div class="reminder-work-order__fact reminder-work-order__fact--company">
            <span>所属公司</span>
            <strong :title="state.openData?.row.companyName || '--'">
              {{ state.openData?.row.companyName || '--' }}
            </strong>
          </div>
          <div class="reminder-work-order__fact">
            <span>到期日期</span>
            <strong>{{ formatDate(state.openData?.row.expireDate) }}</strong>
          </div>
          <div class="reminder-work-order__fact" :class="{ 'is-overdue': isOverdue }">
            <span>到期情况</span>
            <strong>{{ remainingText }}</strong>
          </div>
          <div class="reminder-work-order__fact">
            <span>当前处理人</span>
            <strong>{{ state.workOrder?.assigneeName || '尚未认领' }}</strong>
          </div>
        </div>
      </section>

      <section v-if="state.workOrder" class="reminder-work-order__workflow art-card-xs">
        <div class="reminder-work-order__section-heading">
          <div>
            <ArtSectionTitle :show-line="false">处置进度</ArtSectionTitle>
            <p>关键节点及处理时间</p>
          </div>
          <span class="reminder-work-order__progress-count">
            已完成 {{ completedStepCount }}/{{ progressSteps.length }}
          </span>
        </div>
        <div class="reminder-work-order__timeline">
          <div
            v-for="(step, index) in progressSteps"
            :key="step.key"
            class="reminder-work-order__step"
            :class="{
              'is-complete': step.complete,
              'is-line-complete': progressSteps[index + 1]?.complete
            }"
          >
            <div class="reminder-work-order__step-track">
              <span class="reminder-work-order__step-node">
                <ArtSvgIcon :icon="step.complete ? 'ri:check-line' : step.icon" />
              </span>
              <span
                v-if="index < progressSteps.length - 1"
                class="reminder-work-order__step-line"
              />
            </div>
            <strong>{{ step.label }}</strong>
            <span>{{ step.time }}</span>
          </div>
        </div>

        <div v-if="state.workOrder.resolution" class="reminder-work-order__resolution">
          <span>最近处置结果</span>
          <p>{{ state.workOrder.resolution }}</p>
        </div>
      </section>

      <section
        v-if="state.workOrder && canTransition"
        class="reminder-work-order__action art-card-xs"
      >
        <div class="reminder-work-order__section-heading">
          <div>
            <ArtSectionTitle :show-line="false">下一步处置</ArtSectionTitle>
            <p>选择本次处理结果，提交后将同步更新处置进度。</p>
          </div>
        </div>
        <ArtForm
          ref="formRef"
          v-model="form.data"
          :items="form.items"
          :rules="form.rules"
          :show-reset="false"
          :show-submit="false"
          label-position="top"
        />
      </section>

      <section v-else-if="state.workOrder" class="reminder-work-order__action art-card-xs">
        <ElAlert title="该处置单已结束，仅保留审计查看。" type="info" :closable="false" show-icon />
      </section>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import {
    createVehicleReminderWorkOrder,
    transitionVehicleReminderWorkOrder
  } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'VehicleReminderWorkOrderDrawer' })

  type ReminderRow = Api.VehicleMgtSys.ReminderManage.VehicleReminderRow
  type ReminderKind = Api.VehicleMgtSys.ReminderManage.ReminderKind
  type WorkOrder = Api.VehicleMgtSys.ReminderManage.VehicleReminderWorkOrder
  type WorkOrderStatus = Api.VehicleMgtSys.ReminderManage.WorkOrderStatus

  interface OpenData {
    row: ReminderRow
    sourceType: ReminderKind
    sourceLabel: string
  }

  interface FormModel {
    nextStatus: WorkOrderStatus | ''
    resolution: string
  }

  interface FormGroup {
    data: FormModel
    items: ComputedRef<FormItem[]>
    rules: FormRules<FormModel>
  }

  interface DrawerState {
    openData: OpenData | null
    workOrder: WorkOrder | null
  }

  interface ProgressStep {
    key: 'created' | 'started' | 'resolved' | 'closed'
    label: string
    icon: string
    time: string
    complete: boolean
  }

  const emit = defineEmits<{ success: [] }>()
  const drawerRef = ref<ArtDrawerExpose<OpenData>>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const { getDictMap } = storeToRefs(useUserStore())

  const state = reactive<DrawerState>({ openData: null, workOrder: null })
  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    items: computed(() => [
      {
        label: '下一状态',
        key: 'nextStatus',
        type: 'select',
        span: 24,
        props: {
          options: transitionOptions.value,
          placeholder: '请选择下一步处置动作'
        }
      },
      {
        label: '处置说明',
        key: 'resolution',
        type: 'input',
        span: 24,
        hidden: !['resolved', 'cancelled'].includes(form.data.nextStatus),
        props: {
          type: 'textarea',
          rows: 4,
          maxlength: 1000,
          showWordLimit: true,
          placeholder:
            form.data.nextStatus === 'resolved'
              ? '请填写已采取的措施、结果及后续建议'
              : '可填写取消原因'
        }
      }
    ]),
    rules: {
      nextStatus: [{ required: true, message: '请选择下一状态', trigger: 'change' }],
      resolution: [
        {
          validator: (_rule, value, callback) => {
            if (form.data.nextStatus === 'resolved' && !String(value || '').trim()) {
              callback(new Error('标记为已解决前必须填写处置说明'))
              return
            }
            callback()
          },
          trigger: 'blur'
        }
      ]
    }
  })

  const transitionMap: Record<WorkOrderStatus, WorkOrderStatus[]> = {
    pending: ['in_progress', 'cancelled'],
    in_progress: ['resolved', 'cancelled'],
    resolved: ['closed', 'in_progress'],
    closed: [],
    cancelled: []
  }

  const transitionOptions = computed(() => {
    const status = state.workOrder?.status
    if (!status) return []
    const allowed = transitionMap[status]
    const dictionary = getUserStoreDictionary()
    return allowed.map((value) => {
      const item = dictionary.find((option) => option.value === value)
      return { label: item?.label || value, value }
    })
  })

  const terminalStatus = computed(() =>
    state.workOrder ? ['closed', 'cancelled'].includes(state.workOrder.status) : false
  )
  const canTransition = computed(() => Boolean(state.workOrder) && !terminalStatus.value)
  const remainingText = computed(() => {
    const days = state.openData?.row.remainingDays
    if (days === null || days === undefined) return '未配置'
    if (days < 0) return `已逾期 ${Math.abs(days)} 天`
    if (days === 0) return '今日到期'
    return `剩余 ${days} 天`
  })
  const isOverdue = computed(() => (state.openData?.row.remainingDays ?? 0) < 0)
  const progressSteps = computed<ProgressStep[]>(() => {
    const workOrder = state.workOrder
    return [
      {
        key: 'created',
        label: '建立工单',
        icon: 'ri:file-add-line',
        time: formatProgressTime(workOrder?.createTime, '待建立'),
        complete: Boolean(workOrder?.createTime)
      },
      {
        key: 'started',
        label: '开始处理',
        icon: 'ri:play-line',
        time: formatProgressTime(workOrder?.startedAt, '待开始'),
        complete: Boolean(workOrder?.startedAt)
      },
      {
        key: 'resolved',
        label: '问题解决',
        icon: 'ri:checkbox-circle-line',
        time: formatProgressTime(workOrder?.resolvedAt, '待解决'),
        complete: Boolean(workOrder?.resolvedAt)
      },
      {
        key: 'closed',
        label: '关闭工单',
        icon: 'ri:flag-line',
        time: formatProgressTime(workOrder?.closedAt, '待关闭'),
        complete: Boolean(workOrder?.closedAt)
      }
    ]
  })
  const completedStepCount = computed(
    () => progressSteps.value.filter((step) => step.complete).length
  )

  function getUserStoreDictionary(): Api.DataCenter.DictListItem[] {
    return getDictMap.value.vehicleReminderWorkOrderStatus ?? []
  }

  function createInitialForm(): FormModel {
    return { nextStatus: '', resolution: '' }
  }

  function resetForm(): void {
    Object.assign(form.data, createInitialForm())
    void nextTick(() => formRef.value?.clearValidate())
  }

  function formatDate(value?: string | null): string {
    return value && dayjs(value).isValid() ? dayjs(value).format('YYYY-MM-DD') : '--'
  }

  function formatProgressTime(value: string | null | undefined, fallback: string): string {
    return value && dayjs(value).isValid() ? dayjs(value).format('MM-DD HH:mm') : fallback
  }

  function createPayload(data: OpenData) {
    const { row, sourceType, sourceLabel } = data
    return {
      sourceType,
      sourceKey: row.id,
      sourceVersion: row.sourceVersion || row.expireDate || 'current',
      sourceId: row.sourceId || null,
      vehicleId: String(row.vehicleId || ''),
      plateNo: row.plateNo,
      companyName: row.companyName || null,
      title: `${row.plateNo} ${sourceLabel}处置`,
      dueDate: row.expireDate || row.nextMaintenanceDate || null,
      remainingDays: row.remainingDays ?? null
    }
  }

  async function handleSubmit(): Promise<boolean> {
    if (!state.workOrder || !canTransition.value) return false
    try {
      await formRef.value?.validate()
      const { data } = await transitionVehicleReminderWorkOrder({
        workOrderId: state.workOrder.id,
        nextStatus: form.data.nextStatus as WorkOrderStatus,
        resolution: form.data.resolution.trim() || null
      })
      if (!data) return false
      state.workOrder = data
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(data: OpenData): Promise<void> {
    state.openData = data
    state.workOrder = data.row.workOrder ?? null
    resetForm()

    const isReadOnly = state.workOrder
      ? ['closed', 'cancelled'].includes(state.workOrder.status)
      : false
    await drawerRef.value?.handleOpen(data, {
      title: `${data.sourceLabel}处置单`,
      size: 'lg',
      contentHeight: 'calc(100vh - 154px)',
      showFooter: !isReadOnly,
      confirmText: '提交流转',
      onConfirm: handleSubmit,
      onOpen: async (_openData, api) => {
        if (state.workOrder) return
        api.setLoading(true)
        try {
          const { data: workOrder } = await createVehicleReminderWorkOrder(createPayload(data))
          state.workOrder = workOrder
          emit('success')
        } finally {
          api.setLoading(false)
        }
      },
      onReset: resetForm,
      drawerProps: { appendToBody: true, closeOnClickModal: false, resizable: true }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .reminder-work-order {
    display: grid;
    gap: 12px;
    min-width: 0;

    &__summary,
    &__workflow,
    &__action {
      padding: 16px;
    }

    &__summary-header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;

      h3 {
        margin: 3px 0 4px;
        font-size: 20px;
        line-height: 1.35;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        line-height: 1.5;
        color: var(--art-text-gray-600);
      }
    }

    &__identity {
      display: flex;
      gap: 12px;
      align-items: flex-start;
      min-width: 0;
    }

    &__identity-icon {
      display: inline-grid;
      flex: 0 0 40px;
      place-items: center;
      width: 40px;
      height: 40px;
      font-size: 20px;
      color: var(--el-color-warning);
      background: var(--el-color-warning-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__eyebrow {
      font-size: 12px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.04em;
    }

    &__facts {
      display: grid;
      grid-template-columns: 1.5fr repeat(3, minmax(0, 1fr));
      gap: 1px;
      margin-top: 16px;
      overflow: hidden;
      background: var(--el-border-color-lighter);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__fact {
      min-width: 0;
      padding: 12px;
      background: var(--default-box-color);

      span,
      strong {
        display: block;
      }

      span {
        margin-bottom: 5px;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-weight: 600;
        color: var(--art-text-gray-800);
        white-space: nowrap;
      }

      &.is-overdue strong {
        color: var(--el-color-danger);
      }
    }

    &__section-heading {
      display: flex;
      gap: 12px;
      align-items: flex-start;
      justify-content: space-between;

      :deep(.art-section-title) {
        margin-bottom: 0;
      }

      p {
        margin: 2px 0 0;
        font-size: 12px;
        line-height: 1.5;
        color: var(--art-text-gray-500);
      }
    }

    &__progress-count {
      flex: 0 0 auto;
      padding: 4px 9px;
      font-size: 12px;
      font-weight: 600;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 999px;
    }

    &__timeline {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      margin-top: 16px;
    }

    &__step {
      min-width: 0;
      text-align: center;

      > strong,
      > span {
        display: block;
      }

      > strong {
        margin-top: 8px;
        font-size: 13px;
        color: var(--art-text-gray-700);
      }

      > span {
        margin-top: 3px;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }

      &.is-complete {
        .reminder-work-order__step-node {
          color: var(--el-color-white);
          background: var(--el-color-primary);
          border-color: var(--el-color-primary);
        }

        > strong {
          color: var(--art-text-gray-900);
        }
      }

      &.is-line-complete .reminder-work-order__step-line {
        background: var(--el-color-primary-light-5);
      }
    }

    &__step-track {
      position: relative;
      display: flex;
      justify-content: center;
    }

    &__step-node {
      position: relative;
      z-index: 1;
      display: inline-grid;
      place-items: center;
      width: 32px;
      height: 32px;
      font-size: 15px;
      color: var(--art-text-gray-400);
      background: var(--default-box-color);
      border: 1px solid var(--el-border-color);
      border-radius: 50%;
    }

    &__step-line {
      position: absolute;
      top: 15px;
      left: calc(50% + 16px);
      width: calc(100% - 32px);
      height: 2px;
      background: var(--el-border-color-lighter);
    }

    &__resolution {
      padding: 12px;
      margin-top: 16px;
      background: color-mix(in srgb, var(--el-color-success) 8%, transparent);
      border-left: 3px solid var(--el-color-success);
      border-radius: var(--el-border-radius-small);

      span {
        font-size: 12px;
        color: var(--art-text-gray-500);
      }

      p {
        margin: 6px 0 0;
        line-height: 1.6;
        color: var(--art-text-gray-800);
        overflow-wrap: anywhere;
      }
    }

    &__action {
      :deep(.art-form) {
        padding: 12px 0 0;
      }

      :deep(.el-form-item) {
        margin-bottom: 12px;
      }
    }

    @media (width <= 900px) {
      &__facts {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (width <= 560px) {
      &__summary-header {
        flex-direction: column;
      }

      &__facts {
        grid-template-columns: 1fr;
      }

      &__timeline {
        grid-template-columns: repeat(2, minmax(0, 1fr));
        row-gap: 20px;
      }

      &__step:nth-child(2) .reminder-work-order__step-line {
        display: none;
      }
    }
  }
</style>
