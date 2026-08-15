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
        label-width="124px"
        :validate-on-rule-change="false"
        scroll-to-error
        :show-reset="false"
        :show-submit="false"
      />

      <ContractTransportDetails
        v-model="form.data.transportDetails"
        :unit-options="cargoUnitOptions"
      />

      <section class="contract-dialog__section art-card-xs">
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
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep, omit } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElButton, ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import type { ColumnOption } from '@/types'
  import { formatNameCodeOption } from '@/utils/form'
  import {
    addContract,
    editContract,
    fetchCarrierOptions,
    fetchCustomerOptions,
    submitContractForApproval
  } from '@/api/tms'
  import { uploadAttachment } from '@/api/common'
  import { useUserStore } from '@/store/modules/user'
  import { downloadAttachment, getFileExtension } from '@/utils/file'
  import { usesCarrierParty } from './contract-business-type'
  import ContractTransportDetails from './contract-transport-details.vue'

  defineOptions({ name: 'TmsContractDialog' })

  const { confirmAction } = useArtFeedback()

  type Contract = Api.Tms.BasicData.Contract
  type ContractAttachment = Api.Tms.BasicData.ContractAttachment
  type ContractBusinessType = Api.Tms.BasicData.ContractBusinessType
  type ContractTransportDetail = Api.Tms.BasicData.ContractTransportDetail
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type SubmitMode = 'save' | 'submit'
  type FooterApi = Pick<ArtDialogExpose<Contract | undefined>, 'handleConfirm'>

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: (props?: string | string[]) => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface FormGroup {
    data: Contract
    items: ComputedRef<FormItem[]>
    rules: FormRules<Contract>
    carrierOptions: CarrierOption[]
    customerOptions: CustomerOption[]
    attachmentUploading: boolean
  }

  interface Emits {
    (event: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Contract | undefined>>()
  const formRef = ref<FormExpose>()
  const contractNumber = useDocumentNumberRule('tms.contract')
  const submitMode = ref<SubmitMode>('save')

  const billingMethodOptions = computed(() => getDictMap.value.tmsContractBillingMethod ?? [])
  const contractCategoryOptions = computed(() => getDictMap.value.tmsContractCategory ?? [])
  const businessTypeOptions = computed(() => getDictMap.value.tmsContractBusinessType ?? [])
  const transportModeOptions = computed(() => getDictMap.value.tmsContractTransportMode ?? [])
  const cargoUnitOptions = computed(() => getDictMap.value.tmsCargoUnit ?? [])
  const completionOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const createInitialForm = (): Contract => ({
    id: undefined,
    contractNo: '',
    contractName: '',
    contractStatus: 'draft',
    paperContractNo: '',
    mnemonicCode: '',
    contractCategory: 'annual_framework',
    transportMode: 'road',
    businessContractType: 'carrier',
    customerId: null,
    carrierId: null,
    contactName: '',
    waybillNo: '',
    customerSignatory: '',
    billingMethod: '',
    contractAmount: null,
    transportUnitPrice: null,
    roadConsumptionRate: null,
    lossDeductionPrice: null,
    signTime: '',
    effectiveDate: null,
    expiryDate: null,
    isCompleted: false,
    agreedTransportQuantity: null,
    transportRoute: '',
    shipperName: '',
    payerName: '',
    consigneeName: '',
    specialTransportRequirements: '',
    otherDeductionTerms: '',
    handler: '',
    contractDescription: '',
    transportDetails: [],
    attachments: []
  })

  const dateProps = {
    type: 'date',
    valueFormat: 'YYYY-MM-DD',
    class: '!w-full'
  }

  const moneyProps = (precision = 2) => ({
    min: 0,
    precision,
    controlsPosition: 'right',
    class: '!w-full'
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    carrierOptions: [],
    customerOptions: [],
    attachmentUploading: false,
    items: computed<FormItem[]>(() => [
      { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
      {
        label: '合同编号',
        key: 'contractNo',
        type: 'input',
        props: {
          maxlength: 40,
          ...contractNumber.inputProps(Boolean(form.data.id), '请输入合同编号', true)
        },
        description: contractNumber.description.value
      },
      {
        label: '纸质合同编号',
        key: 'paperContractNo',
        type: 'input',
        props: { maxlength: 60, clearable: true, placeholder: '请输入纸质合同编号' }
      },
      {
        label: '助记码',
        key: 'mnemonicCode',
        type: 'input',
        props: { maxlength: 40, clearable: true, placeholder: '请输入助记码' }
      },
      {
        label: '合同名称',
        key: 'contractName',
        type: 'input',
        span: 16,
        props: { maxlength: 120, placeholder: '请输入合同名称' }
      },
      {
        label: '合同类别',
        key: 'contractCategory',
        type: 'select',
        props: { options: contractCategoryOptions.value, clearable: false, placeholder: '请选择' }
      },
      {
        label: '业务合同分类',
        key: 'businessContractType',
        type: 'radioGroup',
        span: 16,
        props: {
          options: businessTypeOptions.value,
          onChange: handleBusinessTypeChange
        }
      },
      {
        label: '运输方式',
        key: 'transportMode',
        type: 'select',
        span: 8,
        props: {
          options: transportModeOptions.value,
          clearable: false,
          placeholder: '请选择运输方式'
        }
      },
      {
        label: '承运商',
        key: 'carrierId',
        type: 'select',
        hidden: () => !usesCarrierParty(form.data.businessContractType),
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
        label: '客户/货主',
        key: 'customerId',
        type: 'select',
        hidden: () => usesCarrierParty(form.data.businessContractType),
        api: fetchCustomerOptions,
        immediate: false,
        resultField: 'data',
        labelField: 'customerName',
        valueField: 'id',
        labelFn: formatCustomerOption,
        afterFetch: syncCustomerOptions,
        props: {
          clearable: true,
          filterable: true,
          placeholder: '请选择客户或货主',
          onChange: handleCustomerChange
        }
      },
      {
        label: '业务联系人',
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
        label: '客户签约人',
        key: 'customerSignatory',
        type: 'input',
        props: { maxlength: 60, clearable: true, placeholder: '请输入客户签约人' }
      },
      {
        label: '经办人',
        key: 'handler',
        type: 'input',
        props: { maxlength: 40, placeholder: '请输入经办人' }
      },
      { label: '计费与履约', key: 'termsSection', type: 'divider', span: 24 },
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
        props: moneyProps()
      },
      {
        label: '运输单价',
        key: 'transportUnitPrice',
        type: 'number',
        props: { ...moneyProps(4), placeholder: '请输入合同级默认单价' }
      },
      {
        label: '路耗标准%',
        key: 'roadConsumptionRate',
        type: 'number',
        props: { min: 0, max: 100, precision: 4, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '亏扣价',
        key: 'lossDeductionPrice',
        type: 'number',
        props: moneyProps(4)
      },
      {
        label: '约定运输量',
        key: 'agreedTransportQuantity',
        type: 'number',
        props: { ...moneyProps(4), placeholder: '请输入合同约定运输总量' }
      },
      {
        label: '签约日期',
        key: 'signTime',
        type: 'date',
        props: dateProps
      },
      {
        label: '生效日期',
        key: 'effectiveDate',
        type: 'date',
        props: dateProps
      },
      {
        label: '到期日期',
        key: 'expiryDate',
        type: 'date',
        props: dateProps
      },
      {
        label: '是否完成',
        key: 'isCompleted',
        type: 'radioGroup',
        props: { options: completionOptions.value }
      },
      {
        label: '关联运单号',
        key: 'waybillNo',
        type: 'input',
        span: 16,
        props: { maxlength: 60, clearable: true, placeholder: '可选，填写关联运单号' }
      },
      { label: '运输与合同约定', key: 'routeSection', type: 'divider', span: 24 },
      {
        label: '运输路线',
        key: 'transportRoute',
        type: 'input',
        span: 16,
        props: { maxlength: 240, clearable: true, placeholder: '请输入合同约定运输路线' }
      },
      {
        label: '发货方',
        key: 'shipperName',
        type: 'input',
        props: { maxlength: 120, clearable: true, placeholder: '请输入发货方' }
      },
      {
        label: '付款方',
        key: 'payerName',
        type: 'input',
        props: { maxlength: 120, clearable: true, placeholder: '请输入付款方' }
      },
      {
        label: '收货方',
        key: 'consigneeName',
        type: 'input',
        props: { maxlength: 120, clearable: true, placeholder: '请输入收货方' }
      },
      {
        label: '运输特殊要求',
        key: 'specialTransportRequirements',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 3,
          maxlength: 1000,
          showWordLimit: true,
          placeholder: '请输入装卸、时效、温控、安全等特殊要求'
        }
      },
      {
        label: '其他扣款约定',
        key: 'otherDeductionTerms',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 3,
          maxlength: 1000,
          showWordLimit: true,
          placeholder: '请输入其他扣款或违约约定'
        }
      },
      {
        label: '合同说明摘要',
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
    rules: {
      contractNo: [
        {
          validator: (_rule, value, callback) => {
            if (contractNumber.manualRequired(Boolean(form.data.id)) && !value) {
              callback(new Error('请输入合同编号'))
              return
            }
            callback()
          },
          trigger: 'blur'
        }
      ],
      contractName: [
        { required: true, message: '请输入合同名称', trigger: 'blur' },
        { min: 2, max: 120, message: '长度应为 2 到 120 个字符', trigger: 'blur' }
      ],
      contractCategory: [{ required: true, message: '请选择合同类别', trigger: 'change' }],
      businessContractType: [{ required: true, message: '请选择业务合同分类', trigger: 'change' }],
      transportMode: [{ required: true, message: '请选择运输方式', trigger: 'change' }],
      carrierId: [
        {
          validator: (_rule, value, callback) => {
            if (usesCarrierParty(form.data.businessContractType) && !value) {
              callback(new Error('请选择承运商'))
              return
            }
            callback()
          },
          trigger: 'change'
        }
      ],
      customerId: [
        {
          validator: (_rule, value, callback) => {
            if (!usesCarrierParty(form.data.businessContractType) && !value) {
              callback(new Error('请选择客户或货主'))
              return
            }
            callback()
          },
          trigger: 'change'
        }
      ],
      billingMethod: [{ required: true, message: '请选择计费方式', trigger: 'change' }],
      signTime: [{ required: true, message: '请选择签约日期', trigger: 'change' }],
      expiryDate: [
        {
          validator: (_rule, value, callback) => {
            const effectiveDate = form.data.effectiveDate
            if (value && effectiveDate && String(value) < String(effectiveDate)) {
              callback(new Error('到期日期不能早于生效日期'))
              return
            }
            callback()
          },
          trigger: 'change'
        }
      ],
      handler: [{ required: true, message: '请输入经办人', trigger: 'blur' }],
      specialTransportRequirements: [
        { max: 1000, message: '运输特殊要求不能超过 1000 个字符', trigger: 'blur' }
      ],
      otherDeductionTerms: [
        { max: 1000, message: '其他扣款约定不能超过 1000 个字符', trigger: 'blur' }
      ],
      contractDescription: [
        { max: 1000, message: '合同说明摘要不能超过 1000 个字符', trigger: 'blur' }
      ]
    }
  })

  const contactNameOptions = computed(() => {
    const options = new Map<string, { label: string; value: string }>()
    const carrier = form.carrierOptions.find((item) => item.id === form.data.carrierId)
    const customer = form.customerOptions.find((item) => item.id === form.data.customerId)
    if (carrier?.contactName) {
      options.set(carrier.contactName, { label: carrier.contactName, value: carrier.contactName })
    }
    if (customer?.contactName) {
      options.set(customer.contactName, {
        label: customer.contactName,
        value: customer.contactName
      })
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

  const syncCustomerOptions = (result: unknown): unknown => {
    form.customerOptions = getResponseData<CustomerOption>(result)
    return result
  }

  const formatCarrierOption = (option: Record<string, unknown>): string => {
    return formatNameCodeOption(option, 'companyName', 'carrierCode')
  }

  const formatCustomerOption = (option: Record<string, unknown>): string => {
    return formatNameCodeOption(option, 'customerName', 'customerCode')
  }

  const handleBusinessTypeChange = (businessType: ContractBusinessType): void => {
    const partyPatch: Partial<Contract> = usesCarrierParty(businessType)
      ? { customerId: null, customer: null, customerSignatory: '', contactName: '' }
      : { carrierId: null, carrier: null, contactName: '' }
    Object.assign(form.data, partyPatch)
    void nextTick(() => formRef.value?.clearValidate(['carrierId', 'customerId']))
  }

  const handleCarrierChange = (carrierId?: string): void => {
    const carrier = form.carrierOptions.find((item) => item.id === carrierId)
    form.data.contactName = carrier?.contactName || ''
  }

  const handleCustomerChange = (customerId?: string): void => {
    const customer = form.customerOptions.find((item) => item.id === customerId)
    Object.assign(form.data, {
      contactName: customer?.contactName || '',
      customerSignatory: customer?.contactName || form.data.customerSignatory || ''
    })
  }

  const replaceForm = (data: Contract): void => {
    Object.assign(form.data, createInitialForm(), cloneDeep(toRaw(data)))
    form.data.contractStatus ??= 'draft'
    form.data.businessContractType ??= 'carrier'
    form.data.contractCategory ||= 'annual_framework'
    form.data.transportMode ||= 'road'
    form.data.isCompleted ??= false
    form.data.transportDetails ??= []
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
      'customer',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as Contract

    if (!payload.contractNo) delete payload.contractNo
    const hasCarrierParty = usesCarrierParty(payload.businessContractType)
    return {
      ...payload,
      contractStatus: payload.contractStatus || 'draft',
      customerId: hasCarrierParty ? null : normalizeText(payload.customerId),
      carrierId: hasCarrierParty ? normalizeText(payload.carrierId) : null,
      paperContractNo: normalizeText(payload.paperContractNo),
      mnemonicCode: normalizeText(payload.mnemonicCode),
      contactName: normalizeText(payload.contactName),
      waybillNo: normalizeText(payload.waybillNo),
      customerSignatory: normalizeText(payload.customerSignatory),
      contractAmount: normalizeNumber(payload.contractAmount),
      transportUnitPrice: normalizeNumber(payload.transportUnitPrice),
      roadConsumptionRate: normalizeNumber(payload.roadConsumptionRate),
      lossDeductionPrice: normalizeNumber(payload.lossDeductionPrice),
      effectiveDate: normalizeText(payload.effectiveDate),
      expiryDate: normalizeText(payload.expiryDate),
      agreedTransportQuantity: normalizeNumber(payload.agreedTransportQuantity),
      transportRoute: normalizeText(payload.transportRoute),
      shipperName: normalizeText(payload.shipperName),
      payerName: normalizeText(payload.payerName),
      consigneeName: normalizeText(payload.consigneeName),
      specialTransportRequirements: normalizeText(payload.specialTransportRequirements),
      otherDeductionTerms: normalizeText(payload.otherDeductionTerms),
      contractDescription: normalizeText(payload.contractDescription),
      transportDetails: (payload.transportDetails ?? []).map(normalizeTransportDetail),
      attachments: payload.attachments ?? []
    }
  }

  const normalizeTransportDetail = (detail: ContractTransportDetail): ContractTransportDetail => ({
    cargoId: normalizeText(detail.cargoId),
    cargoDescription: String(detail.cargoDescription ?? '').trim(),
    cargoCode: String(detail.cargoCode ?? '').trim(),
    contractQuantity: Number(detail.contractQuantity ?? 0),
    unit: String(detail.unit ?? '').trim(),
    transportUnitPrice: Number(detail.transportUnitPrice ?? 0),
    freight: Number(detail.freight ?? 0)
  })

  const validateTransportDetails = (): boolean => {
    const invalidIndex = (form.data.transportDetails ?? []).findIndex((detail) => {
      const numericValues = [
        Number(detail.contractQuantity),
        Number(detail.transportUnitPrice),
        Number(detail.freight)
      ]
      return (
        !String(detail.cargoDescription ?? '').trim() ||
        !String(detail.cargoCode ?? '').trim() ||
        !String(detail.unit ?? '').trim() ||
        numericValues.some((value) => !Number.isFinite(value) || value < 0)
      )
    })
    if (invalidIndex < 0) return true
    ElMessage.warning(`请完整填写第 ${invalidIndex + 1} 条运输合同明细`)
    return false
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (!validateTransportDetails()) return false

    try {
      const payload = normalizePayload()
      const type = form.data.id ? 'edit' : 'add'
      if (type === 'edit') {
        await editContract(payload)
      } else {
        const response = await addContract(payload)
        payload.id = response.data?.id
        form.data.id = response.data?.id
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
    await Promise.all([resetForm(), contractNumber.loadRule()])
    if (row?.id) replaceForm(row)

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑合同' : '新增合同',
      subtitle: '维护合同相对方、履约条款、运输明细和附件',
      contentMaxHeight: '78vh',
      loading: true,
      onOpen: async (_data, api) => {
        try {
          await formRef.value?.reloadOptions()
        } finally {
          await nextTick()
          formRef.value?.clearValidate()
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

      if ((form.data.attachments ?? []).some((attachment) => attachment.url === resource.url)) {
        ElMessage.info('该附件已在当前合同中，无需重复添加')
        return
      }

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
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;

    &__section {
      min-width: 0;
      padding: 16px;
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

    @media (width <= 680px) {
      :deep(.art-form .el-col) {
        flex: 0 0 100%;
        max-width: 100%;
      }

      :deep(.art-form .el-form-item) {
        display: block;
      }

      :deep(.art-form .el-form-item__label) {
        justify-content: flex-start;
        width: 100% !important;
        height: auto;
        margin-bottom: 6px;
      }

      :deep(.art-form .el-form-item__content) {
        margin-left: 0 !important;
      }

      &__section-header,
      &__footer {
        flex-wrap: wrap;
      }
    }
  }
</style>
