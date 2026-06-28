<template>
  <div class="carrier-detail" v-loading="page.loading">
    <div class="carrier-detail__header art-card-xs">
      <div>
        <h2>{{ detail.data?.companyName || '承运商详情' }}</h2>
        <p>{{ detail.data?.carrierCode || '--' }}</p>
      </div>
      <div class="carrier-detail__actions">
        <ElButton @click="goBack">返回</ElButton>
      </div>
    </div>

    <div class="carrier-detail__content">
      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ElDescriptions :column="4" border>
          <ElDescriptionsItem label="承运商编码">{{
            formatValue(detail.data?.carrierCode)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="公司名称">{{
            formatValue(detail.data?.companyName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="承运商类型">
            <ArtDictDisplay
              dict-code="tmsCarrierType"
              :value="detail.data?.carrierType"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="营业执照号码">{{
            formatValue(detail.data?.businessLicenseNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="税务登记号码">{{
            formatValue(detail.data?.taxRegistrationNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="法人代表">{{
            formatValue(detail.data?.legalRepresentative)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="公司地址">{{ formatAddress(detail.data) }}</ElDescriptionsItem>
          <ElDescriptionsItem label="邮编">{{
            formatValue(detail.data?.postalCode)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="承运商状态">
            <ArtDictDisplay
              dict-code="commonBoolean"
              :value="getBooleanDictValue(detail.data?.enabled)"
              display="tag"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="营业执照">
            <ElImage
              v-if="detail.data?.businessLicenseUrl"
              class="carrier-detail__image"
              :src="detail.data.businessLicenseUrl"
              :preview-src-list="[detail.data.businessLicenseUrl]"
              fit="cover"
              preview-teleported
            />
            <span v-else>--</span>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="司机数量">
            <span class="carrier-detail__link-value">{{ relationStats.driverCount }}</span>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="车辆数量">
            <span class="carrier-detail__link-value">{{ relationStats.vehicleCount }}</span>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="备注信息" :span="4">{{
            formatValue(detail.data?.remark)
          }}</ElDescriptionsItem>
        </ElDescriptions>
      </section>

      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>联系人信息</ArtSectionTitle>
        <ElDescriptions :column="4" border>
          <ElDescriptionsItem label="姓名">{{
            formatValue(detail.data?.contactName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="手机号码">{{
            formatValue(detail.data?.contactPhone)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="部门">{{
            formatValue(detail.data?.contactDepartment)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="职位">{{
            formatValue(detail.data?.contactPosition)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="E-mail">{{
            formatValue(detail.data?.contactEmail)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="QQ">{{
            formatValue(detail.data?.contactQq)
          }}</ElDescriptionsItem>
        </ElDescriptions>
      </section>

      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>财务信息</ArtSectionTitle>
        <ElDescriptions :column="4" border>
          <ElDescriptionsItem label="发票抬头">{{
            formatValue(detail.data?.invoiceTitle)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="纳税人识别号">{{
            formatValue(detail.data?.taxNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="开户行">{{
            formatValue(detail.data?.bankName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="开户名称">{{
            formatValue(detail.data?.bankAccountName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="银行账号">{{
            formatValue(detail.data?.bankAccount)
          }}</ElDescriptionsItem>
        </ElDescriptions>
      </section>

      <section class="carrier-detail__section art-card-xs">
        <ArtSectionTitle>合同信息</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="是否签订合同">
            <ArtDictDisplay
              dict-code="commonBoolean"
              :value="getBooleanDictValue(detail.data?.signedContract)"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="合同附件">
            <ElImage
              v-if="detail.data?.contractAttachmentUrl"
              class="carrier-detail__image"
              :src="detail.data.contractAttachmentUrl"
              :preview-src-list="[detail.data.contractAttachmentUrl]"
              fit="cover"
              preview-teleported
            />
            <span v-else>--</span>
          </ElDescriptionsItem>
        </ElDescriptions>
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
  </div>
</template>

<script setup lang="tsx">
  import { isNil } from 'lodash-es'
  import { ElButton, ElDescriptions, ElDescriptionsItem, ElImage } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import VehicleQueryTable from '@/views/vehicle-manage-system/vehicle-query/modules/vehicle-query-table.vue'
  import { fetchCarrierDetail, fetchDriverListByCarrierId } from '@/api/tms'
  import { fetchVehicleArchiveList } from '@/api/vehicle-manage-system'
  import type { ColumnOption } from '@/types'

  defineOptions({ name: 'TmsCarrierDetail' })

  type Carrier = Api.Tms.BasicData.Carrier
  type Driver = Api.Tms.BasicData.Driver
  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive

  interface PageState {
    loading: boolean
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

  const route = useRoute()
  const router = useRouter()

  const page = reactive<PageState>({ loading: false })
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
    if (!id) return

    page.loading = true
    try {
      const { data } = await fetchCarrierDetail(id)
      detail.data = data ?? undefined

      await Promise.all([loadDrivers(id), loadVehicles(id)])
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

  const formatValue = (value?: string | number | null): string => {
    if (isNil(value) || value === '') return '--'
    return String(value)
  }

  const formatAddress = (row?: Carrier): string => {
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

    &__header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 18px 20px;

      h2 {
        margin: 0;
        font-size: 20px;
        font-weight: 600;
      }

      p {
        margin: 6px 0 0;
        color: var(--el-text-color-secondary);
      }
    }

    &__actions {
      display: flex;
      gap: 10px;
      align-items: center;
    }

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
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 12px;
    }

    &__image {
      width: 72px;
      height: 72px;
      border-radius: 6px;
    }

    &__link-value {
      color: var(--el-color-primary);
      font-weight: 600;
    }

    :deep(.el-descriptions__label) {
      width: 132px;
      font-weight: 600;
    }

    @media (max-width: 768px) {
      &__header {
        flex-direction: column;
        align-items: flex-start;
        gap: 14px;
      }

      &__section-header {
        flex-direction: column;
        align-items: flex-start;
      }
    }
  }
</style>
