<template>
  <ArtDialog ref="dialogRef" size="lg">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="8"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #addressPicker>
        <ArtAddressPicker
          v-if="canViewAddressField('addressDetail')"
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
          :disabled="!canEditAddressField('addressDetail')"
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
  import { fetchRegionOptions } from '@/api/common'
  import { addCustomerAddress, editCustomerAddress, fetchCustomerOptions } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { canEditField, canViewField, getFieldAccess } from '@/utils/field-permission'

  defineOptions({ name: 'TmsCustomerAddressDialog' })

  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type CustomerAddressForm = Omit<CustomerAddress, 'customerId'> & {
    customerId: string
    addressPicker?: undefined
    regionPath: string[]
  }

  interface CustomerContext {
    customerId?: string
    customerName?: string
  }

  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<CustomerAddress | undefined>>()
  const formRef = ref<DialogFormExpose>()
  const customerOptions = shallowRef<CustomerOption[]>([])
  const customerContext = reactive<CustomerContext>({})

  const addressTypeOptions = computed(() => getDictMap.value.tmsAddressType ?? [])

  const createInitialForm = (): CustomerAddressForm => ({
    id: undefined,
    customerId: '',
    addressType: 'shipping',
    contactName: '',
    contactPhone: '',
    region: '',
    regionAdcode: '',
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
    isDefault: false,
    remark: '',
    fieldAccess: {
      contactPhone: 'edit',
      addressDetail: 'edit'
    },
    isRecordOwner: true
  })

  const form = reactive<CustomerAddressForm>(createInitialForm())

  const canViewAddressField = (field: Api.Tms.BasicData.CustomerAddressFieldKey): boolean =>
    canViewField(form.fieldAccess, field)

  const canEditAddressField = (field: Api.Tms.BasicData.CustomerAddressFieldKey): boolean =>
    canEditField(form.fieldAccess, field)

  const formRules: FormRules<CustomerAddressForm> = {
    addressType: [{ required: true, message: '请选择地址类型', trigger: 'change' }],
    contactName: [{ required: true, message: '请输入联系人', trigger: 'blur' }],
    contactPhone: [
      {
        validator: (_rule, value, callback) => {
          if (!canEditAddressField('contactPhone')) return callback()
          if (!value) return callback(new Error('请输入联系电话'))
          return /^(?:1[3-9]\d{9}|0\d{2,3}-?\d{7,8})$/.test(String(value))
            ? callback()
            : callback(new Error('请输入正确的手机号或座机号'))
        },
        trigger: 'blur'
      }
    ],
    regionPath: [
      {
        validator: (_rule, value, callback) =>
          !canEditAddressField('addressDetail') || (Array.isArray(value) && value.length)
            ? callback()
            : callback(new Error('请选择区域')),
        trigger: 'change'
      }
    ],
    addressDetail: [
      {
        validator: (_rule, value, callback) =>
          !canEditAddressField('addressDetail') || value
            ? callback()
            : callback(new Error('请输入详细地址')),
        trigger: 'blur'
      }
    ],
    postalCode: [{ pattern: /^\d{6}$/, message: '邮编应为 6 位数字', trigger: 'blur' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '地址类型',
      key: 'addressType',
      type: 'select',
      props: {
        options: addressTypeOptions.value,
        placeholder: '请选择地址类型'
      }
    },
    {
      label: '客户',
      key: 'customerId',
      type: 'select',
      span: 16,
      api: fetchCustomerOptions,
      resultField: 'data',
      labelField: 'customerName',
      valueField: 'id',
      afterFetch: syncCustomerOptions,
      labelFn: (option) => {
        const customer = option as CustomerOption
        return customer.customerCode
          ? `${customer.customerName}（${customer.customerCode}）`
          : customer.customerName
      },
      props: {
        disabled: Boolean(customerContext.customerId),
        filterable: true,
        clearable: !customerContext.customerId,
        onChange: handleCustomerChange,
        placeholder: '请选择客户'
      }
    },
    {
      label: '联系人',
      key: 'contactName',
      type: 'input',
      props: { maxlength: 50, placeholder: '请输入联系人' }
    },
    {
      label: '联系电话',
      key: 'contactPhone',
      type: 'input',
      hidden: !canViewAddressField('contactPhone'),
      props: {
        maxlength: 20,
        placeholder: '请输入联系电话',
        disabled: !canEditAddressField('contactPhone')
      }
    },
    {
      label: '邮编',
      key: 'postalCode',
      type: 'input',
      hidden: !canViewAddressField('addressDetail'),
      props: {
        maxlength: 6,
        placeholder: '请输入邮编',
        disabled: !canEditAddressField('addressDetail')
      }
    },
    {
      label: '',
      key: 'addressPicker',
      type: 'input',
      span: 24,
      labelWidth: 0,
      hidden: !canViewAddressField('addressDetail')
    },
    {
      label: '默认地址',
      key: 'isDefault',
      type: 'switch',
      props: { activeText: '是', inactiveText: '否', inlinePrompt: true }
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
    }
  ])

  const replaceForm = (nextForm: CustomerAddressForm): void => {
    Object.assign(form, createInitialForm(), nextForm)
  }

  const getResponseData = <TRecord,>(result: unknown): TRecord[] => {
    if (!result || typeof result !== 'object') return []
    const data = (result as { data?: TRecord[] }).data
    return Array.isArray(data) ? data : []
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

  const syncCustomerOptions = (result: unknown): unknown => {
    customerOptions.value = getResponseData<CustomerOption>(result)
    if (!form.id && form.customerId) applyCustomerProfile(form.customerId)
    return result
  }

  const handleCustomerChange = (customerId?: string): void => {
    if (!customerId) return
    applyCustomerProfile(customerId)
  }

  const applyCustomerProfile = (customerId: string): void => {
    const customer = customerOptions.value.find((item) => item.id === customerId)
    if (!customer) return

    const phoneAccess = getFieldAccess(customer.fieldAccess, 'contactPhone')
    const addressAccess = getFieldAccess(customer.fieldAccess, 'addressDetail')
    const canUsePhone = phoneAccess === 'read' || phoneAccess === 'edit'
    const canUseAddress = addressAccess === 'read' || addressAccess === 'edit'
    const longitude = canUseAddress ? normalizeNullableNumber(customer.longitude) : null
    const latitude = canUseAddress ? normalizeNullableNumber(customer.latitude) : null
    const hasCoordinate = longitude !== null && latitude !== null

    Object.assign(form, {
      contactName: customer.contactName || '',
      contactPhone: canUsePhone ? customer.contactPhone || '' : '',
      region: customer.region || '',
      regionAdcode: canUseAddress ? customer.regionAdcode || '' : '',
      regionPath: customer.region?.split('/').filter(Boolean) ?? [],
      addressDetail: canUseAddress ? customer.addressDetail || '' : '',
      longitude,
      latitude,
      coordinateSystem: hasCoordinate ? customer.coordinateSystem || 'gcj02' : 'gcj02',
      coordinateSource: canUseAddress ? customer.coordinateSource || '' : '',
      coordinateStatus: hasCoordinate
        ? customer.coordinateStatus || 'located'
        : customer.coordinateStatus || 'pending',
      geocodeProvider: canUseAddress ? customer.geocodeProvider || '' : '',
      geocodedAt: canUseAddress ? customer.geocodedAt || '' : '',
      postalCode: canUseAddress ? customer.postalCode || '' : ''
    })
  }

  const buildSubmitPayload = (data: CustomerAddressForm): CustomerAddress => {
    const { regionPath, ...rawRest } = data
    const rest: Partial<CustomerAddressForm> = rawRest
    delete rest.addressPicker
    delete rest.customer
    delete rest.tenantId
    delete rest.createBy
    delete rest.createTime
    delete rest.updateBy
    delete rest.updateTime

    if (data.id && !canEditField(data.fieldAccess, 'contactPhone')) delete rest.contactPhone
    if (data.id && !canEditField(data.fieldAccess, 'addressDetail')) {
      delete rest.region
      delete rest.regionAdcode
      delete rest.addressDetail
      delete rest.longitude
      delete rest.latitude
      delete rest.coordinateSystem
      delete rest.coordinateSource
      delete rest.coordinateStatus
      delete rest.geocodeProvider
      delete rest.geocodedAt
      delete rest.postalCode
    }

    const longitude = normalizeNullableNumber(rest.longitude)
    const latitude = normalizeNullableNumber(rest.latitude)
    const hasCoordinate = longitude !== null && latitude !== null

    const payload: Partial<CustomerAddress> = {
      ...rest,
      customerId: normalizeNullableText(rest.customerId),
      ...(rest.region === undefined ? {} : { region: regionPath.join('/') }),
      regionAdcode: normalizeNullableText(rest.regionAdcode),
      longitude,
      latitude,
      coordinateSystem: hasCoordinate
        ? rest.coordinateSystem || 'gcj02'
        : normalizeNullableText(rest.coordinateSystem),
      coordinateSource: normalizeNullableText(rest.coordinateSource),
      coordinateStatus: hasCoordinate
        ? rest.coordinateStatus || 'located'
        : rest.coordinateStatus || 'pending',
      geocodeProvider: normalizeNullableText(rest.geocodeProvider),
      geocodedAt: normalizeNullableText(rest.geocodedAt)
    }

    if (data.id && !canEditField(data.fieldAccess, 'addressDetail')) {
      delete payload.region
      delete payload.regionAdcode
      delete payload.addressDetail
      delete payload.longitude
      delete payload.latitude
      delete payload.coordinateSystem
      delete payload.coordinateSource
      delete payload.coordinateStatus
      delete payload.geocodeProvider
      delete payload.geocodedAt
      delete payload.postalCode
    }
    return payload as CustomerAddress
  }

  const resetForm = async (): Promise<void> => {
    replaceForm({
      ...createInitialForm(),
      customerId: customerContext.customerId ?? ''
    })
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
      if (type === 'edit') await editCustomerAddress(payload)
      else await addCustomerAddress(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (
    row?: CustomerAddress,
    context: CustomerContext = {}
  ): Promise<void> => {
    Object.assign(customerContext, context)
    await resetForm()
    const isEdit = Boolean(row?.id)
    if (row) {
      replaceForm({
        ...createInitialForm(),
        ...structuredClone(toRaw(row)),
        customerId: row.customerId ?? '',
        regionPath: row.region?.split('/').filter(Boolean) ?? []
      })
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑地址' : '新增地址',
      subtitle: customerContext.customerName
        ? `当前客户：${customerContext.customerName}`
        : '维护客户常用发货与收货地址',
      contentMaxHeight: '64vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
