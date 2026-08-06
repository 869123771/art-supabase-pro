<template>
  <ArtDrawer ref="drawerRef">
    <div class="reminder-work-order">
      <section class="reminder-work-order__summary art-card-xs">
        <header>
          <div>
            <span class="reminder-work-order__eyebrow">VEHICLE REMINDER</span>
            <h3>{{ state.openData?.row.plateNo || '--' }} · {{ state.openData?.sourceLabel }}</h3>
            <p>从到期提醒建立处置任务，状态流转和处理结果均保留审计记录。</p>
          </div>
          <ArtDictDisplay
            v-if="state.workOrder"
            dict-code="vehicleReminderWorkOrderStatus"
            :value="state.workOrder.status"
            display="tag"
          />
        </header>

        <div class="reminder-work-order__facts">
          <div>
            <span>所属公司</span>
            <strong>{{ state.openData?.row.companyName || '--' }}</strong>
          </div>
          <div>
            <span>到期日期</span>
            <strong>{{ formatDate(state.openData?.row.expireDate) }}</strong>
          </div>
          <div>
            <span>剩余时间</span>
            <strong>{{ remainingText }}</strong>
          </div>
          <div>
            <span>当前处理人</span>
            <strong>{{ state.workOrder?.assigneeName || '尚未认领' }}</strong>
          </div>
        </div>
      </section>

      <section v-if="state.workOrder" class="reminder-work-order__workflow art-card-xs">
        <ArtSectionTitle>处置进度</ArtSectionTitle>
        <div class="reminder-work-order__timeline">
          <div>
            <span>建立工单</span>
            <strong>{{ formatDateTime(state.workOrder.createTime) }}</strong>
          </div>
          <div>
            <span>开始处理</span>
            <strong>{{ formatDateTime(state.workOrder.startedAt) }}</strong>
          </div>
          <div>
            <span>解决时间</span>
            <strong>{{ formatDateTime(state.workOrder.resolvedAt) }}</strong>
          </div>
          <div>
            <span>关闭时间</span>
            <strong>{{ formatDateTime(state.workOrder.closedAt) }}</strong>
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
        <ArtForm
          ref="formRef"
          v-model="form.data"
          :items="form.items"
          :rules="form.rules"
          :show-reset="false"
          :show-submit="false"
          label-width="108px"
        />
      </section>

      <ElAlert
        v-else-if="state.workOrder"
        :title="terminalStatus ? '该处置单已结束，仅保留审计查看。' : '当前角色为只读模式。'"
        type="info"
        :closable="false"
        show-icon
      />
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

  const emit = defineEmits<{ success: [] }>()
  const drawerRef = ref<ArtDrawerExpose<OpenData>>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const { getUserInfo, getDictMap, isPlatformSuper } = storeToRefs(useUserStore())

  const canManage = computed(() => {
    if (isPlatformSuper.value) return true
    const roles = getUserInfo.value.userRoles ?? []
    return roles.some((role) => ['R_ADMIN', 'YQ_ADMIN', 'R_REGISTER'].includes(role))
  })

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
  const canTransition = computed(
    () => canManage.value && Boolean(state.workOrder) && !terminalStatus.value
  )
  const remainingText = computed(() => {
    const days = state.openData?.row.remainingDays
    if (days === null || days === undefined) return '未配置'
    if (days < 0) return `已逾期 ${Math.abs(days)} 天`
    if (days === 0) return '今日到期'
    return `剩余 ${days} 天`
  })

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

  function formatDateTime(value?: string | null): string {
    return value && dayjs(value).isValid() ? dayjs(value).format('YYYY-MM-DD HH:mm') : '--'
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

    if (!state.workOrder && !canManage.value) return

    const isReadOnly = state.workOrder
      ? ['closed', 'cancelled'].includes(state.workOrder.status) || !canManage.value
      : false
    await drawerRef.value?.handleOpen(data, {
      title: `${data.sourceLabel}处置单`,
      size: 'lg',
      contentMaxHeight: 'calc(100vh - 160px)',
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
    gap: 16px;
    min-width: 0;

    &__summary,
    &__workflow,
    &__action {
      padding: 20px;
    }

    &__summary {
      header {
        display: flex;
        gap: 16px;
        align-items: flex-start;
        justify-content: space-between;

        h3 {
          margin: 4px 0 6px;
          font-size: 20px;
          color: var(--art-text-gray-900);
        }

        p {
          margin: 0;
          color: var(--art-text-gray-600);
        }
      }
    }

    &__eyebrow {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.12em;
      color: var(--el-color-primary);
    }

    &__facts,
    &__timeline {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      margin-top: 20px;

      div {
        min-width: 0;
        padding: 12px;
        background: var(--art-main-bg-color);
        border-radius: var(--el-border-radius-base);

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
          color: var(--art-text-gray-800);
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }
    }

    &__resolution {
      padding: 14px;
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

    @media (width <= 900px) {
      &__facts,
      &__timeline {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (width <= 560px) {
      &__summary header {
        flex-direction: column;
      }

      &__facts,
      &__timeline {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
