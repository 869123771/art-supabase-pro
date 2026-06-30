<template>
  <div ref="pageRef" class="customer-price-edit" v-loading="page.loading">
    <div class="customer-price-edit__content">
      <section class="customer-price-edit__section art-card-xs">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ArtForm
          ref="baseFormRef"
          v-model="form.data"
          :items="form.baseItems"
          :rules="form.rules"
          :span="8"
          :gutter="24"
          label-width="98px"
          root-class="customer-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />

        <div class="customer-price-edit__contact-grid">
          <div class="customer-price-edit__contact-panel">
            <div
              class="customer-price-edit__contact-title customer-price-edit__contact-title--send"
            >
              <span>发</span>
            </div>
            <ArtForm
              ref="shippingFormRef"
              v-model="form.data"
              :items="form.shippingItems"
              :rules="form.rules"
              :span="24"
              label-width="92px"
              root-class="customer-price-edit__form"
              :show-reset="false"
              :show-submit="false"
            />
          </div>

          <div class="customer-price-edit__contact-panel">
            <div
              class="customer-price-edit__contact-title customer-price-edit__contact-title--receive"
            >
              <span>收</span>
            </div>
            <ArtForm
              ref="receivingFormRef"
              v-model="form.data"
              :items="form.receivingItems"
              :rules="form.rules"
              :span="24"
              label-width="92px"
              root-class="customer-price-edit__form"
              :show-reset="false"
              :show-submit="false"
            />
          </div>
        </div>
      </section>

      <section class="customer-price-edit__section art-card-xs">
        <div class="customer-price-edit__section-header">
          <ArtSectionTitle :show-line="false">货物信息</ArtSectionTitle>
          <ElButton type="primary" plain :icon="Plus" @click="addCargoItem">添加</ElButton>
        </div>
        <ArtTable
          :data="form.cargoItems"
          :columns="form.cargoColumns"
          :pagination="undefined"
          :show-table-header="false"
          table-layout="fixed"
          empty-height="160px"
        />
        <div class="customer-price-edit__cargo-summary">
          <span>合计</span>
          <div>
            <span>总数量：{{ form.cargoQuantityText }}</span>
            <span>总体积：{{ form.cargoVolumeText }}m³</span>
            <span>总质量：{{ form.cargoWeightText }}kg</span>
          </div>
        </div>
      </section>

      <section class="customer-price-edit__section art-card-xs">
        <ArtSectionTitle>需求车辆</ArtSectionTitle>
        <ArtForm
          ref="vehicleFormRef"
          v-model="form.data"
          :items="form.vehicleItems"
          :rules="form.rules"
          :span="8"
          :gutter="24"
          label-width="98px"
          root-class="customer-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />
      </section>

      <section class="customer-price-edit__section art-card-xs">
        <ArtSectionTitle>费用信息</ArtSectionTitle>
        <ArtForm
          ref="feeFormRef"
          v-model="form.data"
          :items="form.feeItems"
          :rules="form.rules"
          :span="8"
          :gutter="24"
          label-width="98px"
          root-class="customer-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />
      </section>

      <section class="customer-price-edit__section art-card-xs">
        <ArtSectionTitle>付款方式</ArtSectionTitle>
        <ArtForm
          ref="paymentFormRef"
          v-model="form.data"
          :items="form.paymentItems"
          :rules="form.rules"
          :span="8"
          :gutter="24"
          label-width="98px"
          root-class="customer-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />
      </section>
    </div>

    <div class="customer-price-edit__footer art-card-xs">
      <ElButton :disabled="page.saving" @click="goBack">取消</ElButton>
      <ElButton type="primary" :loading="page.saving" @click="handleSave">保存</ElButton>
    </div>
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep, omit } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElButton, ElInput, ElInputNumber, ElOption, ElSelect } from 'element-plus'
  import { Plus } from '@element-plus/icons-vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchRegionOptions } from '@/api/common'
  import {
    addCustomerPrice,
    editCustomerPrice,
    fetchCustomerOptions,
    fetchCustomerPriceDetail
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsCustomerPriceEdit' })

  type CustomerPrice = Api.Tms.BasicData.CustomerPrice
  type CustomerPriceCargoItem = Api.Tms.BasicData.CustomerPriceCargoItem
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type CustomerPriceForm = CustomerPrice & {
    customerCode?: string
    originRegionPath: string[]
    destinationRegionPath: string[]
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface PageState {
    loading: boolean
    saving: boolean
  }

  interface CargoSummary {
    quantity: number
    volume: number
    weight: number
  }

  interface FormGroup {
    data: CustomerPriceForm
    customerOptions: CustomerOption[]
    cargoUnitOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    transportTypeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    cargoTypeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    vehicleTypeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    vehicleLengthOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    billingMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    baseItems: ComputedRef<FormItem[]>
    shippingItems: ComputedRef<FormItem[]>
    receivingItems: ComputedRef<FormItem[]>
    vehicleItems: ComputedRef<FormItem[]>
    feeItems: ComputedRef<FormItem[]>
    paymentItems: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<CustomerPriceForm>>
    cargoColumns: ComputedRef<ColumnOption<CustomerPriceCargoItem>[]>
    cargoItems: ComputedRef<CustomerPriceCargoItem[]>
    cargoSummary: ComputedRef<CargoSummary>
    cargoQuantityText: ComputedRef<string>
    cargoVolumeText: ComputedRef<string>
    cargoWeightText: ComputedRef<string>
  }

  const route = useRoute()
  const router = useRouter()
  const pageRef = ref<HTMLElement>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const baseFormRef = ref<FormExpose>()
  const shippingFormRef = ref<FormExpose>()
  const receivingFormRef = ref<FormExpose>()
  const vehicleFormRef = ref<FormExpose>()
  const feeFormRef = ref<FormExpose>()
  const paymentFormRef = ref<FormExpose>()

  const isEdit = computed(() => Boolean(route.params.id))
  const dictCodes = [
    'tmsCargoUnit',
    'tmsCustomerPriceTransportType',
    'tmsCustomerPriceCargoType',
    'tmsCustomerPriceVehicleType',
    'tmsCustomerPriceVehicleLength',
    'tmsCustomerPriceBillingMethod'
  ]

  const moneyProps = {
    min: 0,
    precision: 2,
    controlsPosition: 'right',
    class: '!w-full'
  }

  const countProps = {
    min: 0,
    precision: 0,
    controlsPosition: 'right',
    class: '!w-full'
  }

  function createInitialCargoItem(): CustomerPriceCargoItem {
    return {
      cargoName: '',
      quantity: null,
      unit: '',
      volumeM3: null,
      weightKg: null
    }
  }

  function createInitialForm(): CustomerPriceForm {
    return {
      id: undefined,
      customerId: '',
      customerCode: '',
      originRegion: '',
      destinationRegion: '',
      originRegionPath: [],
      destinationRegionPath: [],
      transportType: '',
      cargoType: '',
      shippingContactName: '',
      shippingContactPhone: '',
      shippingAddressDetail: '',
      receivingContactName: '',
      receivingContactPhone: '',
      receivingAddressDetail: '',
      cargoItems: [createInitialCargoItem()],
      cargoQuantityTotal: 0,
      cargoVolumeTotal: 0,
      cargoWeightTotal: 0,
      vehicleType: '',
      vehicleLength: '',
      vehicleCount: null,
      billingMethod: '',
      transportFee: 0,
      insuranceFee: 0,
      packageFee: 0,
      loadingFee: 0,
      transferFee: 0,
      fuelFee: 0,
      serviceFee: 0,
      otherFee: 0,
      totalFee: 0,
      cashAmount: 0,
      prepaidAmount: 0,
      collectAmount: 0,
      periodicAmount: 0,
      paymentTotal: 0,
      remark: ''
    }
  }

  function createEmptyCargoSummary(): CargoSummary {
    return {
      quantity: 0,
      volume: 0,
      weight: 0
    }
  }

  function toNumber(value?: number | string | null): number {
    const numberValue = Number(value ?? 0)
    return Number.isNaN(numberValue) ? 0 : numberValue
  }

  function roundNumber(value: number, precision = 2): number {
    const factor = 10 ** precision
    return Math.round((value + Number.EPSILON) * factor) / factor
  }

  function formatNumber(value?: number | string | null, precision = 2): string {
    const numberValue = Number(value ?? 0)
    if (Number.isNaN(numberValue)) return '0'
    return numberValue
      .toFixed(precision)
      .replace(/\.0+$/, '')
      .replace(/(\.\d*?)0+$/, '$1')
  }

  const page = reactive<PageState>({ loading: false, saving: false })
  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    customerOptions: [],
    cargoUnitOptions: computed(() => getDictMap.value.tmsCargoUnit ?? []),
    transportTypeOptions: computed(() => getDictMap.value.tmsCustomerPriceTransportType ?? []),
    cargoTypeOptions: computed(() => getDictMap.value.tmsCustomerPriceCargoType ?? []),
    vehicleTypeOptions: computed(() => getDictMap.value.tmsCustomerPriceVehicleType ?? []),
    vehicleLengthOptions: computed(() => getDictMap.value.tmsCustomerPriceVehicleLength ?? []),
    billingMethodOptions: computed(() => getDictMap.value.tmsCustomerPriceBillingMethod ?? []),
    baseItems: computed<FormItem[]>(() => [
      {
        label: '客户名称',
        key: 'customerId',
        type: 'select',
        api: fetchCustomerOptions,
        resultField: 'data',
        labelField: 'customerName',
        valueField: 'id',
        labelFn: formatCustomerOption,
        afterFetch: syncCustomerOptions,
        props: {
          clearable: true,
          filterable: true,
          placeholder: '请选择',
          onChange: handleCustomerChange
        }
      },
      {
        label: '客户编码',
        key: 'customerCode',
        type: 'input',
        props: { disabled: true, placeholder: '请输入内容' }
      },
      {
        label: '始发地',
        key: 'originRegionPath',
        type: 'cascader',
        api: fetchRegionOptions,
        labelField: 'name',
        valueField: 'name',
        childrenField: 'children',
        props: {
          class: 'w-full',
          clearable: true,
          filterable: true,
          placeholder: '请选择',
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
        label: '目的地',
        key: 'destinationRegionPath',
        type: 'cascader',
        api: fetchRegionOptions,
        labelField: 'name',
        valueField: 'name',
        childrenField: 'children',
        props: {
          class: 'w-full',
          clearable: true,
          filterable: true,
          placeholder: '请选择',
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
        label: '运输类型',
        key: 'transportType',
        type: 'select',
        props: { options: form.transportTypeOptions, clearable: true, placeholder: '请选择' }
      },
      {
        label: '货物类型',
        key: 'cargoType',
        type: 'select',
        props: { options: form.cargoTypeOptions, clearable: true, placeholder: '请选择' }
      }
    ]),
    shippingItems: computed<FormItem[]>(() => [
      {
        label: '联系人',
        key: 'shippingContactName',
        type: 'input',
        props: { maxlength: 50, placeholder: '请输入内容' }
      },
      {
        label: '联系电话',
        key: 'shippingContactPhone',
        type: 'input',
        props: { maxlength: 20, placeholder: '请输入内容' }
      },
      {
        label: '详细地址',
        key: 'shippingAddressDetail',
        type: 'input',
        props: { maxlength: 200, placeholder: '请输入内容' }
      }
    ]),
    receivingItems: computed<FormItem[]>(() => [
      {
        label: '联系人',
        key: 'receivingContactName',
        type: 'input',
        props: { maxlength: 50, placeholder: '请输入内容' }
      },
      {
        label: '联系电话',
        key: 'receivingContactPhone',
        type: 'input',
        props: { maxlength: 20, placeholder: '请输入内容' }
      },
      {
        label: '详细地址',
        key: 'receivingAddressDetail',
        type: 'input',
        props: { maxlength: 200, placeholder: '请输入内容' }
      }
    ]),
    vehicleItems: computed<FormItem[]>(() => [
      {
        label: '车型',
        key: 'vehicleType',
        type: 'select',
        props: { options: form.vehicleTypeOptions, clearable: true, placeholder: '请选择' }
      },
      {
        label: '车长',
        key: 'vehicleLength',
        type: 'select',
        props: { options: form.vehicleLengthOptions, clearable: true, placeholder: '请选择' }
      },
      {
        label: '用车数量',
        key: 'vehicleCount',
        type: 'number',
        props: countProps
      }
    ]),
    feeItems: computed<FormItem[]>(() => [
      {
        label: '计费方式',
        key: 'billingMethod',
        type: 'select',
        props: { options: form.billingMethodOptions, clearable: true, placeholder: '请选择' }
      },
      { label: '运输费', key: 'transportFee', type: 'number', props: moneyProps },
      { label: '保险费', key: 'insuranceFee', type: 'number', props: moneyProps },
      { label: '包装费', key: 'packageFee', type: 'number', props: moneyProps },
      { label: '装卸费', key: 'loadingFee', type: 'number', props: moneyProps },
      { label: '中转费', key: 'transferFee', type: 'number', props: moneyProps },
      { label: '燃油费', key: 'fuelFee', type: 'number', props: moneyProps },
      { label: '服务费', key: 'serviceFee', type: 'number', props: moneyProps },
      { label: '其他费用', key: 'otherFee', type: 'number', props: moneyProps },
      {
        label: '费用合计',
        key: 'totalFee',
        type: 'number',
        props: { ...moneyProps, disabled: true }
      }
    ]),
    paymentItems: computed<FormItem[]>(() => [
      { label: '现付', key: 'cashAmount', type: 'number', props: moneyProps },
      { label: '预付', key: 'prepaidAmount', type: 'number', props: moneyProps },
      { label: '到付', key: 'collectAmount', type: 'number', props: moneyProps },
      { label: '周期付', key: 'periodicAmount', type: 'number', props: moneyProps },
      {
        label: '付款合计',
        key: 'paymentTotal',
        type: 'number',
        props: { ...moneyProps, disabled: true }
      }
    ]),
    rules: computed<FormRules<CustomerPriceForm>>(() => ({
      customerId: [{ required: true, message: '请选择客户名称', trigger: 'change' }],
      originRegionPath: [
        { required: true, type: 'array', message: '请选择始发地', trigger: 'change' }
      ],
      destinationRegionPath: [
        { required: true, type: 'array', message: '请选择目的地', trigger: 'change' }
      ],
      transportType: [{ required: true, message: '请选择运输类型', trigger: 'change' }],
      shippingContactName: [{ required: true, message: '请输入发货联系人', trigger: 'blur' }],
      shippingContactPhone: [{ required: true, message: '请输入发货联系电话', trigger: 'blur' }],
      shippingAddressDetail: [{ required: true, message: '请输入发货详细地址', trigger: 'blur' }],
      receivingContactName: [{ required: true, message: '请输入收货联系人', trigger: 'blur' }],
      receivingContactPhone: [{ required: true, message: '请输入收货联系电话', trigger: 'blur' }],
      receivingAddressDetail: [{ required: true, message: '请输入收货详细地址', trigger: 'blur' }],
      billingMethod: [{ required: true, message: '请选择计费方式', trigger: 'change' }],
      transportFee: [{ required: true, message: '请输入运输费', trigger: 'blur' }]
    })),
    cargoColumns: computed<ColumnOption<CustomerPriceCargoItem>[]>(() => [
      { type: 'globalIndex', label: '序号', width: 70 },
      {
        prop: 'cargoName',
        label: '货物名称',
        minWidth: 180,
        formatter: (row) => (
          <ElInput v-model={row.cargoName} maxlength={80} placeholder="请输入内容" />
        )
      },
      {
        prop: 'quantity',
        label: '数量',
        width: 150,
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
        prop: 'unit',
        label: '单位',
        width: 150,
        formatter: (row) => (
          <ElSelect v-model={row.unit} class="w-full!" clearable filterable placeholder="请选择">
            {form.cargoUnitOptions.map((item) => (
              <ElOption key={item.value} label={item.label || item.name} value={item.value} />
            ))}
          </ElSelect>
        )
      },
      {
        prop: 'volumeM3',
        label: '体积（m³）',
        width: 170,
        formatter: (row) => (
          <ElInputNumber
            v-model={row.volumeM3}
            min={0}
            precision={3}
            controls={false}
            class="w-full!"
          />
        )
      },
      {
        prop: 'weightKg',
        label: '重量（kg）',
        width: 170,
        formatter: (row) => (
          <ElInputNumber
            v-model={row.weightKg}
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
        width: 100,
        fixed: 'right',
        formatter: (row) => <ArtButtonTable type="delete" onClick={() => removeCargoItem(row)} />
      }
    ]),
    cargoItems: computed(() => form.data.cargoItems ?? []),
    cargoSummary: computed(() => {
      const items = form.data.cargoItems ?? []
      return {
        quantity: roundNumber(
          items.reduce((sum, item) => sum + toNumber(item.quantity), 0),
          2
        ),
        volume: roundNumber(
          items.reduce((sum, item) => sum + toNumber(item.volumeM3), 0),
          3
        ),
        weight: roundNumber(
          items.reduce((sum, item) => sum + toNumber(item.weightKg), 0),
          2
        )
      }
    }),
    cargoQuantityText: computed(() => formatNumber(form.cargoSummary.quantity, 0)),
    cargoVolumeText: computed(() => formatNumber(form.cargoSummary.volume, 3)),
    cargoWeightText: computed(() => formatNumber(form.cargoSummary.weight, 2))
  })

  const feeFields: Array<keyof CustomerPriceForm> = [
    'transportFee',
    'insuranceFee',
    'packageFee',
    'loadingFee',
    'transferFee',
    'fuelFee',
    'serviceFee',
    'otherFee'
  ]

  const paymentFields: Array<keyof CustomerPriceForm> = [
    'cashAmount',
    'prepaidAmount',
    'collectAmount',
    'periodicAmount'
  ]

  function sumFields(fields: Array<keyof CustomerPriceForm>): number {
    return roundNumber(
      fields.reduce((sum, field) => sum + toNumber(form.data[field] as number), 0),
      2
    )
  }

  onMounted(async () => {
    page.loading = true
    try {
      await Promise.all([
        loadDetail(),
        ...dictCodes.map((code) => userStore.ensureDictLoaded(code))
      ])
      await nextTick()
      clearFormsValidate()
    } finally {
      page.loading = false
    }
  })

  watch(
    () => form.cargoSummary,
    (summary) => {
      const nextSummary = summary ?? createEmptyCargoSummary()
      form.data.cargoQuantityTotal = nextSummary.quantity
      form.data.cargoVolumeTotal = nextSummary.volume
      form.data.cargoWeightTotal = nextSummary.weight
    },
    { immediate: true }
  )

  watch(
    () => feeFields.map((field) => form.data[field]),
    () => {
      form.data.totalFee = sumFields(feeFields)
    },
    { immediate: true }
  )

  watch(
    () => paymentFields.map((field) => form.data[field]),
    () => {
      form.data.paymentTotal = sumFields(paymentFields)
    },
    { immediate: true }
  )

  async function loadDetail(): Promise<void> {
    if (!isEdit.value) return

    const id = String(route.params.id || '')
    const { data } = await fetchCustomerPriceDetail(id)
    if (!data) return

    replaceForm({
      ...createInitialForm(),
      ...data,
      customerCode: data.customer?.customerCode ?? '',
      originRegionPath: splitRegionPath(data.originRegion),
      destinationRegionPath: splitRegionPath(data.destinationRegion),
      cargoItems: data.cargoItems?.length ? data.cargoItems : [createInitialCargoItem()]
    })
  }

  function replaceForm(nextForm: CustomerPriceForm): void {
    Object.assign(form.data, createInitialForm(), cloneDeep(nextForm))
  }

  function getResponseData<TRecord>(result: unknown): TRecord[] {
    if (!result || typeof result !== 'object') return []
    const data = (result as { data?: TRecord[] }).data
    return Array.isArray(data) ? data : []
  }

  function syncCustomerOptions(result: unknown): unknown {
    form.customerOptions = getResponseData<CustomerOption>(result)
    syncCustomerCode(form.data.customerId)
    return result
  }

  function formatCustomerOption(option: Record<string, unknown>): string {
    const customer = option as unknown as CustomerOption
    return customer.customerCode
      ? `${customer.customerName}（${customer.customerCode}）`
      : customer.customerName
  }

  function handleCustomerChange(customerId?: string): void {
    syncCustomerCode(customerId || '')
  }

  function syncCustomerCode(customerId?: string): void {
    if (!customerId) {
      form.data.customerCode = ''
      form.data.customer = null
      return
    }
    const customer = form.customerOptions.find((item) => item.id === customerId)
    form.data.customerCode =
      customer?.customerCode ||
      (form.data.customer?.id === customerId ? form.data.customer.customerCode : '') ||
      ''
  }

  function addCargoItem(): void {
    form.data.cargoItems = [...(form.data.cargoItems ?? []), createInitialCargoItem()]
  }

  function removeCargoItem(row: CustomerPriceCargoItem): void {
    const rows = form.data.cargoItems ?? []
    if (rows.length <= 1) {
      form.data.cargoItems = [createInitialCargoItem()]
      return
    }
    form.data.cargoItems = rows.filter((item) => item !== row)
  }

  async function validateForms(): Promise<boolean> {
    const formRefs = [
      baseFormRef,
      shippingFormRef,
      receivingFormRef,
      vehicleFormRef,
      feeFormRef,
      paymentFormRef
    ]

    for (const item of formRefs) {
      try {
        await item.value?.validate()
      } catch {
        await nextTick()
        focusFirstInvalidField()
        return false
      }
    }

    return true
  }

  function clearFormsValidate(): void {
    baseFormRef.value?.clearValidate()
    shippingFormRef.value?.clearValidate()
    receivingFormRef.value?.clearValidate()
    vehicleFormRef.value?.clearValidate()
    feeFormRef.value?.clearValidate()
    paymentFormRef.value?.clearValidate()
  }

  function focusFirstInvalidField(): void {
    const invalidItem = pageRef.value?.querySelector<HTMLElement>('.el-form-item.is-error')
    if (!invalidItem) return

    invalidItem.scrollIntoView({ behavior: 'smooth', block: 'center' })
    invalidItem
      .querySelector<HTMLElement>(
        'input:not([type="hidden"]):not([disabled]), textarea:not([disabled]), button:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )
      ?.focus()
  }

  function normalizePayload(): CustomerPrice {
    const raw = cloneDeep(toRaw(form.data))
    const payload = omit(raw, [
      'tenantId',
      'customer',
      'customerCode',
      'originRegionPath',
      'destinationRegionPath',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as CustomerPrice

    payload.originRegion = joinRegionPath(raw.originRegionPath)
    payload.destinationRegion = joinRegionPath(raw.destinationRegionPath)
    payload.cargoItems = normalizeCargoItems(raw.cargoItems)
    payload.cargoQuantityTotal = form.cargoSummary.quantity
    payload.cargoVolumeTotal = form.cargoSummary.volume
    payload.cargoWeightTotal = form.cargoSummary.weight
    payload.vehicleType = normalizeText(raw.vehicleType)
    payload.vehicleLength = normalizeText(raw.vehicleLength)
    payload.vehicleCount = normalizeNullableNumber(raw.vehicleCount)
    payload.cargoType = normalizeText(raw.cargoType)
    payload.remark = normalizeText(raw.remark)
    payload.transportFee = normalizeMoney(raw.transportFee)
    payload.insuranceFee = normalizeMoney(raw.insuranceFee)
    payload.packageFee = normalizeMoney(raw.packageFee)
    payload.loadingFee = normalizeMoney(raw.loadingFee)
    payload.transferFee = normalizeMoney(raw.transferFee)
    payload.fuelFee = normalizeMoney(raw.fuelFee)
    payload.serviceFee = normalizeMoney(raw.serviceFee)
    payload.otherFee = normalizeMoney(raw.otherFee)
    payload.totalFee = sumFields(feeFields)
    payload.cashAmount = normalizeMoney(raw.cashAmount)
    payload.prepaidAmount = normalizeMoney(raw.prepaidAmount)
    payload.collectAmount = normalizeMoney(raw.collectAmount)
    payload.periodicAmount = normalizeMoney(raw.periodicAmount)
    payload.paymentTotal = sumFields(paymentFields)
    payload.shippingContactName = normalizeRequiredText(raw.shippingContactName)
    payload.shippingContactPhone = normalizeRequiredText(raw.shippingContactPhone)
    payload.shippingAddressDetail = normalizeRequiredText(raw.shippingAddressDetail)
    payload.receivingContactName = normalizeRequiredText(raw.receivingContactName)
    payload.receivingContactPhone = normalizeRequiredText(raw.receivingContactPhone)
    payload.receivingAddressDetail = normalizeRequiredText(raw.receivingAddressDetail)

    return payload
  }

  function normalizeCargoItems(
    items: CustomerPriceCargoItem[] | undefined
  ): CustomerPriceCargoItem[] {
    return (items ?? [])
      .map((item) => ({
        cargoName: normalizeText(item.cargoName),
        quantity: normalizeNullableNumber(item.quantity),
        unit: normalizeText(item.unit),
        volumeM3: normalizeNullableNumber(item.volumeM3),
        weightKg: normalizeNullableNumber(item.weightKg)
      }))
      .filter(
        (item) => item.cargoName || item.quantity || item.unit || item.volumeM3 || item.weightKg
      )
  }

  async function handleSave(): Promise<void> {
    const valid = await validateForms()
    if (!valid) return

    page.saving = true
    try {
      const payload = normalizePayload()
      if (form.data.id) await editCustomerPrice(payload)
      else await addCustomerPrice(payload)
      goBack()
    } catch {
      // API 层已经展示错误信息，当前页保持编辑状态。
    } finally {
      page.saving = false
    }
  }

  function goBack(): void {
    void router.push({ name: 'TmsCustomerPrice' })
  }

  function splitRegionPath(region?: string | null): string[] {
    return String(region ?? '')
      .split('/')
      .map((item) => item.trim())
      .filter(Boolean)
  }

  function joinRegionPath(regionPath?: string[]): string {
    return (regionPath ?? []).filter(Boolean).join('/')
  }

  function normalizeText(value?: string | null): string | null {
    const text = String(value ?? '').trim()
    return text || null
  }

  function normalizeRequiredText(value?: string | null): string {
    return String(value ?? '').trim()
  }

  function normalizeNullableNumber(value?: number | string | null): number | null {
    if (value === null || value === undefined || value === '') return null
    const numberValue = Number(value)
    return Number.isNaN(numberValue) ? null : numberValue
  }

  function normalizeMoney(value?: number | string | null): number {
    const numberValue = normalizeNullableNumber(value)
    return roundNumber(numberValue ?? 0, 2)
  }
</script>

<style scoped lang="scss">
  .customer-price-edit {
    min-height: 100%;
    padding: 8px;
    background: var(--art-main-bg-color);

    &__content {
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    &__section {
      padding: 18px 20px 24px;
    }

    &__section-header {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 14px;
    }

    &__contact-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 16px;
      margin-top: 8px;
    }

    &__contact-panel {
      min-width: 0;
    }

    &__contact-title {
      display: flex;
      align-items: center;
      height: 40px;
      margin: 0 0 12px;
      padding-left: 0;

      &::after {
        flex: 1;
        height: 100%;
        content: '';
      }

      span {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 40px;
        height: 40px;
        font-size: 18px;
        font-weight: 600;
        color: #fff;
        border-radius: 4px;
      }

      &--send {
        &::after {
          background: #fff4ec;
        }

        span {
          background: #ff8a2a;
        }
      }

      &--receive {
        &::after {
          background: #eafaf1;
        }

        span {
          background: #2fca72;
        }
      }
    }

    &__cargo-summary {
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 48px;
      padding: 0 12px;
      color: var(--art-text-gray-600);
      background: var(--el-fill-color-lighter);

      div {
        display: flex;
        flex-wrap: wrap;
        gap: 20px;
        justify-content: flex-end;
      }
    }

    &__footer {
      position: sticky;
      bottom: 0;
      z-index: 5;
      display: flex;
      gap: 10px;
      justify-content: flex-end;
      margin-top: 16px;
      padding: 16px 20px;
    }

    :deep(.customer-price-edit__form) {
      padding-right: 0;
      padding-left: 0;
    }

    :deep(.art-table__cell-content) {
      width: 100%;
    }

    :deep(.art-table__cell-value) {
      width: 100%;
    }
  }

  @media (max-width: 900px) {
    .customer-price-edit {
      &__contact-grid {
        grid-template-columns: 1fr;
      }

      &__cargo-summary {
        align-items: flex-start;
        flex-direction: column;
        gap: 8px;
        padding: 12px;

        div {
          justify-content: flex-start;
        }
      }
    }
  }
</style>
