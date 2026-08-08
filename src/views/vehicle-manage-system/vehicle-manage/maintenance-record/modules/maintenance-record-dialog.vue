<template>
  <ArtDialog ref="dialogRef" size="xl" show-fullscreen-button>
    <template #subtitle
      >记录维修保养项目、工期、费用、承修机构与附件，沉淀车辆完整维保履历。</template
    >

    <div class="maintenance-record-dialog">
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
      </ArtForm>

      <section class="maintenance-record-dialog__section">
        <div class="maintenance-record-dialog__section-header">
          <ArtSectionTitle :show-line="false">项目清单</ArtSectionTitle>
          <ElButton type="primary" plain @click="addItem">新增</ElButton>
        </div>
        <ArtTable
          :data="form.data.items"
          :columns="itemColumns"
          :pagination="undefined"
          :show-table-header="false"
          empty-height="160px"
        />
      </section>

      <section class="maintenance-record-dialog__section">
        <div class="maintenance-record-dialog__section-header">
          <ArtSectionTitle :show-line="false">维修保养附件</ArtSectionTitle>
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
    <div class="maintenance-attachment-dialog">
      <ArtForm
        ref="attachmentFormRef"
        v-model="attachment.data"
        :items="attachment.items"
        :rules="attachment.rules"
        :span="24"
        label-width="170px"
        :show-reset="false"
        :show-submit="false"
      >
        <template #file>
          <div class="maintenance-attachment-dialog__upload">
            <ArtExcelImport
              accept=""
              :parse-excel="false"
              :disabled="attachment.uploading"
              :button-props="{ loading: attachment.uploading }"
              @file-change="handleAttachmentFileChange"
            >
              选择上传文件
            </ArtExcelImport>
            <div v-if="attachment.data.fileName" class="maintenance-attachment-dialog__file">
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
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElButton, ElInput, ElInputNumber, ElMessage } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
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
  import {
    addVehicleMaintenance,
    editVehicleMaintenance,
    fetchVehicleArchiveList
  } from '@/api/vehicle-manage-system'
  import { uploadAttachment } from '@/api/common'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { downloadAttachment, getFileExtension } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'MaintenanceRecordDialog' })

  const { confirmAction } = useArtFeedback()

  type MaintenanceRecord = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceRecord
  type MaintenanceItem = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceItem
  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: MaintenanceRecord
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<MaintenanceRecord>>
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
  const dialogRef = ref<ArtDialogExpose<MaintenanceRecord | undefined>>()
  const attachmentDialogRef = ref<ArtDialogExpose<void>>()
  const formRef = ref<FormExpose>()
  const attachmentFormRef = ref<FormExpose>()

  const createInitialItem = (): MaintenanceItem => ({
    itemName: '',
    totalAmount: null,
    laborAmount: null,
    partName: '',
    partPrice: null,
    quantity: null
  })

  const createInitialForm = (): MaintenanceRecord => ({
    id: undefined,
    vehicleId: null,
    plateNo: '',
    companyName: '',
    maintenanceNo: '',
    maintenanceType: 'repair',
    initiator: '',
    startTime: '',
    endTime: '',
    costAmount: null,
    workshop: '',
    externalRepair: false,
    remark: '',
    items: [createInitialItem()],
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
      { label: '维修单号', key: 'maintenanceNo', type: 'input', props: { maxlength: 80 } },
      {
        label: '维修类型',
        key: 'maintenanceType',
        type: 'select',
        props: { options: getDictMap.value.vehicleMaintenanceType ?? [] }
      },
      { label: '发起人', key: 'initiator', type: 'input', props: { maxlength: 50 } },
      { label: '开始时间', key: 'startTime', type: 'date', props: dateTimeProps },
      { label: '结束时间', key: 'endTime', type: 'date', props: dateTimeProps },
      { label: '费用金额', key: 'costAmount', type: 'number', props: moneyProps },
      { label: '维修厂', key: 'workshop', type: 'input', props: { maxlength: 120 } },
      {
        label: '外部维修',
        key: 'externalRepair',
        type: 'radioGroup',
        props: { options: getBooleanDictOptions() }
      },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]),
    rules: computed<FormRules<MaintenanceRecord>>(() => ({
      vehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      maintenanceNo: [{ required: true, message: '请输入维修单号', trigger: 'blur' }],
      maintenanceType: [{ required: true, message: '请选择维修类型', trigger: 'change' }],
      startTime: [{ required: true, message: '请选择开始时间', trigger: 'change' }]
    }))
  })

  const attachment: UnwrapNestedRefs<AttachmentGroup> = reactive<AttachmentGroup>({
    data: createInitialAttachmentForm(),
    uploading: false,
    items: computed<FormItem[]>(() => [
      {
        label: '维修保养附件名称',
        key: 'name',
        type: 'input',
        props: { maxlength: 100 }
      },
      { label: '选择上传文件', key: 'file' }
    ]),
    rules: computed<FormRules<AttachmentFormData>>(() => ({
      name: [{ required: true, message: '请输入维修保养附件名称', trigger: 'blur' }],
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
      prop: 'operationStatus',
      label: '营运状态',
      width: 120,
      dict: { code: 'vehicleOperationStatus', display: 'auto' }
    }
  ]

  const itemColumns: ColumnOption<MaintenanceItem>[] = [
    { type: 'globalIndex', label: '序号', width: 56 },
    {
      prop: 'itemName',
      label: '项目名称',
      minWidth: 130,
      formatter: (row) => <ElInput v-model={row.itemName} placeholder="项目名称" />
    },
    {
      prop: 'partName',
      label: '配件名称',
      minWidth: 120,
      formatter: (row) => <ElInput v-model={row.partName} placeholder="配件名称" />
    },
    {
      prop: 'quantity',
      label: '数量',
      width: 96,
      formatter: (row) => (
        <ElInputNumber
          v-model={row.quantity}
          min={0}
          precision={2}
          controls={false}
          class="w-full!"
        />
      )
    },
    {
      prop: 'partPrice',
      label: '配件金额',
      width: 112,
      formatter: (row) => (
        <ElInputNumber
          v-model={row.partPrice}
          min={0}
          precision={2}
          controls={false}
          class="w-full!"
        />
      )
    },
    {
      prop: 'laborAmount',
      label: '工时费',
      width: 112,
      formatter: (row) => (
        <ElInputNumber
          v-model={row.laborAmount}
          min={0}
          precision={2}
          controls={false}
          class="w-full!"
        />
      )
    },
    {
      prop: 'totalAmount',
      label: '合计',
      width: 112,
      formatter: (row) => (
        <ElInputNumber
          v-model={row.totalAmount}
          min={0}
          precision={2}
          controls={false}
          class="w-full!"
        />
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 64,
      formatter: (row) => (
        <ArtIconButton icon="ri:delete-bin-5-line" tone="danger" onClick={() => removeItem(row)} />
      )
    }
  ]

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 56 },
    { prop: 'name', label: '附件名称', minWidth: 180, formatter: renderAttachmentLink },
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
    form.data.vehicleId = vehicle?.id ?? null
    form.data.plateNo = vehicle?.plateNo ?? ''
    form.data.companyName = vehicle?.companyName ?? ''
  }

  const replaceForm = (data: MaintenanceRecord): void => {
    Object.assign(form.data, createInitialForm(), cloneDeep(toRaw(data)))
    form.data.items = form.data.items?.length ? form.data.items : [createInitialItem()]
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

  const addItem = (): void => {
    form.data.items = [...(form.data.items ?? []), createInitialItem()]
  }

  const removeItem = (row: MaintenanceItem): void => {
    form.data.items = (form.data.items ?? []).filter((item) => item !== row)
  }

  const openAttachmentDialog = async (): Promise<void> => {
    await resetAttachmentForm()
    await attachmentDialogRef.value?.handleOpen(undefined, {
      title: '上传维修保养附件',
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
      ElMessage.error(error instanceof Error ? error.message : '附件上传失败')
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

  const normalizePayload = (): MaintenanceRecord => {
    const payload = { ...toRaw(form.data) }
    delete payload.tenantId
    delete payload.createBy
    delete payload.createTime
    delete payload.updateBy
    delete payload.updateTime
    return {
      ...payload,
      vehicleId: payload.vehicleId || null,
      endTime: payload.endTime || null,
      items: (payload.items ?? []).filter((item) => item.itemName || item.partName),
      attachments: payload.attachments ?? []
    }
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
        await editVehicleMaintenance(payload)
      } else {
        await addVehicleMaintenance(payload)
      }
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: MaintenanceRecord): Promise<void> => {
    await resetForm()
    if (row?.id) replaceForm(row)

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑维修保养记录' : '新增维修保养记录',
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
  .maintenance-record-dialog {
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

  .maintenance-attachment-dialog {
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
