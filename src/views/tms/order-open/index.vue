<template>
  <ArtPageShell
    class="order-open"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    @retry="initializePage"
  >
    <div ref="pageRef" class="order-open__content">
      <ArtPageHeader
        title="货物运输单"
        :subtitle="
          isNewOrder ? '填写运输业务信息，保存后进入调度流程。' : '核对并更新运输业务信息。'
        "
        class="order-open__page-header"
      >
        <template #status>
          <ElTag :type="isNewOrder ? 'primary' : 'warning'" effect="plain">
            {{ isNewOrder ? '新建订单' : '编辑订单' }}
          </ElTag>
        </template>
        <template #meta>
          <div class="order-open__document-meta">
            <label class="order-open__document-number">
              <span>运单号</span>
              <ElInput
                v-if="isNewOrder && orderNumberRule && !orderNumberRule.autoEnabled"
                v-model="form.data.orderNo"
                size="small"
                maxlength="50"
                placeholder="请手工填写运单号"
              />
              <strong v-else translate="no">{{
                form.data.orderNo || orderNumberRule?.preview || '保存后自动生成'
              }}</strong>
            </label>
            <label class="order-open__document-number">
              <span>货号</span>
              <ElInput
                v-if="isNewOrder && cargoNumberRule && !cargoNumberRule.autoEnabled"
                v-model="form.data.cargoNo"
                size="small"
                maxlength="50"
                placeholder="可手工填写货号"
              />
              <strong v-else translate="no">{{
                form.data.cargoNo || cargoNumberRule?.preview || '保存后自动生成'
              }}</strong>
            </label>
            <span class="order-open__time">
              <ArtSvgIcon icon="ri:calendar-line" aria-hidden="true" />
              {{ page.nowText }}
            </span>
          </div>
        </template>
      </ArtPageHeader>

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
              <ArtSectionTitle :show-line="false" class="order-open__contact-title">
                发货人信息
              </ArtSectionTitle>
              <div class="order-open__contact-actions">
                <ElButton
                  v-if="canEditContactEndpoint('shipping')"
                  size="small"
                  type="primary"
                  plain
                  @click="openFavoriteRouteSelector"
                >
                  <ArtSvgIcon icon="ri:route-line" />
                  选择线路
                </ElButton>
                <ElButton
                  v-if="canEditContactEndpoint('shipping')"
                  size="small"
                  @click="openCustomerSelector('shipping')"
                >
                  选择地址
                </ElButton>
              </div>
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
            <ElButton
              v-if="canEditContactEndpoint('shipping') && canEditContactEndpoint('receiving')"
              circle
              text
              aria-label="交换发货人与收货人"
              @click="swapContacts"
            >
              <ArtSvgIcon icon="ri:arrow-left-right-line" />
            </ElButton>
          </div>

          <div class="order-open__contact-panel">
            <div class="order-open__contact-heading">
              <ArtSectionTitle :show-line="false" class="order-open__contact-title">
                收货人信息
              </ArtSectionTitle>
              <ElButton
                v-if="canEditContactEndpoint('receiving')"
                size="small"
                @click="openCustomerSelector('receiving')"
                >选择地址</ElButton
              >
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
          <div class="order-open__section-actions">
            <ElButton
              v-if="canEditOrderField('cargoPricing')"
              plain
              @click="openContractDetailSelector"
            >
              <template #icon><ArtSvgIcon icon="ri:file-list-3-line" /></template>
              批量选合同明细
            </ElButton>
            <ElButton plain :icon="Collection" @click="openCargoSelector">批量选货物</ElButton>
            <ElButton type="primary" plain :icon="Plus" @click="addCargoItem">添加</ElButton>
          </div>
        </div>
        <ArtTable
          :data="form.cargoItems"
          :columns="form.cargoColumns"
          :pagination="undefined"
          :show-table-header="false"
          table-layout="fixed"
          empty-height="160px"
          empty-text="尚未添加货物"
          empty-description="可选择常用货物或手动添加货物明细"
        />
        <div class="order-open__cargo-summary">
          <span>总数量：{{ form.cargoQuantityText }}</span>
          <span>总重量：{{ form.cargoWeightText }}kg</span>
          <span>总体积：{{ form.cargoVolumeText }}方</span>
        </div>
      </section>

      <section v-if="canViewOrderField('freightAmounts')" class="order-open__section art-card-xs">
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
        <div v-if="canViewOrderField('proofAttachments')" class="order-open__upload-row">
          <span>图片上传</span>
          <ArtUploadImage
            v-model="form.data.imageUrls"
            title="上传图片"
            :size="104"
            :limit="3"
            multiple
            :readonly="!canEditOrderField('proofAttachments')"
          />
        </div>
      </section>

      <ArtStickyActionBar class="order-open__footer">
        <template #summary>
          <div v-if="canViewOrderField('freightAmounts')" class="order-open__footer-total">
            <span>总运费：</span>
            <strong>￥{{ form.totalFeeText }}</strong>
            <ElPopover
              placement="top-start"
              width="280"
              trigger="click"
              popper-class="order-open-fee-popover"
            >
              <template #reference>
                <ElButton link type="primary">
                  明细 <ArtSvgIcon icon="ri:arrow-down-s-line" />
                </ElButton>
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
        </template>

        <div class="order-open__footer-actions order-open__footer-actions--desktop">
          <ElButton
            v-auth="'TmsOrderOpen:Create'"
            size="large"
            type="primary"
            :loading="page.saving"
            @click="handleSaveOnly"
          >
            仅开单
          </ElButton>
          <ElButton
            v-auth="'TmsOrderOpen:AiFill'"
            size="large"
            type="primary"
            plain
            @click="openAiOrderDrawer"
          >
            AI智能填单
          </ElButton>
          <ElButton
            v-auth="'TmsOrderOpen:PrintWaybill'"
            size="large"
            plain
            @click="openPrintDialog('waybill')"
          >
            打印运单
          </ElButton>
          <ElButton
            v-auth="'TmsOrderOpen:PrintLabel'"
            size="large"
            plain
            @click="openPrintDialog('label')"
          >
            打印标签
          </ElButton>
          <ElButton
            v-auth="'TmsOrderOpen:DoublePrint'"
            size="large"
            plain
            @click="handleDoublePrint"
            >双打</ElButton
          >
        </div>

        <div class="order-open__footer-actions order-open__footer-actions--mobile">
          <ElButton
            v-auth="'TmsOrderOpen:Create'"
            size="large"
            type="primary"
            :loading="page.saving"
            @click="handleSaveOnly"
          >
            仅开单
          </ElButton>
          <ElDropdown trigger="click" @command="handleFooterCommand">
            <ElButton size="large" plain>
              更多操作
              <ArtSvgIcon icon="ri:arrow-down-s-line" />
            </ElButton>
            <template #dropdown>
              <ElDropdownMenu>
                <ElDropdownItem v-auth="'TmsOrderOpen:AiFill'" command="ai">
                  AI 智能填单
                </ElDropdownItem>
                <ElDropdownItem v-auth="'TmsOrderOpen:PrintWaybill'" command="print-waybill">
                  打印运单
                </ElDropdownItem>
                <ElDropdownItem v-auth="'TmsOrderOpen:PrintLabel'" command="print-label">
                  打印标签
                </ElDropdownItem>
                <ElDropdownItem v-auth="'TmsOrderOpen:DoublePrint'" command="double-print">
                  双打
                </ElDropdownItem>
              </ElDropdownMenu>
            </template>
          </ElDropdown>
        </div>
      </ArtStickyActionBar>

      <CustomerSelectorDialog ref="customerDialogRef" @select="handleCustomerSelect" />
      <FavoriteRouteSelectorDialog
        ref="favoriteRouteDialogRef"
        @select="handleFavoriteRouteSelect"
      />
      <PrintCountDialog ref="printDialogRef" @confirm="handlePrintConfirm" />
      <ContractDetailMultipleSelect
        ref="contractDetailSelectorRef"
        @confirm="handleContractDetailSelectorConfirm"
      />
      <CargoMultipleSelect ref="cargoSelectorRef" @confirm="handleCargoSelectorConfirm" />
      <AiOrderDrawer ref="aiOrderDrawerRef" @apply="handleAiOrderApply" />
    </div>
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { useDateFormat, useNow } from '@vueuse/core'
  import { cloneDeep, isNil, round } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import { ElAutocomplete, ElInputNumber, ElMessage, ElOption, ElSelect } from 'element-plus'
  import { Collection, Plus } from '@element-plus/icons-vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import { useAmapGeocoder } from '@/hooks/core/useAmapGeocoder'
  import type { ColumnOption } from '@/types'
  import { formatNameCodeOption } from '@/utils/form'
  import { canEditField, canViewField, getFieldAccess } from '@/utils/field-permission'
  import {
    addOrder,
    editOrder,
    fetchCargoList,
    fetchCustomerDefaultAddress,
    fetchCustomerPriceList,
    fetchOrderDetail,
    fetchStationOptions,
    reviewAiOrderArtifact
  } from '@/api/tms'
  import { fetchDocumentNumberRulesByKeys } from '@/api/document-number'
  import { useUserStore } from '@/store/modules/user'
  import { clearFormRefsValidation, validateFormRefs } from '@/utils/form/validation'
  import CargoMultipleSelect from '../modules/cargo-multiple-select.vue'
  import ContractDetailMultipleSelect from './modules/contract-detail-multiple-select.vue'
  import {
    calculateContractTransportFee,
    mergeOrderContractDetails,
    synchronizeContractCargoFreight
  } from './modules/order-contract-detail'
  import AiOrderDrawer from './modules/ai-order-drawer.vue'
  import { buildAiOrderFinalPayload } from './modules/ai-order-review'
  import CustomerSelectorDialog from './modules/customer-selector-dialog.vue'
  import FavoriteRouteSelectorDialog from './modules/favorite-route-selector-dialog.vue'
  import PrintCountDialog from './modules/print-count-dialog.vue'
  import type {
    AiAddressReferenceMatch,
    AiOrderApplyPayload,
    AiOrderDrawerExpose
  } from './modules/ai-order-types'
  import {
    createInitialCargoItem,
    createInitialForm,
    createCustomerPriceBusinessPatch,
    createFavoriteRouteContactPatch,
    calculateOrderCargoSummary,
    formatNumber,
    formatOrderAddress,
    getDictLabel,
    moneyValue,
    nullableNumber,
    normalizeOrderPayload,
    numericValue,
    textValue,
    type OrderForm
  } from './modules/order-open-model'

  defineOptions({ name: 'TmsOrderOpen' })

  type OrderRecord = Api.Tms.Order.OrderRecord
  type CargoItem = Api.Tms.Order.CargoItem
  type CargoMaster = Api.Tms.BasicData.Cargo
  type ContractDetail = Api.Tms.BasicData.ContractDetailSelectorItem
  type CustomerItem = Api.Tms.Order.CustomerSelectorItem
  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerPriceCargoItem = Api.Tms.BasicData.CustomerPriceCargoItem
  type FavoriteRoute = Api.Tms.BasicData.FavoriteRoute
  type StationOption = Api.Tms.Order.StationOption
  type SelectorMode = 'shipping' | 'receiving'
  type StationMode = 'origin' | 'destination' | 'transfer'
  type PrintKind = 'waybill' | 'label'
  type FooterCommand = 'ai' | 'print-waybill' | 'print-label' | 'double-print'
  type CargoSuggestionCallback = (items: CargoSuggestion[]) => void

  interface CargoSuggestion extends CargoMaster {
    value: string
  }

  type ContactPatch = Partial<
    Pick<
      OrderForm,
      | 'shippingCustomerId'
      | 'shippingCustomerName'
      | 'shippingAddressId'
      | 'shippingContactName'
      | 'shippingContactPhone'
      | 'shippingAddressDetail'
      | 'shippingLongitude'
      | 'shippingLatitude'
      | 'receivingCustomerId'
      | 'receivingCustomerName'
      | 'receivingAddressId'
      | 'receivingContactName'
      | 'receivingContactPhone'
      | 'receivingAddressDetail'
      | 'receivingLongitude'
      | 'receivingLatitude'
    >
  >

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface CustomerSelectorExpose {
    handleOpen: (mode: SelectorMode) => Promise<void>
  }

  interface FavoriteRouteSelectorExpose {
    handleOpen: () => Promise<void>
  }

  interface PrintDialogExpose {
    handleOpen: (data: { kind: PrintKind; cargoQuantity: number }) => Promise<void>
  }

  interface CargoSelectorExpose {
    open: () => Promise<void>
  }

  interface ContractDetailSelectorExpose {
    open: () => Promise<void>
  }

  interface PageGroup {
    loading: boolean
    saving: boolean
    nowText: ComputedRef<string>
    error: Error | null
  }

  interface CargoSummary {
    quantity: number
    weight: number
    volume: number
  }

  interface AiAddressCoordinateResolution {
    patch: ContactPatch
    failed: boolean
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
  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { geocodeAddress } = useAmapGeocoder()
  const { getDictMap } = storeToRefs(userStore)
  const stationFormRef = ref<FormExpose>()
  const shippingFormRef = ref<FormExpose>()
  const receivingFormRef = ref<FormExpose>()
  const feeFormRef = ref<FormExpose>()
  const paymentFormRef = ref<FormExpose>()
  const otherFormRef = ref<FormExpose>()
  const customerDialogRef = ref<CustomerSelectorExpose>()
  const favoriteRouteDialogRef = ref<FavoriteRouteSelectorExpose>()
  const printDialogRef = ref<PrintDialogExpose>()
  const cargoSelectorRef = ref<CargoSelectorExpose>()
  const contractDetailSelectorRef = ref<ContractDetailSelectorExpose>()
  const aiOrderDrawerRef = ref<AiOrderDrawerExpose>()
  const aiArtifactId = ref<string>()
  const initializedOrderId = ref<string>()
  const numberRules = ref<Record<string, Api.SystemManage.DocumentNumberRuleItem>>({})
  const validatedFormRefs = [stationFormRef, shippingFormRef, receivingFormRef, paymentFormRef]

  const dictCodes = [
    'tmsOrderDeliveryMethod',
    'tmsOrderPaymentMethod',
    'tmsOrderTransportMode',
    'tmsCargoUnit'
  ]

  const isNewOrder = computed(() => !getOrderId())
  const orderNumberRule = computed(() => numberRules.value['tms.order'])
  const cargoNumberRule = computed(() => numberRules.value['tms.order_cargo'])

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
    nowText: useDateFormat(useNow({ interval: 1000 }), 'YYYY/MM/DD HH:mm:ss'),
    error: null
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
        label: '客户名称',
        key: 'shippingCustomerName',
        type: 'input',
        props: { maxlength: 100, readonly: true, placeholder: '请选择发货方客户' }
      },
      {
        label: '姓名',
        key: 'shippingContactName',
        type: 'input',
        props: { maxlength: 50, placeholder: '请输入发货人姓名' }
      },
      ...(canViewOrderField('shipperContact')
        ? [
            {
              label: '手机号',
              key: 'shippingContactPhone',
              type: 'input' as const,
              props: {
                maxlength: 20,
                placeholder: '请输入发货人手机号',
                readonly: !canEditOrderField('shipperContact')
              }
            }
          ]
        : []),
      ...(canViewOrderField('shipperAddress')
        ? [
            {
              label: '发货地址',
              key: 'shippingAddressDetail',
              type: 'input' as const,
              props: {
                maxlength: 200,
                placeholder: '请输入发货地址',
                readonly: !canEditOrderField('shipperAddress'),
                onInput: () => clearAddressCoordinates('shipping')
              }
            }
          ]
        : [])
    ]),
    receivingItems: computed<FormItem[]>(() => [
      {
        label: '客户名称',
        key: 'receivingCustomerName',
        type: 'input',
        props: { maxlength: 100, readonly: true, placeholder: '请选择收货方客户' }
      },
      {
        label: '姓名',
        key: 'receivingContactName',
        type: 'input',
        props: { maxlength: 50, placeholder: '请输入收货人姓名' }
      },
      ...(canViewOrderField('receiverContact')
        ? [
            {
              label: '手机号',
              key: 'receivingContactPhone',
              type: 'input' as const,
              props: {
                maxlength: 20,
                placeholder: '请输入收货人手机号',
                readonly: !canEditOrderField('receiverContact')
              }
            }
          ]
        : []),
      ...(canViewOrderField('receiverAddress')
        ? [
            {
              label: '收货地址',
              key: 'receivingAddressDetail',
              type: 'input' as const,
              props: {
                maxlength: 200,
                placeholder: '请输入收货地址，配送上门请输入详细地址',
                readonly: !canEditOrderField('receiverAddress'),
                onInput: () => clearAddressCoordinates('receiving')
              }
            }
          ]
        : [])
    ]),
    feeItems: computed<FormItem[]>(() => {
      const props = { ...moneyProps, disabled: !canEditOrderField('freightAmounts') }
      return [
        { label: '运费', key: 'transportFee', type: 'number', props },
        { label: '配送费', key: 'deliveryFee', type: 'number', props },
        { label: '卸货费', key: 'unloadingFee', type: 'number', props },
        { label: '回款费', key: 'collectPaymentFee', type: 'number', props },
        { label: '中转费', key: 'transferFee', type: 'number', props },
        { label: '保费', key: 'insuranceFee', type: 'number', props },
        { label: '包装费', key: 'packageFee', type: 'number', props },
        { label: '其他费用', key: 'otherFee', type: 'number', props }
      ]
    }),
    paymentItems: computed<FormItem[]>(() => [
      {
        label: '付款方式',
        key: 'paymentMethod',
        type: 'radioGroup',
        span: 24,
        props: { options: form.paymentMethodOptions }
      },
      ...(canViewOrderField('settlementAmounts')
        ? [
            { label: '声明价值', key: 'declaredValue', type: 'number' as const },
            { label: '现付', key: 'cashAmount', type: 'number' as const },
            { label: '到付', key: 'collectAmount', type: 'number' as const },
            { label: '月结', key: 'monthlyAmount', type: 'number' as const },
            { label: '代收货款', key: 'codAmount', type: 'number' as const },
            { label: '手续费', key: 'handlingFee', type: 'number' as const }
          ].map((item) => ({
            ...item,
            props: { ...moneyProps, disabled: !canEditOrderField('settlementAmounts') }
          }))
        : [])
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
      ...(canEditOrderField('shipperContact')
        ? {
            shippingContactPhone: [
              { required: true, message: '请输入发货人手机号', trigger: 'blur' }
            ]
          }
        : {}),
      ...(canEditOrderField('shipperAddress')
        ? {
            shippingAddressDetail: [{ required: true, message: '请输入发货地址', trigger: 'blur' }]
          }
        : {}),
      receivingContactName: [{ required: true, message: '请输入收货人姓名', trigger: 'blur' }],
      ...(canEditOrderField('receiverContact')
        ? {
            receivingContactPhone: [
              { required: true, message: '请输入收货人手机号', trigger: 'blur' }
            ]
          }
        : {}),
      ...(canEditOrderField('receiverAddress')
        ? {
            receivingAddressDetail: [{ required: true, message: '请输入收货地址', trigger: 'blur' }]
          }
        : {}),
      paymentMethod: [{ required: true, message: '请选择付款方式', trigger: 'change' }]
    })),
    cargoColumns: computed<ColumnOption<CargoItem>[]>(() => [
      { type: 'globalIndex', label: '序号', width: 58 },
      {
        prop: 'cargoName',
        label: '货物名称',
        minWidth: 180,
        formatter: (row) => (
          <ElAutocomplete
            v-model={row.cargoName}
            aria-label="货物名称"
            fetchSuggestions={(keyword, callback) =>
              void fetchCargoSuggestions(keyword, callback as CargoSuggestionCallback)
            }
            triggerOnFocus={true}
            valueKey="value"
            maxlength={80}
            clearable
            placeholder="请选择或输入货物名称"
            onSelect={(item) => handleCargoSelect(row, item)}
          />
        )
      },
      {
        prop: 'cargoCode',
        label: '货物编码',
        width: 130,
        formatter: (row) => row.cargoCode || '-'
      },
      {
        prop: 'packageType',
        label: '计量单位',
        width: 150,
        formatter: (row) => (
          <ElSelect
            v-model={row.packageType}
            aria-label="计量单位"
            class="w-full!"
            clearable
            placeholder="请选择"
          >
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
          <ElInputNumber
            modelValue={row.quantity}
            aria-label="货物数量"
            {...countProps}
            precision={2}
            controls={false}
            onUpdate:modelValue={(value?: number) => handleCargoQuantityChange(row, value)}
          />
        )
      },
      {
        prop: 'weightKg',
        label: '重量(kg)',
        width: 150,
        formatter: (row) => (
          <ElInputNumber
            v-model={row.weightKg}
            aria-label="货物重量"
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
            aria-label="货物体积"
            min={0}
            precision={3}
            controls={false}
            class="w-full!"
          />
        )
      },
      ...(canViewOrderField('cargoPricing')
        ? [
            {
              prop: 'unitPrice',
              label: '合同单价(元)',
              width: 145,
              formatter: (row: CargoItem) =>
                row.sourceContractId ? `¥ ${formatNumber(row.unitPrice)}` : '-'
            },
            {
              prop: 'freight',
              label: '运费(元)',
              width: 135,
              formatter: (row: CargoItem) =>
                row.sourceContractId ? `¥ ${formatNumber(row.freight)}` : '-'
            }
          ]
        : []),
      {
        prop: 'sourceContractNo',
        label: '来源合同',
        minWidth: 150,
        formatter: (row) => row.sourceContractNo || '-'
      },
      {
        prop: 'operation',
        label: '操作',
        width: 90,
        formatter: (row) => <ArtButtonTable type="delete" onClick={() => removeCargoItem(row)} />
      }
    ]),
    cargoItems: computed(() => form.data.cargoItems ?? []),
    cargoSummary: computed(() => calculateOrderCargoSummary(form.data.cargoItems)),
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
    await initializePage()
  })

  onActivated(() => {
    void initializePage()
  })

  function getOrderId(): string {
    return typeof route.query.id === 'string' ? route.query.id : ''
  }

  async function initializePage(): Promise<void> {
    const orderId = getOrderId()
    if (page.loading || (initializedOrderId.value === orderId && !page.error)) return

    page.loading = true
    page.error = null
    try {
      aiArtifactId.value = undefined
      await Promise.all([
        ...dictCodes.map((code) => userStore.ensureDictLoaded(code)),
        loadNumberRules()
      ])
      if (orderId) await loadOrderDetail(orderId)
      else replaceForm(createInitialForm())
      fillDefaultOptions()
      await nextTick()
      clearFormRefsValidation(validatedFormRefs)
      initializedOrderId.value = orderId
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('开单信息加载失败')
    } finally {
      page.loading = false
    }
  }

  async function loadNumberRules(): Promise<void> {
    const { data } = await fetchDocumentNumberRulesByKeys(['tms.order', 'tms.order_cargo'])
    numberRules.value = Object.fromEntries((data ?? []).map((rule) => [rule.ruleKey, rule]))
  }

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
    () =>
      (form.data.cargoItems ?? []).map((item) => [
        item.sourceContractId,
        item.quantity,
        item.unitPrice
      ]),
    syncContractFreightTotals,
    { deep: true, immediate: true }
  )

  function syncContractFreightTotals(): void {
    const result = synchronizeContractCargoFreight(form.data.cargoItems ?? [])
    if (result.hasContractCargo) form.data.transportFee = result.transportFee
  }

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

  async function loadOrderDetail(id: string): Promise<void> {
    const { data } = await fetchOrderDetail(id)
    if (!data) {
      ElMessage.warning('订单不存在或无权访问')
      await router.replace({ name: 'TmsOrderList' })
      return
    }
    if (data.orderStatus !== 'pending_load') {
      ElMessage.warning('只有待配载订单可以编辑')
      await router.replace({ name: 'TmsOrderList' })
      return
    }

    replaceForm({
      ...createInitialForm(),
      ...cloneDeep(data),
      cargoItems: data.cargoItems?.length ? cloneDeep(data.cargoItems) : [createInitialCargoItem()],
      imageUrls: data.imageUrls ?? []
    })
  }

  function replaceForm(nextForm: OrderForm): void {
    const clonedForm = cloneDeep(nextForm)
    Object.assign(form.data, createInitialForm(), clonedForm, {
      shippingCustomerName:
        clonedForm.shippingCustomerName || clonedForm.shippingCustomer?.customerName || '',
      receivingCustomerName:
        clonedForm.receivingCustomerName || clonedForm.receivingCustomer?.customerName || ''
    })
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
    return formatNameCodeOption(option, 'stationName', 'regionCode')
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

  function handleCargoQuantityChange(row: CargoItem, value?: number): void {
    form.data.cargoItems = (form.data.cargoItems ?? []).map((item) =>
      item === row ? { ...item, quantity: nullableNumber(value) } : item
    )
  }

  async function openCargoSelector(): Promise<void> {
    await cargoSelectorRef.value?.open()
  }

  async function openContractDetailSelector(): Promise<void> {
    await contractDetailSelectorRef.value?.open()
  }

  function handleContractDetailSelectorConfirm(selectedDetails: ContractDetail[]): void {
    const result = mergeOrderContractDetails(form.data.cargoItems ?? [], selectedDetails)
    if (!result.addedCount) return
    form.data.cargoItems = result.items
    form.data.transportFee = calculateContractTransportFee(result.items)
  }

  function handleCargoSelectorConfirm(selectedCargoes: CargoMaster[]): void {
    const currentItems = form.data.cargoItems ?? []
    const existingNames = new Set(
      currentItems.map((item) => textValue(item.cargoName)).filter(Boolean)
    )
    const additions = selectedCargoes
      .filter((item) => item.cargoName && !existingNames.has(item.cargoName))
      .map(createCargoItemFromMaster)
    if (!additions.length) return

    const isSingleEmptyRow = currentItems.length === 1 && !textValue(currentItems[0].cargoName)
    form.data.cargoItems = isSingleEmptyRow ? additions : [...currentItems, ...additions]
  }

  function removeCargoItem(row: CargoItem): void {
    const rows = form.data.cargoItems ?? []
    if (rows.length <= 1) {
      form.data.cargoItems = [createInitialCargoItem()]
      if (row.sourceContractId) form.data.transportFee = 0
      return
    }
    form.data.cargoItems = rows.filter((item) => item !== row)
    if (row.sourceContractId) {
      form.data.transportFee = calculateContractTransportFee(form.data.cargoItems)
    }
  }

  async function fetchCargoSuggestions(
    keyword: string,
    callback: CargoSuggestionCallback
  ): Promise<void> {
    try {
      const result = await fetchCargoList({
        keyword: textValue(keyword),
        enabled: true,
        from: 0,
        to: 19
      })
      callback((result.data ?? []).map(createCargoSuggestion))
    } catch {
      callback([])
    }
  }

  function createCargoSuggestion(item: CargoMaster): CargoSuggestion {
    return {
      ...item,
      value: item.cargoName
    }
  }

  function createCargoItemFromMaster(cargo: CargoMaster): CargoItem {
    return {
      ...createInitialCargoItem(),
      cargoId: cargo.id ?? null,
      cargoName: cargo.cargoName,
      cargoCode: cargo.cargoCode ?? '',
      packageType: cargo.unit || '',
      quantity: 1,
      unit: cargo.unit || '',
      weightKg: cargo.weightKg ?? null,
      volumeM3: cargo.volumeM3 ?? null
    }
  }

  function handleCargoSelect(row: CargoItem, item: Record<string, unknown>): void {
    const wasContractCargo = Boolean(row.sourceContractId)
    const cargoName = String(item.cargoName ?? item.value ?? '')
    const unit = String(item.unit ?? '')
    const weightKg = typeof item.weightKg === 'number' ? item.weightKg : null
    const volumeM3 = typeof item.volumeM3 === 'number' ? item.volumeM3 : null
    const patch: Partial<CargoItem> = {
      cargoId: item.id ? String(item.id) : null,
      cargoName,
      cargoCode: String(item.cargoCode ?? ''),
      packageType: unit || row.packageType || '',
      unit: unit || row.unit || '',
      quantity: row.quantity ?? 1,
      weightKg: weightKg ?? row.weightKg ?? null,
      volumeM3: volumeM3 ?? row.volumeM3 ?? null,
      unitPrice: null,
      freight: null,
      sourceContractId: null,
      sourceContractNo: null,
      sourceContractName: null,
      sourceContractDetailKey: null
    }
    Object.assign(row, patch)
    if (wasContractCargo) {
      form.data.transportFee = calculateContractTransportFee(form.data.cargoItems ?? [])
    }
  }

  function openCustomerSelector(mode: SelectorMode): void {
    void customerDialogRef.value?.handleOpen(mode)
  }

  function openFavoriteRouteSelector(): void {
    void favoriteRouteDialogRef.value?.handleOpen()
  }

  async function handleFavoriteRouteSelect(route: FavoriteRoute): Promise<void> {
    Object.assign(form.data, createFavoriteRouteContactPatch(route))
    await nextTick()
    clearFormRefsValidation(validatedFormRefs)
    ElMessage.success(`已带入常用线路“${route.routeName}”的发货与收货信息`)
  }

  async function handleCustomerSelect(mode: SelectorMode, row: CustomerItem): Promise<void> {
    Object.assign(form.data, await createCustomerContactPatch(mode, row))
    await applyCustomerPriceTemplate(row.id)
  }

  async function createCustomerContactPatch(
    mode: SelectorMode,
    customer: CustomerItem
  ): Promise<ContactPatch> {
    const address = await fetchDefaultAddress(customer.id, mode)
    return createAddressPatch(mode, customer, address)
  }

  async function fetchDefaultAddress(
    customerId: string,
    mode: SelectorMode
  ): Promise<CustomerAddress | null> {
    const { data } = await fetchCustomerDefaultAddress(customerId, mode)
    return data ?? null
  }

  function createAddressPatch(
    mode: SelectorMode,
    customer: CustomerItem,
    address?: CustomerAddress | null
  ): ContactPatch {
    const contactName = address?.contactName || customer.contactName || customer.customerName
    const effectiveAccess = address?.fieldAccess ?? customer.fieldAccess
    const phoneAccess = getFieldAccess(effectiveAccess, 'contactPhone')
    const addressAccess = getFieldAccess(effectiveAccess, 'addressDetail')
    const canReadPhone = phoneAccess === 'read' || phoneAccess === 'edit'
    const canReadAddress = addressAccess === 'read' || addressAccess === 'edit'
    const contactPhone = canReadPhone ? address?.contactPhone || customer.contactPhone || '' : ''
    const addressText = canReadAddress
      ? formatOrderAddress(
          address?.region || customer.region,
          address?.addressDetail || customer.addressDetail
        )
      : ''
    const longitude = canReadAddress ? (address?.longitude ?? customer.longitude ?? null) : null
    const latitude = canReadAddress ? (address?.latitude ?? customer.latitude ?? null) : null

    const patchMap: Record<SelectorMode, ContactPatch> = {
      shipping: {
        shippingCustomerId: customer.id,
        shippingCustomerName: customer.customerName,
        shippingAddressId: address?.id ?? null,
        shippingContactName: contactName,
        shippingContactPhone: contactPhone,
        shippingAddressDetail: addressText,
        shippingLongitude: longitude,
        shippingLatitude: latitude
      },
      receiving: {
        receivingCustomerId: customer.id,
        receivingCustomerName: customer.customerName,
        receivingAddressId: address?.id ?? null,
        receivingContactName: contactName,
        receivingContactPhone: contactPhone,
        receivingAddressDetail: addressText,
        receivingLongitude: longitude,
        receivingLatitude: latitude
      }
    }

    return patchMap[mode]
  }

  async function applyCustomerPriceTemplate(customerId: string): Promise<void> {
    try {
      const { data } = await fetchCustomerPriceList({
        customerId,
        from: 0,
        to: 0
      })
      const price = data?.[0]
      if (!price) return

      Object.assign(form.data, createCustomerPriceBusinessPatch(price, form.data.orderRemark))
      if (price.cargoItems?.length) {
        form.data.cargoItems = price.cargoItems.map(createCargoItemFromCustomerPrice)
      }
      await nextTick()
      clearFormRefsValidation(validatedFormRefs)
      ElMessage.success('已带入客户价格维护中的费用与货物信息')
    } catch {
      // 价格模板只是辅助回填，查询失败时保留已选择的客户基础信息。
    }
  }

  function createCargoItemFromCustomerPrice(item: CustomerPriceCargoItem): CargoItem {
    return {
      cargoName: textValue(item.cargoName),
      packageType: textValue(item.unit),
      quantity: nullableNumber(item.quantity),
      unit: textValue(item.unit),
      weightKg: nullableNumber(item.weightKg),
      volumeM3: nullableNumber(item.volumeM3)
    }
  }

  function swapContacts(): void {
    const shipping = {
      id: form.data.shippingCustomerId,
      customerName: form.data.shippingCustomerName,
      addressId: form.data.shippingAddressId,
      name: form.data.shippingContactName,
      phone: form.data.shippingContactPhone,
      address: form.data.shippingAddressDetail,
      longitude: form.data.shippingLongitude,
      latitude: form.data.shippingLatitude
    }

    Object.assign(form.data, {
      shippingCustomerId: form.data.receivingCustomerId,
      shippingCustomerName: form.data.receivingCustomerName,
      shippingAddressId: form.data.receivingAddressId,
      shippingContactName: form.data.receivingContactName,
      shippingContactPhone: form.data.receivingContactPhone,
      shippingAddressDetail: form.data.receivingAddressDetail,
      shippingLongitude: form.data.receivingLongitude,
      shippingLatitude: form.data.receivingLatitude,
      receivingCustomerId: shipping.id,
      receivingCustomerName: shipping.customerName,
      receivingAddressId: shipping.addressId,
      receivingContactName: shipping.name,
      receivingContactPhone: shipping.phone,
      receivingAddressDetail: shipping.address,
      receivingLongitude: shipping.longitude,
      receivingLatitude: shipping.latitude
    })
  }

  function openAiOrderDrawer(): void {
    void aiOrderDrawerRef.value?.handleOpen({
      options: {
        deliveryMethods: toAiOptions(form.deliveryMethodOptions),
        paymentMethods: toAiOptions(form.paymentMethodOptions),
        transportModes: toAiOptions(form.transportModeOptions),
        cargoUnits: toAiOptions(form.cargoUnitOptions)
      }
    })
  }

  async function handleAiOrderApply(payload: AiOrderApplyPayload): Promise<void> {
    const draft = payload.analysis.order
    const references = payload.references
    const patch: Partial<OrderForm> = {}

    applyDraftTextFields(patch, draft)
    applyDraftNumberFields(patch, draft)

    const [shippingCoordinates, receivingCoordinates] = await Promise.all([
      resolveAiAddressCoordinates(
        'shipping',
        draft.shippingAddressDetail,
        references.shippingAddress
      ),
      resolveAiAddressCoordinates(
        'receiving',
        draft.receivingAddressDetail,
        references.receivingAddress
      )
    ])
    Object.assign(patch, shippingCoordinates.patch, receivingCoordinates.patch)

    if (references.originStation.id) {
      Object.assign(patch, {
        originStationId: references.originStation.id,
        originStation: references.originStation.label || draft.originStationName || ''
      })
    }
    if (references.destinationStation.id) {
      Object.assign(patch, {
        destinationStationId: references.destinationStation.id,
        destinationStation:
          references.destinationStation.label || draft.destinationStationName || ''
      })
    }
    if (references.transferStation.id) {
      Object.assign(patch, {
        transferStationId: references.transferStation.id,
        transferStation: references.transferStation.label || draft.transferStationName || ''
      })
    }
    if (references.shippingCustomer.id) {
      Object.assign(patch, {
        shippingCustomerId: references.shippingCustomer.id,
        shippingCustomerName: references.shippingCustomer.label || draft.shippingCustomerName || ''
      })
    }
    if (references.receivingCustomer.id) {
      Object.assign(patch, {
        receivingCustomerId: references.receivingCustomer.id,
        receivingCustomerName:
          references.receivingCustomer.label || draft.receivingCustomerName || ''
      })
    }

    Object.assign(form.data, patch)
    await stationFormRef.value?.reloadOptions()
    if (draft.cargoItems?.some((item) => textValue(item.cargoName))) {
      form.data.cargoItems = draft.cargoItems.map((item) => ({
        cargoName: textValue(item.cargoName),
        packageType: textValue(item.packageType || item.unit),
        quantity: nullableNumber(item.quantity),
        unit: textValue(item.unit || item.packageType),
        weightKg: nullableNumber(item.weightKg),
        volumeM3: nullableNumber(item.volumeM3)
      }))
    }

    await nextTick()
    clearFormRefsValidation(validatedFormRefs)
    aiArtifactId.value = payload.analysis.artifactId
    ElMessage.success('AI 识别结果已填入，请检查后保存订单')
    const failedAddressLabels = [
      shippingCoordinates.failed ? '发货地址' : '',
      receivingCoordinates.failed ? '收货地址' : ''
    ].filter(Boolean)
    if (failedAddressLabels.length) {
      ElMessage.warning(`${failedAddressLabels.join('、')}未能定位，请通过客户地址选择地图位置`)
    }
  }

  async function resolveAiAddressCoordinates(
    mode: SelectorMode,
    address: string | null | undefined,
    reference: AiAddressReferenceMatch
  ): Promise<AiAddressCoordinateResolution> {
    const normalizedAddress = textValue(address)
    if (!normalizedAddress) return { patch: {}, failed: false }

    const longitude = nullableNumber(reference.longitude)
    const latitude = nullableNumber(reference.latitude)
    if (isValidCoordinate(longitude, latitude)) {
      return {
        patch: createCoordinatePatch(mode, reference.id ?? null, longitude, latitude),
        failed: false
      }
    }

    try {
      const location = await geocodeAddress(normalizedAddress)
      return location
        ? {
            patch: createCoordinatePatch(
              mode,
              reference.id ?? null,
              location.longitude,
              location.latitude
            ),
            failed: false
          }
        : { patch: createCoordinatePatch(mode, reference.id ?? null, null, null), failed: true }
    } catch {
      return { patch: createCoordinatePatch(mode, reference.id ?? null, null, null), failed: true }
    }
  }

  function createCoordinatePatch(
    mode: SelectorMode,
    addressId: string | null,
    longitude: number | null,
    latitude: number | null
  ): ContactPatch {
    return mode === 'shipping'
      ? {
          shippingAddressId: addressId,
          shippingLongitude: longitude,
          shippingLatitude: latitude
        }
      : {
          receivingAddressId: addressId,
          receivingLongitude: longitude,
          receivingLatitude: latitude
        }
  }

  function clearAddressCoordinates(mode: SelectorMode): void {
    Object.assign(form.data, createCoordinatePatch(mode, null, null, null))
  }

  function isValidCoordinate(
    longitude: number | null,
    latitude: number | null
  ): longitude is number {
    return (
      !isNil(longitude) &&
      !isNil(latitude) &&
      longitude >= -180 &&
      longitude <= 180 &&
      latitude >= -90 &&
      latitude <= 90
    )
  }

  function applyDraftTextFields(
    patch: Partial<OrderForm>,
    draft: Api.Tms.Order.AiOrderDraft
  ): void {
    const fieldMap: Array<[keyof OrderForm, string | null | undefined]> = [
      ['deliveryMethod', draft.deliveryMethod],
      ['shippingCustomerName', draft.shippingCustomerName],
      ['shippingContactName', draft.shippingContactName],
      ['shippingContactPhone', draft.shippingContactPhone],
      ['shippingAddressDetail', draft.shippingAddressDetail],
      ['receivingCustomerName', draft.receivingCustomerName],
      ['receivingContactName', draft.receivingContactName],
      ['receivingContactPhone', draft.receivingContactPhone],
      ['receivingAddressDetail', draft.receivingAddressDetail],
      ['paymentMethod', draft.paymentMethod],
      ['transportMode', draft.transportMode],
      ['orderRemark', draft.orderRemark]
    ]

    fieldMap.forEach(([key, value]) => {
      const normalized = textValue(value)
      if (normalized) Object.assign(patch, { [key]: normalized })
    })
  }

  function applyDraftNumberFields(
    patch: Partial<OrderForm>,
    draft: Api.Tms.Order.AiOrderDraft
  ): void {
    const fieldMap: Array<[keyof OrderForm, number | null | undefined]> = [
      ['transportFee', draft.transportFee],
      ['deliveryFee', draft.deliveryFee],
      ['unloadingFee', draft.unloadingFee],
      ['collectPaymentFee', draft.collectPaymentFee],
      ['transferFee', draft.transferFee],
      ['declaredValue', draft.declaredValue],
      ['insuranceFee', draft.insuranceFee],
      ['packageFee', draft.packageFee],
      ['otherFee', draft.otherFee],
      ['cashAmount', draft.cashAmount],
      ['collectAmount', draft.collectAmount],
      ['monthlyAmount', draft.monthlyAmount],
      ['codAmount', draft.codAmount],
      ['handlingFee', draft.handlingFee]
    ]

    fieldMap.forEach(([key, value]) => {
      if (!isNil(value)) Object.assign(patch, { [key]: moneyValue(value) })
    })
  }

  function toAiOptions(options: Api.DataCenter.DictListItem[]): Api.Tms.Order.AiOrderOption[] {
    return options
      .filter((item) => item.value)
      .map((item) => ({
        label: item.label || item.name || item.value,
        value: item.value
      }))
  }

  async function validateForms(): Promise<boolean> {
    const isFormValid = await validateFormRefs(validatedFormRefs, pageRef)
    if (!isFormValid) return false

    const hasCargoName = (form.data.cargoItems ?? []).some((item) => textValue(item.cargoName))
    if (!hasCargoName) {
      ElMessage.warning('请至少填写一条货物名称')
      return false
    }

    if (
      isNewOrder.value &&
      orderNumberRule.value &&
      !orderNumberRule.value.autoEnabled &&
      !textValue(form.data.orderNo)
    ) {
      ElMessage.warning('当前运单号规则为手工填写，请输入运单号')
      return false
    }

    return true
  }

  async function handleSaveOnly(): Promise<void> {
    const valid = await validateForms()
    if (!valid) return

    page.saving = true
    try {
      const payload = normalizePayload()
      let savedOrderId = payload.id
      if (payload.id) {
        const { data } = await editOrder(payload)
        savedOrderId = data?.id || payload.id
        ElMessage.success('订单修改成功')
      } else {
        const { data } = await addOrder(payload)
        savedOrderId = data?.id
        ElMessage.success('开单成功')
      }
      await recordAiOrderReview(savedOrderId)
      await router.push({ name: 'TmsPendingWaybillList' })
    } catch {
      // API 层已提示错误，页面保留当前输入。
    } finally {
      page.saving = false
    }
  }

  async function recordAiOrderReview(orderId?: string): Promise<void> {
    if (!aiArtifactId.value || !orderId) return

    const { error } = await reviewAiOrderArtifact({
      action: 'review',
      artifactId: aiArtifactId.value,
      entityId: orderId,
      outcome: 'applied',
      finalPayload: buildAiOrderFinalPayload(form.data)
    })
    if (error) {
      ElMessage.warning('订单已保存，但 AI 质量记录失败；不会影响正式订单')
      return
    }
    aiArtifactId.value = undefined
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

  function handleFooterCommand(command: FooterCommand): void {
    const handlers: Record<FooterCommand, () => void> = {
      ai: openAiOrderDrawer,
      'print-waybill': () => openPrintDialog('waybill'),
      'print-label': () => openPrintDialog('label'),
      'double-print': handleDoublePrint
    }
    handlers[command]()
  }

  function handlePrintConfirm(kind: PrintKind, count: number): void {
    ElMessage.success(`${kind === 'waybill' ? '运单' : '标签'}打印数量：${count}`)
  }

  function normalizePayload(): OrderRecord {
    syncContractFreightTotals()
    return normalizeOrderPayload({
      form: toRaw(form.data),
      stationNames: {
        origin: findStationOption('origin', form.data.originStationId)?.stationName,
        destination: findStationOption('destination', form.data.destinationStationId)?.stationName,
        transfer: findStationOption('transfer', form.data.transferStationId)?.stationName
      }
    })
  }

  function sumFields(fields: Array<keyof OrderForm>): number {
    return round(
      fields.reduce((sum, field) => sum + numericValue(form.data[field] as number), 0),
      2
    )
  }

  function canViewOrderField(field: Api.Tms.Order.OrderFieldKey): boolean {
    return isNewOrder.value || canViewField(form.data.fieldAccess, field)
  }

  function canEditOrderField(field: Api.Tms.Order.OrderFieldKey): boolean {
    return isNewOrder.value || canEditField(form.data.fieldAccess, field)
  }

  function canEditContactEndpoint(mode: SelectorMode): boolean {
    return mode === 'shipping'
      ? canEditOrderField('shipperContact') && canEditOrderField('shipperAddress')
      : canEditOrderField('receiverContact') && canEditOrderField('receiverAddress')
  }
</script>

<style scoped lang="scss" src="./modules/order-open.scss"></style>
