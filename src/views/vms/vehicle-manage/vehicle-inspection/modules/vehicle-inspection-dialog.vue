<template>
  <ArtDialog ref="dialogRef" size="xl" show-fullscreen-button>
    <template #subtitle>登记车辆年检编号、检测日期、到期日期、机构费用与证明附件。</template>

    <div class="vehicle-inspection-dialog">
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

      <section v-if="canViewDocuments" class="vehicle-inspection-dialog__section">
        <div class="vehicle-inspection-dialog__section-header">
          <ArtSectionTitle :show-line="false">年检附件</ArtSectionTitle>
          <ArtExcelImport
            v-if="canEditDocuments"
            accept=""
            :parse-excel="false"
            :disabled="form.attachmentUploading"
            :button-props="{ type: 'primary', plain: true, loading: form.attachmentUploading }"
            @file-change="handleAttachmentUpload"
          >
            上传附件
          </ArtExcelImport>
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
</template>

<script setup lang="tsx">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElMessage } from 'element-plus'
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
  import { addVehicleInspection, editVehicleInspection, fetchVehicleArchiveList } from '@/api/vms'
  import { uploadAttachment } from '@/api/common'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { downloadAttachment, getFileExtension } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import { canEditField, canViewField } from '@/utils/field-permission'
  import {
    EDITABLE_VEHICLE_INSPECTION_ACCESS,
    sanitizeVehicleInspectionPayload
  } from './vehicle-inspection-model'

  defineOptions({ name: 'VehicleInspectionDialog' })

  const { confirmAction } = useArtFeedback()

  type VehicleInspection = Api.Vms.VehicleManage.VehicleInspection
  type VehicleArchive = Api.Vms.ArchiveManage.VehicleArchive
  type Attachment = Api.Vms.VehicleManage.VehicleAttachment

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: VehicleInspection
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<VehicleInspection>>
    vehicleSelection: VehicleArchive[]
    attachmentUploading: boolean
  }

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<VehicleInspection | undefined>>()
  const formRef = ref<FormExpose>()
  const inspectionNumber = useDocumentNumberRule('vehicle.inspection')

  const createInitialForm = (): VehicleInspection => ({
    id: undefined,
    vehicleId: null,
    plateNo: '',
    companyName: '',
    inspectionNo: '',
    inspectionDate: '',
    inspectionAmount: null,
    vehicleOffice: '',
    expireDate: '',
    remark: '',
    attachments: [],
    fieldAccess: { ...EDITABLE_VEHICLE_INSPECTION_ACCESS },
    isRecordOwner: true
  })

  const dateProps = {
    type: 'date',
    valueFormat: 'YYYY-MM-DD',
    class: '!w-full'
  }

  const moneyProps = {
    min: 0,
    precision: 2,
    controlsPosition: 'right',
    class: '!w-full'
  }

  const canViewIdentifiers = computed(() =>
    canViewField(form.data.fieldAccess, 'inspectionIdentifiers')
  )
  const canEditIdentifiers = computed(() =>
    canEditField(form.data.fieldAccess, 'inspectionIdentifiers')
  )
  const canViewAmounts = computed(() => canViewField(form.data.fieldAccess, 'monetaryAmounts'))
  const canEditAmounts = computed(() => canEditField(form.data.fieldAccess, 'monetaryAmounts'))
  const canViewDocuments = computed(() => canViewField(form.data.fieldAccess, 'documents'))
  const canEditDocuments = computed(() => canEditField(form.data.fieldAccess, 'documents'))

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    vehicleSelection: [],
    attachmentUploading: false,
    items: computed<FormItem[]>(() => {
      const items: FormItem[] = [
        { label: '年检信息', key: 'inspectionSection', type: 'divider', span: 24 },
        { label: '车牌号', key: 'vehicleId' },
        {
          label: '所属公司',
          key: 'companyName',
          type: 'input',
          props: { disabled: true, placeholder: '选择车辆后自动带出' }
        },
        { label: '年检日期', key: 'inspectionDate', type: 'date', props: dateProps }
      ]
      if (canViewIdentifiers.value) {
        items.push({
          label: '年检号',
          key: 'inspectionNo',
          type: 'input',
          props: {
            maxlength: 80,
            ...inspectionNumber.inputProps(Boolean(form.data.id), '请输入年检号', true),
            disabled: !canEditIdentifiers.value
          },
          description: inspectionNumber.description.value
        })
      }
      if (canViewAmounts.value) {
        items.push({
          label: '年检金额',
          key: 'inspectionAmount',
          type: 'number',
          props: { ...moneyProps, disabled: !canEditAmounts.value }
        })
      }
      items.push(
        { label: '车管所', key: 'vehicleOffice', type: 'input', props: { maxlength: 100 } },
        { label: '到期日期', key: 'expireDate', type: 'date', props: dateProps },
        {
          label: '备注',
          key: 'remark',
          type: 'input',
          span: 24,
          props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
        }
      )
      return items
    }),
    rules: computed<FormRules<VehicleInspection>>(() => ({
      inspectionNo:
        canEditIdentifiers.value && inspectionNumber.manualRequired(Boolean(form.data.id))
          ? [{ required: true, message: '请输入年检号', trigger: 'blur' }]
          : [],
      vehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      inspectionDate: [{ required: true, message: '请选择年检日期', trigger: 'change' }],
      inspectionAmount: canEditAmounts.value
        ? [{ required: true, message: '请输入年检金额', trigger: 'blur' }]
        : [],
      expireDate: [{ required: true, message: '请选择年检到期日期', trigger: 'change' }]
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

  const attachmentColumns = computed<ColumnOption<Attachment>[]>(() => [
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
      width: canEditDocuments.value ? 96 : 64,
      formatter: (row) => (
        <div class="flex items-center">
          <ArtIconButton icon="ri:download-2-line" onClick={() => downloadAttachment(row)} />
          {canEditDocuments.value ? (
            <ArtIconButton
              icon="ri:delete-bin-5-line"
              tone="danger"
              onClick={() => void removeAttachment(row)}
            />
          ) : null}
        </div>
      )
    }
  ])

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

  const replaceForm = (data: VehicleInspection): void => {
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

  const normalizePayload = (): VehicleInspection =>
    sanitizeVehicleInspectionPayload({
      ...toRaw(form.data),
      vehicleId: form.data.vehicleId || null,
      attachments: form.data.attachments ?? []
    })

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = normalizePayload()
      if (form.data.id) {
        await editVehicleInspection(payload)
      } else {
        await addVehicleInspection(payload)
      }
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: VehicleInspection): Promise<void> => {
    await Promise.all([resetForm(), inspectionNumber.loadRule()])
    if (row?.id) replaceForm(row)

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑车辆年检' : '新增车辆年检',
      contentMaxHeight: '72vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  const handleAttachmentUpload = async (file: File): Promise<void> => {
    form.attachmentUploading = true
    try {
      const [resource] = await uploadAttachment(file)
      if (!resource?.url) throw new Error('附件上传失败')
      form.data.attachments = [
        ...(form.data.attachments ?? []),
        {
          name: resource.originName || file.name,
          url: resource.url,
          fileType: getFileExtension(file.name, resource.suffix),
          fileSize: resource.sizeInfo
        }
      ]
      ElMessage.success('附件上传成功')
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '附件上传失败'))
    } finally {
      form.attachmentUploading = false
    }
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
  .vehicle-inspection-dialog {
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
</style>
