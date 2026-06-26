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
            <span class="carrier-detail__link-value">{{ detail.data?.driverCount ?? 0 }}</span>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="车辆数量">
            <span class="carrier-detail__link-value">{{ detail.data?.vehicleCount ?? 0 }}</span>
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
    </div>
  </div>
</template>

<script setup lang="ts">
  import { isNil } from 'lodash-es'
  import { ElButton, ElDescriptions, ElDescriptionsItem, ElImage } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchCarrierDetail } from '@/api/tms'

  defineOptions({ name: 'TmsCarrierDetail' })

  type Carrier = Api.Tms.BasicData.Carrier

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false })
  const detail = reactive<{ data?: Carrier }>({ data: undefined })

  onMounted(() => {
    void loadDetail()
  })

  const loadDetail = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) return
    page.loading = true
    try {
      const { data } = await fetchCarrierDetail(id)
      detail.data = data ?? undefined
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/tms-transportation/basic-data/carrier')
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

    &__image {
      width: 72px;
      height: 72px;
      border-radius: 6px;
    }

    &__link-value {
      color: var(--el-color-primary);
    }

    :deep(.el-descriptions__label) {
      width: 132px;
      font-weight: 600;
    }

    @media (max-width: 768px) {
      &__header {
        align-items: flex-start;
        flex-direction: column;
        gap: 14px;
      }
    }
  }
</style>
