<template>
  <ArtPageShell
    class="carrier-price-edit"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    @retry="initializePage"
  >
    <ArtPageHeader
      class="carrier-price-edit__header"
      :title="isEdit ? '编辑承运商价' : '新增承运商价'"
      subtitle="维护承运路线、车辆司机、货物成本与付款方式"
      show-back
      @back="goBack"
    />

    <div ref="pageRef" class="carrier-price-edit__content">
      <section class="carrier-price-edit__section art-card-xs">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ArtForm
          ref="baseFormRef"
          v-model="form.data"
          :items="form.baseItems"
          :rules="form.rules"
          :span="8"
          :gutter="24"
          label-width="98px"
          root-class="carrier-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />
      </section>

      <section class="carrier-price-edit__section art-card-xs">
        <div class="carrier-price-edit__section-header">
          <ArtSectionTitle :show-line="false">承运商</ArtSectionTitle>
          <ElButton type="primary" plain :icon="Plus" @click="resetCarrierInfo">添加</ElButton>
        </div>
        <ArtForm
          ref="carrierFormRef"
          v-model="form.data"
          :items="form.carrierItems"
          :rules="form.rules"
          :span="8"
          :gutter="24"
          label-width="98px"
          root-class="carrier-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />
      </section>

      <PriceCargoSection
        :quantity-text="form.cargoQuantityText"
        :volume-text="form.cargoVolumeText"
        :weight-text="form.cargoWeightText"
        @select-cargo="openCargoSelector"
        @add-cargo="addCargoItem"
      >
        <ArtTable
          :data="form.cargoItems"
          :columns="form.cargoColumns"
          :pagination="undefined"
          :show-table-header="false"
          table-layout="fixed"
          empty-height="160px"
        />
        <template #after>
          <ArtForm
            ref="feeFormRef"
            v-model="form.data"
            :items="form.feeItems"
            :rules="form.rules"
            :span="8"
            :gutter="24"
            label-width="98px"
            root-class="carrier-price-edit__form carrier-price-edit__fee-form"
            :show-reset="false"
            :show-submit="false"
          />
        </template>
      </PriceCargoSection>

      <section class="carrier-price-edit__section art-card-xs">
        <ArtSectionTitle>付款方式</ArtSectionTitle>
        <ArtForm
          ref="paymentFormRef"
          v-model="form.data"
          :items="form.paymentItems"
          :rules="form.rules"
          :span="8"
          :gutter="24"
          label-width="98px"
          root-class="carrier-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />
      </section>
    </div>

    <ArtStickyActionBar class="carrier-price-edit__footer">
      <ElButton :disabled="page.saving" @click="goBack">取消</ElButton>
      <ElButton type="primary" :loading="page.saving" @click="handleSave">保存</ElButton>
    </ArtStickyActionBar>

    <CargoMultipleSelect ref="cargoSelectorRef" @confirm="handleCargoSelectorConfirm" />
  </ArtPageShell>
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
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import type { ColumnOption } from '@/types'
  import { formatNameCodeOption } from '@/utils/form'
  import { fetchRegionOptions } from '@/api/common'
  import {
    addCarrierPrice,
    editCarrierPrice,
    fetchCarrierOptions,
    fetchCarrierPriceDetail,
    fetchDriverOptions
  } from '@/api/tms'
  import { fetchVehicleArchiveOptions } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import { clearFormRefsValidation, validateFormRefs } from '@/utils/form/validation'
  import CargoMultipleSelect from '../../modules/cargo-multiple-select.vue'
  import PriceCargoSection from '../modules/price-cargo-section.vue'
  import {
    calculateCargoSummary,
    formatNumber,
    getResponseData,
    joinRegionPath,
    mergeCargoSelections,
    normalizeMoney,
    normalizeNullableNumber,
    normalizeText,
    roundNumber,
    splitRegionPath,
    toNumber,
    type CargoSummary
  } from '../modules/price-form-utils'

  defineOptions({ name: 'TmsCarrierPriceEdit' })

  type CarrierPrice = Api.Tms.BasicData.CarrierPrice
  type CarrierPriceCargoItem = Api.Tms.BasicData.CarrierPriceCargoItem
  type CargoMaster = Api.Tms.BasicData.Cargo
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type DriverOption = Api.Tms.BasicData.DriverOption
  type VehicleOption = Api.VehicleMgtSys.VehicleManage.VehicleOption
  type CarrierPriceForm = CarrierPrice & {
    originRegionPath: string[]
    destinationRegionPath: string[]
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface CargoSelectorExpose {
    open: () => Promise<void>
  }

  interface PageState {
    loading: boolean
    saving: boolean
    error: Error | null
  }

  interface FeeSummary {
    splitTransportFee: number
    loadingFee: number
    packageFee: number
    totalFee: number
  }

  interface FormGroup {
    data: CarrierPriceForm
    carrierOptions: CarrierOption[]
    driverOptions: DriverOption[]
    vehicleOptions: VehicleOption[]
    transportModeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    cargoUnitOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    vehicleTypeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    vehicleLengthOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    billingMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    baseItems: ComputedRef<FormItem[]>
    carrierItems: ComputedRef<FormItem[]>
    feeItems: ComputedRef<FormItem[]>
    paymentItems: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<CarrierPriceForm>>
    cargoColumns: ComputedRef<ColumnOption<CarrierPriceCargoItem>[]>
    cargoItems: ComputedRef<CarrierPriceCargoItem[]>
    cargoSummary: ComputedRef<CargoSummary>
    feeSummary: ComputedRef<FeeSummary>
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
  const carrierFormRef = ref<FormExpose>()
  const feeFormRef = ref<FormExpose>()
  const paymentFormRef = ref<FormExpose>()
  const cargoSelectorRef = ref<CargoSelectorExpose>()
  const validatedFormRefs = [baseFormRef, carrierFormRef, feeFormRef, paymentFormRef]
  const quoteNumber = useDocumentNumberRule('tms.carrier_price')

  const isEdit = computed(() => Boolean(route.params.id))
  const dictCodes = [
    'tmsCarrierPriceTransportMode',
    'tmsCargoUnit',
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

  function createInitialCargoItem(): CarrierPriceCargoItem {
    return {
      orderNo: '',
      originRegion: '',
      destinationRegion: '',
      cargoName: '',
      quantity: null,
      unit: 'box',
      volumeM3: null,
      weightKg: null,
      splitTransportFee: 0,
      loadingFee: 0,
      packageFee: 0
    }
  }

  function createInitialForm(): CarrierPriceForm {
    return {
      id: undefined,
      quoteNo: '',
      carrierId: '',
      carrier: null,
      driverId: null,
      driver: null,
      vehicleId: null,
      vehicle: null,
      originRegion: '',
      destinationRegion: '',
      originRegionPath: [],
      destinationRegionPath: [],
      transportMode: '',
      contactName: '',
      contactPhone: '',
      driverName: '',
      driverPhone: '',
      plateNo: '',
      vehicleType: '',
      vehicleLength: '',
      cargoItems: [createInitialCargoItem()],
      cargoQuantityTotal: 0,
      cargoVolumeTotal: 0,
      cargoWeightTotal: 0,
      billingMethod: '',
      transportCost: 0,
      splitTransportFee: 0,
      loadingFee: 0,
      packageFee: 0,
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

  function createEmptyFeeSummary(): FeeSummary {
    return {
      splitTransportFee: 0,
      loadingFee: 0,
      packageFee: 0,
      totalFee: 0
    }
  }

  const page = reactive<PageState>({ loading: false, saving: false, error: null })
  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    carrierOptions: [],
    driverOptions: [],
    vehicleOptions: [],
    transportModeOptions: computed(() => getDictMap.value.tmsCarrierPriceTransportMode ?? []),
    cargoUnitOptions: computed(() => getDictMap.value.tmsCargoUnit ?? []),
    vehicleTypeOptions: computed(() => getDictMap.value.tmsCustomerPriceVehicleType ?? []),
    vehicleLengthOptions: computed(() => getDictMap.value.tmsCustomerPriceVehicleLength ?? []),
    billingMethodOptions: computed(() => getDictMap.value.tmsCustomerPriceBillingMethod ?? []),
    baseItems: computed<FormItem[]>(() => [
      {
        label: '报价单号',
        key: 'quoteNo',
        type: 'input',
        props: {
          maxlength: 50,
          ...quoteNumber.inputProps(Boolean(form.data.id), '请输入报价单号', true)
        },
        description: quoteNumber.description.value
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
        label: '运输方式',
        key: 'transportMode',
        type: 'select',
        props: { options: form.transportModeOptions, clearable: true, placeholder: '请选择' }
      }
    ]),
    carrierItems: computed<FormItem[]>(() => [
      {
        label: '承运商名称',
        key: 'carrierId',
        type: 'select',
        api: fetchCarrierOptions,
        resultField: 'data',
        labelField: 'companyName',
        valueField: 'id',
        labelFn: formatCarrierOption,
        afterFetch: syncCarrierOptions,
        props: {
          clearable: true,
          filterable: true,
          placeholder: '请选择',
          onChange: handleCarrierChange
        }
      },
      {
        label: '联系人姓名',
        key: 'contactName',
        type: 'input',
        props: { disabled: true, placeholder: '选择承运商后自动带出' }
      },
      {
        label: '手机号码',
        key: 'contactPhone',
        type: 'input',
        props: { disabled: true, placeholder: '选择承运商后自动带出' }
      },
      {
        label: '司机姓名',
        key: 'driverId',
        type: 'select',
        api: fetchDriverOptions,
        resultField: 'data',
        labelField: 'driverName',
        valueField: 'id',
        beforeFetch: (params) => ({ ...params, carrierId: form.data.carrierId || undefined }),
        shouldFetch: () => Boolean(form.data.carrierId),
        afterFetch: syncDriverOptions,
        props: {
          clearable: true,
          filterable: true,
          disabled: !form.data.carrierId,
          placeholder: form.data.carrierId ? '请选择' : '请先选择承运商',
          onVisibleChange: (visible: boolean) => {
            if (visible && form.data.carrierId) void carrierFormRef.value?.reloadOptions('driverId')
          },
          onChange: handleDriverChange
        }
      },
      {
        label: '手机号码',
        key: 'driverPhone',
        type: 'input',
        props: { disabled: true, placeholder: '选择司机后自动带出' }
      },
      {
        label: '车牌号',
        key: 'vehicleId',
        type: 'select',
        api: fetchVehicleArchiveOptions,
        resultField: 'data',
        labelField: 'plateNo',
        valueField: 'id',
        beforeFetch: (params) => ({ ...params, carrierId: form.data.carrierId || undefined }),
        shouldFetch: () => Boolean(form.data.carrierId),
        afterFetch: syncVehicleOptions,
        props: {
          clearable: true,
          filterable: true,
          disabled: !form.data.carrierId,
          placeholder: form.data.carrierId ? '请选择' : '请先选择承运商',
          onVisibleChange: (visible: boolean) => {
            if (visible && form.data.carrierId)
              void carrierFormRef.value?.reloadOptions('vehicleId')
          },
          onChange: handleVehicleChange
        }
      },
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
      }
    ]),
    feeItems: computed<FormItem[]>(() => [
      {
        label: '总数量',
        key: 'cargoQuantityTotal',
        type: 'number',
        props: { ...moneyProps, precision: 0, disabled: true }
      },
      {
        label: '总体积',
        key: 'cargoVolumeTotal',
        type: 'number',
        props: { ...moneyProps, precision: 3, disabled: true }
      },
      {
        label: '总重量',
        key: 'cargoWeightTotal',
        type: 'number',
        props: { ...moneyProps, disabled: true }
      },
      {
        label: '计费方式',
        key: 'billingMethod',
        type: 'select',
        props: { options: form.billingMethodOptions, clearable: true, placeholder: '请选择' }
      },
      { label: '运费成本', key: 'transportCost', type: 'number', props: moneyProps },
      {
        label: '分摊运费',
        key: 'splitTransportFee',
        type: 'number',
        props: { ...moneyProps, disabled: true }
      },
      {
        label: '装卸费',
        key: 'loadingFee',
        type: 'number',
        props: { ...moneyProps, disabled: true }
      },
      {
        label: '包装费',
        key: 'packageFee',
        type: 'number',
        props: { ...moneyProps, disabled: true }
      },
      { label: '其他费用', key: 'otherFee', type: 'number', props: moneyProps },
      {
        label: '运费合计',
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
    rules: computed<FormRules<CarrierPriceForm>>(() => ({
      quoteNo: [
        {
          validator: (_rule, value, callback) =>
            quoteNumber.manualRequired(Boolean(form.data.id)) && !String(value || '').trim()
              ? callback(new Error('请输入报价单号'))
              : callback(),
          trigger: 'blur'
        }
      ],
      originRegionPath: [
        { required: true, type: 'array', message: '请选择始发地', trigger: 'change' }
      ],
      destinationRegionPath: [
        { required: true, type: 'array', message: '请选择目的地', trigger: 'change' }
      ],
      transportMode: [{ required: true, message: '请选择运输方式', trigger: 'change' }],
      carrierId: [{ required: true, message: '请选择承运商名称', trigger: 'change' }],
      billingMethod: [{ required: true, message: '请选择计费方式', trigger: 'change' }],
      transportCost: [{ required: true, message: '请输入运费成本', trigger: 'blur' }],
      totalFee: [{ required: true, message: '请输入运费合计', trigger: 'blur' }]
    })),
    cargoColumns: computed<ColumnOption<CarrierPriceCargoItem>[]>(() => [
      { type: 'globalIndex', label: '序号', width: 70 },
      {
        prop: 'orderNo',
        label: '订单编号',
        width: 130,
        formatter: (row) => <ElInput v-model={row.orderNo} maxlength={40} />
      },
      {
        prop: 'originRegion',
        label: '始发地',
        minWidth: 170,
        formatter: (row) => <ElInput v-model={row.originRegion} maxlength={120} />
      },
      {
        prop: 'destinationRegion',
        label: '目的地',
        minWidth: 170,
        formatter: (row) => <ElInput v-model={row.destinationRegion} maxlength={120} />
      },
      {
        prop: 'cargoName',
        label: '货物名称',
        minWidth: 160,
        formatter: (row) => <ElInput v-model={row.cargoName} maxlength={80} />
      },
      {
        prop: 'quantity',
        label: '数量',
        width: 120,
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
        width: 120,
        formatter: (row) => (
          <ElSelect v-model={row.unit} class="w-full!" clearable filterable placeholder="请选择">
            {form.cargoUnitOptions.map((item) => (
              <ElOption key={item.value} label={item.label || item.value} value={item.value} />
            ))}
          </ElSelect>
        )
      },
      {
        prop: 'volumeM3',
        label: '体积（m³）',
        width: 130,
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
        width: 130,
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
        prop: 'splitTransportFee',
        label: '分摊运费（元）',
        width: 140,
        formatter: (row) => (
          <ElInputNumber
            v-model={row.splitTransportFee}
            min={0}
            precision={2}
            controls={false}
            class="w-full!"
          />
        )
      },
      {
        prop: 'loadingFee',
        label: '装卸费（元）',
        width: 130,
        formatter: (row) => (
          <ElInputNumber
            v-model={row.loadingFee}
            min={0}
            precision={2}
            controls={false}
            class="w-full!"
          />
        )
      },
      {
        prop: 'packageFee',
        label: '包装费（元）',
        width: 130,
        formatter: (row) => (
          <ElInputNumber
            v-model={row.packageFee}
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
    cargoSummary: computed(() => calculateCargoSummary(form.data.cargoItems ?? [])),
    feeSummary: computed(() => {
      const items = form.data.cargoItems ?? []
      const splitTransportFee = roundNumber(
        items.reduce((sum, item) => sum + toNumber(item.splitTransportFee), 0),
        2
      )
      const loadingFee = roundNumber(
        items.reduce((sum, item) => sum + toNumber(item.loadingFee), 0),
        2
      )
      const packageFee = roundNumber(
        items.reduce((sum, item) => sum + toNumber(item.packageFee), 0),
        2
      )
      return {
        splitTransportFee,
        loadingFee,
        packageFee,
        totalFee: roundNumber(
          toNumber(form.data.transportCost) +
            splitTransportFee +
            loadingFee +
            packageFee +
            toNumber(form.data.otherFee),
          2
        )
      }
    }),
    cargoQuantityText: computed(() => formatNumber(form.cargoSummary.quantity, 0)),
    cargoVolumeText: computed(() => formatNumber(form.cargoSummary.volume, 3)),
    cargoWeightText: computed(() => formatNumber(form.cargoSummary.weight, 2))
  })

  const paymentFields: Array<keyof CarrierPriceForm> = [
    'cashAmount',
    'prepaidAmount',
    'collectAmount',
    'periodicAmount'
  ]

  function sumFields(fields: Array<keyof CarrierPriceForm>): number {
    return roundNumber(
      fields.reduce((sum, field) => sum + toNumber(form.data[field] as number), 0),
      2
    )
  }

  onMounted(() => {
    void initializePage()
  })

  async function initializePage(): Promise<void> {
    page.loading = true
    page.error = null
    try {
      await Promise.all([
        loadDetail(),
        quoteNumber.loadRule(),
        ...dictCodes.map((code) => userStore.ensureDictLoaded(code))
      ])
      await nextTick()
      clearFormRefsValidation(validatedFormRefs)
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('承运商价信息加载失败')
    } finally {
      page.loading = false
    }
  }

  watch(
    () => form.cargoSummary,
    (summary) => {
      form.data.cargoQuantityTotal = summary.quantity
      form.data.cargoVolumeTotal = summary.volume
      form.data.cargoWeightTotal = summary.weight
    },
    { immediate: true }
  )

  watch(
    () => form.feeSummary,
    (summary) => {
      const nextSummary = summary ?? createEmptyFeeSummary()
      form.data.splitTransportFee = nextSummary.splitTransportFee
      form.data.loadingFee = nextSummary.loadingFee
      form.data.packageFee = nextSummary.packageFee
      form.data.totalFee = nextSummary.totalFee
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

  watch(
    () => route.params.id,
    (id, previousId) => {
      if (route.name !== 'TmsCarrierPriceEdit' || id === previousId) return
      void initializePage()
    }
  )

  async function loadDetail(): Promise<void> {
    if (!isEdit.value) {
      replaceForm(createInitialForm())
      form.driverOptions = []
      form.vehicleOptions = []
      return
    }

    const id = String(route.params.id || '')
    const { data } = await fetchCarrierPriceDetail(id)
    if (!data) throw new Error('承运商价不存在或无权访问')

    replaceForm({
      ...createInitialForm(),
      ...data,
      originRegionPath: splitRegionPath(data.originRegion),
      destinationRegionPath: splitRegionPath(data.destinationRegion),
      cargoItems: data.cargoItems?.length ? data.cargoItems : [createInitialCargoItem()]
    })
    cacheSelectedOptions()
  }

  function replaceForm(nextForm: CarrierPriceForm): void {
    Object.assign(form.data, createInitialForm(), cloneDeep(nextForm))
  }

  function syncCarrierOptions(result: unknown): unknown {
    form.carrierOptions = getResponseData<CarrierOption>(result)
    cacheSelectedOptions()
    return result
  }

  function syncDriverOptions(result: unknown): unknown {
    form.driverOptions = getResponseData<DriverOption>(result)
    cacheSelectedOptions()
    return result
  }

  function syncVehicleOptions(result: unknown): unknown {
    form.vehicleOptions = getResponseData<VehicleOption>(result)
    cacheSelectedOptions()
    return result
  }

  function cacheSelectedOptions(): void {
    if (form.data.carrier && !form.carrierOptions.some((item) => item.id === form.data.carrierId)) {
      form.carrierOptions = [form.data.carrier, ...form.carrierOptions]
    }
    if (form.data.driver && !form.driverOptions.some((item) => item.id === form.data.driverId)) {
      form.driverOptions = [form.data.driver, ...form.driverOptions]
    }
    if (form.data.vehicle && !form.vehicleOptions.some((item) => item.id === form.data.vehicleId)) {
      form.vehicleOptions = [form.data.vehicle, ...form.vehicleOptions]
    }
  }

  function formatCarrierOption(option: Record<string, unknown>): string {
    return formatNameCodeOption(option, 'companyName', 'carrierCode')
  }

  function handleCarrierChange(carrierId?: string): void {
    const carrier = form.carrierOptions.find((item) => item.id === carrierId)
    form.data.contactName = carrier?.contactName ?? ''
    form.data.contactPhone = carrier?.contactPhone ?? ''
    form.data.driverId = null
    form.data.driver = null
    form.data.driverName = ''
    form.data.driverPhone = ''
    form.data.vehicleId = null
    form.data.vehicle = null
    form.data.plateNo = ''
    void nextTick(() => {
      void carrierFormRef.value?.reloadOptions('driverId')
      void carrierFormRef.value?.reloadOptions('vehicleId')
    })
  }

  function handleDriverChange(driverId?: string): void {
    const driver = form.driverOptions.find((item) => item.id === driverId)
    form.data.driverName = driver?.driverName ?? ''
    form.data.driverPhone = driver?.phone ?? ''
  }

  function handleVehicleChange(vehicleId?: string): void {
    const vehicle = form.vehicleOptions.find((item) => item.id === vehicleId)
    form.data.plateNo = vehicle?.plateNo ?? ''
    form.data.vehicleType = vehicle?.vehicleType ?? form.data.vehicleType ?? ''
  }

  function resetCarrierInfo(): void {
    form.data.carrierId = ''
    handleCarrierChange('')
  }

  function addCargoItem(): void {
    form.data.cargoItems = [...(form.data.cargoItems ?? []), createInitialCargoItem()]
  }

  async function openCargoSelector(): Promise<void> {
    await cargoSelectorRef.value?.open()
  }

  function handleCargoSelectorConfirm(selectedCargoes: CargoMaster[]): void {
    const currentItems = form.data.cargoItems ?? []
    const result = mergeCargoSelections(currentItems, selectedCargoes, createCargoItemFromMaster)
    if (!result.addedCount) return

    form.data.cargoItems = result.items
  }

  function createCargoItemFromMaster(cargo: CargoMaster): CarrierPriceCargoItem {
    return {
      ...createInitialCargoItem(),
      cargoName: cargo.cargoName,
      quantity: 1,
      unit: cargo.unit || '',
      volumeM3: cargo.volumeM3 ?? null,
      weightKg: cargo.weightKg ?? null
    }
  }

  function removeCargoItem(row: CarrierPriceCargoItem): void {
    const rows = form.data.cargoItems ?? []
    if (rows.length <= 1) {
      form.data.cargoItems = [createInitialCargoItem()]
      return
    }
    form.data.cargoItems = rows.filter((item) => item !== row)
  }

  function normalizePayload(): CarrierPrice {
    const raw = cloneDeep(toRaw(form.data))
    const payload = omit(raw, [
      'tenantId',
      'carrier',
      'driver',
      'vehicle',
      'originRegionPath',
      'destinationRegionPath',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as CarrierPrice

    payload.originRegion = joinRegionPath(raw.originRegionPath)
    payload.destinationRegion = joinRegionPath(raw.destinationRegionPath)
    payload.driverId = normalizeText(raw.driverId)
    payload.vehicleId = normalizeText(raw.vehicleId)
    payload.contactName = normalizeText(raw.contactName)
    payload.contactPhone = normalizeText(raw.contactPhone)
    payload.driverName = normalizeText(raw.driverName)
    payload.driverPhone = normalizeText(raw.driverPhone)
    payload.plateNo = normalizeText(raw.plateNo)
    payload.vehicleType = normalizeText(raw.vehicleType)
    payload.vehicleLength = normalizeText(raw.vehicleLength)
    payload.cargoItems = normalizeCargoItems(raw.cargoItems)
    payload.cargoQuantityTotal = form.cargoSummary.quantity
    payload.cargoVolumeTotal = form.cargoSummary.volume
    payload.cargoWeightTotal = form.cargoSummary.weight
    payload.transportCost = normalizeMoney(raw.transportCost)
    payload.splitTransportFee = form.feeSummary.splitTransportFee
    payload.loadingFee = form.feeSummary.loadingFee
    payload.packageFee = form.feeSummary.packageFee
    payload.otherFee = normalizeMoney(raw.otherFee)
    payload.totalFee = form.feeSummary.totalFee
    payload.cashAmount = normalizeMoney(raw.cashAmount)
    payload.prepaidAmount = normalizeMoney(raw.prepaidAmount)
    payload.collectAmount = normalizeMoney(raw.collectAmount)
    payload.periodicAmount = normalizeMoney(raw.periodicAmount)
    payload.paymentTotal = sumFields(paymentFields)
    payload.remark = normalizeText(raw.remark)

    return payload
  }

  function normalizeCargoItems(
    items: CarrierPriceCargoItem[] | undefined
  ): CarrierPriceCargoItem[] {
    return (items ?? [])
      .map((item) => ({
        orderNo: normalizeText(item.orderNo),
        originRegion: normalizeText(item.originRegion),
        destinationRegion: normalizeText(item.destinationRegion),
        cargoName: normalizeText(item.cargoName),
        quantity: normalizeNullableNumber(item.quantity),
        unit: normalizeText(item.unit),
        volumeM3: normalizeNullableNumber(item.volumeM3),
        weightKg: normalizeNullableNumber(item.weightKg),
        splitTransportFee: normalizeMoney(item.splitTransportFee),
        loadingFee: normalizeMoney(item.loadingFee),
        packageFee: normalizeMoney(item.packageFee)
      }))
      .filter(
        (item) =>
          item.orderNo ||
          item.cargoName ||
          item.quantity ||
          item.volumeM3 ||
          item.weightKg ||
          item.splitTransportFee ||
          item.loadingFee ||
          item.packageFee
      )
  }

  async function handleSave(): Promise<void> {
    const valid = await validateFormRefs(validatedFormRefs, pageRef)
    if (!valid) return

    page.saving = true
    try {
      const payload = normalizePayload()
      if (form.data.id) await editCarrierPrice(payload)
      else await addCarrierPrice(payload)
      goBack()
    } catch {
      // API 层已经展示错误信息，当前页保持编辑状态。
    } finally {
      page.saving = false
    }
  }

  function goBack(): void {
    void router.push({ name: 'TmsCarrierPrice' })
  }
</script>

<style scoped lang="scss">
  .carrier-price-edit {
    min-height: 100%;
    padding: 8px;
    background: var(--art-main-bg-color);

    &__header {
      margin-bottom: 16px;
    }

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

    &__fee-form {
      margin-top: 18px;
    }

    &__footer {
      margin-top: 16px;
    }

    :deep(.carrier-price-edit__form) {
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
</style>
