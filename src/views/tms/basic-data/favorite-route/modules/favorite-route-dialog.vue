<template>
  <ArtDialog ref="dialogRef" size="lg">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="108px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #routePreview>
        <section class="favorite-route-dialog__preview" aria-label="线路预览">
          <div class="favorite-route-dialog__endpoint is-origin">
            <span><ArtSvgIcon icon="ri:login-circle-line" /></span>
            <div>
              <small>装货地</small>
              <strong :title="getAddressCustomerName(originAddress, '请选择发货地址')">
                {{ getAddressCustomerName(originAddress, '请选择发货地址') }}
              </strong>
              <p v-if="originAddress" class="favorite-route-dialog__contact">
                <span>{{ originAddress.contactName || '未维护联系人' }}</span>
                <span>{{ originAddress.contactPhone || '未维护手机号' }}</span>
              </p>
              <p :title="getFullAddress(originAddress)">
                {{ originAddress ? getFullAddress(originAddress) : '从发货地址中选择' }}
              </p>
            </div>
          </div>
          <div class="favorite-route-dialog__path" aria-hidden="true">
            <span></span><span></span><span></span>
          </div>
          <div class="favorite-route-dialog__endpoint is-destination">
            <span><ArtSvgIcon icon="ri:logout-circle-r-line" /></span>
            <div>
              <small>卸货地</small>
              <strong :title="getAddressCustomerName(destinationAddress, '请选择收货地址')">
                {{ getAddressCustomerName(destinationAddress, '请选择收货地址') }}
              </strong>
              <p v-if="destinationAddress" class="favorite-route-dialog__contact">
                <span>{{ destinationAddress.contactName || '未维护联系人' }}</span>
                <span>{{ destinationAddress.contactPhone || '未维护手机号' }}</span>
              </p>
              <p :title="getFullAddress(destinationAddress)">
                {{ destinationAddress ? getFullAddress(destinationAddress) : '从收货地址中选择' }}
              </p>
            </div>
          </div>
          <div
            v-if="estimateNote"
            class="favorite-route-dialog__estimate"
            :class="`is-${estimate.status}`"
            aria-live="polite"
          >
            <ArtSvgIcon :icon="estimateIcon" aria-hidden="true" />
            <span>{{ estimateNote }}</span>
            <ElButton
              v-if="canEstimate && estimate.status !== 'loading'"
              type="primary"
              link
              @click="calculateRouteEstimate"
            >
              重新估算
            </ElButton>
          </div>
        </section>
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { cloneDeep, omit } from 'lodash-es'
  import { storeToRefs } from 'pinia'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import {
    useAmapDrivingEstimate,
    type AmapRouteCoordinate
  } from '@/hooks/core/useAmapDrivingEstimate'
  import {
    addFavoriteRoute,
    editFavoriteRoute,
    fetchCustomerAddressOptions,
    fetchCustomerOptions
  } from '@/api/tms'
  import { fetchGetTenantList } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'
  import FavoriteRouteAddressOption from './favorite-route-address-option.vue'

  defineOptions({ name: 'TmsFavoriteRouteDialog' })

  type FavoriteRoute = Api.Tms.BasicData.FavoriteRoute
  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type TenantOption = Api.SystemManage.TenantListItem
  type FavoriteRouteForm = Omit<FavoriteRoute, 'distanceKm' | 'estimatedMinutes'> & {
    distanceKm: number | null
    estimatedMinutes: number | null
    routePreview?: undefined
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  type EstimateStatus = 'idle' | 'loading' | 'ready' | 'unavailable'

  interface EstimateGroup {
    status: EstimateStatus
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const dialogRef = ref<ArtDialogExpose<FavoriteRoute | undefined>>()
  const formRef = ref<FormExpose>()
  const { estimateDrivingRoute } = useAmapDrivingEstimate()
  const { getUserInfo, isPlatformSuper } = storeToRefs(useUserStore())
  const addressOptions = reactive<{
    origin: CustomerAddress[]
    destination: CustomerAddress[]
  }>({ origin: [], destination: [] })
  const estimate = reactive<EstimateGroup>({ status: 'idle' })
  let estimateRequestId = 0

  const createInitialForm = (): FavoriteRouteForm => ({
    id: undefined,
    tenantId: '',
    routeName: '',
    customerId: '',
    originAddressId: '',
    destinationAddressId: '',
    distanceKm: null,
    estimatedMinutes: null,
    enabled: true,
    remark: ''
  })

  const form = reactive<FavoriteRouteForm>(createInitialForm())
  const originAddress = computed(() =>
    addressOptions.origin.find((item) => item.id === form.originAddressId)
  )
  const destinationAddress = computed(() =>
    addressOptions.destination.find((item) => item.id === form.destinationAddressId)
  )
  const canEstimate = computed(() =>
    Boolean(toRouteCoordinate(originAddress.value) && toRouteCoordinate(destinationAddress.value))
  )
  const estimateNote = computed(() => {
    if (!form.originAddressId || !form.destinationAddressId) return ''
    const notes: Record<EstimateStatus, string> = {
      idle: canEstimate.value
        ? '可按当前装卸地址估算驾车里程和正常路况时长。'
        : '所选地址缺少有效经纬度，请手动填写里程和预计时长。',
      loading: '正在根据当前装卸地址估算驾车路线…',
      ready: '已自动填入参考里程和预计时长，仍可按实际运营经验调整。',
      unavailable: '路线估算暂不可用，请稍后重试或手动填写。'
    }
    return notes[estimate.status]
  })
  const estimateIcon = computed(() => {
    const icons: Record<EstimateStatus, string> = {
      idle: 'ri:route-line',
      loading: 'ri:loader-4-line',
      ready: 'ri:checkbox-circle-line',
      unavailable: 'ri:information-line'
    }
    return icons[estimate.status]
  })

  const formRules = computed<FormRules<FavoriteRouteForm>>(() => ({
    tenantId: isPlatformSuper.value
      ? [{ required: true, message: '请选择所属租户', trigger: 'change' }]
      : [],
    routeName: [{ required: true, message: '请输入线路名称', trigger: 'blur' }],
    customerId: [{ required: true, message: '请选择所属客户', trigger: 'change' }],
    originAddressId: [{ required: true, message: '请选择装货地址', trigger: 'change' }],
    destinationAddressId: [{ required: true, message: '请选择卸货地址', trigger: 'change' }],
    distanceKm: [{ type: 'number', min: 0.01, message: '线路里程应大于 0 公里' }],
    estimatedMinutes: [{ type: 'number', min: 1, message: '预计时长应大于 0 分钟' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }))

  const getAddressLabel = (option: unknown): string => {
    const address = option as CustomerAddress
    const ownership = address.customer?.customerName || '公共地址'
    const addressSummary = address.addressDetail || address.region || '未命名地址'
    return `${address.isDefault ? '默认 · ' : ''}${ownership} · ${addressSummary}`
  }

  const getAddressCustomerName = (
    address: CustomerAddress | undefined,
    emptyText: string
  ): string => address?.customer?.customerName || (address ? '公共地址' : emptyText)

  const getFullAddress = (address?: CustomerAddress): string =>
    [address?.region, address?.addressDetail].filter(Boolean).join(' ') || '未维护详细地址'

  const syncAddressOptions = (target: 'origin' | 'destination', result: unknown): unknown => {
    if (result && typeof result === 'object' && 'data' in result) {
      const data = (result as { data?: CustomerAddress[] }).data
      addressOptions[target] = Array.isArray(data) ? data : []
    }
    return result
  }

  const fetchTenantOptions = () => fetchGetTenantList({ from: 0, to: 999 })

  const formItems = computed<FormItem[]>(() => [
    { label: '线路信息', key: 'baseSection', type: 'divider', span: 24 },
    ...(isPlatformSuper.value
      ? [
          {
            label: '所属租户',
            key: 'tenantId',
            type: 'select' as const,
            span: 24,
            api: fetchTenantOptions,
            resultField: 'data',
            valueField: 'id',
            labelField: 'tenantName',
            labelFn: (option: unknown) => {
              const tenant = option as TenantOption
              return `${tenant.tenantName}（${tenant.tenantCode}）`
            },
            props: {
              disabled: Boolean(form.id),
              filterable: true,
              clearable: !form.id,
              onChange: handleTenantChange,
              placeholder: '请选择本次维护的数据租户'
            }
          }
        ]
      : []),
    {
      label: '线路名称',
      key: 'routeName',
      type: 'input',
      props: { maxlength: 60, showWordLimit: true, placeholder: '例如：杭州仓—上海浦东门店' }
    },
    {
      label: '所属客户',
      key: 'customerId',
      type: 'select',
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
      immediate: false,
      beforeFetch: () => ({ tenantId: form.tenantId }),
      props: {
        disabled: isPlatformSuper.value && !form.tenantId,
        filterable: true,
        clearable: true,
        placeholder: '请选择客户'
      }
    },
    {
      label: '',
      key: 'routePreview',
      type: 'input',
      span: 24,
      labelWidth: 0
    },
    {
      label: '装货地址',
      key: 'originAddressId',
      type: 'select',
      api: fetchCustomerAddressOptions,
      resultField: 'data',
      valueField: 'id',
      labelFn: getAddressLabel,
      optionComponent: FavoriteRouteAddressOption,
      immediate: false,
      beforeFetch: () => ({ tenantId: form.tenantId, addressType: 'shipping' }),
      afterFetch: (result) => syncAddressOptions('origin', result),
      props: {
        disabled: isPlatformSuper.value && !form.tenantId,
        filterable: true,
        clearable: true,
        class: 'favorite-route-dialog__address-select',
        popperClass: 'favorite-route-address-popper',
        onChange: handleEndpointChange,
        noDataText: '暂无可用装货地址',
        placeholder: '请选择发货地址'
      }
    },
    {
      label: '卸货地址',
      key: 'destinationAddressId',
      type: 'select',
      api: fetchCustomerAddressOptions,
      resultField: 'data',
      valueField: 'id',
      labelFn: getAddressLabel,
      optionComponent: FavoriteRouteAddressOption,
      immediate: false,
      beforeFetch: () => ({ tenantId: form.tenantId, addressType: 'receiving' }),
      afterFetch: (result) => syncAddressOptions('destination', result),
      props: {
        disabled: isPlatformSuper.value && !form.tenantId,
        filterable: true,
        clearable: true,
        class: 'favorite-route-dialog__address-select',
        popperClass: 'favorite-route-address-popper',
        onChange: handleEndpointChange,
        noDataText: '暂无可用卸货地址',
        placeholder: '请选择收货地址'
      }
    },
    { label: '运输参考', key: 'referenceSection', type: 'divider', span: 24 },
    {
      label: '线路里程',
      key: 'distanceKm',
      type: 'number',
      description: '选择装卸地址后自动估算，可手动调整；不替代实际轨迹里程。',
      props: {
        disabled: estimate.status === 'loading',
        min: 0.01,
        max: 99999999,
        precision: 2,
        step: 1,
        controlsPosition: 'right'
      }
    },
    {
      label: '预计时长',
      key: 'estimatedMinutes',
      type: 'number',
      description: '按正常路况自动估算，以分钟记录并允许人工调整。',
      props: {
        disabled: estimate.status === 'loading',
        min: 1,
        max: 999999,
        step: 10,
        controlsPosition: 'right'
      }
    },
    {
      label: '启用线路',
      key: 'enabled',
      type: 'switch',
      props: { activeText: '启用', inactiveText: '停用', inlinePrompt: true }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 3,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '可填写通行限制、装卸时间窗或线路注意事项'
      }
    }
  ])

  const reloadTenantScopedOptions = async (): Promise<void> => {
    if (isPlatformSuper.value && !form.tenantId) {
      Object.assign(addressOptions, { origin: [], destination: [] })
      return
    }
    await Promise.all([
      formRef.value?.reloadOptions('customerId'),
      formRef.value?.reloadOptions('originAddressId'),
      formRef.value?.reloadOptions('destinationAddressId')
    ])
  }

  const resetEstimate = (): void => {
    estimateRequestId += 1
    estimate.status = 'idle'
  }

  const handleTenantChange = async (): Promise<void> => {
    Object.assign(form, {
      customerId: '',
      originAddressId: '',
      destinationAddressId: '',
      distanceKm: null,
      estimatedMinutes: null
    })
    Object.assign(addressOptions, { origin: [], destination: [] })
    resetEstimate()
    await nextTick()
    await reloadTenantScopedOptions()
  }

  const handleEndpointChange = async (): Promise<void> => {
    resetEstimate()
    if (!form.originAddressId || !form.destinationAddressId) return
    await nextTick()
    await calculateRouteEstimate()
  }

  const calculateRouteEstimate = async (): Promise<void> => {
    const origin = toRouteCoordinate(originAddress.value)
    const destination = toRouteCoordinate(destinationAddress.value)
    if (!origin || !destination) {
      estimate.status = 'idle'
      return
    }

    const requestId = ++estimateRequestId
    estimate.status = 'loading'
    try {
      const result = await estimateDrivingRoute(origin, destination)
      if (requestId !== estimateRequestId) return
      Object.assign(form, result)
      estimate.status = 'ready'
    } catch {
      if (requestId === estimateRequestId) estimate.status = 'unavailable'
    }
  }

  const toRouteCoordinate = (address?: CustomerAddress): AmapRouteCoordinate | null => {
    const longitude = Number(address?.longitude)
    const latitude = Number(address?.latitude)
    if (
      !Number.isFinite(longitude) ||
      !Number.isFinite(latitude) ||
      longitude < -180 ||
      longitude > 180 ||
      latitude < -90 ||
      latitude > 90
    ) {
      return null
    }
    return { longitude, latitude }
  }

  const buildPayload = (): FavoriteRoute => {
    const payload = omit(cloneDeep(toRaw(form)), [
      'routePreview',
      'tenant',
      'customer',
      'originAddress',
      'destinationAddress',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as FavoriteRoute
    payload.routeName = payload.routeName.trim()
    payload.distanceKm = form.distanceKm || null
    payload.estimatedMinutes = form.estimatedMinutes || null
    payload.remark = form.remark?.trim() || null
    if (!isPlatformSuper.value || payload.id) delete payload.tenantId
    return payload
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = buildPayload()
      const type = payload.id ? 'edit' : 'add'
      if (type === 'edit') await editFavoriteRoute(payload)
      else await addFavoriteRoute(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: FavoriteRoute, tenantId?: string): Promise<void> => {
    Object.assign(form, createInitialForm(), row ? cloneDeep(toRaw(row)) : {}, {
      tenantId: row?.tenantId || tenantId || getUserInfo.value.tenantId || ''
    })
    Object.assign(addressOptions, { origin: [], destination: [] })
    resetEstimate()

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑常用线路' : '新增常用线路',
      subtitle: '常用线路引用地址簿，开单与调度可复用同一份标准路线',
      contentMaxHeight: '72vh',
      loading: true,
      onOpen: async (_data, api) => {
        try {
          await reloadTenantScopedOptions()
          await nextTick()
          formRef.value?.clearValidate()
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .favorite-route-dialog {
    &__preview {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 80px minmax(0, 1fr);
      gap: 16px;
      align-items: center;
      padding: 18px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__endpoint {
      display: flex;
      gap: 12px;
      align-items: center;
      min-width: 0;

      > span {
        display: grid;
        flex: 0 0 38px;
        place-items: center;
        width: 38px;
        height: 38px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      &.is-destination > span {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      > div {
        min-width: 0;
      }

      small,
      strong,
      p {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small,
      p {
        color: var(--el-text-color-secondary);
      }

      strong {
        margin: 2px 0;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 12px;
      }

      p.favorite-route-dialog__contact {
        display: flex;
        gap: 8px;

        span {
          overflow: hidden;
          text-overflow: ellipsis;
        }

        span + span::before {
          margin-right: 8px;
          color: var(--el-border-color);
          content: '·';
        }
      }
    }

    &__path {
      display: flex;
      gap: 7px;
      align-items: center;
      justify-content: center;

      span {
        width: 7px;
        height: 7px;
        background: var(--el-border-color);
        border-radius: 50%;

        &:last-child {
          width: 28px;
          height: 2px;
          border-radius: 999px;
        }
      }
    }

    &__estimate {
      display: flex;
      grid-column: 1 / -1;
      gap: 8px;
      align-items: center;
      min-width: 0;
      padding-top: 12px;
      font-size: 13px;
      color: var(--el-text-color-secondary);
      border-top: 1px dashed var(--el-border-color-lighter);

      > svg {
        flex: 0 0 auto;
        color: var(--el-color-primary);
      }

      > span {
        min-width: 0;
      }

      .el-button {
        flex: 0 0 auto;
        margin-left: auto;
      }

      &.is-ready {
        color: var(--el-color-success);

        > svg {
          color: currentcolor;
        }
      }

      &.is-unavailable {
        color: var(--el-color-warning);

        > svg {
          color: currentcolor;
        }
      }
    }

    &__address-select {
      min-width: 0;

      :deep(.el-select__selected-item) {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }
  }

  :global(.favorite-route-address-popper) {
    width: min(560px, calc(100vw - 32px)) !important;
    max-width: calc(100vw - 32px);
  }

  :global(.favorite-route-address-popper .el-select-dropdown__wrap) {
    max-height: 360px;
  }

  :global(.favorite-route-address-popper .el-select-dropdown__item) {
    height: auto;
    min-height: 84px;
    padding: 0 12px;
    line-height: normal;
    white-space: normal;
  }

  :deep(.art-form-item__content > .el-input-number) {
    width: 100%;
  }

  @media (width <= 700px) {
    .favorite-route-dialog {
      &__preview {
        grid-template-columns: minmax(0, 1fr);
      }

      &__path {
        display: none;
      }
    }
  }
</style>
