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
              <strong>{{ originAddress?.addressDetail || '请选择发货地址' }}</strong>
              <p>{{ originAddress?.region || '从客户发货地址中选择' }}</p>
            </div>
          </div>
          <div class="favorite-route-dialog__path" aria-hidden="true">
            <span></span><span></span><span></span>
          </div>
          <div class="favorite-route-dialog__endpoint is-destination">
            <span><ArtSvgIcon icon="ri:logout-circle-r-line" /></span>
            <div>
              <small>卸货地</small>
              <strong>{{ destinationAddress?.addressDetail || '请选择收货地址' }}</strong>
              <p>{{ destinationAddress?.region || '从客户收货地址中选择' }}</p>
            </div>
          </div>
        </section>
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { cloneDeep, omit } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import {
    addFavoriteRoute,
    editFavoriteRoute,
    fetchCustomerAddressOptions,
    fetchCustomerOptions
  } from '@/api/tms'

  defineOptions({ name: 'TmsFavoriteRouteDialog' })

  type FavoriteRoute = Api.Tms.BasicData.FavoriteRoute
  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerOption = Api.Tms.BasicData.CustomerOption
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

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const dialogRef = ref<ArtDialogExpose<FavoriteRoute | undefined>>()
  const formRef = ref<FormExpose>()
  const addressOptions = reactive<{
    origin: CustomerAddress[]
    destination: CustomerAddress[]
  }>({ origin: [], destination: [] })

  const createInitialForm = (): FavoriteRouteForm => ({
    id: undefined,
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

  const formRules: FormRules<FavoriteRouteForm> = {
    routeName: [{ required: true, message: '请输入线路名称', trigger: 'blur' }],
    customerId: [{ required: true, message: '请选择所属客户', trigger: 'change' }],
    originAddressId: [{ required: true, message: '请选择装货地址', trigger: 'change' }],
    destinationAddressId: [{ required: true, message: '请选择卸货地址', trigger: 'change' }],
    distanceKm: [{ type: 'number', min: 0.01, message: '线路里程应大于 0 公里' }],
    estimatedMinutes: [{ type: 'number', min: 1, message: '预计时长应大于 0 分钟' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const getAddressLabel = (option: unknown): string => {
    const address = option as CustomerAddress
    const label = [address.region, address.addressDetail].filter(Boolean).join(' ')
    return `${address.isDefault ? '【默认】' : ''}${label || '未命名地址'}`
  }

  const syncAddressOptions = (target: 'origin' | 'destination', result: unknown): unknown => {
    if (result && typeof result === 'object' && 'data' in result) {
      const data = (result as { data?: CustomerAddress[] }).data
      addressOptions[target] = Array.isArray(data) ? data : []
    }
    return result
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '线路信息', key: 'baseSection', type: 'divider', span: 24 },
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
      props: {
        filterable: true,
        clearable: true,
        placeholder: '请选择客户',
        onChange: handleCustomerChange
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
      immediate: false,
      beforeFetch: () => ({ customerId: form.customerId, addressType: 'shipping' }),
      shouldFetch: () => Boolean(form.customerId),
      afterFetch: (result) => syncAddressOptions('origin', result),
      props: {
        filterable: true,
        clearable: true,
        disabled: !form.customerId,
        placeholder: form.customerId ? '请选择客户发货地址' : '请先选择客户'
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
      immediate: false,
      beforeFetch: () => ({ customerId: form.customerId, addressType: 'receiving' }),
      shouldFetch: () => Boolean(form.customerId),
      afterFetch: (result) => syncAddressOptions('destination', result),
      props: {
        filterable: true,
        clearable: true,
        disabled: !form.customerId,
        placeholder: form.customerId ? '请选择客户收货地址' : '请先选择客户'
      }
    },
    { label: '运输参考', key: 'referenceSection', type: 'divider', span: 24 },
    {
      label: '线路里程',
      key: 'distanceKm',
      type: 'number',
      description: '用于报价和计划参考，不替代实际轨迹里程。',
      props: { min: 0.01, max: 99999999, precision: 2, step: 1, controlsPosition: 'right' }
    },
    {
      label: '预计时长',
      key: 'estimatedMinutes',
      type: 'number',
      description: '以分钟记录正常路况下的计划时长。',
      props: { min: 1, max: 999999, step: 10, controlsPosition: 'right' }
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

  const handleCustomerChange = (): void => {
    Object.assign(form, { originAddressId: '', destinationAddressId: '' })
    Object.assign(addressOptions, { origin: [], destination: [] })
    void reloadAddressOptions()
  }

  const reloadAddressOptions = async (): Promise<void> => {
    if (!form.customerId) return
    await Promise.all([
      formRef.value?.reloadOptions('originAddressId'),
      formRef.value?.reloadOptions('destinationAddressId')
    ])
  }

  const buildPayload = (): FavoriteRoute => {
    const payload = omit(cloneDeep(toRaw(form)), [
      'routePreview',
      'customer',
      'originAddress',
      'destinationAddress',
      'tenantId',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as FavoriteRoute
    payload.routeName = payload.routeName.trim()
    payload.distanceKm = form.distanceKm || null
    payload.estimatedMinutes = form.estimatedMinutes || null
    payload.remark = form.remark?.trim() || null
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

  const handleOpen = async (row?: FavoriteRoute): Promise<void> => {
    Object.assign(form, createInitialForm(), row ? cloneDeep(toRaw(row)) : {})
    Object.assign(addressOptions, { origin: [], destination: [] })

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑常用线路' : '新增常用线路',
      subtitle: '常用线路引用客户地址簿，开单与调度可复用同一份标准路线',
      contentMaxHeight: '72vh',
      loading: Boolean(row?.customerId),
      onOpen: async (_data, api) => {
        try {
          await reloadAddressOptions()
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
