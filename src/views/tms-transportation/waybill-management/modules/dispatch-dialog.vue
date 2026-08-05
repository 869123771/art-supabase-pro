<template>
  <ArtDialog ref="dialogRef">
    <div class="dispatch-dialog">
      <ElAlert
        v-if="dialog.rows.length > 1"
        type="info"
        :closable="false"
        show-icon
        :title="`本次将批量配载 ${dialog.rows.length} 条运单`"
      />
      <div v-else class="dispatch-dialog__order">
        <span>运单号：{{ dialog.rows[0]?.orderNo || '-' }}</span>
        <span>货号：{{ dialog.rows[0]?.cargoNo || '-' }}</span>
      </div>

      <section v-if="dialog.mode === 'single'" class="dispatch-dialog__advisor art-card-xs">
        <header>
          <div>
            <span class="dispatch-dialog__advisor-icon"
              ><ArtSvgIcon icon="ri:sparkling-2-line"
            /></span>
            <div>
              <strong>AI 调度推荐</strong>
              <small>综合车辆资格、当前占用、线路经验、准点率与载重利用率</small>
            </div>
          </div>
          <ElButton type="primary" plain :loading="advisor.loading" @click="loadRecommendations">
            {{ advisor.data ? '重新推荐' : '生成推荐' }}
          </ElButton>
        </header>

        <ElAlert
          v-if="advisor.error"
          type="warning"
          :closable="false"
          show-icon
          :title="advisor.error"
        />

        <template v-else-if="advisor.data">
          <p class="dispatch-dialog__advisor-summary">{{ advisor.data.summary }}</p>
          <div v-if="advisor.data.recommendations.length" class="dispatch-dialog__recommendations">
            <article
              v-for="item in advisor.data.recommendations"
              :key="item.vehicle.id"
              :class="{ 'is-first': item.rank === 1 }"
            >
              <div class="dispatch-dialog__recommendation-main">
                <span class="dispatch-dialog__recommendation-rank">#{{ item.rank }}</span>
                <div>
                  <strong>{{ item.vehicle.plateNo }}</strong>
                  <small>
                    {{ item.vehicle.companyName || '公司未维护' }} ·
                    {{ item.vehicle.primaryDriver.driverName }}
                  </small>
                </div>
                <ElTag :type="item.score >= 75 ? 'success' : 'primary'" effect="light">
                  推荐分 {{ item.score }}
                </ElTag>
                <ElButton type="primary" link @click="applyRecommendation(item)">采用</ElButton>
              </div>
              <div class="dispatch-dialog__recommendation-reasons">
                <span v-for="reason in item.reasons" :key="reason">
                  <ArtSvgIcon icon="ri:checkbox-circle-line" />{{ reason }}
                </span>
                <span v-for="warning in item.warnings" :key="warning" class="is-warning">
                  <ArtSvgIcon icon="ri:error-warning-line" />{{ warning }}
                </span>
              </div>
              <footer>
                <span>置信度 {{ Math.round(item.confidence * 100) }}%</span>
                <span>同线路 {{ item.metrics.routeTrips }} 单</span>
                <span
                  v-if="item.metrics.onTimeRate !== null && item.metrics.onTimeRate !== undefined"
                >
                  准点率 {{ Math.round(item.metrics.onTimeRate * 100) }}%
                </span>
              </footer>
            </article>
          </div>
        </template>

        <p v-else class="dispatch-dialog__advisor-empty">
          生成后只提供候选建议，不会自动配载或改变订单状态。
        </p>
      </section>

      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="12"
        label-width="112px"
        root-class="dispatch-dialog__form"
        :show-reset="false"
        :show-submit="false"
      >
        <template #dispatchVehicleId>
          <ArtTableSingleSelect
            v-model="form.data.dispatchVehicleId"
            v-model:selected-data="form.selectedVehicles"
            title="选择配载车辆"
            placeholder="请选择车辆"
            search-placeholder="请输入车牌号、所属公司、司机或电话"
            row-key="id"
            label-key="plateNo"
            description-key="companyName"
            :api-fn="fetchVehicleSelectData"
            :columns="form.vehicleColumns"
            :show-pagination="true"
            @confirm="handleVehicleConfirm"
            @clear="handleVehicleClear"
          />
        </template>
      </ArtForm>

      <div v-if="form.selectedVehicle" class="dispatch-dialog__vehicle art-card-xs">
        <div>
          <span>车牌号</span>
          <strong>{{ formatValue(form.selectedVehicle.plateNo) }}</strong>
        </div>
        <div>
          <span>车型</span>
          <strong>
            <ArtDictDisplay dict-code="vehicleType" :value="form.selectedVehicle.vehicleType" />
          </strong>
        </div>
        <div>
          <span>车长/载重</span>
          <strong>{{ formatVehicleLength(form.selectedVehicle) }}</strong>
        </div>
        <div>
          <span>司机</span>
          <strong>{{ formatValue(form.data.dispatchDriverName) }}</strong>
        </div>
        <div>
          <span>司机电话</span>
          <strong>{{ formatValue(form.data.dispatchDriverPhone) }}</strong>
        </div>
      </div>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import { trim } from 'lodash-es'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import {
    dispatchWaybill,
    dispatchWaybillBatch,
    fetchDispatchVehicleOptions,
    recommendDispatchResourcesByAi
  } from '@/api/tms'

  defineOptions({ name: 'TmsWaybillDispatchDialog' })

  type WaybillRecord = Api.Tms.Waybill.WaybillRecord
  type DispatchVehicleOption = Api.Tms.Waybill.DispatchVehicleOption
  type DispatchPayload = Api.Tms.Waybill.WaybillDispatchPayload
  type DispatchRecommendation = Api.Tms.Waybill.DispatchRecommendation
  type DispatchRecommendationResponse = Api.Tms.Waybill.DispatchRecommendationResponse

  interface DialogOpenData {
    rows: WaybillRecord[]
    mode: 'single' | 'batch'
  }

  interface DialogGroup {
    rows: WaybillRecord[]
    mode: 'single' | 'batch'
  }

  interface FormGroup {
    data: DispatchPayload
    selectedVehicles: DataSelectRecord[]
    selectedVehicle: ComputedRef<DispatchVehicleOption | undefined>
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<DispatchPayload>>
    vehicleColumns: ComputedRef<DataSelectColumn[]>
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface AdvisorGroup {
    loading: boolean
    data: DispatchRecommendationResponse | null
    error: string
  }

  const emit = defineEmits<{
    success: []
  }>()

  const dialogRef = ref<ArtDialogExpose<DialogOpenData>>()
  const formRef = ref<FormExpose>()

  const dialog: UnwrapNestedRefs<DialogGroup> = reactive<DialogGroup>({
    rows: [],
    mode: 'single'
  })

  const advisor: UnwrapNestedRefs<AdvisorGroup> = reactive<AdvisorGroup>({
    loading: false,
    data: null,
    error: ''
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    selectedVehicles: [],
    selectedVehicle: computed(() => form.selectedVehicles[0] as DispatchVehicleOption | undefined),
    items: computed<FormItem[]>(() => [
      { label: '车辆', key: 'dispatchVehicleId', type: 'input', span: 24 },
      {
        label: '计划发车时间',
        key: 'plannedDepartureTime',
        type: 'date',
        span: 12,
        props: {
          type: 'datetime',
          valueFormat: 'YYYY-MM-DD HH:mm:ss',
          placeholder: '请选择计划发车时间',
          class: '!w-full'
        }
      },
      {
        label: '计划到达时间',
        key: 'plannedArrivalTime',
        type: 'date',
        span: 12,
        props: {
          type: 'datetime',
          valueFormat: 'YYYY-MM-DD HH:mm:ss',
          placeholder: '请选择计划到达时间',
          class: '!w-full'
        }
      },
      {
        label: '配载备注',
        key: 'dispatchRemark',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 3,
          maxlength: 200,
          showWordLimit: true,
          placeholder: '请输入配载备注'
        }
      }
    ]),
    rules: computed<FormRules<DispatchPayload>>(() => ({
      dispatchVehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      plannedDepartureTime: [{ required: true, message: '请选择计划发车时间', trigger: 'change' }],
      plannedArrivalTime: [{ required: true, message: '请选择计划到达时间', trigger: 'change' }]
    })),
    vehicleColumns: computed<DataSelectColumn[]>(() => [
      { prop: 'plateNo', label: '车牌号', minWidth: 130 },
      { prop: 'companyName', label: '所属公司', minWidth: 160 },
      {
        prop: 'vehicleType',
        label: '车型',
        width: 120,
        dict: { code: 'vehicleType', display: 'text' }
      },
      { prop: 'tonnageOrSeat', label: '吨位/座位', width: 120 },
      {
        prop: 'primaryDriver',
        label: '司机',
        width: 110,
        formatter: (row) => formatPrimaryDriverName(row as DispatchVehicleOption)
      },
      {
        prop: 'primaryDriver',
        label: '司机电话',
        width: 130,
        formatter: (row) => formatPrimaryDriverPhone(row as DispatchVehicleOption)
      }
    ])
  })

  async function handleOpen(data: DialogOpenData): Promise<void> {
    resetForm(data)
    await dialogRef.value?.handleOpen(data, {
      title: data.mode === 'batch' ? '批量配载' : '车辆配载',
      width: '900px',
      contentMaxHeight: '76vh',
      confirmText: '确认',
      onOpen: async () => {
        await nextTick()
        formRef.value?.clearValidate()
      },
      onConfirm: handleSubmit
    })
  }

  async function fetchVehicleSelectData(params: DataSelectFetchParams) {
    const from = (params.page - 1) * params.pageSize
    const to = from + params.pageSize - 1
    const { data, total } = await fetchDispatchVehicleOptions({
      keyword: params.keyword,
      from,
      to
    })

    return { data: data ?? [], total: total ?? 0 }
  }

  function handleVehicleConfirm(_value: unknown, rows: DataSelectRecord[]): void {
    const vehicle = rows[0] as DispatchVehicleOption | undefined
    applyVehicle(vehicle)
  }

  function handleVehicleClear(): void {
    applyVehicle(undefined)
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      const payload = normalizePayload()
      if (dialog.mode === 'batch') {
        await dispatchWaybillBatch(payload)
      } else {
        await dispatchWaybill(payload)
      }
      emit('success')
      return true
    } catch {
      return false
    }
  }

  function resetForm(data: DialogOpenData): void {
    Object.assign(dialog, {
      rows: data.rows,
      mode: data.mode
    })
    Object.assign(form.data, createInitialForm())
    form.selectedVehicles = []
    Object.assign(advisor, { loading: false, data: null, error: '' })
  }

  async function loadRecommendations(): Promise<void> {
    const orderId = String(dialog.rows[0]?.id || '')
    if (!orderId || advisor.loading) return

    advisor.loading = true
    advisor.error = ''
    try {
      const { data, error } = await recommendDispatchResourcesByAi(orderId, 3)
      if (error) throw error
      if (!data) throw new Error('推荐服务未返回结果')
      advisor.data = data
    } catch (error) {
      advisor.error = getErrorMessage(error)
    } finally {
      advisor.loading = false
    }
  }

  function applyRecommendation(item: DispatchRecommendation): void {
    const vehicle: DispatchVehicleOption = {
      id: item.vehicle.id,
      carrierId: item.vehicle.carrierId,
      plateNo: item.vehicle.plateNo,
      companyName: item.vehicle.companyName || undefined,
      vehicleType: item.vehicle.vehicleType || undefined,
      tonnageOrSeat: item.vehicle.tonnageOrSeat,
      overallLength: item.vehicle.overallLength,
      primaryDriverId: item.vehicle.primaryDriver.id,
      primaryDriver: {
        id: item.vehicle.primaryDriver.id,
        driverName: item.vehicle.primaryDriver.driverName,
        phone: item.vehicle.primaryDriver.phone || undefined,
        licenseType: item.vehicle.primaryDriver.licenseType || undefined,
        enabled: true
      }
    }
    form.selectedVehicles = [vehicle as DataSelectRecord]
    applyVehicle(vehicle)
    ElMessage.success(`已采用 ${vehicle.plateNo}，请确认计划时间后提交配载`)
  }

  function getErrorMessage(error: unknown): string {
    if (error && typeof error === 'object' && 'message' in error) {
      const message = (error as { message?: unknown }).message
      if (typeof message === 'string' && message.trim()) return message.trim()
    }
    return 'AI 调度推荐生成失败，请稍后重试'
  }

  function createInitialForm(): DispatchPayload {
    return {
      ids: [],
      dispatchVehicleId: '',
      dispatchDriverId: null,
      dispatchPlateNo: '',
      dispatchVehicleType: '',
      dispatchVehicleLength: '',
      dispatchDriverName: '',
      dispatchDriverPhone: '',
      plannedDepartureTime: '',
      plannedArrivalTime: '',
      dispatchRemark: ''
    }
  }

  function applyVehicle(vehicle?: DispatchVehicleOption): void {
    const driver = vehicle?.primaryDriver
    Object.assign(form.data, {
      dispatchVehicleId: vehicle?.id || '',
      dispatchDriverId: driver?.id || vehicle?.primaryDriverId || null,
      dispatchPlateNo: vehicle?.plateNo || '',
      dispatchVehicleType: vehicle?.vehicleType || '',
      dispatchVehicleLength: formatVehicleLength(vehicle),
      dispatchDriverName: driver?.driverName || '',
      dispatchDriverPhone: driver?.phone || ''
    })
  }

  function formatPrimaryDriverName(vehicle: DispatchVehicleOption): string {
    return vehicle.primaryDriver?.driverName || '-'
  }

  function formatPrimaryDriverPhone(vehicle: DispatchVehicleOption): string {
    return vehicle.primaryDriver?.phone || '-'
  }

  function normalizePayload(): DispatchPayload {
    const ids = dialog.rows.map((row) => String(row.id || '')).filter(Boolean)
    return {
      ...toRaw(form.data),
      id: dialog.mode === 'single' ? ids[0] : undefined,
      ids: dialog.mode === 'batch' ? ids : undefined,
      dispatchRemark: normalizeText(form.data.dispatchRemark)
    }
  }

  function formatVehicleLength(vehicle?: DispatchVehicleOption): string {
    if (!vehicle) return ''
    if (vehicle.tonnageOrSeat) return vehicle.tonnageOrSeat
    if (vehicle.overallLength) return `${vehicle.overallLength}mm`
    return ''
  }

  function formatValue(value?: string | number | null): string {
    const text = trim(String(value ?? ''))
    return text || '-'
  }

  function normalizeText(value?: string | null): string | null {
    const text = trim(String(value ?? ''))
    return text || null
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .dispatch-dialog {
    display: grid;
    gap: 16px;

    &__order {
      display: flex;
      flex-wrap: wrap;
      margin: 0 6px;
      gap: 12px 24px;
      color: var(--art-text-gray-700);
    }

    &__advisor {
      display: grid;
      gap: 12px;
      padding: 14px;
      margin: 0 6px;
      border: 1px solid var(--el-color-primary-light-8);

      > header {
        display: flex;
        gap: 16px;
        align-items: center;
        justify-content: space-between;

        > div {
          display: flex;
          gap: 10px;
          align-items: center;

          > div {
            display: grid;
            gap: 3px;
          }
        }

        strong {
          color: var(--art-text-gray-800);
        }

        small {
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__advisor-icon {
      display: grid;
      place-items: center;
      width: 36px;
      height: 36px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);

      .art-svg-icon {
        font-size: 20px;
      }
    }

    &__advisor-summary,
    &__advisor-empty {
      margin: 0;
      font-size: 13px;
      color: var(--el-text-color-secondary);
    }

    &__recommendations {
      display: grid;
      gap: 10px;

      article {
        display: grid;
        gap: 9px;
        padding: 12px;
        background: var(--el-fill-color-lighter);
        border: 1px solid var(--el-border-color-extra-light);
        border-radius: var(--el-border-radius-base);

        &.is-first {
          background: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-7);
        }

        > footer {
          display: flex;
          flex-wrap: wrap;
          gap: 8px 16px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__recommendation-main {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto auto;
      gap: 10px;
      align-items: center;

      > div {
        display: grid;
        gap: 2px;
        min-width: 0;

        small {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }
      }
    }

    &__recommendation-rank {
      font-weight: 700;
      color: var(--el-color-primary);
    }

    &__recommendation-reasons {
      display: flex;
      flex-wrap: wrap;
      gap: 6px 14px;
      font-size: 12px;
      color: var(--el-text-color-regular);

      span {
        display: inline-flex;
        gap: 4px;
        align-items: center;

        .art-svg-icon {
          color: var(--el-color-success);
        }

        &.is-warning .art-svg-icon {
          color: var(--el-color-warning);
        }
      }
    }

    &__vehicle {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px 18px;
      padding: 16px;
      background: var(--el-fill-color-lighter);

      div {
        display: grid;
        gap: 6px;
        min-width: 0;
      }

      span {
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }

      strong {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-weight: 600;
        color: var(--art-text-gray-800);
        white-space: nowrap;
      }
    }

    :deep(.dispatch-dialog__form) {
      padding: 0;

      > .el-form > .el-row {
        margin-right: 0 !important;
        margin-left: 0 !important;
      }
    }
  }

  @media (width <= 768px) {
    .dispatch-dialog {
      &__advisor {
        > header {
          align-items: flex-start;

          > div {
            align-items: flex-start;
          }
        }
      }

      &__recommendation-main {
        grid-template-columns: auto minmax(0, 1fr) auto;

        .el-tag {
          display: none;
        }
      }

      &__vehicle {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
