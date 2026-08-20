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
      subtitle="先维护运输路线和承运主体，再完善车辆司机、货物成本与付款方式"
      show-back
      @back="goBack"
    />

    <div ref="pageRef" class="carrier-price-edit__content">
      <section class="carrier-price-edit__section art-card-xs">
        <ArtSectionTitle>路线与运输条件</ArtSectionTitle>

        <ol class="carrier-price-edit__workflow" aria-label="承运商价格维护步骤">
          <li
            v-for="(step, index) in workflowSteps"
            :key="step.key"
            class="carrier-price-edit__workflow-step"
            :class="{ 'is-complete': step.complete, 'is-active': step.active }"
            :aria-current="step.active ? 'step' : undefined"
          >
            <span class="carrier-price-edit__workflow-index" aria-hidden="true">
              <ElIcon v-if="step.complete"><Check /></ElIcon>
              <template v-else>{{ index + 1 }}</template>
            </span>
            <span class="carrier-price-edit__workflow-copy">
              <strong>{{ step.label }}</strong>
              <small>{{ step.description }}</small>
            </span>
            <span class="carrier-price-edit__workflow-status">
              {{ step.complete ? '已完成' : step.active ? '当前步骤' : '待处理' }}
            </span>
          </li>
        </ol>

        <ArtForm
          ref="baseFormRef"
          v-model="form.data"
          :items="form.baseItems"
          :rules="form.rules"
          :span="12"
          :gutter="24"
          label-width="98px"
          root-class="carrier-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />

        <div
          class="carrier-price-edit__route-preview"
          :class="{ 'is-ready': routeReady }"
          aria-label="当前承运路线"
        >
          <div class="carrier-price-edit__route-point">
            <span>始发地</span>
            <strong>{{ getRegionText('origin') || '待选择' }}</strong>
          </div>
          <span class="carrier-price-edit__route-arrow" aria-hidden="true">→</span>
          <div class="carrier-price-edit__route-point">
            <span>目的地</span>
            <strong>{{ getRegionText('destination') || '待选择' }}</strong>
          </div>
          <ElTag :type="routeReady ? 'success' : 'info'" effect="plain" size="small">
            {{ getTransportModeText() || '待选择运输方式' }}
          </ElTag>
        </div>
      </section>

      <section class="carrier-price-edit__section art-card-xs">
        <ArtSectionTitle>承运商与运力</ArtSectionTitle>

        <div class="carrier-price-edit__carrier-grid">
          <div class="carrier-price-edit__carrier-panel">
            <div class="carrier-price-edit__panel-heading">
              <span class="carrier-price-edit__panel-icon" aria-hidden="true">承</span>
              <div class="carrier-price-edit__panel-copy">
                <strong>承运主体</strong>
                <span>选择后自动带入联系人和联系电话</span>
              </div>
              <ElTag :type="form.data.carrierId ? 'success' : 'info'" effect="plain" size="small">
                {{ form.data.carrierId ? '已选择' : '待选择' }}
              </ElTag>
            </div>

            <ArtForm
              ref="carrierFormRef"
              v-model="form.data"
              :items="form.carrierItems"
              :rules="form.rules"
              :span="24"
              label-position="top"
              root-class="carrier-price-edit__form"
              :show-reset="false"
              :show-submit="false"
            />
          </div>

          <div class="carrier-price-edit__carrier-panel">
            <div class="carrier-price-edit__panel-heading">
              <span
                class="carrier-price-edit__panel-icon carrier-price-edit__panel-icon--capacity"
                aria-hidden="true"
              >
                运
              </span>
              <div class="carrier-price-edit__panel-copy">
                <strong>司机与车辆</strong>
                <span>先选承运商，再选择其名下司机和车辆</span>
              </div>
              <ElTag :type="capacityReady ? 'success' : 'info'" effect="plain" size="small">
                {{ capacityReady ? '已配置' : '选填' }}
              </ElTag>
            </div>

            <ArtForm
              ref="capacityFormRef"
              v-model="form.data"
              :items="form.capacityItems"
              :rules="form.rules"
              :span="12"
              :gutter="16"
              label-position="top"
              root-class="carrier-price-edit__form"
              :show-reset="false"
              :show-submit="false"
            />
          </div>
        </div>
      </section>

      <PriceCargoSection
        :quantity-text="form.cargoQuantityText"
        :volume-text="form.cargoVolumeText"
        :weight-text="form.cargoWeightText"
        :editable="canEditSensitiveField('costAmounts')"
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
        <template v-if="canViewSensitiveField('costAmounts')" #after>
          <div class="carrier-price-edit__cost-header">
            <div>
              <ArtSectionTitle :show-line="false">成本与计费</ArtSectionTitle>
              <p>货物明细中的分摊运费、装卸费和包装费会自动汇总。</p>
            </div>
            <div class="carrier-price-edit__cost-total">
              <span>预计总成本</span>
              <strong>¥ {{ form.feeTotalText }}</strong>
            </div>
          </div>
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

      <section
        v-if="canViewSensitiveField('paymentAmounts')"
        class="carrier-price-edit__section art-card-xs"
      >
        <div class="carrier-price-edit__payment-header">
          <ArtSectionTitle :show-line="false">付款方式</ArtSectionTitle>
          <span>支持拆分多种付款方式，付款合计会自动计算。</span>
        </div>
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
      <ElButton
        v-auth="'TmsCarrierPriceEdit:Save'"
        type="primary"
        :loading="page.saving"
        @click="handleSave"
      >
        保存承运商价
      </ElButton>
    </ArtStickyActionBar>

    <CargoMultipleSelect ref="cargoSelectorRef" @confirm="handleCargoSelectorConfirm" />
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep, omit } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElButton, ElIcon, ElInput, ElInputNumber, ElOption, ElSelect, ElTag } from 'element-plus'
  import { Check } from '@element-plus/icons-vue'
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
  import { fetchVehicleArchiveOptions } from '@/api/vms'
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
  import {
    canEditField,
    canViewField,
    formatSensitiveNumber,
    type FieldAccessLevel
  } from '@/utils/field-permission'

  defineOptions({ name: 'TmsCarrierPriceEdit' })

  type CarrierPrice = Api.Tms.BasicData.CarrierPrice
  type CarrierPriceCargoItem = Api.Tms.BasicData.CarrierPriceCargoItem
  type CarrierPriceFieldKey = Api.Tms.BasicData.CarrierPriceFieldKey
  type CargoMaster = Api.Tms.BasicData.Cargo
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type DriverOption = Api.Tms.BasicData.DriverOption
  type VehicleOption = Api.Vms.VehicleManage.VehicleOption
  type RegionMode = 'origin' | 'destination'
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
    capacityItems: ComputedRef<FormItem[]>
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
    feeTotalText: ComputedRef<string>
  }

  interface WorkflowStep {
    key: string
    label: string
    description: string
    complete: boolean
    active: boolean
  }

  const route = useRoute()
  const router = useRouter()
  const pageRef = ref<HTMLElement>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const baseFormRef = ref<FormExpose>()
  const carrierFormRef = ref<FormExpose>()
  const capacityFormRef = ref<FormExpose>()
  const feeFormRef = ref<FormExpose>()
  const paymentFormRef = ref<FormExpose>()
  const cargoSelectorRef = ref<CargoSelectorExpose>()
  const validatedFormRefs = [
    baseFormRef,
    carrierFormRef,
    capacityFormRef,
    feeFormRef,
    paymentFormRef
  ]
  const quoteNumber = useDocumentNumberRule('tms.carrier_price')

  const isEdit = computed(() => Boolean(route.params.id))
  const sensitiveFieldFallback = computed<FieldAccessLevel>(() =>
    isEdit.value ? 'hidden' : 'edit'
  )
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

  function canViewSensitiveField(field: CarrierPriceFieldKey): boolean {
    return canViewField(form.data.fieldAccess, field, sensitiveFieldFallback.value)
  }

  function canEditSensitiveField(field: CarrierPriceFieldKey): boolean {
    return canEditField(form.data.fieldAccess, field, sensitiveFieldFallback.value)
  }

  function createSensitiveMoneyItem(
    label: string,
    key: keyof CarrierPriceForm,
    field: Extract<CarrierPriceFieldKey, 'costAmounts' | 'paymentAmounts'>,
    calculated = false
  ): FormItem {
    const editable = canEditSensitiveField(field) && !calculated
    return {
      label,
      key: String(key),
      type: editable ? 'number' : 'input',
      props: editable ? moneyProps : { disabled: true, class: '!w-full' }
    }
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
        span: 12,
        props: {
          maxlength: 50,
          ...quoteNumber.inputProps(Boolean(form.data.id), '请输入报价单号', true)
        },
        description: quoteNumber.description.value
      },
      {
        label: '运输方式',
        key: 'transportMode',
        type: 'select',
        span: 12,
        props: {
          options: form.transportModeOptions,
          clearable: true,
          placeholder: '请选择运输方式'
        }
      },
      {
        label: '始发地',
        key: 'originRegionPath',
        type: 'cascader',
        span: 12,
        api: fetchRegionOptions,
        labelField: 'name',
        valueField: 'name',
        childrenField: 'children',
        props: {
          class: 'w-full',
          clearable: true,
          filterable: true,
          placeholder: '请选择始发地',
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
        span: 12,
        api: fetchRegionOptions,
        labelField: 'name',
        valueField: 'name',
        childrenField: 'children',
        props: {
          class: 'w-full',
          clearable: true,
          filterable: true,
          placeholder: '请选择目的地',
          props: {
            label: 'name',
            value: 'name',
            children: 'children',
            emitPath: true,
            checkStrictly: true
          }
        }
      }
    ]),
    carrierItems: computed<FormItem[]>(() => [
      {
        label: '承运商名称',
        key: 'carrierId',
        type: 'select',
        span: 24,
        description: '更换承运商会清空已选司机和车辆，请重新确认运力。',
        api: fetchCarrierOptions,
        resultField: 'data',
        labelField: 'companyName',
        valueField: 'id',
        labelFn: formatCarrierOption,
        afterFetch: syncCarrierOptions,
        props: {
          clearable: true,
          filterable: true,
          disabled: !canEditSensitiveField('contactPhones'),
          placeholder: '搜索并选择承运商',
          onChange: handleCarrierChange
        }
      },
      {
        label: '联系人姓名',
        key: 'contactName',
        type: 'input',
        span: 12,
        props: { disabled: true, placeholder: '选择承运商后自动带出' }
      },
      ...(canViewSensitiveField('contactPhones')
        ? [
            {
              label: '手机号码',
              key: 'contactPhone',
              type: 'input',
              span: 12,
              props: { disabled: true, placeholder: '选择承运商后自动带出' }
            } satisfies FormItem
          ]
        : [])
    ]),
    capacityItems: computed<FormItem[]>(() => [
      {
        label: '司机姓名',
        key: 'driverId',
        type: 'select',
        span: 12,
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
          disabled: !form.data.carrierId || !canEditSensitiveField('contactPhones'),
          placeholder: form.data.carrierId ? '请选择司机' : '请先选择承运商',
          onVisibleChange: (visible: boolean) => {
            if (visible && form.data.carrierId)
              void capacityFormRef.value?.reloadOptions('driverId')
          },
          onChange: handleDriverChange
        }
      },
      ...(canViewSensitiveField('contactPhones')
        ? [
            {
              label: '手机号码',
              key: 'driverPhone',
              type: 'input',
              span: 12,
              props: { disabled: true, placeholder: '选择司机后自动带出' }
            } satisfies FormItem
          ]
        : []),
      {
        label: '车牌号',
        key: 'vehicleId',
        type: 'select',
        span: 12,
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
          placeholder: form.data.carrierId ? '请选择车辆' : '请先选择承运商',
          onVisibleChange: (visible: boolean) => {
            if (visible && form.data.carrierId)
              void capacityFormRef.value?.reloadOptions('vehicleId')
          },
          onChange: handleVehicleChange
        }
      },
      {
        label: '车型',
        key: 'vehicleType',
        type: 'select',
        span: 12,
        props: { options: form.vehicleTypeOptions, clearable: true, placeholder: '请选择车型' }
      },
      {
        label: '车长',
        key: 'vehicleLength',
        type: 'select',
        span: 12,
        props: { options: form.vehicleLengthOptions, clearable: true, placeholder: '请选择车长' }
      }
    ]),
    feeItems: computed<FormItem[]>(() => [
      {
        label: '计费方式',
        key: 'billingMethod',
        type: 'select',
        props: {
          options: form.billingMethodOptions,
          clearable: true,
          placeholder: '请选择计费方式'
        }
      },
      createSensitiveMoneyItem('运费成本', 'transportCost', 'costAmounts'),
      createSensitiveMoneyItem('其他费用', 'otherFee', 'costAmounts'),
      createSensitiveMoneyItem('分摊运费', 'splitTransportFee', 'costAmounts', true),
      createSensitiveMoneyItem('装卸费', 'loadingFee', 'costAmounts', true),
      createSensitiveMoneyItem('包装费', 'packageFee', 'costAmounts', true),
      createSensitiveMoneyItem('运费合计', 'totalFee', 'costAmounts', true)
    ]),
    paymentItems: computed<FormItem[]>(() => [
      createSensitiveMoneyItem('现付', 'cashAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('预付', 'prepaidAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('到付', 'collectAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('周期付', 'periodicAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('付款合计', 'paymentTotal', 'paymentAmounts', true)
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
      ...(canEditSensitiveField('contactPhones')
        ? {
            carrierId: [{ required: true, message: '请选择承运商名称', trigger: 'change' }]
          }
        : {}),
      billingMethod: [{ required: true, message: '请选择计费方式', trigger: 'change' }],
      ...(canEditSensitiveField('costAmounts')
        ? {
            transportCost: [{ required: true, message: '请输入运费成本', trigger: 'blur' }],
            totalFee: [{ required: true, message: '请输入运费合计', trigger: 'blur' }]
          }
        : {})
    })),
    cargoColumns: computed<ColumnOption<CarrierPriceCargoItem>[]>(() =>
      canEditSensitiveField('costAmounts')
        ? [
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
                <ElSelect
                  v-model={row.unit}
                  class="w-full!"
                  clearable
                  filterable
                  placeholder="请选择"
                >
                  {form.cargoUnitOptions.map((item) => (
                    <ElOption
                      key={item.value}
                      label={item.label || item.value}
                      value={item.value}
                    />
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
              formatter: (row) => (
                <ArtButtonTable type="delete" onClick={() => removeCargoItem(row)} />
              )
            }
          ]
        : createReadonlyCargoColumns()
    ),
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
    cargoWeightText: computed(() => formatNumber(form.cargoSummary.weight, 2)),
    feeTotalText: computed(() =>
      canEditSensitiveField('costAmounts')
        ? formatNumber(form.feeSummary.totalFee, 2)
        : formatSensitiveNumber(form.data.totalFee)
    )
  })

  function createReadonlyCargoColumns(): ColumnOption<CarrierPriceCargoItem>[] {
    const columns: ColumnOption<CarrierPriceCargoItem>[] = [
      { type: 'globalIndex', label: '序号', width: 70 },
      { prop: 'orderNo', label: '订单编号', width: 130 },
      { prop: 'originRegion', label: '始发地', minWidth: 170 },
      { prop: 'destinationRegion', label: '目的地', minWidth: 170 },
      { prop: 'cargoName', label: '货物名称', minWidth: 160 },
      {
        prop: 'quantity',
        label: '数量',
        width: 110,
        align: 'right',
        formatter: (row) => formatNumber(row.quantity, 2)
      },
      { prop: 'unit', label: '单位', width: 100, dict: { code: 'tmsCargoUnit', display: 'text' } },
      {
        prop: 'volumeM3',
        label: '体积（m³）',
        width: 130,
        align: 'right',
        formatter: (row) => formatNumber(row.volumeM3, 3)
      },
      {
        prop: 'weightKg',
        label: '重量（kg）',
        width: 130,
        align: 'right',
        formatter: (row) => formatNumber(row.weightKg, 2)
      }
    ]
    if (!canViewSensitiveField('costAmounts')) return columns
    return [
      ...columns,
      {
        prop: 'splitTransportFee',
        label: '分摊运费（元）',
        width: 140,
        align: 'right',
        formatter: (row) => formatSensitiveNumber(row.splitTransportFee)
      },
      {
        prop: 'loadingFee',
        label: '装卸费（元）',
        width: 130,
        align: 'right',
        formatter: (row) => formatSensitiveNumber(row.loadingFee)
      },
      {
        prop: 'packageFee',
        label: '包装费（元）',
        width: 130,
        align: 'right',
        formatter: (row) => formatSensitiveNumber(row.packageFee)
      }
    ]
  }

  const routeReady = computed(
    () =>
      Boolean(form.data.originRegionPath.length) &&
      Boolean(form.data.destinationRegionPath.length) &&
      Boolean(form.data.transportMode)
  )
  const capacityReady = computed(() =>
    Boolean(
      form.data.driverId || form.data.vehicleId || form.data.vehicleType || form.data.vehicleLength
    )
  )
  const workflowSteps = computed<WorkflowStep[]>(() => {
    const hasCargoCost =
      !canEditSensitiveField('costAmounts') ||
      Boolean(form.data.cargoItems?.some((item) => item.cargoName) && form.data.billingMethod)
    const steps = [
      {
        key: 'route',
        label: '维护运输路线',
        description: '始发地、目的地与方式',
        complete: routeReady.value
      },
      {
        key: 'carrier',
        label: '选择承运商',
        description: '带入联系人信息',
        complete: Boolean(form.data.carrierId)
      },
      {
        key: 'capacity',
        label: '配置运力与货物',
        description: '司机、车辆与货物成本',
        complete: hasCargoCost
      },
      {
        key: 'payment',
        label: '核对成本付款',
        description: '确认总成本与付款拆分',
        complete:
          !canEditSensitiveField('costAmounts') || (hasCargoCost && form.feeSummary.totalFee > 0)
      }
    ]
    const activeIndex = steps.findIndex((step) => !step.complete)

    return steps.map((step, index) => ({
      ...step,
      active: index === (activeIndex === -1 ? steps.length - 1 : activeIndex)
    }))
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

  function getRegionText(mode: RegionMode): string {
    const path = mode === 'origin' ? form.data.originRegionPath : form.data.destinationRegionPath
    return path.filter(Boolean).join(' / ')
  }

  function getTransportModeText(): string {
    const option = form.transportModeOptions.find(
      (item) => String(item.value) === form.data.transportMode
    )
    return String(option?.label || option?.name || option?.value || '')
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
      if (!canEditSensitiveField('costAmounts')) return
      form.data.cargoQuantityTotal = summary.quantity
      form.data.cargoVolumeTotal = summary.volume
      form.data.cargoWeightTotal = summary.weight
    },
    { immediate: true }
  )

  watch(
    () => form.feeSummary,
    (summary) => {
      if (!canEditSensitiveField('costAmounts')) return
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
      if (!canEditSensitiveField('paymentAmounts')) return
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
    if (!canEditSensitiveField('contactPhones')) return
    const carrier = form.carrierOptions.find((item) => item.id === carrierId)
    Object.assign(form.data, {
      contactName: carrier?.contactName ?? '',
      contactPhone: carrier?.contactPhone ?? '',
      driverId: null,
      driver: null,
      driverName: '',
      driverPhone: '',
      vehicleId: null,
      vehicle: null,
      plateNo: ''
    })
    void nextTick(() => {
      void capacityFormRef.value?.reloadOptions('driverId')
      void capacityFormRef.value?.reloadOptions('vehicleId')
    })
  }

  function handleDriverChange(driverId?: string): void {
    if (!canEditSensitiveField('contactPhones')) return
    const driver = form.driverOptions.find((item) => item.id === driverId)
    Object.assign(form.data, {
      driverName: driver?.driverName ?? '',
      driverPhone: driver?.phone ?? ''
    })
  }

  function handleVehicleChange(vehicleId?: string): void {
    const vehicle = form.vehicleOptions.find((item) => item.id === vehicleId)
    Object.assign(form.data, {
      plateNo: vehicle?.plateNo ?? '',
      vehicleType: vehicle?.vehicleType ?? form.data.vehicleType ?? ''
    })
  }

  function addCargoItem(): void {
    if (!canEditSensitiveField('costAmounts')) return
    form.data.cargoItems = [...(form.data.cargoItems ?? []), createInitialCargoItem()]
  }

  async function openCargoSelector(): Promise<void> {
    if (!canEditSensitiveField('costAmounts')) return
    await cargoSelectorRef.value?.open()
  }

  function handleCargoSelectorConfirm(selectedCargoes: CargoMaster[]): void {
    if (!canEditSensitiveField('costAmounts')) return
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
    if (!canEditSensitiveField('costAmounts')) return
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
      'updateTime',
      'fieldAccess',
      'isRecordOwner'
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

    if (!canEditSensitiveField('contactPhones')) {
      removePayloadFields(payload, [
        'carrierId',
        'contactName',
        'contactPhone',
        'driverId',
        'driverName',
        'driverPhone'
      ])
    }
    if (!canEditSensitiveField('costAmounts')) {
      removePayloadFields(payload, [
        'cargoItems',
        'cargoQuantityTotal',
        'cargoVolumeTotal',
        'cargoWeightTotal',
        'transportCost',
        'splitTransportFee',
        'loadingFee',
        'packageFee',
        'otherFee',
        'totalFee'
      ])
    }
    if (!canEditSensitiveField('paymentAmounts')) {
      removePayloadFields(payload, [
        'cashAmount',
        'prepaidAmount',
        'collectAmount',
        'periodicAmount',
        'paymentTotal'
      ])
    }

    return payload
  }

  function removePayloadFields(payload: CarrierPrice, fields: Array<keyof CarrierPrice>): void {
    fields.forEach((field) => Reflect.deleteProperty(payload, field))
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

    &__workflow {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      padding: 0;
      margin: 16px 0 24px;
      overflow: hidden;
      list-style: none;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__workflow-step {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 4px 10px;
      align-items: center;
      min-width: 0;
      padding: 14px 16px;

      & + & {
        border-left: 1px solid var(--el-border-color-lighter);
      }

      &.is-active {
        background: var(--el-color-primary-light-9);

        .carrier-price-edit__workflow-index {
          color: var(--theme-color);
          background: var(--el-bg-color);
          border-color: var(--theme-color);
        }

        .carrier-price-edit__workflow-status {
          color: var(--theme-color);
        }
      }

      &.is-complete {
        .carrier-price-edit__workflow-index {
          color: #fff;
          background: var(--theme-color);
          border-color: var(--theme-color);
        }
      }
    }

    &__workflow-index {
      display: inline-flex;
      grid-row: 1 / 3;
      align-items: center;
      justify-content: center;
      width: 30px;
      height: 30px;
      font-size: 13px;
      font-weight: 600;
      color: var(--el-text-color-secondary);
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color);
      border-radius: 50%;
    }

    &__workflow-copy {
      display: flex;
      flex-direction: column;
      min-width: 0;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 14px;
        font-weight: 600;
        line-height: 20px;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
        white-space: normal;
      }
    }

    &__workflow-status {
      align-self: start;
      font-size: 12px;
      line-height: 20px;
      color: var(--el-text-color-placeholder);
      white-space: nowrap;
    }

    &__route-preview {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr) auto;
      gap: 14px;
      align-items: center;
      min-width: 0;
      padding: 14px 16px;
      margin-top: 8px;
      background: var(--el-fill-color-extra-light);
      border: 1px dashed var(--el-border-color);
      border-radius: var(--el-border-radius-base);

      &.is-ready {
        background: var(--el-color-primary-light-9);
        border-color: var(--theme-color);
        border-style: solid;
      }
    }

    &__route-point {
      display: flex;
      flex-direction: column;
      min-width: 0;

      span {
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 14px;
        font-weight: 600;
        line-height: 22px;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    &__route-arrow {
      font-size: 18px;
      color: var(--theme-color);
    }

    &__carrier-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 16px;
      margin-top: 16px;
    }

    &__carrier-panel {
      min-width: 0;
      padding: 16px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__panel-heading {
      display: flex;
      gap: 10px;
      align-items: center;
      margin-bottom: 16px;
    }

    &__panel-icon {
      display: inline-flex;
      flex: none;
      align-items: center;
      justify-content: center;
      width: 36px;
      height: 36px;
      font-size: 16px;
      font-weight: 600;
      color: #fff;
      background: var(--theme-color);
      border-radius: var(--el-border-radius-base);

      &--capacity {
        background: var(--el-color-success);
      }
    }

    &__panel-copy {
      display: flex;
      flex: 1;
      flex-direction: column;
      min-width: 0;

      strong {
        font-size: 15px;
        font-weight: 600;
        line-height: 22px;
        color: var(--el-text-color-primary);
      }

      span {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    &__cost-header {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      padding-top: 18px;
      margin-top: 20px;
      border-top: 1px solid var(--el-border-color-lighter);

      p {
        margin: 4px 0 0;
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
      }
    }

    &__cost-total {
      display: flex;
      flex: none;
      gap: 12px;
      align-items: baseline;
      padding: 10px 14px;
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 20px;
        font-weight: 600;
        color: var(--theme-color);
      }
    }

    &__payment-header {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;

      > span {
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
      }
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

  @media (width <= 900px) {
    .carrier-price-edit {
      &__workflow {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__workflow-step {
        &:nth-child(3) {
          border-left: 0;
        }

        &:nth-child(n + 3) {
          border-top: 1px solid var(--el-border-color-lighter);
        }
      }

      &__carrier-grid {
        grid-template-columns: 1fr;
      }
    }
  }

  @media (width <= 600px) {
    .carrier-price-edit {
      padding: 0;

      &__section {
        padding: 16px 12px 20px;
      }

      &__workflow {
        grid-template-columns: 1fr;
      }

      &__workflow-step {
        & + & {
          border-top: 1px solid var(--el-border-color-lighter);
          border-left: 0;
        }
      }

      &__route-preview {
        grid-template-columns: 1fr;
      }

      &__route-arrow {
        transform: rotate(90deg);
      }

      &__carrier-panel {
        padding: 14px 12px;
      }

      &__panel-copy span {
        white-space: normal;
      }

      &__cost-header,
      &__payment-header {
        flex-direction: column;
        align-items: stretch;
      }

      &__cost-total {
        justify-content: space-between;
      }

      :deep(.carrier-price-edit__form .el-col-xs-8),
      :deep(.carrier-price-edit__form .el-col-xs-12) {
        flex: 0 0 100%;
        max-width: 100%;
      }
    }
  }
</style>
