<template>
  <ArtDialog ref="dialogRef" size="md">
    <div class="address-geofence-dialog">
      <section class="address-geofence-dialog__summary art-card-xs">
        <div class="address-geofence-dialog__address-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:map-pin-2-line" />
        </div>
        <div class="address-geofence-dialog__address-copy">
          <div>
            <strong>{{ addressTitle }}</strong>
            <ElTag :type="addressTypeTag" effect="plain" round>{{ addressTypeLabel }}</ElTag>
          </div>
          <p>{{ fullAddress }}</p>
          <small>{{ coordinateText }}</small>
        </div>
      </section>

      <ArtForm
        ref="formRef"
        v-model="form"
        :items="formItems"
        :rules="formRules"
        :disabled="!canManage"
        :span="24"
        label-width="118px"
        :show-reset="false"
        :show-submit="false"
      />

      <section class="address-geofence-dialog__preview" aria-label="围栏半径预览">
        <div class="address-geofence-dialog__radar" :class="{ 'is-disabled': !form.enabled }">
          <span class="address-geofence-dialog__ring is-outer"></span>
          <span class="address-geofence-dialog__ring is-middle"></span>
          <span class="address-geofence-dialog__ring is-inner"></span>
          <span class="address-geofence-dialog__center"><ArtSvgIcon icon="ri:map-pin-fill" /></span>
        </div>
        <div class="address-geofence-dialog__preview-copy">
          <span>当前覆盖半径</span>
          <strong>{{ form.enabled ? `${form.radiusM} 米` : '未启用' }}</strong>
          <p>
            {{
              form.enabled
                ? `以当前地址坐标为中心，进入约 ${form.radiusM} 米范围时判定为到场。`
                : '启用后才会参与运输执行的到离场定位校验。'
            }}
          </p>
        </div>
      </section>

      <ElAlert v-if="!hasCoordinate" type="warning" :closable="false" show-icon>
        <template #title>该地址尚未完成地图定位</template>
        请先编辑地址并通过地图选点保存经纬度，再启用电子围栏。
      </ElAlert>
      <ElAlert v-else-if="!canManage" type="info" :closable="false" show-icon>
        普通用户可查看地址围栏范围；修改围栏仅允许平台超级管理员执行。
      </ElAlert>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchGeofenceConfig } from '@/api/system-manage'
  import { updateCustomerAddressGeofence } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsCustomerAddressGeofenceDialog' })

  type CustomerAddress = Api.Tms.BasicData.CustomerAddress

  interface GeofenceForm {
    enabled: boolean
    radiusM: number
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{
    (event: 'success'): void
  }>()

  const { isPlatformSuper } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<CustomerAddress>>()
  const formRef = ref<FormExpose>()
  const address = shallowRef<CustomerAddress>()
  const form = reactive<GeofenceForm>({ enabled: false, radiusM: 1000 })
  const canManage = computed(() => isPlatformSuper.value)
  const hasCoordinate = computed(() => {
    const longitude = address.value?.longitude
    const latitude = address.value?.latitude
    const hasLongitude = longitude !== null && longitude !== undefined && longitude !== ''
    const hasLatitude = latitude !== null && latitude !== undefined && latitude !== ''

    return (
      hasLongitude &&
      hasLatitude &&
      Number.isFinite(Number(longitude)) &&
      Number.isFinite(Number(latitude))
    )
  })
  const addressTitle = computed(
    () => address.value?.customer?.customerName || address.value?.contactName || '客户地址'
  )
  const fullAddress = computed(
    () =>
      [address.value?.region, address.value?.addressDetail].filter(Boolean).join(' ') ||
      '未填写地址'
  )
  const addressTypeLabel = computed(() =>
    address.value?.addressType === 'shipping' ? '发货地址' : '收货地址'
  )
  const addressTypeTag = computed(() =>
    address.value?.addressType === 'shipping' ? ('primary' as const) : ('success' as const)
  )
  const coordinateText = computed(() => {
    if (!hasCoordinate.value) return '未定位'
    return `经纬度：${Number(address.value?.longitude).toFixed(6)}, ${Number(address.value?.latitude).toFixed(6)}`
  })

  const formRules: FormRules<GeofenceForm> = {
    radiusM: [
      { required: true, message: '请输入围栏半径', trigger: 'blur' },
      { type: 'number', min: 50, max: 50000, message: '围栏半径应在 50 至 50000 米之间' }
    ]
  }

  const formItems = computed<FormItem[]>(() => [
    {
      label: '启用地址围栏',
      key: 'enabled',
      type: 'switch',
      description: hasCoordinate.value
        ? '启用后，该地址将参与装货或卸货到场定位校验。'
        : '请先完成地址地图定位。',
      props: {
        disabled: !hasCoordinate.value,
        activeText: '启用',
        inactiveText: '停用',
        inlinePrompt: true
      }
    },
    {
      label: '围栏半径',
      key: 'radiusM',
      type: 'number',
      hidden: !form.enabled,
      description: '建议按园区入口、装卸月台范围和现场定位漂移合理设置。',
      props: { min: 50, max: 50000, step: 50, controlsPosition: 'right' }
    }
  ])

  const loadDefaultRadius = async (): Promise<void> => {
    if (address.value?.geofenceRadiusM) return
    const { data } = await fetchGeofenceConfig()
    form.radiusM =
      address.value?.addressType === 'shipping'
        ? (data?.loadingRadiusM ?? 1000)
        : (data?.unloadingRadiusM ?? 1000)
  }

  const handleSubmit = async (): Promise<boolean> => {
    if (!canManage.value || !address.value?.id) return false
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      await updateCustomerAddressGeofence(address.value.id, {
        geofenceEnabled: form.enabled,
        geofenceRadiusM: form.enabled
          ? form.radiusM
          : (address.value.geofenceRadiusM ?? form.radiusM),
        geofenceUpdatedAt: new Date().toISOString()
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row: CustomerAddress): Promise<void> => {
    address.value = row
    Object.assign(form, {
      enabled: row.geofenceEnabled === true,
      radiusM: Number(row.geofenceRadiusM) || 1000
    })

    await dialogRef.value?.handleOpen(row, {
      title: canManage.value ? '设置地址围栏' : '查看地址围栏',
      subtitle: '围栏中心直接使用地址管理中已保存的地图坐标',
      confirmText: '保存围栏',
      showConfirmButton: canManage.value,
      contentMaxHeight: '68vh',
      loading: true,
      onOpen: async (_data, api) => {
        try {
          await loadDefaultRadius()
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
  .address-geofence-dialog {
    display: grid;
    gap: 16px;

    &__summary {
      display: flex;
      gap: 14px;
      align-items: center;
      min-width: 0;
      padding: 16px;
      background: linear-gradient(120deg, var(--el-color-primary-light-9), transparent 72%);
    }

    &__address-icon {
      display: grid;
      flex: 0 0 44px;
      place-items: center;
      width: 44px;
      height: 44px;
      color: var(--el-color-primary);
      background: var(--default-box-color);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--el-border-radius-base);
    }

    &__address-copy {
      min-width: 0;

      > div {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        align-items: center;
      }

      p,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      p {
        margin: 5px 0 2px;
        color: var(--el-text-color-regular);
      }

      small {
        color: var(--el-text-color-secondary);
      }
    }

    &__preview {
      display: grid;
      grid-template-columns: 160px minmax(0, 1fr);
      gap: 24px;
      align-items: center;
      padding: 20px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__radar {
      position: relative;
      width: 150px;
      height: 150px;
      margin: auto;

      &.is-disabled {
        filter: grayscale(1);
        opacity: 0.55;
      }
    }

    &__ring,
    &__center {
      position: absolute;
      top: 50%;
      left: 50%;
      border-radius: 50%;
      transform: translate(-50%, -50%);
    }

    &__ring {
      border: 1px solid color-mix(in srgb, var(--theme-color) 35%, transparent);

      &.is-outer {
        width: 100%;
        height: 100%;
        background: color-mix(in srgb, var(--theme-color) 5%, transparent);
      }

      &.is-middle {
        width: 68%;
        height: 68%;
        background: color-mix(in srgb, var(--theme-color) 7%, transparent);
      }

      &.is-inner {
        width: 36%;
        height: 36%;
        background: color-mix(in srgb, var(--theme-color) 10%, transparent);
      }
    }

    &__center {
      display: grid;
      z-index: 2;
      place-items: center;
      width: 34px;
      height: 34px;
      color: white;
      background: var(--theme-color);
      box-shadow: 0 6px 16px color-mix(in srgb, var(--theme-color) 30%, transparent);
    }

    &__preview-copy {
      min-width: 0;

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      strong {
        display: block;
        margin: 2px 0 6px;
        font-size: 24px;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        line-height: 1.65;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.art-form) {
      padding-inline: 0;
    }

    :deep(.art-form-item__content > .el-input-number) {
      width: 100%;
    }
  }

  @media (width <= 620px) {
    .address-geofence-dialog {
      &__preview {
        grid-template-columns: minmax(0, 1fr);
        text-align: center;
      }

      &__address-copy {
        p,
        small {
          white-space: normal;
        }
      }
    }
  }
</style>
