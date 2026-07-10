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
  import { dispatchWaybill, dispatchWaybillBatch, fetchDispatchVehicleOptions } from '@/api/tms'

  defineOptions({ name: 'TmsWaybillDispatchDialog' })

  type WaybillRecord = Api.Tms.Waybill.WaybillRecord
  type DispatchVehicleOption = Api.Tms.Waybill.DispatchVehicleOption
  type DispatchPayload = Api.Tms.Waybill.WaybillDispatchPayload

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

  const emit = defineEmits<{
    success: []
  }>()

  const dialogRef = ref<ArtDialogExpose<DialogOpenData>>()
  const formRef = ref<FormExpose>()

  const dialog: UnwrapNestedRefs<DialogGroup> = reactive<DialogGroup>({
    rows: [],
    mode: 'single'
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
      { prop: 'driverOneName', label: '司机', width: 110 },
      { prop: 'driverOnePhone', label: '司机电话', width: 130 }
    ])
  })

  async function handleOpen(data: DialogOpenData): Promise<void> {
    resetForm(data)
    await dialogRef.value?.handleOpen(data, {
      title: data.mode === 'batch' ? '批量配载' : '车辆配载',
      width: '680px',
      contentMaxHeight: '70vh',
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
      dispatchDriverName: driver?.driverName || vehicle?.driverOneName || '',
      dispatchDriverPhone: driver?.phone || vehicle?.driverOnePhone || ''
    })
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
      gap: 12px 24px;
      color: var(--art-text-gray-700);
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
        font-weight: 600;
        color: var(--art-text-gray-800);
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    :deep(.dispatch-dialog__form) {
      padding: 0;
    }
  }

  @media (width <= 768px) {
    .dispatch-dialog {
      &__vehicle {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
