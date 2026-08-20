<template>
  <ArtPageShell
    class="customer-price-edit"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    @retry="initializePage"
  >
    <ArtPageHeader
      class="customer-price-edit__header"
      :title="isEdit ? '编辑客户价' : '新增客户价'"
      subtitle="先选择客户和收发货地址，再完善货物、车辆与结算费用"
      show-back
      @back="goBack()"
    />

    <div ref="pageRef" class="customer-price-edit__content">
      <section class="customer-price-edit__section art-card-xs">
        <ArtSectionTitle>客户与运输路线</ArtSectionTitle>

        <ol class="customer-price-edit__workflow" aria-label="客户价格维护步骤">
          <li
            v-for="(step, index) in workflowSteps"
            :key="step.key"
            class="customer-price-edit__workflow-step"
            :class="{ 'is-complete': step.complete, 'is-active': step.active }"
            :aria-current="step.active ? 'step' : undefined"
          >
            <span class="customer-price-edit__workflow-index" aria-hidden="true">
              <ElIcon v-if="step.complete"><Check /></ElIcon>
              <template v-else>{{ index + 1 }}</template>
            </span>
            <span class="customer-price-edit__workflow-copy">
              <strong>{{ step.label }}</strong>
              <small>{{ step.description }}</small>
            </span>
            <span class="customer-price-edit__workflow-status">
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
          root-class="customer-price-edit__form"
          :show-reset="false"
          :show-submit="false"
        />

        <div class="customer-price-edit__contact-grid">
          <div class="customer-price-edit__contact-panel">
            <div class="customer-price-edit__contact-heading">
              <span class="customer-price-edit__contact-icon" aria-hidden="true">发</span>
              <div class="customer-price-edit__contact-copy">
                <strong>发货信息</strong>
                <span>选择客户后，自动带入默认发货地址</span>
              </div>
              <ElTag :type="getAddressStatusType('shipping')" effect="plain" size="small">
                {{ getAddressStatusText('shipping') }}
              </ElTag>
            </div>

            <ElAlert
              v-if="page.shippingAddressError"
              class="customer-price-edit__address-alert"
              type="error"
              :closable="false"
              show-icon
            >
              <template #title>
                <span>{{ page.shippingAddressError }}</span>
                <ElButton link type="primary" @click="retryShippingAddressLoad">
                  重新加载
                </ElButton>
              </template>
            </ElAlert>
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
            >
              <template #shippingAddressDetail>
                <div
                  class="customer-price-edit__address-card"
                  :class="{
                    'is-empty': !form.data.shippingAddressDetail,
                    'is-disabled': !form.data.customerId || page.shippingAddressLoading
                  }"
                >
                  <div class="customer-price-edit__address-main">
                    <div class="customer-price-edit__address-text">
                      {{ form.data.shippingAddressDetail || getAddressEmptyText('shipping') }}
                    </div>
                    <div
                      v-if="form.data.shippingAddressDetail"
                      class="customer-price-edit__address-meta"
                    >
                      <span
                        :class="{
                          'is-warning': !getAddressCoordinateText('shipping')
                        }"
                      >
                        {{ getAddressCoordinateText('shipping') || '缺少经纬度' }}
                      </span>
                    </div>
                  </div>
                  <div v-if="canEditAddressSelection" class="customer-price-edit__address-actions">
                    <ElButton
                      type="primary"
                      plain
                      :loading="page.shippingAddressLoading"
                      :disabled="!form.data.customerId"
                      @click="openAddressSelector('shipping')"
                    >
                      {{ form.data.shippingAddressDetail ? '更换' : '选择地址' }}
                    </ElButton>
                    <ElButton
                      v-if="form.data.shippingAddressDetail"
                      text
                      @click="handleAddressClear('shipping')"
                    >
                      清空
                    </ElButton>
                  </div>
                </div>
              </template>

              <template #originRegionPath>
                <div
                  class="customer-price-edit__region-field"
                  :class="{ 'is-empty': !form.data.originRegionPath.length }"
                >
                  <span>{{ getRegionText('shipping') || '选择发货地址后自动生成始发地' }}</span>
                  <ElTag v-if="form.data.originRegionPath.length" effect="plain" size="small">
                    自动生成
                  </ElTag>
                </div>
              </template>
            </ArtForm>
          </div>

          <div class="customer-price-edit__contact-panel">
            <div class="customer-price-edit__contact-heading">
              <span
                class="customer-price-edit__contact-icon customer-price-edit__contact-icon--receive"
                aria-hidden="true"
              >
                收
              </span>
              <div class="customer-price-edit__contact-copy">
                <strong>收货信息</strong>
                <span>选择收货地址后，自动更新目的地</span>
              </div>
              <ElTag :type="getAddressStatusType('receiving')" effect="plain" size="small">
                {{ getAddressStatusText('receiving') }}
              </ElTag>
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
            >
              <template #receivingAddressDetail>
                <div
                  class="customer-price-edit__address-card"
                  :class="{ 'is-empty': !form.data.receivingAddressDetail }"
                >
                  <div class="customer-price-edit__address-main">
                    <div class="customer-price-edit__address-text">
                      {{ form.data.receivingAddressDetail || getAddressEmptyText('receiving') }}
                    </div>
                    <div
                      v-if="form.data.receivingAddressDetail"
                      class="customer-price-edit__address-meta"
                    >
                      <span
                        :class="{
                          'is-warning': !getAddressCoordinateText('receiving')
                        }"
                      >
                        {{ getAddressCoordinateText('receiving') || '缺少经纬度' }}
                      </span>
                    </div>
                  </div>
                  <div v-if="canEditAddressSelection" class="customer-price-edit__address-actions">
                    <ElButton type="primary" plain @click="openAddressSelector('receiving')">
                      {{ form.data.receivingAddressDetail ? '更换' : '选择地址' }}
                    </ElButton>
                    <ElButton
                      v-if="form.data.receivingAddressDetail"
                      text
                      @click="handleAddressClear('receiving')"
                    >
                      清空
                    </ElButton>
                  </div>
                </div>
              </template>

              <template #destinationRegionPath>
                <div
                  class="customer-price-edit__region-field"
                  :class="{ 'is-empty': !form.data.destinationRegionPath.length }"
                >
                  <span>{{ getRegionText('receiving') || '选择收货地址后自动生成目的地' }}</span>
                  <ElTag v-if="form.data.destinationRegionPath.length" effect="plain" size="small">
                    自动生成
                  </ElTag>
                </div>
              </template>
            </ArtForm>
          </div>
        </div>
      </section>

      <PriceCargoSection
        :quantity-text="form.cargoQuantityText"
        :volume-text="form.cargoVolumeText"
        :weight-text="form.cargoWeightText"
        weight-label="总质量"
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
      </PriceCargoSection>

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

      <section
        v-if="canViewSensitiveField('quoteAmounts')"
        class="customer-price-edit__section art-card-xs"
      >
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

      <section
        v-if="canViewSensitiveField('paymentAmounts')"
        class="customer-price-edit__section art-card-xs"
      >
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

    <ArtStickyActionBar class="customer-price-edit__footer">
      <ElButton :disabled="page.saving" @click="goBack()">取消</ElButton>
      <ElButton
        v-auth="'TmsCustomerPriceEdit:Save'"
        type="primary"
        :loading="page.saving"
        @click="handleSave"
      >
        保存客户价
      </ElButton>
    </ArtStickyActionBar>

    <ArtTableSingleSelect
      ref="addressSelectRef"
      v-model="addressSelector.value"
      v-model:selected-data="addressSelector.selectedRows"
      :api-fn="fetchAddressSelectorData"
      :columns="addressSelector.columns"
      :title="addressSelector.title"
      :subtitle="addressSelector.subtitle"
      row-key="id"
      :label-key="getAddressLabel"
      :description-key="getAddressDescription"
      search-placeholder="请输入联系人/电话/地址搜索"
      dialog-width="xl"
      show-pagination
      :page-size="10"
      @confirm="handleAddressSelectorConfirm"
    >
      <template #trigger></template>
    </ArtTableSingleSelect>

    <ArtTableMultipleSelect
      ref="cargoSelectRef"
      v-model="cargoSelector.value"
      v-model:selected-data="cargoSelector.selectedRows"
      :api-fn="fetchCargoSelectorData"
      :columns="cargoSelector.columns"
      title="批量选择货物"
      subtitle="从货物管理中选择后，会自动带入计量单位、单件体积和单件重量。"
      row-key="id"
      label-key="cargoName"
      description-key="cargoCode"
      search-placeholder="请输入货物名称、编码、单位或备注"
      dialog-width="xl"
      show-pagination
      :page-size="10"
      @confirm="handleCargoSelectorConfirm"
    >
      <template #trigger></template>
    </ArtTableMultipleSelect>
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { cloneDeep } from 'lodash-es'
  import type { FormRules, TagProps } from 'element-plus'
  import {
    ElAlert,
    ElAutocomplete,
    ElButton,
    ElIcon,
    ElInputNumber,
    ElMessage,
    ElOption,
    ElSelect,
    ElTag
  } from 'element-plus'
  import { Check } from '@element-plus/icons-vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtTableMultipleSelect from '@/components/core/forms/art-data-select/table-multiple.vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    ArtDataSelectExpose,
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { formatNameCodeOption } from '@/utils/form'
  import {
    addCustomerPrice,
    editCustomerPrice,
    fetchCargoList,
    fetchCustomerAddressList,
    fetchCustomerOptions,
    fetchCustomerPriceDetail
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { clearFormRefsValidation, validateFormRefs } from '@/utils/form/validation'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import PriceCargoSection from '../modules/price-cargo-section.vue'
  import {
    calculateCargoSummary,
    formatNumber,
    getResponseData,
    mergeCargoSelections,
    roundNumber,
    splitRegionPath,
    toNumber,
    type CargoSummary
  } from '../modules/price-form-utils'
  import {
    createInitialCustomerPriceCargoItem,
    createInitialCustomerPriceForm,
    normalizeCustomerPricePayload,
    type CustomerPrice,
    type CustomerPriceCargoItem,
    type CustomerPriceForm
  } from './modules/customer-price-model'
  import { canEditField, canViewField, type FieldAccessLevel } from '@/utils/field-permission'

  defineOptions({ name: 'TmsCustomerPriceEdit' })

  type CargoMaster = Api.Tms.BasicData.Cargo
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerPriceFieldKey = Api.Tms.BasicData.CustomerPriceFieldKey
  type AddressMode = 'shipping' | 'receiving'
  type CargoSuggestionCallback = (items: CargoSuggestion[]) => void

  interface CargoSuggestion extends CargoMaster {
    value: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface PageState {
    loading: boolean
    saving: boolean
    shippingAddressLoading: boolean
    shippingAddressLoaded: boolean
    shippingAddressError: string
    error: Error | null
  }

  interface AddressSelectorGroup {
    mode: AddressMode
    title: string
    subtitle: string
    value?: string | number
    selectedRows: DataSelectRecord[]
    columns: DataSelectColumn[]
  }

  interface CargoSelectorGroup {
    value: Array<string | number>
    selectedRows: DataSelectRecord[]
    columns: DataSelectColumn[]
  }

  interface FormGroup {
    data: CustomerPriceForm
    customerOptions: CustomerOption[]
    shippingAddressOptions: CustomerAddress[]
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
  const shippingFormRef = ref<FormExpose>()
  const receivingFormRef = ref<FormExpose>()
  const vehicleFormRef = ref<FormExpose>()
  const feeFormRef = ref<FormExpose>()
  const paymentFormRef = ref<FormExpose>()
  const addressSelectRef = ref<ArtDataSelectExpose>()
  const cargoSelectRef = ref<ArtDataSelectExpose>()
  const validatedFormRefs = [
    baseFormRef,
    shippingFormRef,
    receivingFormRef,
    vehicleFormRef,
    feeFormRef,
    paymentFormRef
  ]

  const isEdit = computed(() => Boolean(route.params.id))
  const sensitiveFieldFallback = computed<FieldAccessLevel>(() =>
    isEdit.value ? 'hidden' : 'edit'
  )
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

  function canViewSensitiveField(field: CustomerPriceFieldKey): boolean {
    return canViewField(form.data.fieldAccess, field, sensitiveFieldFallback.value)
  }

  function canEditSensitiveField(field: CustomerPriceFieldKey): boolean {
    return canEditField(form.data.fieldAccess, field, sensitiveFieldFallback.value)
  }

  const canEditAddressSelection = computed(
    () => canEditSensitiveField('contactPhones') && canEditSensitiveField('addressDetails')
  )

  function createSensitiveMoneyItem(
    label: string,
    key: keyof CustomerPriceForm,
    field: Extract<CustomerPriceFieldKey, 'quoteAmounts' | 'paymentAmounts'>,
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

  const countProps = {
    min: 0,
    precision: 0,
    controlsPosition: 'right',
    class: '!w-full'
  }

  const cargoSelector = reactive<CargoSelectorGroup>({
    value: [],
    selectedRows: [],
    columns: [
      { prop: 'cargoCode', label: '货物编码', width: 150 },
      { prop: 'cargoName', label: '货物名称', minWidth: 220 },
      { prop: 'unit', label: '单位', width: 100, formatter: formatCargoUnit },
      {
        prop: 'volumeM3',
        label: '单件体积(m³)',
        width: 140,
        align: 'right',
        formatter: (row) => formatCargoNumber((row as CargoMaster).volumeM3, 3)
      },
      {
        prop: 'weightKg',
        label: '单件重量(kg)',
        width: 140,
        align: 'right',
        formatter: (row) => formatCargoNumber((row as CargoMaster).weightKg, 2)
      }
    ]
  })

  const createInitialCargoItem = createInitialCustomerPriceCargoItem
  const createInitialForm = createInitialCustomerPriceForm

  const page = reactive<PageState>({
    loading: false,
    saving: false,
    shippingAddressLoading: false,
    shippingAddressLoaded: false,
    shippingAddressError: '',
    error: null
  })
  let addressLoadRequestId = 0
  const addressSelector = reactive<AddressSelectorGroup>({
    mode: 'shipping',
    title: '选择发货地址',
    subtitle: '仅展示当前客户的发货地址，选择后会同步联系人与始发地。',
    value: undefined,
    selectedRows: [],
    columns: [
      { prop: 'customer.customerName', label: '客户', minWidth: 170 },
      { prop: 'contactName', label: '联系人', width: 110 },
      { prop: 'contactPhone', label: '联系电话', width: 140 },
      { prop: 'region', label: '区域', minWidth: 160 },
      { prop: 'addressDetail', label: '详细地址', minWidth: 260 },
      { prop: 'coordinateText', label: '经纬度', width: 180, formatter: formatCoordinateColumn }
    ]
  })
  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    customerOptions: [],
    shippingAddressOptions: [],
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
        span: 12,
        description: '更换客户会重新读取默认发货地址，并清空原收货信息。',
        api: fetchCustomerOptions,
        resultField: 'data',
        labelField: 'customerName',
        valueField: 'id',
        labelFn: formatCustomerOption,
        afterFetch: syncCustomerOptions,
        props: {
          clearable: true,
          filterable: true,
          disabled: !canEditAddressSelection.value,
          placeholder: '搜索并选择客户',
          onChange: handleCustomerChange
        }
      },
      {
        label: '客户编码',
        key: 'customerCode',
        type: 'input',
        span: 12,
        props: { disabled: true, placeholder: '选择客户后自动带入' }
      },
      {
        label: '运输类型',
        key: 'transportType',
        type: 'select',
        span: 12,
        props: {
          options: form.transportTypeOptions,
          clearable: true,
          placeholder: '请选择运输类型'
        }
      },
      {
        label: '货物类型',
        key: 'cargoType',
        type: 'select',
        span: 12,
        props: {
          options: form.cargoTypeOptions,
          clearable: true,
          placeholder: '请选择货物类型'
        }
      }
    ]),
    shippingItems: computed<FormItem[]>(() => [
      ...(canViewSensitiveField('addressDetails')
        ? [
            {
              label: '发货地址',
              key: 'shippingAddressDetail',
              type: 'input',
              span: 24,
              props: { disabled: true, maxlength: 200, placeholder: '请选择发货地址' }
            } satisfies FormItem
          ]
        : []),
      {
        label: '始发地',
        key: 'originRegionPath',
        type: 'input',
        span: 24
      },
      {
        label: '联系人',
        key: 'shippingContactName',
        type: 'input',
        span: 12,
        props: { disabled: true, maxlength: 50, placeholder: '选择发货地址后带出' }
      },
      ...(canViewSensitiveField('contactPhones')
        ? [
            {
              label: '联系电话',
              key: 'shippingContactPhone',
              type: 'input',
              span: 12,
              props: {
                disabled: !canEditSensitiveField('contactPhones'),
                maxlength: 20,
                placeholder: '选择发货地址后带出'
              }
            } satisfies FormItem
          ]
        : [])
    ]),
    receivingItems: computed<FormItem[]>(() => [
      ...(canViewSensitiveField('addressDetails')
        ? [
            {
              label: '收货地址',
              key: 'receivingAddressDetail',
              type: 'input',
              span: 24,
              props: { disabled: true, maxlength: 200, placeholder: '请选择收货地址' }
            } satisfies FormItem
          ]
        : []),
      {
        label: '目的地',
        key: 'destinationRegionPath',
        type: 'input',
        span: 24
      },
      {
        label: '联系人',
        key: 'receivingContactName',
        type: 'input',
        span: 12,
        props: { disabled: true, maxlength: 50, placeholder: '选择收货地址后带出' }
      },
      ...(canViewSensitiveField('contactPhones')
        ? [
            {
              label: '联系电话',
              key: 'receivingContactPhone',
              type: 'input',
              span: 12,
              props: {
                disabled: !canEditSensitiveField('contactPhones'),
                maxlength: 20,
                placeholder: '选择收货地址后带出'
              }
            } satisfies FormItem
          ]
        : [])
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
      createSensitiveMoneyItem('运输费', 'transportFee', 'quoteAmounts'),
      createSensitiveMoneyItem('保险费', 'insuranceFee', 'quoteAmounts'),
      createSensitiveMoneyItem('包装费', 'packageFee', 'quoteAmounts'),
      createSensitiveMoneyItem('装卸费', 'loadingFee', 'quoteAmounts'),
      createSensitiveMoneyItem('中转费', 'transferFee', 'quoteAmounts'),
      createSensitiveMoneyItem('燃油费', 'fuelFee', 'quoteAmounts'),
      createSensitiveMoneyItem('服务费', 'serviceFee', 'quoteAmounts'),
      createSensitiveMoneyItem('其他费用', 'otherFee', 'quoteAmounts'),
      createSensitiveMoneyItem('费用合计', 'totalFee', 'quoteAmounts', true)
    ]),
    paymentItems: computed<FormItem[]>(() => [
      createSensitiveMoneyItem('现付', 'cashAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('预付', 'prepaidAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('到付', 'collectAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('周期付', 'periodicAmount', 'paymentAmounts'),
      createSensitiveMoneyItem('付款合计', 'paymentTotal', 'paymentAmounts', true)
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
      receivingContactName: [{ required: true, message: '请输入收货联系人', trigger: 'blur' }],
      billingMethod: [{ required: true, message: '请选择计费方式', trigger: 'change' }],
      ...(canEditSensitiveField('contactPhones')
        ? {
            shippingContactPhone: [
              { required: true, message: '请输入发货联系电话', trigger: 'blur' }
            ],
            receivingContactPhone: [
              { required: true, message: '请输入收货联系电话', trigger: 'blur' }
            ]
          }
        : {}),
      ...(canEditSensitiveField('addressDetails')
        ? {
            shippingAddressDetail: [
              { required: true, message: '请输入发货详细地址', trigger: 'blur' }
            ],
            receivingAddressDetail: [
              { required: true, message: '请输入收货详细地址', trigger: 'blur' }
            ]
          }
        : {}),
      ...(canEditSensitiveField('quoteAmounts')
        ? { transportFee: [{ required: true, message: '请输入运输费', trigger: 'blur' }] }
        : {})
    })),
    cargoColumns: computed<ColumnOption<CustomerPriceCargoItem>[]>(() => [
      { type: 'globalIndex', label: '序号', width: 70 },
      {
        prop: 'cargoName',
        label: '货物名称',
        minWidth: 180,
        formatter: (row) => (
          <ElAutocomplete
            v-model={row.cargoName}
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
    cargoSummary: computed(() => calculateCargoSummary(form.data.cargoItems ?? [])),
    cargoQuantityText: computed(() => formatNumber(form.cargoSummary.quantity, 0)),
    cargoVolumeText: computed(() => formatNumber(form.cargoSummary.volume, 3)),
    cargoWeightText: computed(() => formatNumber(form.cargoSummary.weight, 2))
  })

  const workflowSteps = computed<WorkflowStep[]>(() => {
    const steps = [
      {
        key: 'customer',
        label: '选择客户',
        description: '识别客户编码',
        complete: Boolean(form.data.customerId)
      },
      {
        key: 'shipping',
        label: '确认发货信息',
        description: '默认地址自动带入',
        complete:
          !canEditAddressSelection.value ||
          Boolean(form.data.shippingAddressDetail && form.data.originRegionPath.length)
      },
      {
        key: 'receiving',
        label: '选择收货地址',
        description: '目的地自动更新',
        complete:
          !canEditAddressSelection.value ||
          Boolean(form.data.receivingAddressDetail && form.data.destinationRegionPath.length)
      },
      {
        key: 'pricing',
        label: '完善价格',
        description: '货物、车辆与费用',
        complete:
          !canEditSensitiveField('quoteAmounts') ||
          Boolean(
            form.data.transportType &&
            form.data.billingMethod &&
            form.data.cargoItems?.some((item) => item.cargoName)
          )
      }
    ]
    const activeIndex = steps.findIndex((step) => !step.complete)

    return steps.map((step, index) => ({
      ...step,
      active: index === (activeIndex === -1 ? steps.length - 1 : activeIndex)
    }))
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

  onMounted(() => {
    void initializePage()
  })

  async function initializePage(): Promise<void> {
    page.loading = true
    page.error = null
    try {
      await Promise.all([
        loadDetail(),
        ...dictCodes.map((code) => userStore.ensureDictLoaded(code))
      ])
      await nextTick()
      clearFormRefsValidation(validatedFormRefs)
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('客户价信息加载失败')
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
    () => feeFields.map((field) => form.data[field]),
    () => {
      if (!canEditSensitiveField('quoteAmounts')) return
      form.data.totalFee = sumFields(feeFields)
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

  async function loadDetail(): Promise<void> {
    if (!isEdit.value) return

    const id = String(route.params.id || '')
    const { data } = await fetchCustomerPriceDetail(id)
    if (!data) throw new Error('客户价不存在或无权访问')

    replaceForm({
      ...createInitialForm(),
      ...data,
      customerCode: data.customer?.customerCode ?? '',
      originRegionPath: splitRegionPath(data.originRegion),
      destinationRegionPath: splitRegionPath(data.destinationRegion),
      cargoItems: data.cargoItems?.length ? data.cargoItems : [createInitialCargoItem()]
    })
    if (canEditAddressSelection.value) {
      await loadCustomerAddressOptions(data.customerId, false)
    }
  }

  function replaceForm(nextForm: CustomerPriceForm): void {
    Object.assign(form.data, createInitialForm(), cloneDeep(nextForm))
  }

  function syncCustomerOptions(result: unknown): unknown {
    form.customerOptions = getResponseData<CustomerOption>(result)
    syncCustomerCode(form.data.customerId)
    return result
  }

  function formatCustomerOption(option: Record<string, unknown>): string {
    return formatNameCodeOption(option, 'customerName', 'customerCode')
  }

  function handleCustomerChange(customerId?: string): void {
    if (!canEditAddressSelection.value) return
    syncCustomerCode(customerId || '')
    void loadCustomerAddressOptions(customerId || '', true)
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

  async function loadCustomerAddressOptions(
    customerId: string,
    applyDefault: boolean,
    clearReceiving = applyDefault
  ): Promise<void> {
    if (!canEditAddressSelection.value) return
    const requestId = ++addressLoadRequestId

    if (applyDefault) {
      applyAddressPatch('shipping')
    }
    if (clearReceiving) {
      applyAddressPatch('receiving')
    }

    if (!customerId) {
      form.shippingAddressOptions = []
      Object.assign(page, {
        shippingAddressLoading: false,
        shippingAddressLoaded: false,
        shippingAddressError: ''
      })
      return
    }

    Object.assign(page, {
      shippingAddressLoading: true,
      shippingAddressLoaded: false,
      shippingAddressError: ''
    })

    try {
      const shippingResult = await fetchCustomerAddressList({
        customerId,
        addressType: 'shipping',
        from: 0,
        to: 99
      })
      if (requestId !== addressLoadRequestId) return

      form.shippingAddressOptions = shippingResult.data ?? []
      page.shippingAddressLoaded = true
      if (applyDefault) {
        applyAddressPatch('shipping', findDefaultAddress(form.shippingAddressOptions))
      }
    } catch {
      if (requestId !== addressLoadRequestId) return
      form.shippingAddressOptions = []
      page.shippingAddressError = '发货地址读取失败，请检查网络后重试。'
    } finally {
      if (requestId === addressLoadRequestId) page.shippingAddressLoading = false
    }
  }

  function findDefaultAddress(addresses: CustomerAddress[]): CustomerAddress | undefined {
    return addresses.find((item) => item.isDefault) ?? addresses[0]
  }

  async function openAddressSelector(mode: AddressMode): Promise<void> {
    if (!canEditAddressSelection.value) return
    if (mode === 'shipping' && !form.data.customerId) {
      ElMessage.warning('请先选择客户名称')
      return
    }

    if (mode === 'shipping' && page.shippingAddressLoading) {
      ElMessage.info('正在读取该客户的发货地址，请稍候')
      return
    }

    Object.assign(addressSelector, {
      mode,
      title: mode === 'shipping' ? '选择发货地址' : '选择收货地址',
      subtitle:
        mode === 'shipping'
          ? '仅展示当前客户的发货地址，选择后会同步联系人与始发地。'
          : '选择后会同步收货联系人、详细地址与目的地。',
      value:
        mode === 'shipping'
          ? (form.data.shippingAddressId ?? undefined)
          : (form.data.receivingAddressId ?? undefined),
      selectedRows: []
    })
    await nextTick()
    await addressSelectRef.value?.open()
  }

  function handleAddressClear(mode: AddressMode): void {
    if (!canEditAddressSelection.value) return
    applyAddressPatch(mode)
  }

  function retryShippingAddressLoad(): void {
    if (!canEditAddressSelection.value) return
    if (!form.data.customerId) return
    void loadCustomerAddressOptions(form.data.customerId, true, false)
  }

  async function fetchAddressSelectorData(params: DataSelectFetchParams) {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCustomerAddressList({
      customerId: addressSelector.mode === 'shipping' ? form.data.customerId : undefined,
      addressType: addressSelector.mode,
      keyword: params.keyword,
      from,
      to
    })

    return { data: data ?? [], total: total ?? 0 }
  }

  function handleAddressSelectorConfirm(_value: unknown, rows: DataSelectRecord[]): void {
    if (!canEditAddressSelection.value) return
    const address = rows[0] as CustomerAddress | undefined
    if (!address) return
    applyAddressPatch(addressSelector.mode, address)
  }

  function applyAddressPatch(mode: AddressMode, address?: CustomerAddress): void {
    if (!canEditAddressSelection.value) return
    // 详细地址只存 addressDetail；区域单独写入 origin/destinationRegionPath。
    // 列表会用 region + detail 拼接展示，这里不能再把区域拼进 detail，否则会重复。
    const patchMap: Record<AddressMode, Partial<CustomerPriceForm>> = {
      shipping: address
        ? {
            shippingAddressId: address.id ?? null,
            shippingContactName: address.contactName,
            shippingContactPhone: address.contactPhone,
            shippingAddressDetail: normalizeAddressDetail(address.addressDetail),
            shippingLongitude: address.longitude ?? null,
            shippingLatitude: address.latitude ?? null,
            originRegionPath: splitRegionPath(address.region)
          }
        : {
            shippingAddressId: null,
            shippingContactName: '',
            shippingContactPhone: '',
            shippingAddressDetail: '',
            shippingLongitude: null,
            shippingLatitude: null,
            originRegionPath: []
          },
      receiving: address
        ? {
            receivingAddressId: address.id ?? null,
            receivingContactName: address.contactName,
            receivingContactPhone: address.contactPhone,
            receivingAddressDetail: normalizeAddressDetail(address.addressDetail),
            receivingLongitude: address.longitude ?? null,
            receivingLatitude: address.latitude ?? null,
            destinationRegionPath: splitRegionPath(address.region)
          }
        : {
            receivingAddressId: null,
            receivingContactName: '',
            receivingContactPhone: '',
            receivingAddressDetail: '',
            receivingLongitude: null,
            receivingLatitude: null,
            destinationRegionPath: []
          }
    }

    Object.assign(form.data, patchMap[mode])
    void nextTick(() => {
      if (mode === 'shipping') shippingFormRef.value?.clearValidate()
      else receivingFormRef.value?.clearValidate()
      baseFormRef.value?.clearValidate()
    })
  }

  function formatAddress(address: CustomerAddress): string {
    // 仅用于选择器描述展示，不用于落库。
    return [address.region, normalizeAddressDetail(address.addressDetail)].filter(Boolean).join(' ')
  }

  function normalizeAddressDetail(addressDetail?: string | null): string {
    return String(addressDetail ?? '').trim()
  }

  function hasCoordinate(longitude?: number | string | null, latitude?: number | string | null) {
    return (
      longitude !== null &&
      longitude !== undefined &&
      longitude !== '' &&
      latitude !== null &&
      latitude !== undefined &&
      latitude !== ''
    )
  }

  function formatCoordinate(address: CustomerAddress): string {
    if (!hasCoordinate(address.longitude, address.latitude)) return ''
    return `${address.longitude}, ${address.latitude}`
  }

  function formatCoordinateColumn(row: DataSelectRecord): string {
    return formatCoordinate(row as CustomerAddress) || '缺少经纬度'
  }

  function getAddressLabel(row: DataSelectRecord): string {
    const address = row as CustomerAddress
    return address.customer?.customerName || address.contactName || address.addressDetail
  }

  function getAddressDescription(row: DataSelectRecord): string {
    const address = row as CustomerAddress
    return [address.contactName, address.contactPhone, formatAddress(address)]
      .filter(Boolean)
      .join(' / ')
  }

  function getAddressCoordinateText(mode: AddressMode): string {
    const longitude =
      mode === 'shipping' ? form.data.shippingLongitude : form.data.receivingLongitude
    const latitude = mode === 'shipping' ? form.data.shippingLatitude : form.data.receivingLatitude
    if (!hasCoordinate(longitude, latitude)) return ''
    return `${longitude}, ${latitude}`
  }

  function getAddressEmptyText(mode: AddressMode): string {
    if (mode === 'receiving') return '请选择收货地址，系统会自动更新目的地'
    if (!form.data.customerId) return '请先选择客户，系统会读取默认发货地址'
    if (page.shippingAddressLoading) return '正在读取该客户的默认发货地址…'
    if (page.shippingAddressError) return '发货地址读取失败，请重新加载'
    if (page.shippingAddressLoaded && !form.shippingAddressOptions.length) {
      return '该客户暂无发货地址，请先在地址管理中维护'
    }
    return '请选择该客户的发货地址'
  }

  function getRegionText(mode: AddressMode): string {
    const path = mode === 'shipping' ? form.data.originRegionPath : form.data.destinationRegionPath
    return path.filter(Boolean).join(' / ')
  }

  function getAddressStatusText(mode: AddressMode): string {
    if (mode === 'shipping' && page.shippingAddressLoading) return '读取中'
    const hasAddress =
      mode === 'shipping'
        ? Boolean(form.data.shippingAddressDetail)
        : Boolean(form.data.receivingAddressDetail)
    if (hasAddress) return mode === 'shipping' ? '已带入' : '已选择'
    if (mode === 'shipping' && page.shippingAddressLoaded && !form.shippingAddressOptions.length) {
      return '待维护'
    }
    return '待选择'
  }

  function getAddressStatusType(mode: AddressMode): TagProps['type'] {
    if (mode === 'shipping' && page.shippingAddressLoading) return 'warning'
    const hasAddress =
      mode === 'shipping'
        ? Boolean(form.data.shippingAddressDetail)
        : Boolean(form.data.receivingAddressDetail)
    return hasAddress ? 'success' : 'info'
  }

  function addCargoItem(): void {
    form.data.cargoItems = [...(form.data.cargoItems ?? []), createInitialCargoItem()]
  }

  async function openCargoSelector(): Promise<void> {
    await nextTick()
    await cargoSelectRef.value?.open()
  }

  async function fetchCargoSelectorData(params: DataSelectFetchParams) {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCargoList({
      keyword: String(params.keyword ?? '').trim(),
      enabled: true,
      from,
      to
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  function handleCargoSelectorConfirm(_value: unknown, rows: DataSelectRecord[]): void {
    const selectedCargoes = rows as CargoMaster[]
    const currentItems = form.data.cargoItems ?? []
    const result = mergeCargoSelections(
      currentItems,
      selectedCargoes,
      createCargoItemFromMaster,
      (item) =>
        !Object.values(item).some((value) => value !== null && value !== undefined && value !== '')
    )

    if (!result.addedCount) return

    form.data.cargoItems = result.items
    cargoSelector.value = []
    cargoSelector.selectedRows = []
  }

  async function fetchCargoSuggestions(
    keyword: string,
    callback: CargoSuggestionCallback
  ): Promise<void> {
    try {
      const result = await fetchCargoList({
        keyword: String(keyword ?? '').trim(),
        enabled: true,
        from: 0,
        to: 19
      })
      callback((result.data ?? []).map((item) => ({ ...item, value: item.cargoName })))
    } catch {
      callback([])
    }
  }

  function handleCargoSelect(row: CustomerPriceCargoItem, item: Record<string, unknown>): void {
    const cargo: CargoMaster = {
      cargoName: String(item.cargoName ?? item.value ?? ''),
      unit: String(item.unit ?? ''),
      weightKg: typeof item.weightKg === 'number' ? item.weightKg : null,
      volumeM3: typeof item.volumeM3 === 'number' ? item.volumeM3 : null
    }
    Object.assign(row, createCargoItemFromMaster(cargo), {
      quantity: row.quantity
    })
  }

  function createCargoItemFromMaster(cargo: CargoMaster): CustomerPriceCargoItem {
    return {
      cargoName: cargo.cargoName,
      quantity: null,
      unit: cargo.unit || '',
      volumeM3: cargo.volumeM3 ?? null,
      weightKg: cargo.weightKg ?? null
    }
  }

  function formatCargoUnit(row: DataSelectRecord): string {
    const unit = String(row.unit ?? '')
    return form.cargoUnitOptions.find((item) => String(item.value) === unit)?.label || unit || '-'
  }

  function formatCargoNumber(value?: number | null, precision = 2): string {
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue.toFixed(precision) : '-'
  }

  function removeCargoItem(row: CustomerPriceCargoItem): void {
    const rows = form.data.cargoItems ?? []
    if (rows.length <= 1) {
      form.data.cargoItems = [createInitialCargoItem()]
      return
    }
    form.data.cargoItems = rows.filter((item) => item !== row)
  }

  function normalizePayload(): CustomerPrice {
    const payload = normalizeCustomerPricePayload(toRaw(form.data))
    if (!canEditAddressSelection.value) removePayloadFields(payload, ['customerId'])
    if (!canEditSensitiveField('contactPhones')) {
      removePayloadFields(payload, ['shippingContactPhone', 'receivingContactPhone'])
    }
    if (!canEditSensitiveField('addressDetails')) {
      removePayloadFields(payload, [
        'shippingAddressId',
        'receivingAddressId',
        'shippingAddressDetail',
        'shippingLongitude',
        'shippingLatitude',
        'receivingAddressDetail',
        'receivingLongitude',
        'receivingLatitude'
      ])
    }
    if (!canEditSensitiveField('quoteAmounts')) {
      removePayloadFields(payload, [
        'transportFee',
        'insuranceFee',
        'packageFee',
        'loadingFee',
        'transferFee',
        'fuelFee',
        'serviceFee',
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

  function removePayloadFields(payload: CustomerPrice, fields: Array<keyof CustomerPrice>): void {
    fields.forEach((field) => Reflect.deleteProperty(payload, field))
  }

  async function handleSave(): Promise<void> {
    const valid = await validateFormRefs(validatedFormRefs, pageRef)
    if (!valid) return

    page.saving = true
    try {
      const payload = normalizePayload()
      if (form.data.id) await editCustomerPrice(payload)
      else await addCustomerPrice(payload)
      goBack(true)
    } catch {
      // API 层已经展示错误信息，当前页保持编辑状态。
    } finally {
      page.saving = false
    }
  }

  function goBack(refresh = false): void {
    void router.push({
      name: 'TmsCustomerPrice',
      query: refresh
        ? {
            refresh: String(Date.now()),
            refreshType: isEdit.value ? 'update' : 'create'
          }
        : undefined
    })
  }
</script>

<style scoped lang="scss">
  .customer-price-edit {
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
      position: relative;
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

        .customer-price-edit__workflow-index {
          color: var(--theme-color);
          background: var(--el-bg-color);
          border-color: var(--theme-color);
        }

        .customer-price-edit__workflow-status {
          color: var(--theme-color);
        }
      }

      &.is-complete {
        .customer-price-edit__workflow-index {
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

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 14px;
        font-weight: 600;
        line-height: 20px;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    &__workflow-status {
      align-self: start;
      font-size: 12px;
      line-height: 20px;
      color: var(--el-text-color-placeholder);
      white-space: nowrap;
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
      margin-top: 20px;
    }

    &__contact-panel {
      min-width: 0;
      padding: 16px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__contact-heading {
      display: flex;
      gap: 10px;
      align-items: center;
      margin-bottom: 16px;
    }

    &__contact-icon {
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

      &--receive {
        background: var(--el-color-success);
      }
    }

    &__contact-copy {
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

    &__address-alert {
      margin-bottom: 12px;

      :deep(.el-alert__title) {
        display: flex;
        gap: 8px;
        align-items: center;
      }
    }

    &__address-card {
      display: flex;
      gap: 12px;
      align-items: center;
      min-height: 84px;
      padding: 10px 12px;
      background: var(--el-fill-color-blank);
      border: 1px solid var(--el-border-color);
      border-radius: var(--el-border-radius-base);

      &.is-empty {
        border-style: dashed;

        .customer-price-edit__address-text {
          font-weight: 400;
          color: var(--el-text-color-placeholder);
        }
      }

      &.is-disabled {
        background: var(--el-fill-color-light);
      }
    }

    &__address-main {
      flex: 1;
      min-width: 0;
    }

    &__address-text {
      display: -webkit-box;
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      -webkit-line-clamp: 2;
      font-size: 14px;
      font-weight: 500;
      line-height: 20px;
      color: var(--el-text-color-primary);
      overflow-wrap: anywhere;
      -webkit-box-orient: vertical;
    }

    &__address-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-top: 8px;

      span {
        display: inline-flex;
        align-items: center;
        max-width: 100%;
        height: 22px;
        padding: 0 8px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        line-height: 22px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
        background: var(--el-fill-color-light);
        border-radius: var(--el-border-radius-small);

        &.is-warning {
          color: var(--el-color-warning);
          background: var(--el-color-warning-light-9);
        }
      }
    }

    &__address-actions {
      display: flex;
      flex: none;
      gap: 4px;
      align-items: center;
    }

    &__region-field {
      display: flex;
      gap: 10px;
      align-items: center;
      justify-content: space-between;
      min-height: 40px;
      padding: 0 12px;
      color: var(--el-text-color-regular);
      background: var(--el-fill-color-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > span:first-child {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 13px;
        line-height: 20px;
        white-space: nowrap;
      }

      &.is-empty {
        color: var(--el-text-color-placeholder);
        border-style: dashed;
      }
    }

    &__footer {
      margin-top: 16px;
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

  @media (width <= 900px) {
    .customer-price-edit {
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

      &__contact-grid {
        grid-template-columns: 1fr;
      }

      &__address-card {
        flex-direction: column;
        align-items: stretch;
      }

      &__address-actions {
        justify-content: flex-end;
      }
    }
  }

  @media (width <= 600px) {
    .customer-price-edit {
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

      &__contact-panel {
        padding: 14px 12px;
      }

      &__contact-copy span {
        white-space: normal;
      }

      :deep(.customer-price-edit__form .el-col-12),
      :deep(.customer-price-edit__form .el-col-xs-12) {
        flex: 0 0 100%;
        max-width: 100%;
      }
    }
  }
</style>
