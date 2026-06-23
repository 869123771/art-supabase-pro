<template>
  <ArtDialog ref="dialogRef" width="980px">
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
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchRegionOptions } from '@/api/common'
  import { addCustomerAddress, editCustomerAddress, fetchCustomerOptions } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsCustomerAddressDialog' })

  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type CustomerAddressForm = CustomerAddress & { regionPath: string[] }

  interface CustomerContext {
    customerId?: string
    customerName?: string
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<CustomerAddress | undefined>>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const customerContext = reactive<CustomerContext>({})

  const addressTypeOptions = computed(() => getDictMap.value.tmsAddressType ?? [])

  const createInitialForm = (): CustomerAddressForm => ({
    id: undefined,
    customerId: '',
    addressType: 'shipping',
    contactName: '',
    contactPhone: '',
    region: '',
    regionPath: [],
    addressDetail: '',
    postalCode: '',
    isDefault: false,
    remark: ''
  })

  const form = reactive<CustomerAddressForm>(createInitialForm())

  const formRules: FormRules<CustomerAddressForm> = {
    customerId: [{ required: true, message: '请选择客户', trigger: 'change' }],
    addressType: [{ required: true, message: '请选择地址类型', trigger: 'change' }],
    contactName: [{ required: true, message: '请输入联系人', trigger: 'blur' }],
    contactPhone: [
      { required: true, message: '请输入联系电话', trigger: 'blur' },
      {
        pattern: /^(?:1[3-9]\d{9}|0\d{2,3}-?\d{7,8})$/,
        message: '请输入正确的手机号或座机号',
        trigger: 'blur'
      }
    ],
    regionPath: [{ required: true, message: '请选择区域', trigger: 'change' }],
    addressDetail: [{ required: true, message: '请输入详细地址', trigger: 'blur' }],
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
      props: { maxlength: 20, placeholder: '请输入联系电话' }
    },
    {
      label: '邮编',
      key: 'postalCode',
      type: 'input',
      props: { maxlength: 6, placeholder: '请输入邮编' }
    },
    {
      label: '区域',
      key: 'regionPath',
      type: 'cascader',
      api: fetchRegionOptions,
      labelField: 'name',
      valueField: 'name',
      childrenField: 'children',
      props: {
        clearable: true,
        filterable: true,
        props: {
          label: 'name',
          value: 'name',
          children: 'children',
          emitPath: true,
          checkStrictly: true
        }
      }
    },
    {
      label: '详细地址',
      key: 'addressDetail',
      type: 'input',
      span: 16,
      props: { maxlength: 200, placeholder: '请输入道路、门牌号、小区、楼栋等' }
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
    Object.keys(form).forEach((key) => delete form[key as keyof CustomerAddressForm])
    Object.assign(form, nextForm)
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
      const { regionPath, ...rawPayload } = structuredClone(toRaw(form))
      delete rawPayload.customer
      const payload: CustomerAddress = {
        ...rawPayload,
        region: regionPath.join('/')
      }
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
