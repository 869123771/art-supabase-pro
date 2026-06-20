<template>
  <ArtDialog ref="dialogRef" width="1040px" show-fullscreen-button>
    <div class="vehicle-insurance-dialog">
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
      />

      <section class="vehicle-insurance-dialog__section">
        <div class="vehicle-insurance-dialog__section-header">
          <ArtSectionTitle :show-line="false">保险附件</ArtSectionTitle>
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
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    addVehicleInsurance,
    editVehicleInsurance,
    fetchInsuranceCompanyOptions,
    fetchVehicleArchiveOptions
  } from '@/api/vehicle-manage-system'
  import { uploadAttachment } from '@/api/common'
  import { downloadAttachment, getFileExtension, viewAttachment } from '@/utils/file'

  defineOptions({ name: 'VehicleInsuranceDialog' })

  type VehicleInsurance = Api.VehicleMgtSys.VehicleManage.VehicleInsurance
  type VehicleOption = Api.VehicleMgtSys.VehicleManage.VehicleOption
  type InsuranceCompanyOption = Api.VehicleMgtSys.VehicleManage.InsuranceCompanyOption
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface FormGroup {
    data: VehicleInsurance
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<VehicleInsurance>>
    vehicleOptions: VehicleOption[]
    companyOptions: InsuranceCompanyOption[]
    attachmentUploading: boolean
  }

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<VehicleInsurance | undefined>>()
  const formRef = ref<FormExpose>()

  const createInitialForm = (): VehicleInsurance => ({
    id: undefined,
    vehicleId: null,
    plateNo: '',
    companyName: '',
    commercialPolicyNo: '',
    commercialCompanyId: null,
    commercialCompanyName: '',
    commercialInsureDate: '',
    commercialPremium: null,
    commercialExpireDate: '',
    compulsoryPolicyNo: '',
    compulsoryCompanyId: null,
    compulsoryCompanyName: '',
    compulsoryInsureDate: '',
    compulsoryPremium: null,
    compulsoryExpireDate: '',
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
    vehicleOptions: [],
    companyOptions: [],
    attachmentUploading: false,
    items: computed<FormItem[]>(() => [
      { label: '车辆信息', key: 'vehicleSection', type: 'divider', span: 24 },
      {
        label: '车牌号',
        key: 'vehicleId',
        type: 'select',
        api: fetchVehicleArchiveOptions,
        immediate: false,
        resultField: 'data',
        labelField: 'plateNo',
        valueField: 'id',
        afterFetch: syncVehicleOptions,
        props: {
          onChange: handleVehicleChange
        }
      },
      {
        label: '所属公司',
        key: 'companyName',
        type: 'input',
        props: {
          disabled: true,
          placeholder: '选择车辆后自动带出'
        }
      },
      { label: '商业险', key: 'commercialSection', type: 'divider', span: 24 },
      {
        label: '商业险保单号',
        key: 'commercialPolicyNo',
        type: 'input',
        props: { maxlength: 80 }
      },
      {
        label: '保险公司',
        key: 'commercialCompanyId',
        type: 'select',
        api: fetchInsuranceCompanyOptions,
        immediate: false,
        resultField: 'data',
        labelField: 'companyName',
        valueField: 'id',
        afterFetch: syncCompanyOptions,
        props: {
          onChange: (value?: string) => handleInsuranceCompanyChange(value, 'commercial')
        }
      },
      { label: '投保日期', key: 'commercialInsureDate', type: 'date', props: dateProps },
      { label: '投保金额', key: 'commercialPremium', type: 'number', props: moneyProps },
      { label: '到期日期', key: 'commercialExpireDate', type: 'date', props: dateProps },
      { label: '交强险', key: 'compulsorySection', type: 'divider', span: 24 },
      {
        label: '交强险保单号',
        key: 'compulsoryPolicyNo',
        type: 'input',
        props: { maxlength: 80 }
      },
      {
        label: '保险公司',
        key: 'compulsoryCompanyId',
        type: 'select',
        api: fetchInsuranceCompanyOptions,
        immediate: false,
        resultField: 'data',
        labelField: 'companyName',
        valueField: 'id',
        afterFetch: syncCompanyOptions,
        props: {
          onChange: (value?: string) => handleInsuranceCompanyChange(value, 'compulsory')
        }
      },
      { label: '投保日期', key: 'compulsoryInsureDate', type: 'date', props: dateProps },
      { label: '投保金额', key: 'compulsoryPremium', type: 'number', props: moneyProps },
      { label: '到期日期', key: 'compulsoryExpireDate', type: 'date', props: dateProps },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]),
    rules: computed<FormRules<VehicleInsurance>>(() => ({
      vehicleId: [{ required: true, message: '请选择车辆', trigger: 'change' }],
      commercialPolicyNo: [{ required: true, message: '请输入商业险保单号', trigger: 'blur' }],
      commercialCompanyId: [{ required: true, message: '请选择商业险保险公司', trigger: 'change' }],
      commercialInsureDate: [
        { required: true, message: '请选择商业险投保日期', trigger: 'change' }
      ],
      commercialPremium: [{ required: true, message: '请输入商业险投保金额', trigger: 'blur' }],
      commercialExpireDate: [
        { required: true, message: '请选择商业险到期日期', trigger: 'change' }
      ],
      compulsoryPolicyNo: [{ required: true, message: '请输入交强险保单号', trigger: 'blur' }],
      compulsoryCompanyId: [{ required: true, message: '请选择交强险保险公司', trigger: 'change' }],
      compulsoryInsureDate: [
        { required: true, message: '请选择交强险投保日期', trigger: 'change' }
      ],
      compulsoryPremium: [{ required: true, message: '请输入交强险投保金额', trigger: 'blur' }],
      compulsoryExpireDate: [{ required: true, message: '请选择交强险到期日期', trigger: 'change' }]
    }))
  })

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'name', label: '附件名称', minWidth: 220 },
    {
      prop: 'fileType',
      label: '格式类型',
      width: 120,
      dict: { code: 'FILE_EXTENSION_LABEL_MAP', display: 'text' }
    },
    { prop: 'fileSize', label: '附件大小', width: 120 },
    {
      prop: 'operation',
      label: '操作',
      width: 150,
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable type="view" onClick={() => viewAttachment(row)} />
          <ArtButtonMore
            list={getAttachmentMoreActions()}
            onClick={(item: ButtonMoreItem) => handleAttachmentMoreAction(item, row)}
          />
        </div>
      )
    }
  ]

  const getResponseData = <TRecord,>(result: unknown): TRecord[] => {
    if (!result || typeof result !== 'object') return []
    const data = (result as { data?: TRecord[] }).data
    return Array.isArray(data) ? data : []
  }

  const syncVehicleOptions = (result: unknown): unknown => {
    form.vehicleOptions = getResponseData<VehicleOption>(result)
    return result
  }

  const syncCompanyOptions = (result: unknown): unknown => {
    form.companyOptions = getResponseData<InsuranceCompanyOption>(result)
    return result
  }

  const handleVehicleChange = (vehicleId?: string): void => {
    const vehicle = form.vehicleOptions.find((item) => item.id === vehicleId)
    form.data.vehicleId = vehicle?.id ?? null
    form.data.plateNo = vehicle?.plateNo ?? ''
    form.data.companyName = vehicle?.companyName ?? ''
  }

  const handleInsuranceCompanyChange = (
    companyId: string | undefined,
    type: 'commercial' | 'compulsory'
  ): void => {
    const company = form.companyOptions.find((item) => item.id === companyId)
    if (type === 'commercial') {
      form.data.commercialCompanyName = company?.companyName ?? ''
      return
    }
    form.data.compulsoryCompanyName = company?.companyName ?? ''
  }

  const replaceForm = (data: VehicleInsurance): void => {
    Object.assign(form.data, createInitialForm(), cloneDeep(toRaw(data)))
    form.data.attachments ??= []
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const normalizePayload = (): VehicleInsurance => {
    const payload = { ...toRaw(form.data) }
    delete payload.tenantId
    delete payload.createBy
    delete payload.createTime
    delete payload.updateBy
    delete payload.updateTime
    return {
      ...payload,
      vehicleId: payload.vehicleId || null,
      commercialCompanyId: payload.commercialCompanyId || null,
      compulsoryCompanyId: payload.compulsoryCompanyId || null,
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
        await editVehicleInsurance(payload)
      } else {
        await addVehicleInsurance(payload)
      }
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: VehicleInsurance): Promise<void> => {
    await resetForm()
    if (row?.id) {
      replaceForm(row)
    }

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑车辆保险' : '新增车辆保险',
      contentMaxHeight: '72vh',
      loading: true,
      onOpen: async (_data, api) => {
        try {
          await formRef.value?.reloadOptions()
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  const getAttachmentMoreActions = (): ButtonMoreItem[] => [
    { key: 'download', label: '下载', icon: 'ri:download-2-line' },
    { key: 'delete', label: '删除', icon: 'ri:delete-bin-5-line', color: '#f56c6c' }
  ]

  const handleAttachmentMoreAction = (item: ButtonMoreItem, row: Attachment): void => {
    if (item.key === 'download') {
      downloadAttachment(row)
      return
    }
    if (item.key === 'delete') {
      void removeAttachment(row)
    }
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
  .vehicle-insurance-dialog {
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
