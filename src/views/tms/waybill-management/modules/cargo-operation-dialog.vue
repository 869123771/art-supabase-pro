<template>
  <ArtDialog ref="dialogRef" size="lg">
    <div class="cargo-operation-dialog">
      <section class="cargo-operation-dialog__summary art-card-xs">
        <div class="cargo-operation-dialog__summary-icon" :class="`is-${operationType}`">
          <ArtSvgIcon
            :icon="
              operationType === 'loading' ? 'ri:upload-cloud-2-line' : 'ri:download-cloud-2-line'
            "
          />
        </div>
        <div class="cargo-operation-dialog__summary-copy">
          <span>{{ operationTitle }}作业</span>
          <strong>{{ currentRow?.orderNo || '运单' }}</strong>
          <small>{{ operationAddress }}</small>
        </div>
        <ElTag :type="statusTag.type" effect="light" round>{{ statusTag.label }}</ElTag>
      </section>

      <ElAlert
        v-if="context"
        class="cargo-operation-dialog__policy"
        :type="context.allowOutsideCheckIn ? 'warning' : 'info'"
        :closable="false"
        show-icon
        :title="policyTitle"
        :description="policyDescription"
      />

      <section class="cargo-operation-dialog__checkin art-card-xs">
        <ArtSectionTitle :show-line="false">定位打卡</ArtSectionTitle>
        <div v-if="context?.operation" class="cargo-operation-dialog__checkin-grid">
          <div
            ><span>打卡时间</span><strong>{{ checkinTimeText }}</strong></div
          >
          <div
            ><span>打卡方式</span><strong>{{ checkinModeText }}</strong></div
          >
          <div
            ><span>围栏判定</span><strong>{{ geofenceResultText }}</strong></div
          >
          <div
            ><span>定位精度</span><strong>{{ accuracyText }}</strong></div
          >
        </div>
        <div v-else class="cargo-operation-dialog__locate">
          <div>
            <strong>请先获取当前定位并完成打卡</strong>
            <p>系统会在服务端计算与{{ operationTitle }}地的距离，并保存坐标、精度和围栏快照。</p>
          </div>
          <ElButton type="primary" :loading="state.locating" @click="handleCheckIn">
            <ArtSvgIcon icon="ri:map-pin-user-line" />
            获取定位并打卡
          </ElButton>
        </div>
      </section>

      <ArtForm
        v-if="!checkinOnly"
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :disabled="!context?.operation || context.operation.operationStatus === 'completed'"
        :span="12"
        :gutter="20"
        label-position="top"
        :show-reset="false"
        :show-submit="false"
        class="cargo-operation-dialog__form art-card-xs"
      >
        <template #photoUrls>
          <ArtUploadImage
            v-model="form.data.photoUrls"
            :title="`${operationTitle}照片`"
            :size="92"
            :limit="5"
            multiple
          />
        </template>
        <template #weighbridgeTicketUrls>
          <ArtUploadImage
            v-model="form.data.weighbridgeTicketUrls"
            :title="`${operationTitle}磅单`"
            :size="92"
            :limit="3"
            multiple
          />
        </template>
      </ArtForm>
    </div>

    <template #footer="{ loading, api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
      <ElButton
        v-if="!checkinOnly && context?.operation?.operationStatus !== 'completed'"
        type="primary"
        :loading="loading"
        :disabled="!context?.operation"
        @click="api.handleConfirm()"
      >
        提交{{ operationTitle }}信息
      </ElButton>
    </template>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { ComputedRef } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import {
    checkInWaybillCargoOperation,
    completeWaybillCargoOperation,
    fetchWaybillCargoOperationContext
  } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'
  import { useAmapSdk } from '@/hooks/core/useAmapSdk'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { WaybillRecord } from './waybill-shared'

  defineOptions({ name: 'TmsWaybillCargoOperationDialog' })

  type OperationType = Api.Tms.Waybill.CargoOperationType
  type OperationContext = Api.Tms.Waybill.CargoOperationContext

  interface OpenData {
    row: WaybillRecord
    operationType: OperationType
    checkinOnly?: boolean
  }

  interface OperationForm {
    weightTon: number | null
    checkinTimeDisplay: string
    photoUrls: string[]
    weighbridgeTicketUrls: string[]
    remark: string
  }

  interface FormGroup {
    data: OperationForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<OperationForm>
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface LocationResult {
    longitude: number
    latitude: number
    accuracy: number | null
    locationText?: string
  }

  interface AmapLocationResult {
    position?: { getLng: () => number; getLat: () => number }
    accuracy?: number
    formattedAddress?: string
  }

  interface AmapNamespace {
    Geolocation: new (options: Record<string, unknown>) => {
      getCurrentPosition: (
        callback: (status: string, result: AmapLocationResult | { message?: string }) => void
      ) => void
    }
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<FormExpose>()
  const currentRow = shallowRef<WaybillRecord>()
  const operationType = ref<OperationType>('loading')
  const checkinOnly = ref(false)
  const context = shallowRef<OperationContext>()
  const state = reactive({ locating: false })
  const { loadAmap } = useAmapSdk<AmapNamespace>({
    key: import.meta.env.VITE_AMAP_KEY,
    securityJsCode: import.meta.env.VITE_AMAP_SECURITY_JS_CODE,
    plugins: ['AMap.Geolocation']
  })
  const { promptReason } = useArtFeedback()

  const createInitialForm = (): OperationForm => ({
    weightTon: null,
    checkinTimeDisplay: '',
    photoUrls: [],
    weighbridgeTicketUrls: [],
    remark: ''
  })

  const operationTitle = computed(() => (operationType.value === 'loading' ? '装货' : '卸货'))
  const operationAddress = computed(() =>
    operationType.value === 'loading'
      ? currentRow.value?.shippingAddressDetail || '未维护装货地址'
      : currentRow.value?.receivingAddressDetail || '未维护卸货地址'
  )
  const statusTag = computed(() => {
    const status = context.value?.operation?.operationStatus
    if (status === 'completed')
      return { label: `${operationTitle.value}已完成`, type: 'success' as const }
    if (status === 'checked_in') return { label: '已打卡，待补资料', type: 'warning' as const }
    return { label: '待打卡', type: 'info' as const }
  })
  const policyTitle = computed(() => {
    if (!context.value?.geofenceEnabled) return '电子围栏校验已停用'
    return context.value.allowOutsideCheckIn ? '可围栏外手动打卡' : '仅支持围栏内打卡'
  })
  const policyDescription = computed(() => {
    if (!context.value) return ''
    const automatic = context.value.autoCheckIn ? '围栏内支持自动打卡' : '围栏内仍需手动打卡'
    return `围栏半径 ${context.value.radiusM.toLocaleString()} 米；${automatic}。围栏外打卡会记录异常原因。`
  })
  const checkinTimeText = computed(
    () => formatWithDayjs(context.value?.operation?.checkinTime) || '--'
  )
  const checkinModeText = computed(() => {
    const labels: Record<string, string> = {
      manual: '司机手动',
      automatic: '围栏自动',
      admin: 'PC 端操作'
    }
    return labels[context.value?.operation?.checkinMode || ''] || '--'
  })
  const geofenceResultText = computed(() => {
    const operation = context.value?.operation
    if (!operation) return '--'
    return `${operation.insideGeofence ? '围栏内' : '围栏外'} · 距中心 ${Math.round(operation.distanceM)} 米`
  })
  const accuracyText = computed(() => {
    const accuracy = context.value?.operation?.locationAccuracyM
    return accuracy === null || accuracy === undefined ? '--' : `约 ${Math.round(accuracy)} 米`
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      weightTon: [
        { required: true, message: '请输入实际重量', trigger: 'blur' },
        { type: 'number', min: 0.001, message: '重量必须大于 0 吨', trigger: 'blur' }
      ],
      photoUrls: [{ type: 'array', required: true, min: 1, message: '请至少上传 1 张现场照片' }],
      weighbridgeTicketUrls: [
        { type: 'array', required: true, min: 1, message: '请至少上传 1 张磅单' }
      ]
    },
    items: computed<FormItem[]>(() => [
      { label: `${operationTitle.value}资料`, key: 'operationSection', type: 'divider', span: 24 },
      {
        label: `${operationTitle.value}重量（吨）`,
        key: 'weightTon',
        type: 'number',
        props: { min: 0.001, precision: 3, step: 0.1, controlsPosition: 'right', class: '!w-full' },
        description: '以现场实际磅重为准，最多保留 3 位小数。'
      },
      {
        label: `${operationTitle.value}时间`,
        key: 'checkinTimeDisplay',
        type: 'text',
        props: { emptyText: '--', class: 'font-medium text-theme' },
        description: '以服务端首次打卡时间为准，提交资料不会覆盖。'
      },
      { label: `${operationTitle.value}照片`, key: 'photoUrls', span: 24 },
      { label: `${operationTitle.value}磅单`, key: 'weighbridgeTicketUrls', span: 24 },
      {
        label: '备注',
        key: 'remark',
        type: 'textarea',
        span: 24,
        props: {
          rows: 3,
          maxlength: 300,
          showWordLimit: true,
          placeholder: '可填写货损、磅差或现场说明'
        }
      }
    ])
  })

  async function getCurrentLocation(): Promise<LocationResult> {
    if (!window.isSecureContext && !['localhost', '127.0.0.1'].includes(window.location.hostname)) {
      throw new Error('浏览器仅允许在 HTTPS 页面使用精确定位')
    }
    const AMap = await loadAmap()
    return await new Promise((resolve, reject) => {
      const geolocation = new AMap.Geolocation({
        convert: true,
        enableHighAccuracy: true,
        extensions: 'all',
        needAddress: true,
        showButton: false,
        showCircle: false,
        showMarker: false,
        timeout: 15000
      })
      geolocation.getCurrentPosition((status, result) => {
        if (status !== 'complete' || !('position' in result) || !result.position) {
          reject(new Error('定位失败，请检查浏览器定位权限和系统定位服务'))
          return
        }
        resolve({
          longitude: result.position.getLng(),
          latitude: result.position.getLat(),
          accuracy: Number.isFinite(result.accuracy) ? Number(result.accuracy) : null,
          locationText: result.formattedAddress || operationAddress.value
        })
      })
    })
  }

  function distanceMeters(location: LocationResult, target: OperationContext): number | null {
    if (target.centerLongitude == null || target.centerLatitude == null) return null
    const radians = (value: number) => (value * Math.PI) / 180
    const latitudeDelta = radians(target.centerLatitude - location.latitude)
    const longitudeDelta = radians(target.centerLongitude - location.longitude)
    const a =
      Math.sin(latitudeDelta / 2) ** 2 +
      Math.cos(radians(location.latitude)) *
        Math.cos(radians(target.centerLatitude)) *
        Math.sin(longitudeDelta / 2) ** 2
    return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  }

  async function resolveOutsideReason(location: LocationResult): Promise<string | null> {
    if (!context.value || !context.value.geofenceEnabled) return null
    const distance = distanceMeters(location, context.value)
    if (distance === null || distance <= context.value.radiusM) return null
    if (!context.value.allowOutsideCheckIn) {
      throw new Error(`当前不在${operationTitle.value}地围栏内，请到达现场后重新打卡`)
    }
    return await promptReason(
      `当前距${operationTitle.value}地约 ${Math.round(distance).toLocaleString()} 米，请说明围栏外打卡原因。`,
      '围栏外打卡确认',
      {
        confirmButtonText: '确认打卡',
        cancelButtonText: '取消',
        placeholder: '例如：园区入口封闭，车辆在指定临时作业区',
        minLength: 4,
        minLengthMessage: '请至少填写 4 个字'
      }
    )
  }

  async function handleCheckIn(): Promise<void> {
    if (!currentRow.value?.driverWaybillId || !context.value || state.locating) return
    state.locating = true
    try {
      const location = await getCurrentLocation()
      const outsideReason = await resolveOutsideReason(location)
      const result = await checkInWaybillCargoOperation({
        waybillId: currentRow.value.driverWaybillId,
        operationType: operationType.value,
        longitude: location.longitude,
        latitude: location.latitude,
        accuracyM: location.accuracy,
        locationText: location.locationText || operationAddress.value,
        outsideReason
      })
      if (result.data) context.value = result.data
      if (checkinOnly.value) {
        emit('success')
        await dialogRef.value?.handleClose()
      }
    } catch (error) {
      if (isMessageBoxCancelled(error)) return
      if (error instanceof Error && error.message) ElMessage.error(error.message)
    } finally {
      state.locating = false
    }
  }

  async function handleSubmit(): Promise<boolean> {
    if (!currentRow.value?.driverWaybillId || !context.value?.operation) return false
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    try {
      await completeWaybillCargoOperation({
        waybillId: currentRow.value.driverWaybillId,
        operationType: operationType.value,
        weightTon: Number(form.data.weightTon),
        photoUrls: [...form.data.photoUrls],
        weighbridgeTicketUrls: [...form.data.weighbridgeTicketUrls],
        remark: form.data.remark.trim() || null
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function loadContext(): Promise<void> {
    const waybillId = currentRow.value?.driverWaybillId
    if (!waybillId) throw new Error('该订单尚未生成司机运单，请先完成配载')
    const result = await fetchWaybillCargoOperationContext(waybillId, operationType.value)
    context.value = result.data ?? undefined
    const operation = result.data?.operation
    Object.assign(form.data, createInitialForm(), {
      weightTon: operation?.weightTon ?? null,
      checkinTimeDisplay: operation?.checkinTime ? formatWithDayjs(operation.checkinTime) : '',
      photoUrls: operation?.photoUrls ?? [],
      weighbridgeTicketUrls: operation?.weighbridgeTicketUrls ?? [],
      remark: operation?.remark ?? ''
    })
  }

  function isMessageBoxCancelled(error: unknown): boolean {
    const action =
      typeof error === 'string'
        ? error
        : error && typeof error === 'object' && 'action' in error
          ? String(error.action)
          : ''
    return action === 'cancel' || action === 'close'
  }

  async function resetForm(): Promise<void> {
    context.value = undefined
    currentRow.value = undefined
    Object.assign(form.data, createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleOpen(data: OpenData): Promise<void> {
    await resetForm()
    currentRow.value = data.row
    operationType.value = data.operationType
    checkinOnly.value = data.checkinOnly === true
    await dialogRef.value?.handleOpen(data, {
      title: checkinOnly.value ? '确认到达目的地' : `${operationTitle.value}打卡与资料`,
      subtitle: checkinOnly.value
        ? '获取当前地址与经纬度，服务端校验卸货地围栏后进入卸货节点。'
        : '打卡时间和位置由服务端留痕，现场照片与磅单用于履约核验',
      confirmText: `提交${operationTitle.value}信息`,
      contentMaxHeight: '78vh',
      loading: true,
      onOpen: async (_openData, api) => {
        try {
          await loadContext()
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .cargo-operation-dialog {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-3);
    min-width: 0;

    &__summary {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      padding: var(--art-space-4);
    }

    &__summary-icon {
      display: grid;
      flex: 0 0 48px;
      place-items: center;
      width: 48px;
      height: 48px;
      font-size: 24px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--custom-radius);

      &.is-unloading {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }
    }

    &__summary-copy {
      min-width: 0;
      margin-right: auto;

      span,
      small {
        display: block;
        color: var(--el-text-color-secondary);
      }

      strong {
        display: block;
        margin: 3px 0;
        font-size: 18px;
        color: var(--el-text-color-primary);
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__checkin,
    &__form {
      padding: var(--art-space-4);
    }

    &__checkin-grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: var(--art-space-3);
      margin-top: var(--art-space-3);

      > div {
        min-width: 0;
        padding: 12px;
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);

        span,
        strong {
          display: block;
        }

        span {
          margin-bottom: 6px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }
      }
    }

    &__locate {
      display: flex;
      gap: var(--art-space-4);
      align-items: center;
      justify-content: space-between;
      padding: 16px;
      margin-top: var(--art-space-3);
      background: var(--el-fill-color-lighter);
      border: 1px dashed var(--el-border-color);
      border-radius: var(--el-border-radius-base);

      p {
        margin: 5px 0 0;
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 767px) {
      &__summary {
        flex-wrap: wrap;
        align-items: flex-start;
      }

      &__checkin-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__locate {
        flex-direction: column;
        align-items: stretch;
      }
    }
  }
</style>
