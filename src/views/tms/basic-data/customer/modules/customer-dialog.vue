<template>
  <ArtDialog ref="dialogRef" size="xl">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="8"
      :gutter="20"
      label-width="108px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #addressPicker>
        <ArtAddressPicker
          v-model:region-path="form.regionPath"
          v-model:address-detail="form.addressDetail"
          v-model:region-adcode="form.regionAdcode"
          v-model:longitude="form.longitude"
          v-model:latitude="form.latitude"
          v-model:coordinate-system="form.coordinateSystem"
          v-model:coordinate-source="form.coordinateSource"
          v-model:coordinate-status="form.coordinateStatus"
          v-model:geocode-provider="form.geocodeProvider"
          v-model:geocoded-at="form.geocodedAt"
          :region-api="fetchRegionOptions"
          label-width="108px"
        />
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtAddressPicker from '@/components/core/forms/art-address-picker/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import { addCustomer, editCustomer, fetchCustomerOptions } from '@/api/tms'
  import { fetchRegionOptions } from '@/api/common'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsCustomerDialog' })

  type Customer = Api.Tms.BasicData.Customer
  type CustomerForm = Customer & { addressPicker?: undefined; regionPath: string[] }

  interface DialogExposeForm {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Customer | undefined>>()
  const formRef = ref<DialogExposeForm>()

  const customerLevelOptions = computed(() => getDictMap.value.tmsCustomerLevel ?? [])
  const customerIndustryOptions = computed(() => getDictMap.value.tmsCustomerIndustry ?? [])
  const customerTagOptions = computed(() => getDictMap.value.tmsCustomerTag ?? [])

  const createInitialForm = (): CustomerForm => ({
    id: undefined,
    parentUnitId: null,
    customerCode: '',
    customerName: '',
    industry: '',
    customerLevel: '',
    tags: [],
    region: '',
    regionAdcode: '',
    addressPicker: undefined,
    regionPath: [],
    addressDetail: '',
    longitude: null,
    latitude: null,
    coordinateSystem: 'gcj02',
    coordinateSource: '',
    coordinateStatus: 'pending',
    geocodeProvider: '',
    geocodedAt: '',
    postalCode: '',
    enabled: true,
    contactName: '',
    contactPhone: '',
    contactDepartment: '',
    contactPosition: '',
    contactEmail: '',
    contactQq: '',
    invoiceTitle: '',
    taxNo: '',
    bankName: '',
    bankAccount: '',
    remark: ''
  })

  const form = reactive<CustomerForm>(createInitialForm())
  const customerNumber = useDocumentNumberRule('master.customer')

  const formRules: FormRules<CustomerForm> = {
    customerName: [
      { required: true, message: '请输入客户名称', trigger: 'blur' },
      { min: 2, max: 100, message: '长度应为 2 到 100 个字符', trigger: 'blur' }
    ],
    customerCode: [
      {
        validator: (_rule, value, callback) =>
          customerNumber.manualRequired(Boolean(form.id)) && !String(value || '').trim()
            ? callback(new Error('请输入客户编号'))
            : callback(),
        trigger: 'blur'
      },
      { max: 30, message: '客户编号不能超过 30 个字符', trigger: 'blur' }
    ],
    contactPhone: [
      {
        pattern: /^(?:1[3-9]\d{9}|0\d{2,3}-?\d{7,8})$/,
        message: '请输入正确的手机号或座机号',
        trigger: 'blur'
      }
    ],
    contactEmail: [{ type: 'email', message: '请输入正确的邮箱地址', trigger: 'blur' }],
    postalCode: [{ pattern: /^\d{6}$/, message: '邮编应为 6 位数字', trigger: 'blur' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '客户编号',
      key: 'customerCode',
      type: 'input',
      props: {
        maxlength: 30,
        ...customerNumber.inputProps(Boolean(form.id), '请输入客户编号')
      },
      description: customerNumber.description.value
    },
    {
      label: '客户名称',
      key: 'customerName',
      type: 'input',
      props: { maxlength: 100, placeholder: '请输入客户名称' }
    },
    {
      label: '所属行业',
      key: 'industry',
      type: 'select',
      props: {
        options: customerIndustryOptions.value,
        clearable: true,
        placeholder: '请选择所属行业'
      }
    },
    {
      label: '上级单位',
      key: 'parentUnitId',
      type: 'select',
      api: fetchCustomerOptions,
      immediate: false,
      beforeFetch: () => ({ excludeId: form.id, includeDisabled: true }),
      resultField: 'data',
      labelField: 'customerName',
      valueField: 'id',
      labelFn: (option) => {
        const customer = option as Api.Tms.BasicData.CustomerOption
        const code = customer.customerCode ? `（${customer.customerCode}）` : ''
        const status = customer.enabled === false ? ' · 已停用' : ''
        return `${customer.customerName}${code}${status}`
      },
      props: {
        clearable: true,
        filterable: true,
        placeholder: '请选择上级客户单位'
      },
      description: '选填；不选择则作为一级客户单位。'
    },
    {
      label: '客户级别',
      key: 'customerLevel',
      type: 'select',
      props: {
        options: customerLevelOptions.value,
        clearable: true,
        placeholder: '请选择客户级别'
      }
    },
    {
      label: '客户标签',
      key: 'tags',
      type: 'select',
      span: 16,
      props: {
        options: customerTagOptions.value,
        multiple: true,
        collapseTags: true,
        collapseTagsTooltip: true,
        maxCollapseTags: 3,
        clearable: true,
        placeholder: '请选择客户标签'
      }
    },
    {
      label: '客户状态',
      key: 'enabled',
      type: 'switch',
      props: { activeText: '启用', inactiveText: '停用', inlinePrompt: true }
    },
    {
      label: '',
      key: 'addressPicker',
      type: 'input',
      span: 24,
      labelWidth: 0
    },
    {
      label: '邮编',
      key: 'postalCode',
      type: 'input',
      props: { maxlength: 6, placeholder: '请输入邮编' }
    },
    {
      label: '备注信息',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 3,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '请输入备注信息'
      }
    },
    { label: '联系人信息', key: 'contactSection', type: 'divider', span: 24 },
    {
      label: '姓名',
      key: 'contactName',
      type: 'input',
      props: { maxlength: 50, placeholder: '请输入联系人姓名' }
    },
    {
      label: '手机号码',
      key: 'contactPhone',
      type: 'input',
      props: { maxlength: 20, placeholder: '请输入联系电话' }
    },
    {
      label: '部门',
      key: 'contactDepartment',
      type: 'input',
      props: { maxlength: 50, placeholder: '请输入部门' }
    },
    {
      label: '职位',
      key: 'contactPosition',
      type: 'input',
      props: { maxlength: 50, placeholder: '请输入职位' }
    },
    {
      label: 'E-mail',
      key: 'contactEmail',
      type: 'input',
      props: { maxlength: 100, placeholder: '请输入邮箱地址' }
    },
    {
      label: 'QQ',
      key: 'contactQq',
      type: 'input',
      props: { maxlength: 20, placeholder: '请输入 QQ' }
    },
    { label: '财务信息', key: 'financeSection', type: 'divider', span: 24 },
    {
      label: '发票抬头',
      key: 'invoiceTitle',
      type: 'input',
      props: { maxlength: 100, placeholder: '请输入发票抬头' }
    },
    {
      label: '纳税人识别号',
      key: 'taxNo',
      type: 'input',
      props: { maxlength: 40, placeholder: '请输入纳税人识别号' }
    },
    {
      label: '开户行',
      key: 'bankName',
      type: 'input',
      props: { maxlength: 100, placeholder: '请输入开户行' }
    },
    {
      label: '银行账号',
      key: 'bankAccount',
      type: 'input',
      span: 16,
      props: { maxlength: 50, placeholder: '请输入银行账号' }
    }
  ])

  const replaceForm = (nextForm: CustomerForm): void => {
    Object.keys(form).forEach((key) => delete form[key as keyof CustomerForm])
    Object.assign(form, nextForm)
  }

  const normalizeNullableNumber = (value: unknown): number | null => {
    if (value === null || value === undefined || value === '') return null
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : null
  }

  const normalizeNullableText = (value: unknown): string | null => {
    const text = String(value ?? '').trim()
    return text || null
  }

  const buildSubmitPayload = (data: CustomerForm): Customer => {
    const { regionPath, ...rawPayload } = data
    delete rawPayload.addressPicker

    const longitude = normalizeNullableNumber(rawPayload.longitude)
    const latitude = normalizeNullableNumber(rawPayload.latitude)
    const hasCoordinate = longitude !== null && latitude !== null

    const payload: Customer = {
      ...rawPayload,
      parentUnitId: rawPayload.parentUnitId || null,
      region: regionPath.join('/'),
      regionAdcode: normalizeNullableText(rawPayload.regionAdcode),
      longitude,
      latitude,
      coordinateSystem: hasCoordinate
        ? rawPayload.coordinateSystem || 'gcj02'
        : normalizeNullableText(rawPayload.coordinateSystem),
      coordinateSource: normalizeNullableText(rawPayload.coordinateSource),
      coordinateStatus: hasCoordinate
        ? rawPayload.coordinateStatus || 'located'
        : rawPayload.coordinateStatus || 'pending',
      geocodeProvider: normalizeNullableText(rawPayload.geocodeProvider),
      geocodedAt: normalizeNullableText(rawPayload.geocodedAt)
    }

    if (!payload.customerCode) delete payload.customerCode
    return payload
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = buildSubmitPayload(structuredClone(toRaw(form)))
      const type = form.id ? 'edit' : 'add'
      if (type === 'edit') await editCustomer(payload)
      else await addCustomer(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Customer): Promise<void> => {
    await Promise.all([resetForm(), customerNumber.loadRule()])
    const isEdit = Boolean(row?.id)
    if (row) {
      replaceForm({
        ...createInitialForm(),
        ...structuredClone(toRaw(row)),
        tags: [...(row.tags ?? [])],
        regionPath: row.region?.split('/').filter(Boolean) ?? []
      })
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑客户' : '新增客户',
      subtitle: '维护客户基础、联系人和财务信息',
      contentMaxHeight: '72vh',
      loading: true,
      onOpen: async (_openData, api) => {
        try {
          await formRef.value?.reloadOptions('parentUnitId')
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
