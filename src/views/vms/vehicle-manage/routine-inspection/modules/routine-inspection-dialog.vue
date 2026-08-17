<template>
  <ArtDialog ref="dialogRef" size="xl" show-fullscreen-button>
    <template #subtitle
      >记录检查类型、人员、检查结果和处置方式，形成可复核的车辆安全检查记录。</template
    >

    <div class="routine-inspection-dialog">
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

      <section class="routine-inspection-dialog__section">
        <div class="routine-inspection-dialog__section-header">
          <ArtSectionTitle :show-line="false">例检附件</ArtSectionTitle>
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
    <div class="routine-attachment-dialog">
      <ArtForm
        ref="attachmentFormRef"
        v-model="attachment.data"
        :items="attachment.items"
        :rules="attachment.rules"
        :span="24"
        label-width="140px"
        :show-reset="false"
        :show-submit="false"
      >
        <template #file>
          <div class="routine-attachment-dialog__upload">
            <ArtExcelImport
              accept=""
              :parse-excel="false"
              :disabled="attachment.uploading"
              :button-props="{ loading: attachment.uploading }"
              @file-change="handleAttachmentFileChange"
            >
              选择上传文件
            </ArtExcelImport>
            <div v-if="attachment.data.fileName" class="routine-attachment-dialog__file">
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
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    DataSelectColumn,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    addVehicleRoutineInspection,
    editVehicleRoutineInspection,
    fetchVehicleArchiveList
  } from '@/api/vms'
  import { uploadAttachment } from '@/api/common'
  import { useUserStore } from '@/store/modules/user'
  import { downloadAttachment, getFileExtension } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import { pageInfoHandler } from '@/utils/table/tableUtils'

  defineOptions({ name: 'RoutineInspectionDialog' })

  const { confirmAction } = useArtFeedback()

  type RoutineInspection = Api.Vms.VehicleManage.VehicleRoutineInspectionRecord
  type VehicleArchive = Api.Vms.ArchiveManage.VehicleArchive
  type Attachment = Api.Vms.VehicleManage.VehicleAttachment

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: RoutineInspection
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<RoutineInspection>>
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
  const dialogRef = ref<ArtDialogExpose<RoutineInspection | undefined>>()
  const attachmentDialogRef = ref<ArtDialogExpose<void>>()
  const formRef = ref<FormExpose>()
  const routineNumber = useDocumentNumberRule('vehicle.routine_inspection')
  const attachmentFormRef = ref<FormExpose>()

  const createInitialForm = (): RoutineInspection => ({
    id: undefined,
    vehicleId: null,
    plateNo: '',
    companyName: '',
    routineInspectionNo: '',
    inspectionType: 'daily',
    inspectionTime: '',
    inspector: '',
    driverName: '',
    checkCondition: '',
    checkResult: 'qualified',
    handlingMethod: '',
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

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    vehicleSelection: [],
    items: computed<FormItem[]>(() => [
      { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
      { label: '车牌号', key: 'vehicleId', span: 12 },
      { label: '所属公司', key: 'companyName', type: 'input', props: { disabled: true } },
      {
        label: '例检编号',
        key: 'routineInspectionNo',
        type: 'input',
        props: {
          maxlength: 80,
          ...routineNumber.inputProps(Boolean(form.data.id), '请输入例检编号', true)
        },
        description: routineNumber.description.value
      },
      {
        label: '例检类型',
        key: 'inspectionType',
        type: 'select',
        props: { options: getDictMap.value.vehicleRoutineInspectionType ?? [] }
      },
      { label: '例检时间', key: 'inspectionTime', type: 'date', props: dateTimeProps },
      { label: '检查人', key: 'inspector', type: 'input', props: { maxlength: 50 } },
      { label: '驾驶员', key: 'driverName', type: 'input', props: { maxlength: 50 } },
      {
        label: '检查结果',
        key: 'checkResult',
        type: 'select',
        props: { options: getDictMap.value.vehicleRoutineInspectionResult ?? [] }
      },
      {
        label: '检查情况',
        key: 'checkCondition',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      },
      {
        label: '处理方式',
        key: 'handlingMethod',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]),
    rules: computed<FormRules<RoutineInspection>>(() => ({
      vehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      routineInspectionNo: routineNumber.manualRequired(Boolean(form.data.id))
        ? [{ required: true, message: '请输入例检编号', trigger: 'blur' }]
        : [],
      inspectionType: [{ required: true, message: '请选择例检类型', trigger: 'change' }],
      inspectionTime: [{ required: true, message: '请选择例检时间', trigger: 'change' }],
      inspector: [{ required: true, message: '请输入检查人', trigger: 'blur' }],
      checkResult: [{ required: true, message: '请选择检查结果', trigger: 'change' }]
    }))
  })

  const attachment: UnwrapNestedRefs<AttachmentGroup> = reactive<AttachmentGroup>({
    data: createInitialAttachmentForm(),
    uploading: false,
    items: computed<FormItem[]>(() => [
      { label: '附件名称', key: 'name', type: 'input', props: { maxlength: 100 } },
      { label: '上传文件', key: 'file' }
    ]),
    rules: computed<FormRules<AttachmentFormData>>(() => ({
      name: [{ required: true, message: '请输入附件名称', trigger: 'blur' }],
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
      label: '运营状态',
      width: 120,
      dict: { code: 'vehicleOperationStatus', display: 'auto' }
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

  const replaceForm = (data: RoutineInspection): void => {
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
      title: '上传例检附件',
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
      if (!attachment.data.name) attachment.data.name = resource.originName || file.name
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

  const normalizePayload = (): RoutineInspection => {
    const payload = { ...toRaw(form.data) }
    delete payload.tenantId
    delete payload.createBy
    delete payload.createTime
    delete payload.updateBy
    delete payload.updateTime
    return {
      ...payload,
      vehicleId: payload.vehicleId || null,
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
        await editVehicleRoutineInspection(payload)
      } else {
        await addVehicleRoutineInspection(payload)
      }
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: RoutineInspection): Promise<void> => {
    await Promise.all([resetForm(), routineNumber.loadRule()])
    if (row?.id) replaceForm(row)

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑例检记录' : '新增例检记录',
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
  .routine-inspection-dialog {
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

  .routine-attachment-dialog {
    &__upload {
      display: flex;
      gap: 12px;
      align-items: center;
      min-width: 0;
    }

    &__file {
      display: inline-flex;
      gap: 6px;
      align-items: center;
      min-width: 0;
      color: var(--el-text-color-regular);

      span {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }
  }
</style>
