<template>
  <div class="art-address-picker">
    <ElRow :gutter="gutter">
      <ElCol :xs="24" :sm="24" :md="regionSpan">
        <ElFormItem
          ref="regionFormItemRef"
          :label="regionLabel"
          :label-width="labelWidth"
          :prop="regionPathProp"
        >
          <ElCascader
            v-model="regionPath"
            class="art-address-picker__control"
            :options="resolvedRegionOptions"
            :props="mergedCascaderProps"
            :placeholder="regionPlaceholder"
            :clearable="clearable"
            :filterable="filterable"
            :disabled="disabled"
            :loading="regionLoading"
            @change="handleRegionChange"
          />
        </ElFormItem>
      </ElCol>

      <ElCol :xs="24" :sm="24" :md="detailSpan">
        <ElFormItem
          ref="detailFormItemRef"
          :label="detailLabel"
          :label-width="labelWidth"
          :prop="addressDetailProp"
        >
          <div class="art-address-picker__detail">
            <ElInput
              v-model.trim="addressDetail"
              class="art-address-picker__control"
              :maxlength="detailMaxlength"
              :placeholder="detailPlaceholder"
              :disabled="disabled"
              :clearable="clearable"
              show-word-limit
              @focus="openPickerOnFocus && handleOpenPicker()"
              @input="handleDetailChange"
              @clear="handleDetailClear"
            >
              <template #prefix>
                <ElIcon><Location /></ElIcon>
              </template>
              <template #append>
                <ElButton :icon="MapLocation" :disabled="disabled" @click="handleOpenPicker">
                  地图选择
                </ElButton>
              </template>
            </ElInput>

            <div v-if="showCoordinateHint" class="art-address-picker__hint">
              <ElTag :type="statusMeta.type" effect="light" round>{{ statusMeta.label }}</ElTag>
              <span v-if="hasCoordinate">{{ longitude }}, {{ latitude }}</span>
              <span v-else>地图选择后自动回填地址和坐标</span>
            </div>
          </div>
        </ElFormItem>
      </ElCol>
    </ElRow>

    <ArtDialog
      ref="dialogRef"
      width="1080px"
      :show-footer="true"
      append-to-body
      :close-on-click-modal="false"
      show-fullscreen-button
      @opened="handleDialogOpened"
      @closed="handleDialogClosed"
    >
      <div class="art-address-picker-map">
        <ArtAddressMap
          ref="mapRef"
          class="art-address-picker-map__canvas"
          v-model:search-keyword="searchKeyword"
          :amap-key="amapKey"
          :amap-security-js-code="amapSecurityJsCode"
          :show-poi-search="true"
          enable-map-pick
          :search-scope="searchScope"
          :city-limit="limitSearchCity"
          :region-path="regionPath"
          :region-adcode="regionAdcode"
          :region-search-text="regionSearchText"
          :district-level="districtLevel"
          :fallback-address="fullAddress || addressDetail"
          :message="mapMessage"
          @location-pick="setDraftLocation"
          @error="mapMessage = $event"
        />
      </div>

      <template #footer="{ api }">
        <div class="art-address-picker-map__footer">
          <div class="art-address-picker-map__selected">
            <span class="art-address-picker-map__selected-label">已选地址</span>
            <strong>{{ draftAddress || '请搜索或点击地图选择地址' }}</strong>
          </div>
          <div class="art-address-picker-map__coordinate">
            <span>地址坐标</span>
            <strong>{{ draftCoordinateText || '-' }}</strong>
          </div>
          <div>
            <ElButton @click="api.handleClose()">取消</ElButton>
            <ElButton
              type="primary"
              :disabled="!canConfirmPick"
              @click="() => void api.handleConfirm()"
            >
              保存地址
            </ElButton>
          </div>
        </div>
      </template>
    </ArtDialog>
  </div>
</template>

<script setup lang="ts">
  import { Location, MapLocation } from '@element-plus/icons-vue'
  import { isNil, trim } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtAddressMap from './modules/map.vue'
  import type {
    AddressCoordinateSource,
    AddressCoordinateStatus,
    AddressCoordinateSystem,
    AddressLocationPayload,
    AddressMapPickResult,
    AddressRegionOption
  } from './types'

  defineOptions({ name: 'ArtAddressPicker' })

  type DistrictLevel = 'province' | 'city' | 'district'

  interface Props {
    regionOptions?: AddressRegionOption[]
    regionApi?: () => Promise<AddressRegionOption[]>
    amapKey?: string
    amapSecurityJsCode?: string
    disabled?: boolean
    clearable?: boolean
    filterable?: boolean
    gutter?: number
    regionSpan?: number
    detailSpan?: number
    regionLabel?: string
    detailLabel?: string
    regionPlaceholder?: string
    detailPlaceholder?: string
    detailMaxlength?: number
    labelWidth?: string | number
    regionPathProp?: string
    addressDetailProp?: string
    cascaderProps?: Record<string, unknown>
    openPickerOnFocus?: boolean
    showCoordinateHint?: boolean
  }

  interface MapExpose {
    initialize: (options: { center: [number, number]; zoom?: number }) => Promise<any>
    setMarker: (longitude: number | string, latitude: number | string) => void
    setZoomAndCenter: (zoom: number, center: [number, number]) => void
    centerByRegion: () => void
    resize: () => void
    searchPoi: (options?: { silent?: boolean; fallbackKeyword?: string }) => void
    setSearchKeyword: (value: string) => void
    setPickedLocation: (payload: AddressMapPickResult) => void
    clearPoi: () => void
    destroy: () => void
  }

  interface FormItemExpose {
    clearValidate: () => void
  }

  const props = withDefaults(defineProps<Props>(), {
    regionOptions: () => [],
    regionApi: undefined,
    amapKey: '',
    amapSecurityJsCode: '',
    disabled: false,
    clearable: true,
    filterable: true,
    gutter: 20,
    regionSpan: 8,
    detailSpan: 16,
    regionLabel: '区域',
    detailLabel: '详细地址',
    regionPlaceholder: '请选择省 / 市 / 区',
    detailPlaceholder: '请输入道路、门牌号、小区、楼栋等，或点击地图选择',
    detailMaxlength: 200,
    labelWidth: '100px',
    regionPathProp: 'regionPath',
    addressDetailProp: 'addressDetail',
    cascaderProps: () => ({}),
    openPickerOnFocus: false,
    showCoordinateHint: true
  })

  const emit = defineEmits<{
    (event: 'address-change', payload: AddressLocationPayload): void
    (event: 'pick-confirm', payload: AddressLocationPayload): void
  }>()

  const regionPath = defineModel<string[]>('regionPath', { default: () => [] })
  const addressDetail = defineModel<string>('addressDetail', { default: '' })
  const regionAdcode = defineModel<string | null | undefined>('regionAdcode', {
    default: undefined
  })
  const longitude = defineModel<number | string | null | undefined>('longitude', { default: null })
  const latitude = defineModel<number | string | null | undefined>('latitude', { default: null })
  const coordinateSystem = defineModel<AddressCoordinateSystem | null | undefined>(
    'coordinateSystem',
    {
      default: 'gcj02'
    }
  )
  const coordinateSource = defineModel<AddressCoordinateSource | '' | null | undefined>(
    'coordinateSource',
    {
      default: ''
    }
  )
  const coordinateStatus = defineModel<AddressCoordinateStatus | null | undefined>(
    'coordinateStatus',
    {
      default: 'pending'
    }
  )
  const geocodeProvider = defineModel<string | null | undefined>('geocodeProvider', {
    default: undefined
  })
  const geocodedAt = defineModel<string | null | undefined>('geocodedAt', { default: undefined })

  const dialogRef = ref<ArtDialogExpose>()
  const mapRef = ref<MapExpose>()
  const regionFormItemRef = ref<FormItemExpose>()
  const detailFormItemRef = ref<FormItemExpose>()
  const regionLoading = ref(false)
  const loadedRegionOptions = ref<AddressRegionOption[]>([])
  const searchKeyword = ref('')
  const draftAddress = ref('')
  const draftLongitude = ref<number | string | null>(null)
  const draftLatitude = ref<number | string | null>(null)
  const draftRegionPath = ref<string[]>([])
  const draftRegionAdcode = ref<string>()
  const mapMessage = ref('')

  const resolvedRegionOptions = computed(() =>
    props.regionOptions.length ? props.regionOptions : loadedRegionOptions.value
  )

  const mergedCascaderProps = computed<Record<string, unknown>>(() => ({
    label: 'name',
    value: 'name',
    children: 'children',
    emitPath: true,
    checkStrictly: true,
    ...props.cascaderProps
  }))

  const hasCoordinate = computed(() => {
    const lng = trim(String(longitude.value ?? ''))
    const lat = trim(String(latitude.value ?? ''))
    return Boolean(lng && lat)
  })

  const canConfirmPick = computed(
    () => Boolean(draftAddress.value) && !isNil(draftLongitude.value) && !isNil(draftLatitude.value)
  )

  const draftCoordinateText = computed(() => {
    if (isNil(draftLongitude.value) || isNil(draftLatitude.value)) return ''
    return `${draftLongitude.value}, ${draftLatitude.value}`
  })

  const effectiveCoordinateStatus = computed<AddressCoordinateStatus>(() => {
    if (hasCoordinate.value && (!coordinateStatus.value || coordinateStatus.value === 'pending')) {
      return 'located'
    }
    return coordinateStatus.value || 'pending'
  })

  const currentRegionPath = computed(() =>
    Array.isArray(regionPath.value) ? regionPath.value : []
  )

  const regionText = computed(() => currentRegionPath.value.filter(Boolean).join('/'))

  const fullAddress = computed(() => {
    const region = currentRegionPath.value.filter(Boolean).join('')
    return trim([region, addressDetail.value].filter(Boolean).join(' '))
  })

  const searchScope = computed(
    () =>
      findRegionAdcode(resolvedRegionOptions.value, currentRegionPath.value) ||
      currentRegionPath.value.at(-1) ||
      currentRegionPath.value[1] ||
      currentRegionPath.value[0] ||
      '全国'
  )

  const limitSearchCity = computed(() => searchScope.value !== '全国')

  const regionSearchText = computed(() => currentRegionPath.value.filter(Boolean).join(''))

  const districtLevel = computed<DistrictLevel>(() => {
    if (currentRegionPath.value.length >= 3) return 'district'
    if (currentRegionPath.value.length === 2) return 'city'
    return 'province'
  })

  const statusMeta = computed(() => {
    const statusMap: Record<
      string,
      { label: string; type: 'success' | 'warning' | 'info' | 'danger' }
    > = {
      located: { label: '已选点', type: 'success' },
      unconfirmed: { label: '待确认', type: 'warning' },
      failed: { label: '选点失败', type: 'danger' },
      pending: { label: '未选点', type: 'info' }
    }
    return statusMap[effectiveCoordinateStatus.value] ?? statusMap.pending
  })

  const createPayload = (): AddressLocationPayload => ({
    regionPath: [...currentRegionPath.value],
    region: regionText.value,
    regionAdcode: regionAdcode.value ?? undefined,
    addressDetail: addressDetail.value,
    fullAddress: fullAddress.value,
    longitude: longitude.value,
    latitude: latitude.value,
    coordinateSystem: coordinateSystem.value ?? 'gcj02',
    coordinateSource: coordinateSource.value ?? '',
    coordinateStatus: effectiveCoordinateStatus.value,
    geocodeProvider: geocodeProvider.value ?? undefined,
    geocodedAt: geocodedAt.value ?? undefined
  })

  const findRegionAdcode = (options: AddressRegionOption[], path: string[]): string | undefined => {
    let currentOptions = options
    let matchedCode: string | undefined
    for (const name of path) {
      const matched = currentOptions.find((item) => item.name === name)
      if (!matched) return matchedCode
      matchedCode = matched.code
      currentOptions = matched.children ?? []
    }
    return matchedCode
  }

  const findRegionPathByCode = (
    options: AddressRegionOption[],
    code: string,
    ancestors: string[] = []
  ): string[] | undefined => {
    for (const option of options) {
      const currentPath = [...ancestors, option.name]
      if (option.code === code) return currentPath
      const childPath = findRegionPathByCode(option.children ?? [], code, currentPath)
      if (childPath) return childPath
    }
    return undefined
  }

  const isSameRegionName = (first?: string, second?: string): boolean => {
    if (!first || !second) return false
    const normalize = (value: string) => value.replace(/[省市区县]/g, '')
    return first === second || normalize(first) === normalize(second)
  }

  const containsNamesInOrder = (path: string[], names: string[]): boolean => {
    if (!names.length) return false
    let nameIndex = 0
    for (const pathName of path) {
      if (isSameRegionName(pathName, names[nameIndex])) nameIndex += 1
      if (nameIndex >= names.length) return true
    }
    return false
  }

  const findRegionPathByNames = (
    options: AddressRegionOption[],
    names: string[],
    ancestors: string[] = []
  ): string[] | undefined => {
    for (const option of options) {
      const currentPath = [...ancestors, option.name]
      if (containsNamesInOrder(currentPath, names)) return currentPath
      const childPath = findRegionPathByNames(option.children ?? [], names, currentPath)
      if (childPath) return childPath
    }
    return undefined
  }

  const resolveRegionPath = (payload: AddressMapPickResult): string[] => {
    const options = resolvedRegionOptions.value
    const matchedByCode = payload.regionAdcode
      ? findRegionPathByCode(options, payload.regionAdcode)
      : undefined
    if (matchedByCode?.length) return matchedByCode
    const names = payload.regionPath.filter(Boolean)
    return findRegionPathByNames(options, names) ?? names
  }

  const stripRegionPrefix = (address: string, path: string[]): string => {
    const normalizedAddress = trim(address)
    if (!normalizedAddress || !path.length) return normalizedAddress
    const prefixes = path
      .filter(Boolean)
      .reduce<string[]>((result, item) => {
        const previous = result.at(-1) ?? ''
        result.push(`${previous}${item}`)
        return result
      }, [])
      .sort((first, second) => second.length - first.length)
    const matchedPrefix = prefixes.find((prefix) => normalizedAddress.startsWith(prefix))
    return trim(matchedPrefix ? normalizedAddress.slice(matchedPrefix.length) : normalizedAddress)
  }

  const markCoordinateUnconfirmed = (): void => {
    if (!hasCoordinate.value || coordinateStatus.value === 'unconfirmed') return
    coordinateStatus.value = 'unconfirmed'
  }

  const clearCoordinateState = (): void => {
    longitude.value = null
    latitude.value = null
    coordinateSource.value = ''
    coordinateStatus.value = 'pending'
    geocodeProvider.value = undefined
    geocodedAt.value = undefined
    draftLongitude.value = null
    draftLatitude.value = null
  }

  const clearLocationState = (): void => {
    addressDetail.value = ''
    clearCoordinateState()
    draftAddress.value = ''
    draftRegionPath.value = []
    draftRegionAdcode.value = undefined
    searchKeyword.value = ''
  }

  const handleRegionChange = (): void => {
    if (!currentRegionPath.value.length) {
      regionAdcode.value = undefined
      clearLocationState()
      emit('address-change', createPayload())
      return
    }
    regionAdcode.value = findRegionAdcode(resolvedRegionOptions.value, currentRegionPath.value)
    markCoordinateUnconfirmed()
    emit('address-change', createPayload())
  }

  const handleDetailChange = (): void => {
    markCoordinateUnconfirmed()
    emit('address-change', createPayload())
  }

  const handleDetailClear = (): void => {
    clearCoordinateState()
    draftAddress.value = ''
    searchKeyword.value = ''
    emit('address-change', createPayload())
  }

  const setDraftLocation = (payload: AddressMapPickResult): void => {
    const nextRegionPath = resolveRegionPath(payload)
    draftAddress.value = payload.address
    draftLongitude.value = payload.longitude
    draftLatitude.value = payload.latitude
    draftRegionPath.value = nextRegionPath.length ? nextRegionPath : draftRegionPath.value
    draftRegionAdcode.value =
      payload.regionAdcode ??
      findRegionAdcode(resolvedRegionOptions.value, nextRegionPath) ??
      draftRegionAdcode.value
    mapRef.value?.setMarker(payload.longitude, payload.latitude)
  }

  const initializeMap = async (): Promise<void> => {
    mapMessage.value = ''
    const defaultCenter: [number, number] = hasCoordinate.value
      ? [Number(longitude.value), Number(latitude.value)]
      : [120.1551, 30.2741]
    await mapRef.value?.initialize({
      center: defaultCenter,
      zoom: hasCoordinate.value ? 15 : 11
    })

    if (hasCoordinate.value) {
      setDraftLocation({
        address: fullAddress.value || addressDetail.value,
        longitude: longitude.value!,
        latitude: latitude.value!,
        regionPath: currentRegionPath.value,
        regionAdcode: regionAdcode.value ?? undefined
      })
    } else {
      mapRef.value?.centerByRegion()
    }

    mapRef.value?.resize()
  }

  const handleOpenPicker = async (): Promise<void> => {
    if (props.disabled) return
    regionAdcode.value = findRegionAdcode(resolvedRegionOptions.value, currentRegionPath.value)
    searchKeyword.value = fullAddress.value
    draftAddress.value = fullAddress.value || addressDetail.value
    draftLongitude.value = longitude.value ?? null
    draftLatitude.value = latitude.value ?? null
    draftRegionPath.value = [...currentRegionPath.value]
    draftRegionAdcode.value = regionAdcode.value ?? undefined
    mapMessage.value = ''
    await dialogRef.value?.handleOpen(undefined, {
      title: '选择地址',
      width: '1080px',
      confirmText: '保存地址',
      onConfirm: () => {
        confirmPick()
      },
      dialogProps: {
        class: 'art-address-picker-dialog'
      }
    })
  }

  const handleDialogOpened = async (): Promise<void> => {
    try {
      await initializeMap()
      mapRef.value?.setSearchKeyword(searchKeyword.value)
      if (hasCoordinate.value) {
        mapRef.value?.setPickedLocation({
          address: draftAddress.value,
          longitude: draftLongitude.value!,
          latitude: draftLatitude.value!,
          regionPath: draftRegionPath.value,
          regionAdcode: draftRegionAdcode.value
        })
      } else if (searchKeyword.value) {
        mapRef.value?.searchPoi({ silent: true, fallbackKeyword: fullAddress.value })
      }
    } catch (error) {
      mapMessage.value = error instanceof Error ? error.message : '高德地图加载失败'
    }
  }

  const handleDialogClosed = (): void => {
    mapRef.value?.destroy()
    mapMessage.value = ''
  }

  const confirmPick = (): void => {
    if (!canConfirmPick.value) return
    const nextRegionPath = draftRegionPath.value.length
      ? draftRegionPath.value
      : currentRegionPath.value
    addressDetail.value = stripRegionPrefix(draftAddress.value, nextRegionPath)
    longitude.value = draftLongitude.value
    latitude.value = draftLatitude.value
    coordinateSystem.value = 'gcj02'
    coordinateSource.value = 'map_pick'
    coordinateStatus.value = 'located'
    geocodeProvider.value = 'amap'
    geocodedAt.value = new Date().toISOString()
    if (nextRegionPath.length) {
      regionPath.value = nextRegionPath
      regionAdcode.value =
        draftRegionAdcode.value ?? findRegionAdcode(resolvedRegionOptions.value, nextRegionPath)
    }
    void nextTick(() => {
      regionFormItemRef.value?.clearValidate()
      detailFormItemRef.value?.clearValidate()
    })
    emit('pick-confirm', createPayload())
  }

  const loadRegionOptions = async (): Promise<void> => {
    if (!props.regionApi || props.regionOptions.length) return
    regionLoading.value = true
    try {
      loadedRegionOptions.value = await props.regionApi()
      regionAdcode.value = findRegionAdcode(loadedRegionOptions.value, regionPath.value)
    } finally {
      regionLoading.value = false
    }
  }

  watch(
    () => props.regionOptions,
    (options) => {
      if (!options.length) return
      regionAdcode.value = findRegionAdcode(options, regionPath.value)
    },
    { deep: true }
  )

  watch(
    () => dialogRef.value?.fullscreen.value,
    async () => {
      await nextTick()
      mapRef.value?.resize()
    }
  )

  onMounted(loadRegionOptions)
</script>

<style scoped lang="scss">
  .art-address-picker {
    width: 100%;

    &__control {
      width: 100%;
    }

    &__detail {
      width: 100%;
      min-width: 0;
    }

    &__hint {
      display: flex;
      gap: 8px;
      align-items: center;
      margin-top: 6px;
      font-size: 12px;
      line-height: 20px;
      color: var(--el-text-color-secondary);
    }
  }

  .art-address-picker-map {
    position: relative;
    height: min(64vh, 620px);
    min-height: 520px;
    overflow: hidden;
    background: var(--el-fill-color-light);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: var(--el-border-radius-base);

    &__canvas {
      width: 100%;
      height: 100%;
    }

    &__footer {
      display: grid;
      grid-template-columns: minmax(220px, 1fr) minmax(180px, 280px) auto auto;
      gap: 12px;
      align-items: center;
      width: 100%;
    }

    &__selected,
    &__coordinate {
      display: flex;
      gap: 8px;
      align-items: center;
      min-width: 0;
    }

    &__selected-label,
    &__coordinate span {
      flex: none;
      color: var(--el-text-color-secondary);
    }

    &__selected strong,
    &__coordinate strong {
      min-width: 0;
      overflow: hidden;
      color: var(--el-text-color-primary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  @media (width <= 900px) {
    .art-address-picker-map {
      height: 560px;

      &__footer {
        grid-template-columns: minmax(0, 1fr);
      }
    }
  }

  :global(.art-address-picker-dialog.is-fullscreen > .el-dialog__body) {
    display: flex;
    flex-direction: column;
    padding-bottom: 0;
  }

  :global(.art-address-picker-dialog.is-fullscreen .art-dialog__content) {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-height: 0;
  }

  :global(.art-address-picker-dialog.is-fullscreen .art-address-picker-map) {
    flex: 1;
    height: auto;
    min-height: 0;
  }

  :global(.art-address-picker-dialog.is-fullscreen > .el-dialog__footer) {
    flex: none;
  }
</style>
