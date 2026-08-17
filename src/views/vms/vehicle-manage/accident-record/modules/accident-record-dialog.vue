<template>
  <ArtDialog ref="dialogRef" size="xl" show-fullscreen-button>
    <template #subtitle
      >完整记录事故事实、损失、责任、处置状态与证据附件，支持后续安全复盘。</template
    >

    <div class="accident-record-dialog">
      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="12"
        :gutter="20"
        label-width="120px"
        :show-reset="false"
        :show-submit="false"
      >
        <template #vehicleId>
          <ArtTableSingleSelect
            v-model="vehicleSelectValue"
            v-model:selected-data="form.vehicleSelection"
            :api-fn="fetchVehicleSelectData"
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
        <template #accidentLocation>
          <ArtAddressPicker
            v-model:address-detail="form.data.accidentLocation"
            v-model:longitude="form.data.accidentLongitude"
            v-model:latitude="form.data.accidentLatitude"
            hide-region-selector
            detail-label="事故地点"
            detail-placeholder="输入事故地点，或使用地图搜索并选点"
            address-detail-prop="accidentLocation"
            label-width="120px"
            @address-change="handleLocationChange"
          />
        </template>
      </ArtForm>

      <section class="accident-record-dialog__section">
        <div class="accident-record-dialog__section-header">
          <ArtSectionTitle :show-line="false">事故附件</ArtSectionTitle>
          <ElButton type="primary" plain @click="openAttachmentDialog">上传</ElButton>
        </div>
        <ArtTable
          :data="form.data.attachments"
          :columns="attachmentColumns"
          :pagination="undefined"
          :show-table-header="false"
          empty-height="160px"
        />
      </section>
    </div>
  </ArtDialog>

  <ArtDialog ref="attachmentDialogRef" size="md">
    <div class="accident-attachment-dialog">
      <ArtForm
        ref="attachmentFormRef"
        v-model="attachment.data"
        :items="attachment.items"
        :rules="attachment.rules"
        :span="24"
        label-width="150px"
        :show-reset="false"
        :show-submit="false"
      >
        <template #file>
          <div class="accident-attachment-dialog__upload">
            <ArtExcelImport
              accept=""
              :parse-excel="false"
              :disabled="attachment.uploading"
              :button-props="{ loading: attachment.uploading }"
              @file-change="handleAttachmentFileChange"
            >
              选择上传文件
            </ArtExcelImport>
            <div v-if="attachment.data.fileName" class="accident-attachment-dialog__file">
              <span>{{ attachment.data.fileName }}</span>
              <ArtSvgIcon v-if="attachment.data.url" icon="ri:check-line" />
            </div>
          </div>
        </template>
      </ArtForm>
    </div>
  </ArtDialog>
</template>

<script setup lang="tsx">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElButton, ElMessage } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtAddressPicker from '@/components/core/forms/art-address-picker/index.vue'
  import type { AddressLocationPayload } from '@/components/core/forms/art-address-picker/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    DataSelectColumn,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { addVehicleAccident, editVehicleAccident, fetchVehicleArchiveList } from '@/api/vms'
  import { uploadAttachment } from '@/api/common'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { downloadAttachment, getFileExtension } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'AccidentRecordDialog' })

  const { confirmAction } = useArtFeedback()

  type AccidentRecord = Api.Vms.VehicleManage.VehicleAccidentRecord
  type VehicleArchive = Api.Vms.ArchiveManage.VehicleArchive
  type Attachment = Api.Vms.VehicleManage.VehicleAttachment

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: AccidentRecord
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<AccidentRecord>>
    vehicleSelection: VehicleArchive[]
  }

  interface AttachmentFormData {
    name: string
    file: string
    fileName: string
    url: string
    fileType?: string
    fileSize?: string
  }

  interface AttachmentGroup {
    data: AttachmentFormData
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<AttachmentFormData>>
    uploading: boolean
  }

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<AccidentRecord | undefined>>()
  const attachmentDialogRef = ref<ArtDialogExpose<void>>()
  const formRef = ref<FormExpose>()
  const attachmentFormRef = ref<FormExpose>()

  const createInitialForm = (): AccidentRecord => ({
    id: undefined,
    vehicleId: null,
    plateNo: '',
    companyName: '',
    driverName: '',
    driverPhone: '',
    accidentTime: '',
    accidentLocation: '',
    accidentLongitude: null,
    accidentLatitude: null,
    accidentSummary: '',
    damageLevel: '',
    responsibilityType: '',
    responsibilityPercent: null,
    companyBearAmount: null,
    economicLoss: null,
    reported: false,
    insuranceReported: false,
    processed: false,
    dataSource: 'self',
    remark: '',
    attachments: []
  })

  const createInitialAttachmentForm = (): AttachmentFormData => ({
    name: '',
    file: '',
    fileName: '',
    url: '',
    fileType: '',
    fileSize: ''
  })

  const dateTimeProps = {
    type: 'datetime',
    valueFormat: 'YYYY-MM-DD HH:mm:ss',
    class: '!w-full'
  }

  const moneyProps = {
    min: 0,
    precision: 2,
    controlsPosition: 'right',
    class: '!w-full'
  }

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    vehicleSelection: [],
    items: computed<FormItem[]>(() => [
      { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
      { label: '车牌号', key: 'vehicleId', span: 12 },
      { label: '所属公司', key: 'companyName', type: 'input', props: { disabled: true } },
      {
        label: '驾驶员',
        key: 'driverName',
        type: 'input',
        props: { maxlength: 50, placeholder: '选择车辆后自动带出，可按实际情况修改' }
      },
      {
        label: '联系方式',
        key: 'driverPhone',
        type: 'input',
        props: { maxlength: 30, placeholder: '选择车辆后自动带出，可按实际情况修改' }
      },
      { label: '事故时间', key: 'accidentTime', type: 'date', props: dateTimeProps },
      {
        label: '',
        key: 'accidentLocation',
        type: 'input',
        span: 24,
        labelWidth: 0
      },
      {
        label: '事故概述',
        key: 'accidentSummary',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      },
      { label: '责任及处理', key: 'processSection', type: 'divider', span: 24 },
      { label: '事故等级', key: 'damageLevel', type: 'input', props: { maxlength: 50 } },
      {
        label: '责任类型',
        key: 'responsibilityType',
        type: 'select',
        props: { options: getDictMap.value.vehicleAccidentResponsibility ?? [] }
      },
      {
        label: '责任比例',
        key: 'responsibilityPercent',
        type: 'number',
        props: { min: 0, max: 100, precision: 0, controlsPosition: 'right', class: '!w-full' }
      },
      { label: '经济损失', key: 'economicLoss', type: 'number', props: moneyProps },
      { label: '公司承担', key: 'companyBearAmount', type: 'number', props: moneyProps },
      {
        label: '是否报案',
        key: 'reported',
        type: 'radioGroup',
        props: { options: getBooleanDictOptions() }
      },
      {
        label: '是否报保险公司',
        key: 'insuranceReported',
        type: 'radioGroup',
        props: { options: getBooleanDictOptions() }
      },
      {
        label: '是否处理',
        key: 'processed',
        type: 'radioGroup',
        props: { options: getProcessedDictOptions() }
      },
      {
        label: '数据来源',
        key: 'dataSource',
        type: 'select',
        props: { options: getDictMap.value.vehicleAccidentDataSource ?? [] }
      },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]),
    rules: computed<FormRules<AccidentRecord>>(() => ({
      vehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      accidentTime: [{ required: true, message: '请选择事故时间', trigger: 'change' }],
      accidentSummary: [{ required: true, message: '请输入事故概述', trigger: 'blur' }],
      dataSource: [{ required: true, message: '请选择数据来源', trigger: 'change' }]
    }))
  })

  const attachment: UnwrapNestedRefs<AttachmentGroup> = reactive<AttachmentGroup>({
    data: createInitialAttachmentForm(),
    uploading: false,
    items: computed<FormItem[]>(() => [
      {
        label: '事故附件名称',
        key: 'name',
        type: 'input',
        props: { maxlength: 100 }
      },
      { label: '选择上传文件', key: 'file' }
    ]),
    rules: computed<FormRules<AttachmentFormData>>(() => ({
      name: [{ required: true, message: '请输入事故附件名称', trigger: 'blur' }],
      file: [{ required: true, message: '请选择上传文件', trigger: 'change' }]
    }))
  })

  const vehicleSelectValue = computed({
    get: () => form.data.vehicleId ?? undefined,
    set: (value?: string | number) => {
      form.data.vehicleId = value ? String(value) : null
    }
  })

  const vehicleColumns: DataSelectColumn[] = [
    { prop: 'companyName', label: '所属公司', minWidth: 180 },
    { prop: 'plateNo', label: '车牌号', width: 140 },
    {
      prop: 'primaryDriver',
      label: '主司机',
      minWidth: 180,
      formatter: (row) => {
        const vehicle = row as VehicleArchive
        const driverName = vehicle.primaryDriver?.driverName || vehicle.driverOneName
        const driverPhone = vehicle.primaryDriver?.phone || vehicle.driverOnePhone
        return [driverName, driverPhone].filter(Boolean).join(' / ') || '--'
      }
    },
    {
      prop: 'operationStatus',
      label: '营运状态',
      width: 120,
      dict: { code: 'vehicleOperationStatus', display: 'auto' }
    }
  ]

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 56 },
    { prop: 'name', label: '事故附件名称', formatter: renderAttachmentLink },
    {
      prop: 'fileType',
      label: '格式类型',
      width: 110,
      dict: { code: 'FILE_EXTENSION_LABEL_MAP', display: 'text' }
    },
    { prop: 'fileSize', label: '附件大小', width: 110 },
    {
      prop: 'operation',
      label: '操作',
      width: 96,
      formatter: (row) => (
        <div class="flex items-center">
          <ArtIconButton icon="ri:download-2-line" onClick={() => downloadAttachment(row)} />
          <ArtIconButton
            icon="ri:delete-bin-5-line"
            tone="danger"
            onClick={() => void removeAttachment(row)}
          />
        </div>
      )
    }
  ]

  const getBooleanDictOptions = () =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))

  const getProcessedDictOptions = () =>
    (getDictMap.value.vehicleRecordProcessed ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))

  const fetchVehicleSelectData = async (params: {
    page: number
    pageSize: number
    keyword?: string
  }) => {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchVehicleArchiveList({
      plateNo: params.keyword,
      auditStatus: 'approved',
      from,
      to
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  const handleVehicleChange = (_value: unknown, rows: DataSelectRecord[]): void => {
    const vehicle = rows[0] as VehicleArchive | undefined
    Object.assign(form.data, {
      vehicleId: vehicle?.id ?? null,
      plateNo: vehicle?.plateNo ?? '',
      companyName: vehicle?.companyName ?? '',
      driverName: vehicle?.primaryDriver?.driverName || vehicle?.driverOneName || '',
      driverPhone: vehicle?.primaryDriver?.phone || vehicle?.driverOnePhone || ''
    })
  }

  const handleLocationChange = (location: AddressLocationPayload): void => {
    if (location.coordinateStatus !== 'unconfirmed') return
    Object.assign(form.data, {
      accidentLongitude: null,
      accidentLatitude: null
    })
  }

  const replaceForm = (data: AccidentRecord): void => {
    Object.assign(form.data, createInitialForm(), cloneDeep(toRaw(data)))
    form.data.attachments ??= []
    form.vehicleSelection = form.data.vehicleId
      ? [
          {
            id: form.data.vehicleId,
            plateNo: form.data.plateNo,
            companyName: form.data.companyName
          } as VehicleArchive
        ]
      : []
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const resetAttachmentForm = async (): Promise<void> => {
    Object.assign(attachment.data, createInitialAttachmentForm())
    attachment.uploading = false
    await nextTick()
    attachmentFormRef.value?.clearValidate()
  }

  const openAttachmentDialog = async (): Promise<void> => {
    await resetAttachmentForm()
    await attachmentDialogRef.value?.handleOpen(undefined, {
      title: '上传事故附件',
      contentMaxHeight: '420px',
      onConfirm: handleAttachmentConfirm,
      onReset: () => void resetAttachmentForm()
    })
  }

  const handleAttachmentFileChange = async (file: File): Promise<void> => {
    attachment.uploading = true
    try {
      const [resource] = await uploadAttachment(file)
      if (!resource?.url) throw new Error('附件上传失败')
      attachment.data.file = resource.url
      attachment.data.fileName = resource.originName || file.name
      attachment.data.url = resource.url
      attachment.data.fileType = getFileExtension(file.name, resource.suffix)
      attachment.data.fileSize = resource.sizeInfo
      if (!attachment.data.name) {
        attachment.data.name = resource.originName || file.name
      }
      attachmentFormRef.value?.clearValidate()
      ElMessage.success('附件上传成功')
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '附件上传失败'))
    } finally {
      attachment.uploading = false
    }
  }

  const handleAttachmentConfirm = async (): Promise<boolean> => {
    try {
      await attachmentFormRef.value?.validate()
    } catch {
      return false
    }

    form.data.attachments = [
      ...(form.data.attachments ?? []),
      {
        name: attachment.data.name,
        url: attachment.data.url,
        fileType: attachment.data.fileType,
        fileSize: attachment.data.fileSize
      }
    ]
    return true
  }

  const normalizePayload = (): AccidentRecord => {
    const payload = { ...toRaw(form.data) }
    delete payload.tenantId
    delete payload.createBy
    delete payload.createTime
    delete payload.updateBy
    delete payload.updateTime
    const accidentLongitude = normalizeNullableNumber(payload.accidentLongitude)
    const accidentLatitude = normalizeNullableNumber(payload.accidentLatitude)
    const hasCoordinate = accidentLongitude !== null && accidentLatitude !== null
    return {
      ...payload,
      vehicleId: payload.vehicleId || null,
      driverName: payload.driverName?.trim() || '',
      driverPhone: payload.driverPhone?.trim() || '',
      accidentLocation: payload.accidentLocation?.trim() || '',
      accidentLongitude: hasCoordinate ? accidentLongitude : null,
      accidentLatitude: hasCoordinate ? accidentLatitude : null,
      attachments: payload.attachments ?? []
    }
  }

  const normalizeNullableNumber = (value: unknown): number | null => {
    if (value === null || value === undefined || value === '') return null
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : null
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
        await editVehicleAccident(payload)
      } else {
        await addVehicleAccident(payload)
      }
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: AccidentRecord): Promise<void> => {
    await resetForm()
    if (row?.id) replaceForm(row)

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑事故记录' : '新增事故记录',
      contentMaxHeight: '74vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  const removeAttachment = async (row: Attachment): Promise<void> => {
    try {
      await confirmAction(`确定删除附件“${row.name}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      form.data.attachments = (form.data.attachments ?? []).filter((item) => item.url !== row.url)
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>

<style scoped lang="scss">
  .accident-record-dialog {
    &__section {
      padding: 0 16px;
      margin-top: 8px;
    }

    &__section-header {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;
    }
  }

  .accident-attachment-dialog {
    padding: 8px 0 4px;

    &__upload {
      display: flex;
      flex-direction: column;
      gap: 14px;
      align-items: flex-start;
    }

    &__file {
      display: flex;
      gap: 8px;
      align-items: center;
      color: var(--el-text-color-secondary);

      :deep(.art-svg-icon) {
        color: var(--el-color-success);
      }
    }
  }
</style>
