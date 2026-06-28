<template>
  <div class="contract-detail" v-loading="page.loading">
    <div class="contract-detail__header art-card-xs">
      <div>
        <h2>{{ detail.data?.contractName || '合同详情' }}</h2>
        <p>{{ detail.data?.contractNo || '--' }}</p>
      </div>
      <div class="contract-detail__actions">
        <ElButton @click="goBack">返回</ElButton>
      </div>
    </div>

    <div class="contract-detail__content">
      <section class="contract-detail__section art-card-xs">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ElDescriptions :column="4" border>
          <ElDescriptionsItem label="合同状态">
            <ElTag
              v-if="detail.data?.contractStatus"
              :type="statusMeta[detail.data.contractStatus].type"
            >
              {{ statusMeta[detail.data.contractStatus].label }}
            </ElTag>
            <span v-else>--</span>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="合同编号">
            {{ formatValue(detail.data?.contractNo) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="合同名称" :span="2">
            {{ formatValue(detail.data?.contractName) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="承运商名称">
            {{ formatValue(detail.data?.carrier?.companyName) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="联系人姓名">
            {{ formatValue(detail.data?.contactName) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="运单号">
            {{ formatValue(detail.data?.waybillNo) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="计费方式">
            <ArtDictDisplay
              dict-code="tmsContractBillingMethod"
              :value="detail.data?.billingMethod"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="合同金额">
            {{ formatMoney(detail.data?.contractAmount) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="签订时间">
            {{ formatDateTime(detail.data?.signTime) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="经办人">
            {{ formatValue(detail.data?.handler) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="合同说明" :span="4">
            {{ formatValue(detail.data?.contractDescription) }}
          </ElDescriptionsItem>
        </ElDescriptions>
      </section>

      <section class="contract-detail__section art-card-xs">
        <ArtSectionTitle>合同附件</ArtSectionTitle>
        <div v-if="attachments.length" class="contract-detail__attachments">
          <ElButton
            v-for="attachment in attachments"
            :key="`${attachment.url}-${attachment.name}`"
            link
            type="primary"
            @click="downloadAttachment(attachment)"
          >
            {{ attachment.name }}
          </ElButton>
        </div>
        <span v-else>--</span>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { isNil } from 'lodash-es'
  import { ElButton, ElDescriptions, ElDescriptionsItem, ElTag } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchContractDetail } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'
  import { downloadAttachment } from '@/utils/file'

  defineOptions({ name: 'TmsContractDetail' })

  type Contract = Api.Tms.BasicData.Contract
  type ContractStatus = Api.Tms.BasicData.ContractStatus
  type StatusTagType = 'success' | 'warning' | 'danger' | 'info'

  interface PageState {
    loading: boolean
  }

  interface DetailState {
    data?: Contract
  }

  const route = useRoute()
  const router = useRouter()

  const page = reactive<PageState>({ loading: false })
  const detail = reactive<DetailState>({ data: undefined })

  const statusMeta: Record<ContractStatus, { label: string; type: StatusTagType }> = {
    draft: { label: '草稿', type: 'info' },
    pending: { label: '待审核', type: 'warning' },
    approved: { label: '已审核', type: 'success' },
    rejected: { label: '已驳回', type: 'danger' },
    terminated: { label: '已终止', type: 'info' }
  }

  const attachments = computed(() => detail.data?.attachments ?? [])

  onMounted(() => {
    void loadPage()
  })

  const loadPage = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) return

    page.loading = true
    try {
      const { data } = await fetchContractDetail(id)
      detail.data = data ?? undefined
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/tms-transportation/basic-data/contract')
  }

  const formatValue = (value?: string | number | null): string => {
    if (isNil(value) || value === '') return '--'
    return String(value)
  }

  const formatMoney = (value?: number | null): string => {
    if (isNil(value) || Number.isNaN(Number(value))) return '--'
    return Number(value).toFixed(2)
  }

  const formatDateTime = (value?: string): string => {
    if (!value) return '--'
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') ?? '--'
  }
</script>

<style scoped lang="scss">
  .contract-detail {
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

    &__attachments {
      display: flex;
      flex-wrap: wrap;
      gap: 10px 16px;
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
    }
  }
</style>
