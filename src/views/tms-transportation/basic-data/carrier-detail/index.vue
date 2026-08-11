<template>
  <ArtPageShell
    class="carrier-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无承运商详情"
    @retry="loadPage"
  >
    <ArtPageHeader
      :title="detail.data?.companyName || '承运商详情'"
      :subtitle="detail.data?.carrierCode || '--'"
      show-back
      @back="goBack"
    >
      <ElButton type="primary" :disabled="!detail.data?.id" @click="openPerformanceAdvisor">
        <ArtSvgIcon icon="ri:sparkling-2-line" />AI 经营评估
      </ElButton>
    </ArtPageHeader>

    <div class="carrier-detail__content">
      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="basicItems" :columns="4">
          <template #item-businessLicenseUrl>
            <ElImage
              v-if="detail.data?.businessLicenseUrl"
              class="carrier-detail__image"
              :src="detail.data.businessLicenseUrl"
              :preview-src-list="[detail.data.businessLicenseUrl]"
              fit="cover"
              preview-teleported
            />
            <span v-else>--</span>
          </template>
          <template #item-driverCount>
            <ElButton
              class="carrier-detail__link-value"
              link
              type="primary"
              @click="goDriverManage"
            >
              {{ relationStats.driverCount }}
            </ElButton>
          </template>
          <template #item-vehicleCount>
            <ElButton
              class="carrier-detail__link-value"
              link
              type="primary"
              @click="goVehicleManage"
            >
              {{ relationStats.vehicleCount }}
            </ElButton>
          </template>
        </ArtDescriptions>
      </section>

      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>联系人信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="contactItems" :columns="4" />
      </section>

      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>财务信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="financeItems" :columns="4" />
      </section>

      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>合同信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="contractItems" :columns="2">
          <template #item-contractAttachmentUrl>
            <ArtAttachmentLink
              v-if="detail.data?.contractAttachmentUrl"
              :file="{
                name: '合同附件',
                url: detail.data.contractAttachmentUrl
              }"
            />
            <span v-else>--</span>
          </template>
        </ArtDescriptions>
      </section>

      <section class="carrier-detail__section art-card-xs">
        <div class="carrier-detail__section-header">
          <ArtSectionTitle :show-line="false">名下司机</ArtSectionTitle>
          <ElButton type="primary" plain @click="goDriverManage">司机管理</ElButton>
        </div>
        <VehicleQueryTable
          :data="relationData.drivers"
          :columns="driverColumns"
          :loading="relationData.loadingDrivers"
          empty-height="180px"
          table-layout="auto"
        />
      </section>

      <section class="carrier-detail__section art-card-xs">
        <div class="carrier-detail__section-header">
          <ArtSectionTitle :show-line="false">名下车辆</ArtSectionTitle>
          <ElButton type="primary" plain @click="goVehicleManage">车辆管理</ElButton>
        </div>
        <VehicleQueryTable
          :data="relationData.vehicles"
          :columns="vehicleColumns"
          :loading="relationData.loadingVehicles"
          empty-height="180px"
          table-layout="auto"
        />
      </section>
    </div>

    <CarrierPerformanceAdvisorDrawer ref="performanceAdvisorRef" />
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import { isNil } from 'lodash-es'
  import { ElButton, ElImage } from 'element-plus'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtAttachmentLink from '@/components/core/media/art-file-viewer/attachment-link.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import VehicleQueryTable from '@/views/vehicle-manage-system/vehicle-query/modules/vehicle-query-table.vue'
  import { fetchCarrierDetail, fetchDriverListByCarrierId } from '@/api/tms'
  import { fetchVehicleArchiveList } from '@/api/vehicle-manage-system'
  import type { ColumnOption } from '@/types'
  import CarrierPerformanceAdvisorDrawer from './modules/carrier-performance-advisor-drawer.vue'

  defineOptions({ name: 'TmsCarrierDetail' })

  type Carrier = Api.Tms.BasicData.Carrier
  type Driver = Api.Tms.BasicData.Driver
  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive

  interface PageState {
    loading: boolean
    error: Error | null
  }

  interface DetailState {
    data?: Carrier
  }

  interface RelationState {
    drivers: Driver[]
    vehicles: VehicleArchive[]
    loadingDrivers: boolean
    loadingVehicles: boolean
  }

  interface PerformanceAdvisorExpose {
    handleOpen: (carrierId: string) => Promise<void>
  }

  const route = useRoute()
  const router = useRouter()
  const performanceAdvisorRef = ref<PerformanceAdvisorExpose>()

  const page = reactive<PageState>({ loading: false, error: null })
  const detail = reactive<DetailState>({ data: undefined })
  const relationData = reactive<RelationState>({
    drivers: [],
    vehicles: [],
    loadingDrivers: false,
    loadingVehicles: false
  })

  const relationStats = computed(() => ({
    driverCount: relationData.drivers.length,
    vehicleCount: relationData.vehicles.length
  }))
  const descriptionData = computed<Partial<Carrier>>(() => detail.data ?? {})
  const basicItems: ArtDescriptionItem<Partial<Carrier>>[] = [
    { key: 'carrierCode', label: '承运商编码', field: 'carrierCode', copyable: true },
    { key: 'companyName', label: '公司名称', field: 'companyName' },
    {
      key: 'carrierType',
      label: '承运商类型',
      field: 'carrierType',
      dictCode: 'tmsCarrierType',
      dictDisplay: 'text'
    },
    { key: 'businessLicenseNo', label: '营业执照号码', field: 'businessLicenseNo', copyable: true },
    { key: 'taxRegistrationNo', label: '税务登记号码', field: 'taxRegistrationNo', copyable: true },
    { key: 'legalRepresentative', label: '法人代表', field: 'legalRepresentative' },
    { key: 'address', label: '公司地址', value: (data: Partial<Carrier>) => formatAddress(data) },
    { key: 'postalCode', label: '邮编', field: 'postalCode' },
    {
      key: 'enabled',
      label: '承运商状态',
      value: (data: Partial<Carrier>) => getBooleanDictValue(data.enabled),
      dictCode: 'commonBoolean',
      dictDisplay: 'tag'
    },
    { key: 'businessLicenseUrl', label: '营业执照', field: 'businessLicenseUrl' },
    { key: 'driverCount', label: '司机数量', value: () => relationStats.value.driverCount },
    { key: 'vehicleCount', label: '车辆数量', value: () => relationStats.value.vehicleCount },
    { key: 'remark', label: '备注信息', field: 'remark', span: 4 }
  ]
  const contactItems: ArtDescriptionItem<Partial<Carrier>>[] = [
    { key: 'contactName', label: '姓名', field: 'contactName' },
    { key: 'contactPhone', label: '手机号码', field: 'contactPhone', copyable: true },
    { key: 'contactDepartment', label: '部门', field: 'contactDepartment' },
    { key: 'contactPosition', label: '职位', field: 'contactPosition' },
    { key: 'contactEmail', label: 'E-mail', field: 'contactEmail', copyable: true },
    { key: 'contactQq', label: 'QQ', field: 'contactQq', copyable: true }
  ]
  const financeItems: ArtDescriptionItem<Partial<Carrier>>[] = [
    { key: 'invoiceTitle', label: '发票抬头', field: 'invoiceTitle' },
    { key: 'taxNo', label: '纳税人识别号', field: 'taxNo', copyable: true },
    { key: 'bankName', label: '开户行', field: 'bankName' },
    { key: 'bankAccountName', label: '开户名称', field: 'bankAccountName' },
    { key: 'bankAccount', label: '银行账号', field: 'bankAccount', copyable: true }
  ]
  const contractItems: ArtDescriptionItem<Partial<Carrier>>[] = [
    {
      key: 'signedContract',
      label: '是否签订合同',
      value: (data: Partial<Carrier>) => getBooleanDictValue(data.signedContract),
      dictCode: 'commonBoolean',
      dictDisplay: 'text'
    },
    { key: 'contractAttachmentUrl', label: '合同附件', field: 'contractAttachmentUrl' }
  ]

  const driverColumns: ColumnOption<Driver>[] = [
    { type: 'globalIndex', label: '序号', width: 70 },
    { prop: 'driverName', label: '司机姓名', minWidth: 120 },
    { prop: 'phone', label: '手机号', minWidth: 140 },
    {
      prop: 'gender',
      label: '性别',
      width: 90,
      dict: { code: 'sex', display: 'text' }
    },
    { prop: 'licenseType', label: '驾照类型', width: 100 },
    { prop: 'licenseExpireDate', label: '驾照有效期', minWidth: 120 },
    {
      prop: 'enabled',
      label: '状态',
      width: 90,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.enabled) }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 110,
      fixed: 'right',
      formatter: (row) => <ArtButtonTable type="edit" onClick={() => openDriverManage(row)} />
    }
  ]

  const vehicleColumns: ColumnOption<VehicleArchive>[] = [
    { type: 'globalIndex', label: '序号', width: 70 },
    { prop: 'plateNo', label: '车牌号', minWidth: 130 },
    {
      prop: 'vehicleType',
      label: '车辆类型',
      minWidth: 140,
      dict: { code: 'vehicleType', display: 'text' }
    },
    { prop: 'manufacturer', label: '车辆厂商', minWidth: 140 },
    { prop: 'primaryDriver.driverName', label: '主司机', minWidth: 120 },
    {
      prop: 'operationStatus',
      label: '运营状态',
      minWidth: 120,
      dict: { code: 'vehicleOperationStatus', display: 'text' }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 110,
      fixed: 'right',
      formatter: (row) => <ArtButtonTable type="edit" onClick={() => openVehicleManage(row)} />
    }
  ]

  onMounted(() => {
    void loadPage()
  })

  const loadPage = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) {
      page.error = new Error('缺少承运商标识')
      return
    }

    page.loading = true
    page.error = null
    try {
      const { data } = await fetchCarrierDetail(id)
      detail.data = data ?? undefined

      await Promise.all([loadDrivers(id), loadVehicles(id)])
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('承运商详情加载失败')
    } finally {
      page.loading = false
    }
  }

  const loadDrivers = async (carrierId: string): Promise<void> => {
    relationData.loadingDrivers = true
    try {
      const { data } = await fetchDriverListByCarrierId(carrierId)
      relationData.drivers = data ?? []
    } finally {
      relationData.loadingDrivers = false
    }
  }

  const loadVehicles = async (carrierId: string): Promise<void> => {
    relationData.loadingVehicles = true
    try {
      const { data } = await fetchVehicleArchiveList({
        carrierId,
        from: 0,
        to: 999
      })
      relationData.vehicles = data ?? []
    } finally {
      relationData.loadingVehicles = false
    }
  }

  const goBack = (): void => {
    void router.push('/tms-transportation/basic-data/carrier')
  }

  const openPerformanceAdvisor = (): void => {
    const carrierId = detail.data?.id
    if (!carrierId) return
    void performanceAdvisorRef.value?.handleOpen(carrierId)
  }

  const goDriverManage = (): void => {
    const carrierId = detail.data?.id
    void router.push({
      path: '/tms-transportation/basic-data/driver',
      query: carrierId ? { carrierId } : undefined
    })
  }

  const goVehicleManage = (): void => {
    const carrierId = detail.data?.id
    void router.push({
      path: '/vehicle-manage-system/archive-manage/vehicle-archive-manage',
      query: carrierId ? { carrierId } : undefined
    })
  }

  const openDriverManage = (row: Driver): void => {
    if (!row.id) {
      goDriverManage()
      return
    }
    void router.push({
      path: '/tms-transportation/basic-data/driver',
      query: {
        carrierId: detail.data?.id,
        driverId: row.id
      }
    })
  }

  const openVehicleManage = (row: VehicleArchive): void => {
    if (!row.id) {
      goVehicleManage()
      return
    }
    void router.push({
      path: `/vehicle-manage-system/archive-manage/vehicle-archive-edit/${row.id}`,
      query: { source: 'carrier-detail' }
    })
  }

  const formatAddress = (row?: Partial<Carrier>): string => {
    if (!row) return '--'
    return [row.region, row.addressDetail].filter(Boolean).join(' ') || '--'
  }

  const getBooleanDictValue = (value?: boolean | null): string | undefined => {
    if (isNil(value)) return undefined
    return String(value)
  }
</script>

<style scoped lang="scss">
  .carrier-detail {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

    &__content {
      display: flex;
      flex-direction: column;
      gap: 12px;
      margin-top: 12px;
    }

    &__section {
      padding: 20px;
    }

    &__section-header {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;
    }

    &__image {
      width: 72px;
      height: 72px;
      border-radius: var(--art-control-radius);
    }

    &__link-value {
      padding: 0;
      font-weight: 600;
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 132px;
      font-weight: 600;
    }

    @media (width <= 768px) {
      &__section-header {
        flex-direction: column;
        align-items: flex-start;
      }
    }
  }
</style>
