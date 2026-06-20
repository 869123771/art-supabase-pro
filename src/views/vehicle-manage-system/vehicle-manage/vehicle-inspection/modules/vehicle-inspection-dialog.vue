<template>
  <ArtDialog ref="dialogRef" width="1040px" show-fullscreen-button>
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

      <section class="vehicle-inspection-dialog__section">
        <div class="vehicle-inspection-dialog__section-header">
          <ArtSectionTitle :show-line="false">年检附件</ArtSectionTitle>
          <ArtExcelImport
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
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    DataSelectColumn,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    addVehicleInspection,
    editVehicleInspection,
    fetchVehicleArchiveList
  } from '@/api/vehicle-manage-system'
  import { uploadAttachment } from '@/api/common'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { downloadAttachment, getFileExtension } from '@/utils/file'

  defineOptions({ name: 'VehicleInspectionDialog' })

  type VehicleInspection = Api.VehicleMgtSys.VehicleManage.VehicleInspection
  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

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
    attachments: []
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

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    vehicleSelection: [],
    attachmentUploading: false,
    items: computed<FormItem[]>(() => [
      { label: '年检信息', key: 'inspectionSection', type: 'divider', span: 24 },
      { label: '车牌号', key: 'vehicleId' },
      {
        label: '所属公司',
        key: 'companyName',
        type: 'input',
        props: { disabled: true, placeholder: '选择车辆后自动带出' }
      },
      { label: '年检日期', key: 'inspectionDate', type: 'date', props: dateProps },
      { label: '年检号', key: 'inspectionNo', type: 'input', props: { maxlength: 80 } },
      { label: '年检金额', key: 'inspectionAmount', type: 'number', props: moneyProps },
      { label: '车管所', key: 'vehicleOffice', type: 'input', props: { maxlength: 100 } },
      { label: '到期日期', key: 'expireDate', type: 'date', props: dateProps },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]),
    rules: computed<FormRules<VehicleInspection>>(() => ({
      vehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      inspectionDate: [{ required: true, message: '请选择年检日期', trigger: 'change' }],
      inspectionAmount: [{ required: true, message: '请输入年检金额', trigger: 'blur' }],
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

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 56 },
    { prop: 'name', label: '附件名称', minWidth: 180 },
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
          <ArtIconButton icon="ri:delete-bin-5-line" onClick={() => void removeAttachment(row)} />
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

  const normalizePayload = (): VehicleInspection => {
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
    await resetForm()
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
      ElMessage.error(error instanceof Error ? error.message : '附件上传失败')
    } finally {
      form.attachmentUploading = false
    }
  }

  const removeAttachment = async (row: Attachment): Promise<void> => {
    try {
      await ElMessageBox.confirm(`确定删除附件“${row.name}”吗？`, '删除确认', {
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
      margin-top: 8px;
      padding: 0 16px;
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
