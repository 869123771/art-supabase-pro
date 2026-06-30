<template>
  <div ref="pageRef" class="order-open" v-loading="page.loading">
    <div class="order-open__header art-card-xs">
      <div class="order-open__badge">
        <span>运单号：{{ form.data.orderNo }}</span>
        <span>货号：{{ form.data.cargoNo }}</span>
      </div>
      <div class="order-open__title">货 物 运 输 单</div>
      <div class="order-open__time">
        <ArtSvgIcon icon="ri:calendar-line" />
        <span>{{ page.nowText }}</span>
      </div>
    </div>

    <section class="order-open__section order-open__section--compact art-card-xs">
      <ArtForm
        ref="stationFormRef"
        v-model="form.data"
        :items="form.stationItems"
        :rules="form.rules"
        :span="6"
        :gutter="24"
        label-width="84px"
        root-class="order-open__form"
        :show-reset="false"
        :show-submit="false"
      />
    </section>

    <section class="order-open__section art-card-xs">
      <div class="order-open__contact-grid">
        <div class="order-open__contact-panel">
          <div class="order-open__contact-heading">
            <span class="order-open__contact-mark order-open__contact-mark--send">寄</span>
            <h3>发货人信息</h3>
            <ElButton size="small" @click="openCustomerSelector('shipping')">选择客户</ElButton>
          </div>
          <ArtForm
            ref="shippingFormRef"
            v-model="form.data"
            :items="form.shippingItems"
            :rules="form.rules"
            :span="24"
            label-width="88px"
            root-class="order-open__form"
            :show-reset="false"
            :show-submit="false"
          />
        </div>

        <div class="order-open__swap">
          <ElButton circle text @click="swapContacts">
            <ArtSvgIcon icon="ri:arrow-left-right-line" />
          </ElButton>
        </div>

        <div class="order-open__contact-panel">
          <div class="order-open__contact-heading">
            <span class="order-open__contact-mark order-open__contact-mark--receive">收</span>
            <h3>收货人信息</h3>
            <ElButton size="small" @click="openCustomerSelector('receiving')">选择客户</ElButton>
          </div>
          <ArtForm
            ref="receivingFormRef"
            v-model="form.data"
            :items="form.receivingItems"
            :rules="form.rules"
            :span="24"
            label-width="88px"
            root-class="order-open__form"
            :show-reset="false"
            :show-submit="false"
          />
        </div>
      </div>
    </section>

    <section class="order-open__section art-card-xs">
      <div class="order-open__section-header">
        <ArtSectionTitle :show-line="false">货品信息</ArtSectionTitle>
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
      <div class="order-open__cargo-summary">
        <span>总数量：{{ form.cargoQuantityText }}</span>
        <span>总重量：{{ form.cargoWeightText }}kg</span>
        <span>总体积：{{ form.cargoVolumeText }}方</span>
      </div>
    </section>

    <section class="order-open__section art-card-xs">
      <ArtSectionTitle>运费设置</ArtSectionTitle>
      <ArtForm
        ref="feeFormRef"
        v-model="form.data"
        :items="form.feeItems"
        :span="5"
        :gutter="22"
        label-width="80px"
        root-class="order-open__form"
        :show-reset="false"
        :show-submit="false"
      />
    </section>

    <section class="order-open__section art-card-xs">
      <ArtSectionTitle>付款设置</ArtSectionTitle>
      <ArtForm
        ref="paymentFormRef"
        v-model="form.data"
        :items="form.paymentItems"
        :rules="form.rules"
        :span="5"
        :gutter="22"
        label-width="88px"
        root-class="order-open__form"
        :show-reset="false"
        :show-submit="false"
      />
    </section>

    <section class="order-open__section art-card-xs">
      <ArtSectionTitle>其他信息</ArtSectionTitle>
      <ArtForm
        ref="otherFormRef"
        v-model="form.data"
        :items="form.otherItems"
        :span="8"
        :gutter="22"
        label-width="80px"
        root-class="order-open__form"
        :show-reset="false"
        :show-submit="false"
      />
      <div class="order-open__upload-row">
        <span>图片上传</span>
        <ArtUploadImage
          v-model="form.data.imageUrls"
          title="上传图片"
          :size="104"
          :limit="3"
          multiple
        />
      </div>
    </section>

    <div class="order-open__footer art-card-xs">
      <div class="order-open__footer-total">
        <span>总运费：</span>
        <strong>￥{{ form.totalFeeText }}</strong>
        <ElPopover
          placement="top-start"
          width="280"
          trigger="click"
          popper-class="order-open-fee-popover"
        >
          <template #reference>
            <ElButton link type="primary">明细 <ArtSvgIcon icon="ri:arrow-down-s-line" /></ElButton>
          </template>
          <div class="order-open__fee-detail">
            <div class="order-open__fee-detail-title">
              <span>预估费用明细</span>
            </div>
            <p>实际费用按开单员揽收时称重或测量体积计算，运费四舍五入取整。</p>
            <dl>
              <dt>基础运费</dt>
              <dd>￥{{ formatNumber(form.data.transportFee) }}</dd>
              <dt>附加服务费</dt>
              <dd>￥{{ formatNumber(form.extraServiceFee) }}</dd>
              <dt>计费类型</dt>
              <dd>{{ form.paymentMethodLabel }}</dd>
              <dt>重量</dt>
              <dd>{{ form.cargoWeightText }}kg</dd>
            </dl>
          </div>
        </ElPopover>
        <ElButton type="info" link>查看计费标准</ElButton>
      </div>

      <div class="order-open__footer-actions">
        <ElButton size="large" :loading="page.saving" @click="handleSaveOnly">仅开单</ElButton>
        <ElButton size="large" type="primary" @click="openPrintDialog('waybill')"
          >打印运单</ElButton
        >
        <ElButton size="large" type="primary" @click="openPrintDialog('label')">打印标签</ElButton>
        <ElButton size="large" type="primary" @click="handleDoublePrint">双打</ElButton>
      </div>
    </div>

    <CustomerSelectorDialog ref="customerDialogRef" @select="handleCustomerSelect" />
    <PrintCountDialog ref="printDialogRef" @confirm="handlePrintConfirm" />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { useDateFormat, useNow } from '@vueuse/core'
  import { cloneDeep, isNil, omit, round, toNumber as lodashToNumber, trim } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElInput, ElInputNumber, ElMessage, ElOption, ElSelect } from 'element-plus'
  import { Plus } from '@element-plus/icons-vue'
  import dayjs from 'dayjs'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { addOrder, fetchStationOptions } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import CustomerSelectorDialog from './modules/customer-selector-dialog.vue'
  import PrintCountDialog from './modules/print-count-dialog.vue'

  defineOptions({ name: 'TmsOrderOpen' })

  type OrderRecord = Api.Tms.Order.OrderRecord
  type CargoItem = Api.Tms.Order.CargoItem
  type CustomerItem = Api.Tms.Order.CustomerSelectorItem
  type StationOption = Api.Tms.Order.StationOption
  type SelectorMode = 'shipping' | 'receiving'
  type StationMode = 'origin' | 'destination' | 'transfer'
  type PrintKind = 'waybill' | 'label'
  type ContactPatch = Partial<
    Pick<
      OrderForm,
      | 'shippingCustomerId'
      | 'shippingContactName'
      | 'shippingContactPhone'
      | 'shippingAddressDetail'
      | 'receivingCustomerId'
      | 'receivingContactName'
      | 'receivingContactPhone'
      | 'receivingAddressDetail'
    >
  >

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface CustomerSelectorExpose {
    handleOpen: (mode: SelectorMode) => Promise<void>
  }

  interface PrintDialogExpose {
    handleOpen: (data: { kind: PrintKind; cargoQuantity: number }) => Promise<void>
  }

  interface PageGroup {
    loading: boolean
    saving: boolean
    nowText: ComputedRef<string>
  }

  interface CargoSummary {
    quantity: number
    weight: number
    volume: number
  }

  type OrderForm = OrderRecord & {
    imageUrls: string[]
  }

  interface FormGroup {
    data: OrderForm
    stationCaches: Record<StationMode, StationOption[]>
    deliveryMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    paymentMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    transportModeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    cargoUnitOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    stationItems: ComputedRef<FormItem[]>
    shippingItems: ComputedRef<FormItem[]>
    receivingItems: ComputedRef<FormItem[]>
    feeItems: ComputedRef<FormItem[]>
    paymentItems: ComputedRef<FormItem[]>
    otherItems: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<OrderForm>>
    cargoColumns: ComputedRef<ColumnOption<CargoItem>[]>
    cargoItems: ComputedRef<CargoItem[]>
    cargoSummary: ComputedRef<CargoSummary>
    extraServiceFee: ComputedRef<number>
    paymentMethodLabel: ComputedRef<string>
    cargoQuantityText: ComputedRef<string>
    cargoWeightText: ComputedRef<string>
    cargoVolumeText: ComputedRef<string>
    totalFeeText: ComputedRef<string>
  }

  const pageRef = ref<HTMLElement>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const stationFormRef = ref<FormExpose>()
  const shippingFormRef = ref<FormExpose>()
  const receivingFormRef = ref<FormExpose>()
  const feeFormRef = ref<FormExpose>()
  const paymentFormRef = ref<FormExpose>()
  const otherFormRef = ref<FormExpose>()
  const customerDialogRef = ref<CustomerSelectorExpose>()
  const printDialogRef = ref<PrintDialogExpose>()

  const dictCodes = [
    'tmsOrderDeliveryMethod',
    'tmsOrderPaymentMethod',
    'tmsOrderTransportMode',
    'tmsCargoUnit'
  ]

  const moneyProps = {
    min: 0,
    precision: 2,
    controlsPosition: 'right' as const,
    class: '!w-full'
  }

  const countProps = {
    min: 0,
    precision: 0,
    controlsPosition: 'right' as const,
    class: '!w-full'
  }

  const page = reactive<PageGroup>({
    loading: false,
    saving: false,
    nowText: useDateFormat(useNow({ interval: 1000 }), 'YYYY/MM/DD HH:mm:ss')
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    stationCaches: {
      origin: [],
      destination: [],
      transfer: []
    },
    deliveryMethodOptions: computed(() => getDictMap.value.tmsOrderDeliveryMethod ?? []),
    paymentMethodOptions: computed(() => getDictMap.value.tmsOrderPaymentMethod ?? []),
    transportModeOptions: computed(() => getDictMap.value.tmsOrderTransportMode ?? []),
    cargoUnitOptions: computed(() => getDictMap.value.tmsCargoUnit ?? []),
    stationItems: computed<FormItem[]>(() => [
      {
        label: '发货站',
        key: 'originStationId',
        type: 'select',
        api: fetchStationOptions,
        resultField: 'data',
        labelField: 'stationName',
        valueField: 'id',
        labelFn: formatStationOption,
        beforeFetch: (params) => ({ ...params, stationType: 'shipping' }),
        afterFetch: (result) => syncStationOptions('origin', result),
        props: {
          filterable: true,
          clearable: true,
          placeholder: '请选择',
          onChange: (value: string) => handleStationChange('origin', value)
        }
      },
      {
        label: '到货站',
        key: 'destinationStationId',
        type: 'select',
        api: fetchStationOptions,
        resultField: 'data',
        labelField: 'stationName',
        valueField: 'id',
        labelFn: formatStationOption,
        beforeFetch: (params) => ({ ...params, stationType: 'arrival' }),
        afterFetch: (result) => syncStationOptions('destination', result),
        props: {
          filterable: true,
          clearable: true,
          placeholder: '请选择',
          onChange: (value: string) => handleStationChange('destination', value)
        }
      },
      {
        label: '中转站',
        key: 'transferStationId',
        type: 'select',
        api: fetchStationOptions,
        resultField: 'data',
        labelField: 'stationName',
        valueField: 'id',
        labelFn: formatStationOption,
        beforeFetch: (params) => ({ ...params, stationType: 'transfer' }),
        afterFetch: (result) => syncStationOptions('transfer', result),
        props: {
          filterable: true,
          clearable: true,
          placeholder: '经由',
          onChange: (value: string) => handleStationChange('transfer', value)
        }
      },
      {
        label: '配送方式',
        key: 'deliveryMethod',
        type: 'select',
        props: { options: form.deliveryMethodOptions, placeholder: '请选择' }
      }
    ]),
    shippingItems: computed<FormItem[]>(() => [
      {
        label: '姓名',
        key: 'shippingContactName',
        type: 'input',
        props: { maxlength: 50, placeholder: '请输入发货人姓名' }
      },
      {
        label: '手机号',
        key: 'shippingContactPhone',
        type: 'input',
        props: { maxlength: 20, placeholder: '请输入发货人手机号' }
      },
      {
        label: '发货地址',
        key: 'shippingAddressDetail',
        type: 'input',
        props: { maxlength: 200, placeholder: '请输入发货地址' }
      }
    ]),
    receivingItems: computed<FormItem[]>(() => [
      {
        label: '姓名',
        key: 'receivingContactName',
        type: 'input',
        props: { maxlength: 50, placeholder: '请输入收货人姓名' }
      },
      {
        label: '手机号',
        key: 'receivingContactPhone',
        type: 'input',
        props: { maxlength: 20, placeholder: '请输入收货人手机号' }
      },
      {
        label: '收货地址',
        key: 'receivingAddressDetail',
        type: 'input',
        props: { maxlength: 200, placeholder: '请输入收货地址，配送上门请输入详细地址' }
      }
    ]),
    feeItems: computed<FormItem[]>(() => [
      { label: '运费', key: 'transportFee', type: 'number', props: moneyProps },
      { label: '配送费', key: 'deliveryFee', type: 'number', props: moneyProps },
      { label: '卸货费', key: 'unloadingFee', type: 'number', props: moneyProps },
      { label: '回款费', key: 'collectPaymentFee', type: 'number', props: moneyProps },
      { label: '中转费', key: 'transferFee', type: 'number', props: moneyProps },
      { label: '声明价值', key: 'declaredValue', type: 'number', props: moneyProps },
      { label: '保费', key: 'insuranceFee', type: 'number', props: moneyProps },
      { label: '包装费', key: 'packageFee', type: 'number', props: moneyProps },
      { label: '其他费用', key: 'otherFee', type: 'number', props: moneyProps }
    ]),
    paymentItems: computed<FormItem[]>(() => [
      {
        label: '付款方式',
        key: 'paymentMethod',
        type: 'radioGroup',
        span: 24,
        props: { options: form.paymentMethodOptions }
      },
      { label: '现付', key: 'cashAmount', type: 'number', props: moneyProps },
      { label: '到付', key: 'collectAmount', type: 'number', props: moneyProps },
      { label: '月结', key: 'monthlyAmount', type: 'number', props: moneyProps },
      { label: '代收货款', key: 'codAmount', type: 'number', props: moneyProps },
      { label: '手续费', key: 'handlingFee', type: 'number', props: moneyProps }
    ]),
    otherItems: computed<FormItem[]>(() => [
      {
        label: '运输方式',
        key: 'transportMode',
        type: 'select',
        props: { options: form.transportModeOptions, clearable: true, placeholder: '请选择' }
      },
      {
        label: '订单备注',
        key: 'orderRemark',
        type: 'input',
        span: 16,
        props: { maxlength: 200, placeholder: '请输入订单备注' }
      }
    ]),
    rules: computed<FormRules<OrderForm>>(() => ({
      originStationId: [{ required: true, message: '请选择发货站', trigger: 'change' }],
      destinationStationId: [{ required: true, message: '请选择到货站', trigger: 'change' }],
      deliveryMethod: [{ required: true, message: '请选择配送方式', trigger: 'change' }],
      shippingContactName: [{ required: true, message: '请输入发货人姓名', trigger: 'blur' }],
      shippingContactPhone: [{ required: true, message: '请输入发货人手机号', trigger: 'blur' }],
      shippingAddressDetail: [{ required: true, message: '请输入发货地址', trigger: 'blur' }],
      receivingContactName: [{ required: true, message: '请输入收货人姓名', trigger: 'blur' }],
      receivingContactPhone: [{ required: true, message: '请输入收货人手机号', trigger: 'blur' }],
      receivingAddressDetail: [{ required: true, message: '请输入收货地址', trigger: 'blur' }],
      paymentMethod: [{ required: true, message: '请选择付款方式', trigger: 'change' }]
    })),
    cargoColumns: computed<ColumnOption<CargoItem>[]>(() => [
      { type: 'globalIndex', label: '序号', width: 58 },
      {
        prop: 'cargoName',
        label: '货物名称',
        minWidth: 180,
        formatter: (row) => (
          <ElInput v-model={row.cargoName} maxlength={80} placeholder="请输入货品名称" />
        )
      },
      {
        prop: 'packageType',
        label: '包装',
        width: 150,
        formatter: (row) => (
          <ElSelect v-model={row.packageType} class="w-full!" clearable placeholder="请选择">
            {form.cargoUnitOptions.map((item) => (
              <ElOption key={item.value} label={item.label || item.name} value={item.value} />
            ))}
          </ElSelect>
        )
      },
      {
        prop: 'quantity',
        label: '数量（箱/袋）',
        width: 150,
        formatter: (row) => (
          <ElInputNumber v-model={row.quantity} {...countProps} controls={false} />
        )
      },
      {
        prop: 'weightKg',
        label: '重量(kg)',
        width: 150,
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
        prop: 'volumeM3',
        label: '体积(方)',
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
        prop: 'operation',
        label: '操作',
        width: 90,
        formatter: (row) => <ArtButtonTable type="delete" onClick={() => removeCargoItem(row)} />
      }
    ]),
    cargoItems: computed(() => form.data.cargoItems ?? []),
    cargoSummary: computed(() => ({
      quantity: round(
        (form.data.cargoItems ?? []).reduce((sum, item) => sum + numericValue(item.quantity), 0),
        0
      ),
      weight: round(
        (form.data.cargoItems ?? []).reduce((sum, item) => sum + numericValue(item.weightKg), 0),
        2
      ),
      volume: round(
        (form.data.cargoItems ?? []).reduce((sum, item) => sum + numericValue(item.volumeM3), 0),
        3
      )
    })),
    extraServiceFee: computed(() =>
      round(
        numericValue(form.data.deliveryFee) +
          numericValue(form.data.unloadingFee) +
          numericValue(form.data.collectPaymentFee) +
          numericValue(form.data.transferFee) +
          numericValue(form.data.insuranceFee) +
          numericValue(form.data.packageFee) +
          numericValue(form.data.otherFee),
        2
      )
    ),
    paymentMethodLabel: computed(() =>
      getDictLabel(form.paymentMethodOptions, form.data.paymentMethod)
    ),
    cargoQuantityText: computed(() => formatNumber(form.cargoSummary.quantity, 0)),
    cargoWeightText: computed(() => formatNumber(form.cargoSummary.weight, 2)),
    cargoVolumeText: computed(() => formatNumber(form.cargoSummary.volume, 3)),
    totalFeeText: computed(() => formatNumber(form.data.totalFee, 2))
  })

  const feeFields: Array<keyof OrderForm> = [
    'transportFee',
    'deliveryFee',
    'unloadingFee',
    'collectPaymentFee',
    'transferFee',
    'insuranceFee',
    'packageFee',
    'otherFee'
  ]

  const paymentFields: Array<keyof OrderForm> = [
    'cashAmount',
    'collectAmount',
    'monthlyAmount',
    'codAmount',
    'handlingFee'
  ]

  onMounted(async () => {
    page.loading = true
    try {
      await Promise.all(dictCodes.map((code) => userStore.ensureDictLoaded(code)))
      fillDefaultOptions()
      clearFormsValidate()
    } finally {
      page.loading = false
    }
  })

  watch(
    () => form.cargoSummary,
    (summary) => {
      Object.assign(form.data, {
        cargoQuantityTotal: summary.quantity,
        cargoWeightTotal: summary.weight,
        cargoVolumeTotal: summary.volume
      })
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

  function createInitialForm(): OrderForm {
    return {
      orderNo: createOrderNo(),
      cargoNo: createCargoNo(),
      orderStatus: 'created',
      originStationId: null,
      destinationStationId: null,
      transferStationId: null,
      originStation: '',
      destinationStation: '',
      transferStation: '',
      deliveryMethod: 'door',
      shippingCustomerId: null,
      receivingCustomerId: null,
      shippingContactName: '',
      shippingContactPhone: '',
      shippingAddressDetail: '',
      receivingContactName: '',
      receivingContactPhone: '',
      receivingAddressDetail: '',
      cargoItems: [createInitialCargoItem()],
      cargoQuantityTotal: 0,
      cargoWeightTotal: 0,
      cargoVolumeTotal: 0,
      transportFee: 0,
      deliveryFee: 0,
      unloadingFee: 0,
      collectPaymentFee: 0,
      transferFee: 0,
      declaredValue: 0,
      insuranceFee: 0,
      packageFee: 0,
      otherFee: 0,
      totalFee: 0,
      paymentMethod: 'collect',
      cashAmount: 0,
      collectAmount: 0,
      monthlyAmount: 0,
      codAmount: 0,
      handlingFee: 0,
      paymentTotal: 0,
      transportMode: 'road',
      orderRemark: '',
      imageUrls: []
    }
  }

  function createInitialCargoItem(): CargoItem {
    return {
      cargoName: '',
      packageType: '',
      quantity: null,
      unit: '',
      weightKg: null,
      volumeM3: null
    }
  }

  function createOrderNo(): string {
    return `NGSJ${dayjs().format('MMDD')}-${Math.floor(100 + Math.random() * 900)}`
  }

  function createCargoNo(): string {
    return `A${dayjs().format('M-D')}-${Math.floor(10 + Math.random() * 90)}`
  }

  function fillDefaultOptions(): void {
    const patch: Partial<OrderForm> = {}
    if (!form.data.deliveryMethod && form.deliveryMethodOptions.length) {
      patch.deliveryMethod = form.deliveryMethodOptions[0]?.value || ''
    }
    if (!form.data.paymentMethod && form.paymentMethodOptions.length) {
      patch.paymentMethod = form.paymentMethodOptions[0]?.value || ''
    }
    if (!form.data.transportMode && form.transportModeOptions.length) {
      patch.transportMode = form.transportModeOptions[0]?.value || ''
    }
    Object.assign(form.data, patch)
  }

  function syncStationOptions(mode: StationMode, result: unknown): unknown {
    const data = Array.isArray(result)
      ? result
      : ((result as { data?: StationOption[] })?.data ?? [])
    const options = data as StationOption[]
    form.stationCaches[mode] = options
    updateStationSnapshot(mode)
    return result
  }

  function formatStationOption(option: Record<string, unknown>): string {
    const station = option as unknown as StationOption
    return station.regionCode
      ? `${station.stationName}（${station.regionCode}）`
      : station.stationName
  }

  function findStationOption(
    mode: StationMode,
    stationId?: string | null
  ): StationOption | undefined {
    if (!stationId) return undefined
    return form.stationCaches[mode].find((item) => item.id === stationId)
  }

  function handleStationChange(mode: StationMode, value?: string | null): void {
    const stationIdKeyMap: Record<
      StationMode,
      'originStationId' | 'destinationStationId' | 'transferStationId'
    > = {
      origin: 'originStationId',
      destination: 'destinationStationId',
      transfer: 'transferStationId'
    }
    Object.assign(form.data, { [stationIdKeyMap[mode]]: value || null })
    updateStationSnapshot(mode)
  }

  function updateStationSnapshot(mode: StationMode): void {
    const patchMap: Record<StationMode, Partial<OrderForm>> = {
      origin: {
        originStation: findStationOption('origin', form.data.originStationId)?.stationName || ''
      },
      destination: {
        destinationStation:
          findStationOption('destination', form.data.destinationStationId)?.stationName || ''
      },
      transfer: {
        transferStation:
          findStationOption('transfer', form.data.transferStationId)?.stationName || ''
      }
    }
    Object.assign(form.data, patchMap[mode])
  }

  function addCargoItem(): void {
    form.data.cargoItems = [...(form.data.cargoItems ?? []), createInitialCargoItem()]
  }

  function removeCargoItem(row: CargoItem): void {
    const rows = form.data.cargoItems ?? []
    if (rows.length <= 1) {
      form.data.cargoItems = [createInitialCargoItem()]
      return
    }
    form.data.cargoItems = rows.filter((item) => item !== row)
  }

  function openCustomerSelector(mode: SelectorMode): void {
    void customerDialogRef.value?.handleOpen(mode)
  }

  function handleCustomerSelect(mode: SelectorMode, row: CustomerItem): void {
    const address = [row.region, row.addressDetail].filter(Boolean).join(' ')
    const contactName = row.contactName || row.customerName
    const patchMap: Record<SelectorMode, ContactPatch> = {
      shipping: {
        shippingCustomerId: row.id,
        shippingContactName: contactName,
        shippingContactPhone: row.contactPhone || '',
        shippingAddressDetail: address
      },
      receiving: {
        receivingCustomerId: row.id,
        receivingContactName: contactName,
        receivingContactPhone: row.contactPhone || '',
        receivingAddressDetail: address
      }
    }

    Object.assign(form.data, patchMap[mode])
  }

  function swapContacts(): void {
    const shipping = {
      id: form.data.shippingCustomerId,
      name: form.data.shippingContactName,
      phone: form.data.shippingContactPhone,
      address: form.data.shippingAddressDetail
    }

    Object.assign(form.data, {
      shippingCustomerId: form.data.receivingCustomerId,
      shippingContactName: form.data.receivingContactName,
      shippingContactPhone: form.data.receivingContactPhone,
      shippingAddressDetail: form.data.receivingAddressDetail,
      receivingCustomerId: shipping.id,
      receivingContactName: shipping.name,
      receivingContactPhone: shipping.phone,
      receivingAddressDetail: shipping.address
    })
  }

  async function validateForms(): Promise<boolean> {
    const formRefs = [stationFormRef, shippingFormRef, receivingFormRef, paymentFormRef]
    for (const item of formRefs) {
      try {
        await item.value?.validate()
      } catch {
        await nextTick()
        focusFirstInvalidField()
        return false
      }
    }

    const hasCargoName = (form.data.cargoItems ?? []).some((item) => textValue(item.cargoName))
    if (!hasCargoName) {
      ElMessage.warning('请至少填写一条货物名称')
      return false
    }

    return true
  }

  async function handleSaveOnly(): Promise<void> {
    const valid = await validateForms()
    if (!valid) return

    page.saving = true
    try {
      await addOrder(normalizePayload())
      resetForm()
    } catch {
      // API 层已提示错误，页面保留当前输入。
    } finally {
      page.saving = false
    }
  }

  function openPrintDialog(kind: PrintKind): void {
    void printDialogRef.value?.handleOpen({
      kind,
      cargoQuantity: Math.max(1, form.cargoSummary.quantity)
    })
  }

  function handleDoublePrint(): void {
    openPrintDialog('waybill')
  }

  function handlePrintConfirm(kind: PrintKind, count: number): void {
    ElMessage.success(`${kind === 'waybill' ? '运单' : '标签'}打印数量：${count}`)
  }

  function resetForm(): void {
    Object.assign(form.data, createInitialForm())
    fillDefaultOptions()
    void nextTick(clearFormsValidate)
  }

  function clearFormsValidate(): void {
    stationFormRef.value?.clearValidate()
    shippingFormRef.value?.clearValidate()
    receivingFormRef.value?.clearValidate()
    paymentFormRef.value?.clearValidate()
  }

  function focusFirstInvalidField(): void {
    const invalidItem = pageRef.value?.querySelector<HTMLElement>('.el-form-item.is-error')
    if (!invalidItem) return
    invalidItem.scrollIntoView({ behavior: 'smooth', block: 'center' })
    invalidItem
      .querySelector<HTMLElement>('input, textarea, button, [tabindex]:not([tabindex="-1"])')
      ?.focus()
  }

  function normalizePayload(): OrderRecord {
    const raw = cloneDeep(toRaw(form.data))
    const payload = omit(raw, [
      'tenantId',
      'shippingCustomer',
      'receivingCustomer',
      'originStationRef',
      'destinationStationRef',
      'transferStationRef',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as OrderRecord

    payload.cargoItems = normalizeCargoItems(raw.cargoItems)
    payload.cargoQuantityTotal = form.cargoSummary.quantity
    payload.cargoWeightTotal = form.cargoSummary.weight
    payload.cargoVolumeTotal = form.cargoSummary.volume
    payload.transportFee = moneyValue(raw.transportFee)
    payload.deliveryFee = moneyValue(raw.deliveryFee)
    payload.unloadingFee = moneyValue(raw.unloadingFee)
    payload.collectPaymentFee = moneyValue(raw.collectPaymentFee)
    payload.transferFee = moneyValue(raw.transferFee)
    payload.declaredValue = moneyValue(raw.declaredValue)
    payload.insuranceFee = moneyValue(raw.insuranceFee)
    payload.packageFee = moneyValue(raw.packageFee)
    payload.otherFee = moneyValue(raw.otherFee)
    payload.totalFee = sumFields(feeFields)
    payload.cashAmount = moneyValue(raw.cashAmount)
    payload.collectAmount = moneyValue(raw.collectAmount)
    payload.monthlyAmount = moneyValue(raw.monthlyAmount)
    payload.codAmount = moneyValue(raw.codAmount)
    payload.handlingFee = moneyValue(raw.handlingFee)
    payload.paymentTotal = sumFields(paymentFields)
    payload.originStationId = nullableText(raw.originStationId)
    payload.destinationStationId = nullableText(raw.destinationStationId)
    payload.transferStationId = nullableText(raw.transferStationId)
    payload.originStation =
      findStationOption('origin', raw.originStationId)?.stationName || textValue(raw.originStation)
    payload.destinationStation =
      findStationOption('destination', raw.destinationStationId)?.stationName ||
      textValue(raw.destinationStation)
    payload.transferStation =
      findStationOption('transfer', raw.transferStationId)?.stationName ||
      nullableText(raw.transferStation)
    payload.transportMode = textValue(raw.transportMode)
    payload.orderRemark = textValue(raw.orderRemark)
    payload.cargoNo = textValue(raw.cargoNo)
    payload.imageUrls = raw.imageUrls ?? []

    return payload
  }

  function normalizeCargoItems(items?: CargoItem[]): CargoItem[] {
    return (items ?? [])
      .map((item) => ({
        cargoName: textValue(item.cargoName),
        packageType: textValue(item.packageType),
        quantity: nullableNumber(item.quantity),
        unit: textValue(item.packageType),
        weightKg: nullableNumber(item.weightKg),
        volumeM3: nullableNumber(item.volumeM3)
      }))
      .filter(
        (item) =>
          item.cargoName || item.packageType || item.quantity || item.weightKg || item.volumeM3
      )
  }

  function sumFields(fields: Array<keyof OrderForm>): number {
    return round(
      fields.reduce((sum, field) => sum + numericValue(form.data[field] as number), 0),
      2
    )
  }

  function numericValue(value?: number | string | null): number {
    const parsed = lodashToNumber(value ?? 0)
    return Number.isFinite(parsed) ? parsed : 0
  }

  function formatNumber(value?: number | string | null, precision = 2): string {
    const numberValue = numericValue(value)
    return numberValue
      .toFixed(precision)
      .replace(/\.0+$/, '')
      .replace(/(\.\d*?)0+$/, '$1')
  }

  function textValue(value?: string | null): string {
    return trim(String(value ?? ''))
  }

  function nullableText(value?: string | null): string | null {
    const text = textValue(value)
    return text || null
  }

  function nullableNumber(value?: number | string | null): number | null {
    if (isNil(value) || value === '') return null
    const parsed = lodashToNumber(value)
    return Number.isFinite(parsed) ? parsed : null
  }

  function moneyValue(value?: number | string | null): number {
    return round(nullableNumber(value) ?? 0, 2)
  }

  function getDictLabel(options: Api.DataCenter.DictListItem[], value?: string | null): string {
    if (!value) return ''
    return options.find((item) => item.value === value)?.label || value
  }
</script>

<style scoped lang="scss">
  .order-open {
    min-height: 100%;
    padding: 12px 18px 18px;
    background: #f5f7fb;

    &__header {
      display: grid;
      grid-template-columns: minmax(260px, 340px) 1fr minmax(240px, 320px);
      gap: 20px;
      align-items: center;
      min-height: 64px;
      padding: 10px 18px;
      margin-bottom: 12px;
    }

    &__badge {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 16px;
      align-items: center;
      min-height: 44px;
      padding: 8px 16px;
      font-size: 17px;
      font-weight: 700;
      line-height: 1.35;
      color: #fff;
      background: var(--el-color-primary);
      border-radius: var(--el-border-radius-base);
      box-shadow: inset 0 -1px 0 rgb(0 0 0 / 8%);
    }

    &__title {
      justify-self: center;
      padding: 0 18px 4px;
      font-size: 18px;
      font-weight: 700;
      letter-spacing: 12px;
      white-space: nowrap;
      border-bottom: 3px double #d8deea;
    }

    &__time {
      display: inline-flex;
      gap: 6px;
      align-items: center;
      justify-self: end;
      font-size: 17px;
      font-weight: 700;
      color: var(--art-text-gray-800);
    }

    &__section {
      padding: 20px 22px;
      margin-bottom: 12px;

      &--compact {
        padding-top: 18px;
        padding-bottom: 2px;
      }
    }

    &__section-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 14px;
    }

    &__contact-grid {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 48px minmax(0, 1fr);
      gap: 28px;
      align-items: center;
    }

    &__contact-panel {
      min-width: 0;
    }

    &__contact-heading {
      display: grid;
      grid-template-columns: auto 1fr auto;
      gap: 12px;
      align-items: center;
      margin-bottom: 18px;

      h3 {
        margin: 0;
        font-size: 16px;
        font-weight: 600;
        color: var(--art-text-gray-800);
      }
    }

    &__contact-mark {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 30px;
      height: 30px;
      font-size: 16px;
      font-weight: 700;
      color: #fff;
      border-radius: var(--el-border-radius-base);

      &--send {
        background: #37c2ff;
      }

      &--receive {
        background: #f4c430;
      }
    }

    &__swap {
      display: flex;
      justify-content: center;
      color: var(--el-color-primary);

      .el-button {
        width: 34px;
        height: 34px;
        background: var(--el-color-primary-light-9);
      }
    }

    &__cargo-summary {
      display: flex;
      gap: 28px;
      justify-content: flex-end;
      padding: 14px 12px 0;
      color: var(--art-text-gray-700);
    }

    &__upload-row {
      display: flex;
      gap: 18px;
      align-items: flex-start;
      padding-top: 4px;
      margin-top: 6px;
      margin-left: 14px;
      color: var(--art-text-gray-700);

      > span {
        padding-top: 8px;
      }
    }

    &__footer {
      position: sticky;
      bottom: 0;
      z-index: 10;
      display: flex;
      gap: 18px;
      align-items: center;
      justify-content: space-between;
      min-height: 80px;
      padding: 14px 20px 14px 28px;
      margin-top: 12px;
    }

    &__footer-total {
      display: flex;
      gap: 8px;
      align-items: center;
      white-space: nowrap;

      strong {
        font-size: 28px;
        color: var(--el-color-primary);
      }
    }

    &__footer-actions {
      display: flex;
      gap: 16px;

      .el-button {
        min-width: 122px;
        height: 46px;
        font-weight: 600;
      }
    }

    &__fee-detail {
      p {
        margin: 8px 0 12px;
        color: var(--art-text-gray-500);
        line-height: 1.6;
      }

      dl {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 8px 12px;
        margin: 0;
      }

      dt {
        color: var(--art-text-gray-600);
      }

      dd {
        margin: 0;
        font-weight: 600;
      }
    }

    &__fee-detail-title {
      font-weight: 600;
      color: var(--art-text-gray-800);
    }

    :deep(.order-open__form) {
      padding-right: 0;
      padding-left: 0;

      .el-form-item {
        margin-bottom: 18px;
      }
    }

    :deep(.art-table__cell-content),
    :deep(.art-table__cell-value) {
      width: 100%;
    }

    :deep(.el-input),
    :deep(.el-select),
    :deep(.el-input-number) {
      width: 100%;
    }
  }

  @media (max-width: 1100px) {
    .order-open {
      &__header {
        grid-template-columns: 1fr;
      }

      &__badge,
      &__title,
      &__time {
        justify-self: stretch;
      }

      &__contact-grid {
        grid-template-columns: 1fr;
      }

      &__footer {
        flex-direction: column;
        align-items: stretch;
      }

      &__footer-actions {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }
</style>
