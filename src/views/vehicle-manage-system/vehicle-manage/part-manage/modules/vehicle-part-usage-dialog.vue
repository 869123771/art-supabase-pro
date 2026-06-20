<template>
  <ArtDialog ref="dialogRef" width="1120px" show-fullscreen-button>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :span="8"
      :gutter="20"
      label-width="120px"
      root-class="vehicle-part-usage-form"
      :show-reset="false"
      :show-submit="false"
    >
      <template #vehicleId>
        <ArtTableSingleSelect
          v-model="vehicleSelectValue"
          v-model:selected-data="form.vehicleSelection"
          :api-fn="fetchVehicleRows"
          :columns="vehicleColumns"
          row-key="id"
          label-key="plateNo"
          description-key="companyName"
          title="选择车辆"
          search-placeholder="输入车牌号或所属公司"
          show-pagination
          @change="handleVehicleChange"
        />
      </template>

      <template #partId>
        <ArtTableSingleSelect
          v-model="partSelectValue"
          v-model:selected-data="form.partSelection"
          :api-fn="fetchPartRows"
          :columns="partColumns"
          row-key="id"
          label-key="partName"
          description-key="partCode"
          title="选择零部件"
          search-placeholder="输入零部件名称或编码"
          show-pagination
          @change="handlePartChange"
        />
      </template>

      <template #rfidTag>
        <div class="vehicle-part-usage-form__inline">
          <ElRadioGroup v-model="form.data.rfidEnabled">
            <ElRadio
              v-for="option in getBooleanDictOptions()"
              :key="String(option.value)"
              :value="option.value"
            >
              {{ option.label }}
            </ElRadio>
          </ElRadioGroup>
          <ElInput
            v-if="form.data.rfidEnabled"
            v-model="form.data.rfidTag"
            placeholder="请输入RFID标签"
            maxlength="80"
            clearable
          />
        </div>
      </template>

      <template #enableDate>
        <div class="vehicle-part-usage-form__inline">
          <ElRadioGroup v-model="form.data.enableMode" @change="handleEnableModeChange">
            <ElRadio
              v-for="option in getDictMap.vehiclePartEnableMode ?? []"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </ElRadio>
          </ElRadioGroup>
          <ElDatePicker
            v-if="form.data.enableMode === 'date'"
            v-model="form.data.enableDate"
            type="date"
            value-format="YYYY-MM-DD"
            placeholder="选择启用日期"
            class="w-full"
          />
        </div>
      </template>

      <template #warrantyMileage>
        <div class="vehicle-part-usage-form__stack">
          <ElRadioGroup v-model="form.data.warrantyMode" @change="handleWarrantyModeChange">
            <ElRadio
              v-for="option in getDictMap.vehiclePartWarrantyMode ?? []"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </ElRadio>
          </ElRadioGroup>
          <div
            v-if="form.data.warrantyMode === 'self'"
            class="vehicle-part-usage-form__metric-list"
          >
            <ElInputNumber
              v-model="form.data.warrantyMileage"
              :min="0"
              :controls="false"
              placeholder="质保里程"
            />
            <span>公里</span>
            <ElInputNumber
              v-model="form.data.warrantyDuration"
              :min="0"
              :precision="0"
              :controls="false"
              placeholder="质保时长"
            />
            <span>个月</span>
          </div>
        </div>
      </template>

      <template #serviceMileage>
        <div class="vehicle-part-usage-form__metric-list">
          <ElCheckbox v-model="form.data.serviceMileageEnabled">使用里程</ElCheckbox>
          <ElInputNumber
            v-if="form.data.serviceMileageEnabled"
            v-model="form.data.serviceMileage"
            :min="0"
            :controls="false"
          />
          <span v-if="form.data.serviceMileageEnabled">公里</span>
          <ElCheckbox v-model="form.data.serviceYearsEnabled">使用年限</ElCheckbox>
          <ElInputNumber
            v-if="form.data.serviceYearsEnabled"
            v-model="form.data.serviceYears"
            :min="0"
            :precision="0"
            :controls="false"
          />
          <span v-if="form.data.serviceYearsEnabled">年</span>
        </div>
      </template>

      <template #status>
        <div class="vehicle-part-usage-form__inline">
          <ElRadioGroup v-model="form.data.status" @change="handleStatusChange">
            <ElRadio
              v-for="option in getDictMap.vehiclePartUsageStatus ?? []"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </ElRadio>
          </ElRadioGroup>
          <ElInput
            v-if="form.data.status === 'scrapped'"
            v-model="form.data.scrapReason"
            placeholder="请输入报废原因"
            maxlength="200"
          />
        </div>
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import { cloneDeep } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectKey,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import {
    addVehiclePartUsage,
    editVehiclePartUsage,
    fetchPartsList,
    fetchVehicleArchiveList
  } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'VehiclePartUsageDialog' })

  type Usage = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage
  type Vehicle = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type Part = Api.VehicleMgtSys.BasicInfo.Parts

  interface FormGroup {
    data: Usage
    vehicleSelection: DataSelectRecord[]
    partSelection: DataSelectRecord[]
    rules: FormRules<Usage>
  }

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Usage | undefined>>()
  const formRef = ref<{
    validate: () => Promise<boolean>
    clearValidate: () => void
  }>()

  const createInitialForm = (): Usage => ({
    id: undefined,
    vehicleId: null,
    plateNo: '',
    companyName: '',
    partId: null,
    partType: 'original',
    partName: '',
    partCode: '',
    categoryId: null,
    categoryName: '',
    brand: '',
    model: '',
    unit: '',
    qualityCategory: '',
    manufacturer: '',
    supplierId: null,
    supplierName: '',
    supplierContact: '',
    isConsumable: false,
    rfidEnabled: false,
    rfidTag: '',
    enableMode: 'vehicle',
    enableDate: null,
    warrantyMode: 'vehicle',
    warrantyMileage: null,
    warrantyDuration: null,
    serviceMileageEnabled: true,
    serviceMileage: null,
    serviceYearsEnabled: false,
    serviceYears: null,
    usedMileage: 0,
    status: 'normal',
    scrapReason: '',
    remark: ''
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    vehicleSelection: [],
    partSelection: [],
    rules: {
      vehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      partType: [{ required: true, message: '请选择零部件类型', trigger: 'change' }],
      partId: [{ required: true, message: '请选择零部件', trigger: 'change' }],
      rfidTag: [{ validator: validateRfidTag, trigger: 'blur' }],
      enableDate: [{ validator: validateEnableDate, trigger: 'change' }],
      warrantyMileage: [{ validator: validateWarranty, trigger: 'change' }],
      serviceMileage: [{ validator: validateServiceLife, trigger: 'change' }],
      status: [{ validator: validateStatus, trigger: 'change' }]
    }
  })

  const formItems = computed<FormItem[]>(() => [
    { label: '零部件信息', key: 'partInfoSection', type: 'divider', span: 24 },
    { label: '车牌号', key: 'vehicleId', span: 12 },
    { label: '所属公司', key: 'companyName', type: 'input', span: 12, props: { disabled: true } },
    {
      label: '零部件类型',
      key: 'partType',
      type: 'radioGroup',
      span: 24,
      options: getDictMap.value.vehiclePartType ?? []
    },
    { label: '零部件名称', key: 'partId', span: 12 },
    {
      label: '零部件类别',
      key: 'categoryName',
      type: 'input',
      span: 12,
      props: { disabled: true }
    },
    {
      label: '零部件品牌',
      key: 'brand',
      type: 'input',
      props: { disabled: true }
    },
    {
      label: '零部件型号',
      key: 'model',
      type: 'input',
      props: { disabled: true }
    },
    { label: '单位', key: 'unit', type: 'input', props: { disabled: true } },
    {
      label: '是否易损/耗件',
      key: 'isConsumable',
      type: 'radioGroup',
      props: {
        disabled: true,
        options: getBooleanDictOptions()
      }
    },
    {
      label: '品质分类',
      key: 'qualityCategory',
      type: 'select',
      options: getDictMap.value.vehiclePartQualityCategory ?? []
    },
    { label: '生产厂商', key: 'manufacturer', type: 'input' },
    {
      label: '供应厂商',
      key: 'supplierName',
      type: 'input',
      props: { disabled: true }
    },
    {
      label: '供应厂商联系人',
      key: 'supplierContact',
      type: 'input',
      span: 16,
      props: { disabled: true }
    },
    { label: '零部件使用', key: 'partUsageSection', type: 'divider', span: 24 },
    { label: 'RFID标签', key: 'rfidTag', span: 24 },
    { label: '启用日期', key: 'enableDate', span: 24 },
    { label: '质保期', key: 'warrantyMileage', span: 24 },
    { label: '使用寿命', key: 'serviceMileage', span: 24 },
    {
      label: '已使用里程',
      key: 'usedMileage',
      type: 'number',
      span: 12,
      props: { min: 0, controls: false, class: 'w-full' }
    },
    { label: '状态', key: 'status', span: 24 },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  const vehicleSelectValue = computed<DataSelectKey | undefined>({
    get: () => form.data.vehicleId ?? undefined,
    set: (value) => {
      form.data.vehicleId = value ? String(value) : null
    }
  })

  const partSelectValue = computed<DataSelectKey | undefined>({
    get: () => form.data.partId ?? undefined,
    set: (value) => {
      form.data.partId = value ? String(value) : null
    }
  })

  const vehicleColumns: DataSelectColumn[] = [
    { prop: 'companyName', label: '所属公司', minWidth: 180 },
    { prop: 'plateNo', label: '车牌号', width: 140 },
    {
      prop: 'operationStatus',
      label: '营运状态',
      width: 120,
      dict: { code: 'vehicleOperationStatus', display: 'auto' }
    }
  ]

  const partColumns: DataSelectColumn[] = [
    { prop: 'partName', label: '零部件名称', minWidth: 180 },
    { prop: 'partCode', label: '零部件编码', minWidth: 150 },
    {
      prop: 'category',
      label: '类别',
      minWidth: 120,
      formatter: (row) => row.category?.categoryName || '-'
    },
    { prop: 'brand', label: '品牌', width: 110 },
    { prop: 'model', label: '型号', minWidth: 130 },
    { prop: 'unit', label: '单位', width: 80 },
    {
      prop: 'supplier',
      label: '供应厂商',
      minWidth: 150,
      formatter: (row) => row.supplier?.supplierName || '-'
    }
  ]

  const getBooleanDictOptions = () =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))

  const fetchVehicleRows = async (params: DataSelectFetchParams) => {
    const from = (params.page - 1) * params.pageSize
    const { data, total } = await fetchVehicleArchiveList({
      plateNo: params.keyword,
      auditStatus: 'approved',
      from,
      to: from + params.pageSize - 1
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  const fetchPartRows = async (params: DataSelectFetchParams) => {
    const from = (params.page - 1) * params.pageSize
    const { data, total } = await fetchPartsList({
      partName: params.keyword,
      status: '1',
      from,
      to: from + params.pageSize - 1
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  const handleVehicleChange = (_value: unknown, rows: DataSelectRecord[]): void => {
    const vehicle = rows[0] as Vehicle | undefined
    form.data.vehicleId = vehicle?.id ?? null
    form.data.plateNo = vehicle?.plateNo ?? ''
    form.data.companyName = vehicle?.companyName ?? ''
    if (form.data.enableMode === 'vehicle') {
      form.data.enableDate = vehicle?.startUseDate ?? vehicle?.registerDate ?? null
    }
  }

  const handlePartChange = (_value: unknown, rows: DataSelectRecord[]): void => {
    const part = rows[0] as Part | undefined
    form.data.partId = part?.id ?? null
    form.data.partName = part?.partName ?? ''
    form.data.partCode = part?.partCode ?? ''
    form.data.categoryId = part?.categoryId ?? null
    form.data.categoryName = part?.category?.categoryName ?? ''
    form.data.brand = part?.brand ?? ''
    form.data.model = part?.model ?? ''
    form.data.unit = part?.unit ?? ''
    form.data.manufacturer = part?.manufacturer ?? ''
    form.data.supplierId = part?.supplierId ?? null
    form.data.supplierName = part?.supplier?.supplierName ?? ''
    form.data.supplierContact = part?.supplierContact ?? ''
    form.data.isConsumable = Boolean(part?.isConsumable)
    form.data.warrantyMileage = part?.warrantyMileage ?? null
    form.data.warrantyDuration = part?.warrantyDuration ?? null
    form.data.serviceMileage = part?.serviceMileage ?? null
    form.data.serviceMileageEnabled =
      part?.serviceMileage !== null && part?.serviceMileage !== undefined
    form.data.serviceYears = part?.serviceLife ?? null
    form.data.serviceYearsEnabled = part?.serviceLife !== null && part?.serviceLife !== undefined
  }

  const handleEnableModeChange = (): void => {
    if (form.data.enableMode === 'date') {
      form.data.enableDate = null
      return
    }
    const vehicle = form.vehicleSelection[0] as Vehicle | undefined
    form.data.enableDate = vehicle?.startUseDate ?? vehicle?.registerDate ?? null
  }

  const handleWarrantyModeChange = (): void => {
    if (form.data.warrantyMode === 'vehicle') {
      form.data.warrantyMileage = null
      form.data.warrantyDuration = null
    }
  }

  const handleStatusChange = (): void => {
    if (form.data.status !== 'scrapped') form.data.scrapReason = ''
  }

  function validateRfidTag(_rule: unknown, value: string, callback: (error?: Error) => void): void {
    if (form.data.rfidEnabled && !String(value ?? '').trim()) {
      callback(new Error('请输入RFID标签'))
      return
    }
    callback()
  }

  function validateEnableDate(
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ): void {
    if (form.data.enableMode === 'date' && !value) {
      callback(new Error('请选择启用日期'))
      return
    }
    callback()
  }

  function validateWarranty(
    _rule: unknown,
    _value: number,
    callback: (error?: Error) => void
  ): void {
    if (
      form.data.warrantyMode === 'self' &&
      !form.data.warrantyMileage &&
      !form.data.warrantyDuration
    ) {
      callback(new Error('请至少填写质保里程或质保时长'))
      return
    }
    callback()
  }

  function validateServiceLife(
    _rule: unknown,
    _value: number,
    callback: (error?: Error) => void
  ): void {
    if (!form.data.serviceMileageEnabled && !form.data.serviceYearsEnabled) {
      callback(new Error('请至少选择一种使用寿命'))
      return
    }
    if (form.data.serviceMileageEnabled && !form.data.serviceMileage) {
      callback(new Error('请输入使用里程'))
      return
    }
    if (form.data.serviceYearsEnabled && !form.data.serviceYears) {
      callback(new Error('请输入使用年限'))
      return
    }
    callback()
  }

  function validateStatus(_rule: unknown, _value: string, callback: (error?: Error) => void): void {
    if (form.data.status === 'scrapped' && !String(form.data.scrapReason ?? '').trim()) {
      callback(new Error('请输入报废原因'))
      return
    }
    callback()
  }

  const replaceForm = (data: Usage): void => {
    Object.assign(form.data, createInitialForm(), cloneDeep(toRaw(data)))
    form.vehicleSelection = data.vehicleId
      ? [
          {
            id: data.vehicleId,
            plateNo: data.plateNo,
            companyName: data.companyName
          }
        ]
      : []
    form.partSelection = data.partId
      ? [
          {
            id: data.partId,
            partName: data.partName,
            partCode: data.partCode,
            categoryName: data.categoryName,
            brand: data.brand,
            model: data.model,
            unit: data.unit,
            supplierName: data.supplierName
          }
        ]
      : []
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const normalizePayload = (): Usage => {
    const payload = { ...toRaw(form.data) }
    delete payload.tenantId
    delete payload.createBy
    delete payload.createTime
    delete payload.updateBy
    delete payload.updateTime

    if (!payload.rfidEnabled) payload.rfidTag = ''
    if (payload.warrantyMode === 'vehicle') {
      payload.warrantyMileage = null
      payload.warrantyDuration = null
    }
    if (!payload.serviceMileageEnabled) payload.serviceMileage = null
    if (!payload.serviceYearsEnabled) payload.serviceYears = null
    if (payload.status !== 'scrapped') payload.scrapReason = ''
    return payload
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = normalizePayload()
      if (form.data.id) {
        await editVehiclePartUsage(payload)
      } else {
        await addVehiclePartUsage(payload)
      }
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Usage): Promise<void> => {
    await resetForm()
    if (row?.id) replaceForm(row)
    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑零部件使用记录' : '新增零部件使用记录',
      contentMaxHeight: '74vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>

<style scoped lang="scss">
  .vehicle-part-usage-form {
    :deep(.art-section-title) {
      margin: 8px 0 20px;
    }

    &__inline,
    &__metric-list {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      width: 100%;

      .el-input,
      .el-date-editor {
        width: min(360px, 100%);
      }
    }

    &__stack {
      display: flex;
      flex-direction: column;
      gap: 12px;
      align-items: flex-start;
      width: 100%;
    }

    &__metric-list {
      .el-input-number {
        width: 180px;
      }
    }

    @media (max-width: 768px) {
      :deep(.el-col-8),
      :deep(.el-col-12),
      :deep(.el-col-16) {
        max-width: 100%;
        flex: 0 0 100%;
      }
    }
  }
</style>
