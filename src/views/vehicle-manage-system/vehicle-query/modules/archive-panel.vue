<template>
  <div class="vehicle-query-archive-panel">
    <ElTabs v-model="panel.activeTab">
      <ElTabPane label="基础信息" name="basic">
        <VehicleQuerySection title="基础信息">
          <VehicleQueryInfoGrid :items="basicItems" />
        </VehicleQuerySection>
        <VehicleQuerySection title="车辆证件" class="vehicle-query-archive-panel__certificates">
          <div class="vehicle-query-archive-panel__images">
            <div
              v-for="item in certificateItems"
              :key="item.key"
              class="vehicle-query-archive-panel__image-item"
            >
              <ElImage
                v-if="vehicle[item.key]"
                :src="vehicle[item.key]"
                fit="cover"
                :preview-src-list="[vehicle[item.key] || '']"
              />
              <div v-else class="vehicle-query-archive-panel__image-empty">--</div>
              <span>{{ item.label }}</span>
            </div>
          </div>
        </VehicleQuerySection>
      </ElTabPane>
      <ElTabPane label="车身参数" name="body">
        <VehicleQuerySection title="车身参数">
          <VehicleQueryInfoGrid :items="bodyItems" />
        </VehicleQuerySection>
      </ElTabPane>
      <ElTabPane label="发动机参数" name="engine">
        <VehicleQuerySection title="发动机参数">
          <VehicleQueryInfoGrid :items="engineItems" />
        </VehicleQuerySection>
      </ElTabPane>
      <ElTabPane label="其他信息" name="other">
        <VehicleQuerySection title="其他信息">
          <VehicleQueryInfoGrid :items="otherItems" />
        </VehicleQuerySection>
      </ElTabPane>
    </ElTabs>
  </div>
</template>

<script setup lang="ts">
  import { ElImage, ElTabPane, ElTabs } from 'element-plus'
  import VehicleQueryInfoGrid from './vehicle-query-info-grid.vue'
  import VehicleQuerySection from './vehicle-query-section.vue'
  import type { InfoItem, VehicleArchive } from './types'
  import { formatBoolean } from './query-format'

  defineOptions({ name: 'VehicleQueryArchivePanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  type ImageKey =
    | 'vehiclePhotoUrl'
    | 'drivingLicenseFrontUrl'
    | 'drivingLicenseBackUrl'
    | 'operationLicenseUrl'

  const panel = reactive({
    activeTab: 'basic'
  })

  const certificateItems: Array<{ key: ImageKey; label: string }> = [
    { key: 'vehiclePhotoUrl', label: '车辆照片' },
    { key: 'drivingLicenseFrontUrl', label: '行驶证正页' },
    { key: 'drivingLicenseBackUrl', label: '行驶证副页' },
    { key: 'operationLicenseUrl', label: '运营证照片' }
  ]

  const basicItems = computed<InfoItem[]>(() => [
    { label: '车牌号', value: props.vehicle.plateNo },
    { label: '所属公司', value: props.vehicle.companyName },
    { label: '自编号', value: props.vehicle.selfNo },
    { label: '车型', value: props.vehicle.vehicleType, dictCode: 'vehicleType' },
    { label: '国产/进口', value: props.vehicle.originType, dictCode: 'vehicleOriginType' },
    { label: '车架号（VIN）', value: props.vehicle.vin },
    { label: '车辆厂商', value: props.vehicle.manufacturer },
    { label: '厂牌型号', value: props.vehicle.brandModel },
    { label: '营运证号', value: props.vehicle.operationCertNo },
    { label: '购置证号', value: props.vehicle.purchaseCertNo },
    { label: '登记证号', value: props.vehicle.registrationCertNo },
    { label: '车身颜色', value: props.vehicle.vehicleColor, dictCode: 'vehicleColor' },
    { label: '底盘号', value: props.vehicle.chassisNo },
    { label: '空调号码', value: props.vehicle.acCode },
    { label: '波箱系列号', value: props.vehicle.gearboxSerialNo },
    { label: '登记日期', value: props.vehicle.registerDate },
    { label: '发证日期', value: props.vehicle.issueDate },
    { label: '购入开票日期', value: props.vehicle.invoiceDate },
    { label: '启用日期', value: props.vehicle.startUseDate },
    { label: '使用年限', value: props.vehicle.serviceYears, suffix: '年' },
    { label: '核定乘员数（人）', value: props.vehicle.approvedPassengerCount },
    { label: '座位数', value: props.vehicle.seatCount },
    { label: '业务类型', value: props.vehicle.businessType, dictCode: 'vehicleBusinessType' },
    { label: '是否空调车', value: formatBoolean(props.vehicle.isAirConditioned) },
    { label: '营运状态', value: props.vehicle.operationStatus, dictCode: 'vehicleOperationStatus' },
    { label: '营运状态变更', value: props.vehicle.operationStatusChangeDate },
    { label: '购置状态', value: props.vehicle.purchaseStatus, dictCode: 'vehiclePurchaseStatus' },
    { label: '购置状态变更', value: props.vehicle.purchaseStatusChangeDate },
    { label: '例检启用日期', value: props.vehicle.inspectionStartDate },
    { label: '车辆等级', value: props.vehicle.vehicleLevel, dictCode: 'vehicleLevel' },
    { label: '是否新能源车', value: formatBoolean(props.vehicle.isNewEnergy) },
    { label: '整车三包里程', value: props.vehicle.threeGuaranteeMileage, suffix: '公里' },
    { label: '整车三包时长', value: props.vehicle.threeGuaranteeDuration, suffix: '个月' },
    { label: '整车包修里程', value: props.vehicle.warrantyMileage, suffix: '公里' },
    { label: '整车包修时长', value: props.vehicle.warrantyDuration, suffix: '个月' },
    { label: '备注', value: props.vehicle.remark }
  ])

  const bodyItems = computed<InfoItem[]>(() => [
    { label: '满载总质量', value: props.vehicle.grossMass, suffix: 'kg' },
    { label: '整备质量', value: props.vehicle.curbWeight, suffix: 'kg' },
    { label: '核定载质量', value: props.vehicle.approvedLoadMass, suffix: 'kg' },
    { label: '外廓长度', value: props.vehicle.overallLength, suffix: 'mm' },
    { label: '外廓宽度', value: props.vehicle.overallWidth, suffix: 'mm' },
    { label: '外廓高度', value: props.vehicle.overallHeight, suffix: 'mm' },
    { label: '标台', value: props.vehicle.platform },
    { label: '前轮距', value: props.vehicle.frontTrack, suffix: 'mm' },
    { label: '后轮距', value: props.vehicle.rearTrack, suffix: 'mm' },
    { label: '轴距', value: props.vehicle.wheelbase },
    { label: '车轴数', value: props.vehicle.axleCount },
    { label: '轮胎数', value: props.vehicle.tireCount },
    { label: '钢板弹簧数', value: props.vehicle.leafSpringCount, suffix: '片' },
    { label: '是否双层', value: formatBoolean(props.vehicle.isDoubleDeck) }
  ])

  const engineItems = computed<InfoItem[]>(() => [
    { label: '发动机号', value: props.vehicle.engineNo },
    { label: '发动机型号', value: props.vehicle.engineModel },
    { label: '燃油类型', value: props.vehicle.fuelType, dictCode: 'vehicleFuelType' },
    { label: '发动机排量', value: props.vehicle.displacement, suffix: 'L' },
    {
      label: '排放标准',
      value: props.vehicle.emissionStandard,
      dictCode: 'vehicleEmissionStandard'
    },
    { label: '发动机功率', value: props.vehicle.enginePower, suffix: 'KW' },
    { label: '额定扭矩转速', value: props.vehicle.ratedTorqueSpeed, suffix: 'r/min' },
    { label: '发动机扭矩', value: props.vehicle.engineTorque, suffix: 'N-M' }
  ])

  const otherItems = computed<InfoItem[]>(() => [
    { label: '车牌颜色', value: props.vehicle.plateColor, dictCode: 'vehicleColor' },
    {
      label: '运输行业',
      value: props.vehicle.transportIndustry,
      dictCode: 'vehicleTransportIndustry'
    },
    { label: '营运类型', value: props.vehicle.operationType, dictCode: 'vehicleOperationType' },
    { label: '业户ID', value: props.vehicle.ownerId },
    { label: '业户名称', value: props.vehicle.ownerName },
    { label: '业户联系电话', value: props.vehicle.ownerPhone },
    { label: '车载终端电话', value: props.vehicle.terminalPhone },
    { label: '车主性别', value: props.vehicle.ownerGender, dictCode: 'sex' },
    { label: '身份证号码', value: props.vehicle.idCardNo },
    { label: '通讯地址', value: props.vehicle.mailingAddress },
    { label: '吨位/座位', value: props.vehicle.tonnageOrSeat },
    { label: '主司机姓名', value: props.vehicle.primaryDriver?.driverName },
    { label: '主司机电话', value: props.vehicle.primaryDriver?.phone },
    { label: '辅司机姓名', value: props.vehicle.secondaryDriver?.driverName },
    { label: '辅司机电话', value: props.vehicle.secondaryDriver?.phone },
    { label: '营运线路', value: props.vehicle.operationRoute },
    { label: '车籍地代码', value: props.vehicle.licensePlateCode },
    { label: '服务开始时间', value: props.vehicle.serviceStartTime },
    { label: '服务结束时间', value: props.vehicle.serviceEndTime },
    { label: '支持拍照', value: formatBoolean(props.vehicle.supportPhoto) }
  ])
</script>

<style scoped lang="scss">
  .vehicle-query-archive-panel {
    :deep(.el-tabs__content) {
      padding-top: 8px;
    }

    &__certificates {
      margin-top: 32px;
    }

    &__images {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
      gap: 20px;
      max-width: 860px;
      padding: 20px;
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__image-item {
      display: flex;
      flex-direction: column;
      gap: 10px;
      align-items: center;

      :deep(.el-image),
      .vehicle-query-archive-panel__image-empty {
        width: 140px;
        height: 110px;
        border: 1px solid var(--el-border-color);
      }

      span {
        font-weight: 600;
        color: var(--el-text-color-secondary);
      }
    }

    &__image-empty {
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--el-text-color-placeholder);
      background: var(--el-fill-color-light);
    }
  }
</style>
