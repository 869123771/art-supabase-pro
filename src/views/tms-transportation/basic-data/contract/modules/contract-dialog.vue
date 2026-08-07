<template>
  <ArtDialog ref="dialogRef" size="xl">
    <div class="contract-dialog">
      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="8"
        :gutter="20"
        label-width="116px"
        :show-reset="false"
        :show-submit="false"
      />

      <section class="contract-dialog__section">
        <div class="contract-dialog__section-header">
          <ArtSectionTitle :show-line="false">合同附件</ArtSectionTitle>
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

    <template #footer="{ loading, api }">
      <div class="contract-dialog__footer">
        <ElButton :disabled="loading" @click="api.handleClose()">取消</ElButton>
        <ElButton
          :loading="loading && submitMode === 'save'"
          @click="handleFooterConfirm(api, 'save')"
        >
          保存
        </ElButton>
        <ElButton
          type="primary"
          :loading="loading && submitMode === 'submit'"
          @click="handleFooterConfirm(api, 'submit')"
        >
          提交审核
        </ElButton>
      </div>
    </template>
  </ArtDialog>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep, omit } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElButton, ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import type { ColumnOption } from '@/types'
  import {
    addContract,
    editContract,
    fetchCarrierOptions,
    submitContractForApproval
  } from '@/api/tms'
  import { uploadAttachment } from '@/api/common'
  import { useUserStore } from '@/store/modules/user'
  import { downloadAttachment, getFileExtension } from '@/utils/file'

  defineOptions({ name: 'TmsContractDialog' })

  const { confirmAction } = useArtFeedback()

  type Contract = Api.Tms.BasicData.Contract
  type ContractAttachment = Api.Tms.BasicData.ContractAttachment
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type SubmitMode = 'save' | 'submit'
  type FooterApi = Pick<ArtDialogExpose<Contract | undefined>, 'handleConfirm'>

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface FormGroup {
    data: Contract
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<Contract>>
    carrierOptions: CarrierOption[]
    attachmentUploading: boolean
  }

  interface Emits {
    (event: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Contract | undefined>>()
  const formRef = ref<FormExpose>()
  const submitMode = ref<SubmitMode>('save')

  const billingMethodOptions = computed(() => getDictMap.value.tmsContractBillingMethod ?? [])

  const createInitialForm = (): Contract => ({
    id: undefined,
    contractNo: '',
    contractName: '',
    contractStatus: 'draft',
    carrierId: '',
    contactName: '',
    waybillNo: '',
    billingMethod: '',
    contractAmount: null,
    signTime: '',
    handler: '',
    contractDescription: '',
    attachments: []
  })

  const datetimeProps = {
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
    carrierOptions: [],
    attachmentUploading: false,
    items: computed<FormItem[]>(() => [
      { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
      {
        label: '合同编号',
        key: 'contractNo',
        type: 'input',
        props: {
          maxlength: 40,
          disabled: Boolean(form.data.id),
          placeholder: '不填则系统自动生成'
        }
      },
      {
        label: '合同名称',
        key: 'contractName',
        type: 'input',
        span: 16,
        props: { maxlength: 120, placeholder: '请输入合同名称' }
      },
      {
        label: '承运商名称',
        key: 'carrierId',
        type: 'select',
        api: fetchCarrierOptions,
        immediate: false,
        resultField: 'data',
        labelField: 'companyName',
        valueField: 'id',
        labelFn: formatCarrierOption,
        afterFetch: syncCarrierOptions,
        props: {
          clearable: true,
          filterable: true,
          placeholder: '请选择承运商',
          onChange: handleCarrierChange
        }
      },
      {
        label: '联系人姓名',
        key: 'contactName',
        type: 'select',
        props: {
          options: contactNameOptions.value,
          clearable: true,
          filterable: true,
          allowCreate: true,
          defaultFirstOption: true,
          placeholder: '请选择或输入联系人'
        }
      },
      {
        label: '运单号',
        key: 'waybillNo',
        type: 'input',
        props: { maxlength: 60, placeholder: '请输入运单号' }
      },
      {
        label: '计费方式',
        key: 'billingMethod',
        type: 'select',
        props: {
          options: billingMethodOptions.value,
          clearable: true,
          placeholder: '请选择计费方式'
        }
      },
      {
        label: '合同金额',
        key: 'contractAmount',
        type: 'number',
        props: moneyProps
      },
      {
        label: '签订时间',
        key: 'signTime',
        type: 'date',
        props: datetimeProps
      },
      {
        label: '经办人',
        key: 'handler',
        type: 'input',
        props: { maxlength: 40, placeholder: '请输入经办人' }
      },
      {
        label: '合同说明',
        key: 'contractDescription',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 4,
          maxlength: 1000,
          showWordLimit: true,
          placeholder: '请输入合同说明'
        }
      }
    ]),
    rules: computed<FormRules<Contract>>(() => ({
      contractName: [
        { required: true, message: '请输入合同名称', trigger: 'blur' },
        { min: 2, max: 120, message: '长度应为 2 到 120 个字符', trigger: 'blur' }
      ],
      carrierId: [{ required: true, message: '请选择承运商', trigger: 'change' }],
      billingMethod: [{ required: true, message: '请选择计费方式', trigger: 'change' }],
      signTime: [{ required: true, message: '请选择签订时间', trigger: 'change' }],
      handler: [{ required: true, message: '请输入经办人', trigger: 'blur' }],
      contractDescription: [{ max: 1000, message: '合同说明不能超过 1000 个字符', trigger: 'blur' }]
    }))
  })

  const contactNameOptions = computed(() => {
    const options = new Map<string, { label: string; value: string }>()
    const carrier = form.carrierOptions.find((item) => item.id === form.data.carrierId)
    if (carrier?.contactName) {
      options.set(carrier.contactName, { label: carrier.contactName, value: carrier.contactName })
    }
    if (form.data.contactName) {
      options.set(form.data.contactName, {
        label: form.data.contactName,
        value: form.data.contactName
      })
    }
    return Array.from(options.values())
  })

  const attachmentColumns: ColumnOption<ContractAttachment>[] = [
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'name',
      label: '附件名称',
      minWidth: 220,
      showOverflowTooltip: true,
      formatter: renderAttachmentLink
    },
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

  const getResponseData = <TRecord,>(result: unknown): TRecord[] => {
    if (!result || typeof result !== 'object') return []
    const data = (result as { data?: TRecord[] }).data
    return Array.isArray(data) ? data : []
  }

  const syncCarrierOptions = (result: unknown): unknown => {
    form.carrierOptions = getResponseData<CarrierOption>(result)
    return result
  }

  const formatCarrierOption = (option: Record<string, unknown>): string => {
    const carrier = option as unknown as CarrierOption
    return carrier.carrierCode
      ? `${carrier.companyName}（${carrier.carrierCode}）`
      : carrier.companyName
  }

  const handleCarrierChange = (carrierId?: string): void => {
    const carrier = form.carrierOptions.find((item) => item.id === carrierId)
    form.data.contactName = carrier?.contactName || ''
  }

  const replaceForm = (data: Contract): void => {
    Object.assign(form.data, createInitialForm(), cloneDeep(toRaw(data)))
    form.data.contractStatus ??= 'draft'
    form.data.attachments ??= []
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    submitMode.value = 'save'
    await nextTick()
    formRef.value?.clearValidate()
  }

  const normalizeNumber = (value?: number | string | null): number | null => {
    if (value === null || value === undefined || value === '') return null
    const numberValue = Number(value)
    return Number.isNaN(numberValue) ? null : numberValue
  }

  const normalizeText = (value?: string | null): string | null => {
    const text = String(value ?? '').trim()
    return text || null
  }

  const normalizePayload = (): Contract => {
    const payload = omit(cloneDeep(toRaw(form.data)), [
      'tenantId',
      'carrier',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as Contract

    if (!payload.contractNo) delete payload.contractNo
    return {
      ...payload,
      contractStatus: payload.contractStatus || 'draft',
      contactName: normalizeText(payload.contactName),
      waybillNo: normalizeText(payload.waybillNo),
      contractAmount: normalizeNumber(payload.contractAmount),
      contractDescription: normalizeText(payload.contractDescription),
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
      const type = form.data.id ? 'edit' : 'add'
      if (type === 'edit') {
        await editContract(payload)
      } else {
        const response = await addContract(payload)
        payload.id = response.data?.id
      }
      if (submitMode.value === 'submit') await submitContractForApproval(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleFooterConfirm = async (api: FooterApi, mode: SubmitMode): Promise<void> => {
    submitMode.value = mode
    await api.handleConfirm()
  }

  const handleOpen = async (row?: Contract): Promise<void> => {
    await resetForm()
    if (row?.id) replaceForm(row)

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑合同' : '新增合同',
      subtitle: '维护合同基础信息、计费方式、金额和附件',
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

  const removeAttachment = async (row: ContractAttachment): Promise<void> => {
    try {
      await confirmAction(`确定删除附件“${row.name}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      form.data.attachments = (form.data.attachments ?? []).filter(
        (item) => item.url !== row.url || item.name !== row.name
      )
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
  .contract-dialog {
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

    &__footer {
      display: flex;
      justify-content: flex-end;
      width: 100%;
    }
  }
</style>
