<template>
  <ArtDrawer ref="drawerRef">
    <div class="recognition-runner">
      <div class="recognition-runner__switcher" role="tablist" aria-label="识别类型">
        <button
          v-for="item in recognitionCapabilities"
          :key="item.feature"
          type="button"
          :class="{ 'is-active': feature === item.feature }"
          @click="selectFeature(item.feature)"
        >
          <ArtSvgIcon :icon="item.icon" />
          <span
            ><strong>{{ item.title }}</strong
            ><small>{{ item.businessLabel }}</small></span
          >
        </button>
      </div>

      <div v-if="feature === 'invoice_ocr'" class="recognition-runner__panel">
        <div class="recognition-runner__direction">
          <span>发票方向</span>
          <ElSegmented v-model="invoiceDirection" :options="invoiceDirections" />
        </div>
        <InvoiceOcrPanel
          ref="invoicePanelRef"
          v-model="invoiceImages"
          :direction="invoiceDirection"
          apply-label="进入待复核"
          @apply="handleCreated"
        />
      </div>

      <div v-else-if="feature === 'cash_voucher_ocr'" class="recognition-runner__panel">
        <div class="recognition-runner__direction">
          <span>资金方向</span>
          <ElSegmented v-model="cashDirection" :options="cashDirections" />
        </div>
        <CashVoucherOcrPanel
          v-if="cashDirection === 'receipt'"
          ref="cashPanelRef"
          v-model="cashImages"
          :direction="cashDirection"
          apply-label="进入待复核"
          @apply="handleCreated"
        />
        <div v-else class="recognition-runner__context">
          <span><ArtSvgIcon icon="ri:secure-payment-line" /></span>
          <div>
            <small>需绑定已审批付款申请</small>
            <h3>付款凭证从付款执行环节识别</h3>
            <p
              >为避免绕过付款审批和额度锁定，请先进入付款申请，待审批通过后在“执行付款”中上传凭证。</p
            >
            <ElButton type="primary" @click="goPaymentApplication">
              前往付款申请<ArtSvgIcon icon="ri:arrow-right-line" />
            </ElButton>
          </div>
        </div>
      </div>

      <div v-else-if="feature === 'waybill_receipt_ocr'" class="recognition-runner__context">
        <span><ArtSvgIcon icon="ri:route-line" /></span>
        <div>
          <small>需绑定运单上下文</small>
          <h3>回单识别从配送任务发起</h3>
          <p>
            签收时间、实收数量和货损判断必须与具体运单比对。请先进入配送管理选择运单，再上传回单。
          </p>
          <ElButton type="primary" @click="goDelivery">
            前往配送管理<ArtSvgIcon icon="ri:arrow-right-line" />
          </ElButton>
        </div>
      </div>

      <div v-else class="recognition-runner__context">
        <span><ArtSvgIcon icon="ri:gas-station-line" /></span>
        <div>
          <small>需绑定运单或在途车辆</small>
          <h3>在途票据从费用申报单识别</h3>
          <p>进入在途费用后选择运单并上传票据，识别结果会自动回填金额、日期、服务商和票据信息。</p>
          <ElButton type="primary" @click="goInTransitExpense">
            前往在途费用<ArtSvgIcon icon="ri:arrow-right-line" />
          </ElButton>
        </div>
      </div>
    </div>

    <template #footer="{ api }"><ElButton @click="api.handleClose()">关闭</ElButton></template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import InvoiceOcrPanel from '@/views/tms-transportation/finance-center/invoice-management/modules/invoice-ocr-panel.vue'
  import CashVoucherOcrPanel from '@/views/tms-transportation/finance-center/cash-transaction/modules/cash-voucher-ocr-panel.vue'
  import { recognitionCapabilities, type RecognitionFeature } from './recognition-config'

  defineOptions({ name: 'RecognitionWorkbenchDrawer' })

  interface ResetExpose {
    reset: () => void
  }
  type AnalyzeResult =
    Api.Tms.Finance.InvoiceOcrAnalyzeResponse | Api.Tms.Finance.CashVoucherOcrAnalyzeResponse

  const emit = defineEmits<{ created: [artifactId: string] }>()
  const router = useRouter()
  const drawerRef = ref<ArtDrawerExpose<RecognitionFeature>>()
  const invoicePanelRef = ref<ResetExpose>()
  const cashPanelRef = ref<ResetExpose>()
  const feature = ref<RecognitionFeature>('invoice_ocr')
  const invoiceImages = ref<string[]>([])
  const cashImages = ref<string[]>([])
  const invoiceDirection = ref<Api.Tms.Finance.InvoiceDirection>('output')
  const cashDirection = ref<Api.Tms.Finance.CashDirection>('receipt')
  const invoiceDirections = [
    { label: '销项发票', value: 'output' },
    { label: '进项发票', value: 'input' }
  ]
  const cashDirections = [
    { label: '客户收款', value: 'receipt' },
    { label: '承运商付款', value: 'payment' }
  ]

  function selectFeature(value: RecognitionFeature): void {
    feature.value = value
  }

  function handleCreated(result: AnalyzeResult): void {
    emit('created', result.artifactId)
    void drawerRef.value?.handleClose()
  }

  function goDelivery(): void {
    void drawerRef.value?.handleClose()
    void router.push('/tms-transportation/delivery-management')
  }

  function goPaymentApplication(): void {
    void drawerRef.value?.handleClose()
    void router.push('/tms-transportation/finance-center/payment-application')
  }

  function goInTransitExpense(): void {
    void drawerRef.value?.handleClose()
    void router.push('/tms-transportation/finance-center/in-transit-expense')
  }

  async function handleOpen(initialFeature: RecognitionFeature = 'invoice_ocr'): Promise<void> {
    feature.value = initialFeature
    await drawerRef.value?.handleOpen(initialFeature, {
      title: '发起智能识别',
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      showConfirmButton: false,
      onReset: () => {
        invoiceImages.value = []
        cashImages.value = []
        invoicePanelRef.value?.reset()
        cashPanelRef.value?.reset()
      },
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .recognition-runner {
    &__switcher {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 9px;
      margin-bottom: 16px;

      button {
        display: flex;
        gap: 9px;
        align-items: center;
        min-width: 0;
        padding: 12px;
        text-align: left;
        cursor: pointer;
        background: var(--art-main-bg-color);
        border: 1px solid var(--art-card-border);
        border-radius: var(--custom-radius);
        transition: 0.18s ease;

        > svg {
          flex: 0 0 auto;
          font-size: 19px;
          color: var(--art-text-gray-500);
        }

        span,
        strong,
        small {
          display: block;
          min-width: 0;
        }

        strong {
          color: var(--art-text-gray-800);
        }

        small {
          margin-top: 2px;
          font-size: 10px;
          color: var(--art-text-gray-400);
        }

        &:hover,
        &.is-active {
          border-color: color-mix(in srgb, var(--theme-color) 55%, transparent);

          > svg,
          strong {
            color: var(--theme-color);
          }
        }

        &.is-active {
          background: color-mix(in srgb, var(--theme-color) 6%, transparent);
        }
      }
    }

    &__direction {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: flex-end;
      padding: 10px 12px;
      margin-bottom: 10px;
      font-size: 12px;
      color: var(--art-text-gray-600);
      background: var(--art-gray-50);
      border-radius: var(--el-border-radius-base);
    }

    &__panel :deep(.art-card-xs) {
      margin-bottom: 0;
    }

    &__context {
      display: flex;
      gap: 18px;
      align-items: flex-start;
      padding: 28px;
      background: var(--art-gray-50);
      border: 1px solid var(--art-card-border);
      border-radius: var(--custom-radius);

      > span {
        display: grid;
        flex: 0 0 54px;
        place-items: center;
        width: 54px;
        height: 54px;
        font-size: 26px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 10%, transparent);
        border-radius: var(--custom-radius);
      }

      small {
        font-weight: 600;
        color: var(--theme-color);
      }

      h3 {
        margin: 5px 0 7px;
        color: var(--art-text-gray-900);
      }

      p {
        max-width: 600px;
        margin: 0 0 18px;
        font-size: 13px;
        line-height: 1.7;
        color: var(--art-text-gray-500);
      }
    }
  }

  :global([data-box-mode='shadow-mode']) .recognition-runner__switcher button:hover,
  :global([data-box-mode='shadow-mode']) .recognition-runner__switcher button:focus-visible,
  :global([data-box-mode='shadow-mode']) .recognition-runner__switcher button.is-active {
    box-shadow: 0 6px 18px color-mix(in srgb, var(--theme-color) 9%, transparent);
  }

  @media (width <= 720px) {
    .recognition-runner {
      &__switcher {
        grid-template-columns: 1fr;
      }

      &__direction {
        flex-direction: column;
        align-items: stretch;
      }

      &__context {
        padding: 18px;
      }
    }
  }
</style>
