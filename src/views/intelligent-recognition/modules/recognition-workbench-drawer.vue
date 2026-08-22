<template>
  <ArtDrawer ref="drawerRef">
    <div class="recognition-runner">
      <div class="recognition-runner__layout">
        <aside class="recognition-runner__sidebar art-card-xs" aria-label="识别场景导航">
          <header class="recognition-runner__sidebar-head">
            <span>RECOGNITION SCENES</span>
            <h3>选择识别场景</h3>
            <p>系统会按业务类型匹配识别与复核流程。</p>
          </header>

          <div class="recognition-runner__switcher" role="group" aria-label="识别类型">
            <button
              v-for="item in recognitionCapabilities"
              :key="item.feature"
              type="button"
              :class="{ 'is-active': feature === item.feature }"
              :aria-pressed="feature === item.feature"
              aria-controls="recognition-current-workspace"
              @click="selectFeature(item.feature)"
            >
              <span class="recognition-runner__scene-icon">
                <ArtSvgIcon :icon="item.icon" />
              </span>
              <span class="recognition-runner__scene-copy">
                <strong>{{ item.title }}</strong>
                <small>{{ getScenarioStatus(item.feature) }}</small>
              </span>
              <ArtSvgIcon
                :icon="feature === item.feature ? 'ri:check-line' : 'ri:arrow-right-s-line'"
                class="recognition-runner__scene-state"
              />
            </button>
          </div>

          <div class="recognition-runner__governance">
            <ArtSvgIcon icon="ri:shield-check-line" />
            <div>
              <strong>人工复核后生效</strong>
              <span>AI 只生成识别建议，不直接写入正式业务数据。</span>
            </div>
          </div>
        </aside>

        <main id="recognition-current-workspace" class="recognition-runner__workspace">
          <section class="recognition-runner__workspace-head art-card-xs">
            <span class="recognition-runner__workspace-icon">
              <ArtSvgIcon :icon="currentCapability.icon" />
            </span>
            <div class="recognition-runner__workspace-copy">
              <span>当前识别场景</span>
              <h2>{{ currentCapability.title }}</h2>
              <p>{{ currentCapability.description }}</p>
            </div>
            <div class="recognition-runner__workspace-meta">
              <ElTag :type="currentStatusType" effect="plain" round>
                {{ currentStatusLabel }}
              </ElTag>
              <small>{{ currentCapability.businessLabel }}</small>
            </div>

            <div v-if="feature === 'invoice_ocr'" class="recognition-runner__direction">
              <span>发票方向</span>
              <ElSegmented v-model="invoiceDirection" :options="invoiceDirections" />
            </div>
            <div v-else-if="feature === 'cash_voucher_ocr'" class="recognition-runner__direction">
              <span>资金方向</span>
              <ElSegmented v-model="cashDirection" :options="cashDirections" />
            </div>
          </section>

          <InvoiceOcrPanel
            v-if="feature === 'invoice_ocr'"
            ref="invoicePanelRef"
            v-model="invoiceImages"
            class="recognition-runner__panel"
            :direction="invoiceDirection"
            apply-label="进入待复核"
            @apply="handleCreated"
          />

          <CashVoucherOcrPanel
            v-else-if="feature === 'cash_voucher_ocr' && cashDirection === 'receipt'"
            ref="cashPanelRef"
            v-model="cashImages"
            class="recognition-runner__panel"
            :direction="cashDirection"
            apply-label="进入待复核"
            @apply="handleCreated"
          />

          <section v-else-if="businessContext" class="recognition-runner__context art-card-xs">
            <div class="recognition-runner__context-hero">
              <span><ArtSvgIcon :icon="businessContext.icon" /></span>
              <div>
                <small>{{ businessContext.eyebrow }}</small>
                <h3>{{ businessContext.title }}</h3>
                <p>{{ businessContext.description }}</p>
              </div>
            </div>

            <ol class="recognition-runner__flow" aria-label="标准处理步骤">
              <li v-for="(step, index) in businessContext.steps" :key="step.title">
                <span>{{ index + 1 }}</span>
                <div>
                  <strong>{{ step.title }}</strong>
                  <small>{{ step.description }}</small>
                </div>
              </li>
            </ol>

            <div class="recognition-runner__context-action">
              <div>
                <ArtSvgIcon icon="ri:information-line" />
                <span>{{ businessContext.helper }}</span>
              </div>
              <ElButton type="primary" @click="goBusinessContext">
                {{ businessContext.actionLabel }}
                <ArtSvgIcon icon="ri:arrow-right-line" />
              </ElButton>
            </div>
          </section>
        </main>
      </div>
    </div>

    <template #footer="{ api }">
      <div class="recognition-runner__footer">
        <span>
          <ArtSvgIcon icon="ri:lock-2-line" />
          识别结果受业务权限控制，并保留人工复核记录
        </span>
        <div>
          <ElButton v-if="hasUploadedMaterials" @click="api.handleReset()">清空已上传材料</ElButton>
          <ElButton @click="api.handleClose()">关闭</ElButton>
        </div>
      </div>
    </template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import { financePaths } from '@/router/business-paths'
  import CashVoucherOcrPanel from '@fms/views/cash-transaction/modules/cash-voucher-ocr-panel.vue'
  import InvoiceOcrPanel from '@fms/views/invoice-management/modules/invoice-ocr-panel.vue'
  import {
    getCapability,
    recognitionCapabilities,
    type RecognitionFeature
  } from './recognition-config'

  defineOptions({ name: 'RecognitionWorkbenchDrawer' })

  interface ResetExpose {
    reset: () => void
  }

  interface BusinessContextStep {
    title: string
    description: string
  }

  interface BusinessContext {
    eyebrow: string
    title: string
    description: string
    helper: string
    icon: string
    actionLabel: string
    steps: BusinessContextStep[]
  }

  type AnalyzeResult = Api.Fms.InvoiceOcrAnalyzeResponse | Api.Fms.CashVoucherOcrAnalyzeResponse

  const emit = defineEmits<{ created: [artifactId: string] }>()
  const router = useRouter()
  const drawerRef = ref<ArtDrawerExpose<RecognitionFeature>>()
  const invoicePanelRef = ref<ResetExpose>()
  const cashPanelRef = ref<ResetExpose>()
  const feature = ref<RecognitionFeature>('invoice_ocr')
  const invoiceImages = ref<string[]>([])
  const cashImages = ref<string[]>([])
  const invoiceDirection = ref<Api.Fms.InvoiceDirection>('output')
  const cashDirection = ref<Api.Fms.CashDirection>('receipt')
  const invoiceDirections = [
    { label: '销项发票', value: 'output' },
    { label: '进项发票', value: 'input' }
  ]
  const cashDirections = [
    { label: '客户收款', value: 'receipt' },
    { label: '承运商付款', value: 'payment' }
  ]

  const currentCapability = computed(() => getCapability(feature.value))
  const hasUploadedMaterials = computed(
    () => invoiceImages.value.length > 0 || cashImages.value.length > 0
  )
  const isDirectRecognition = computed(
    () =>
      feature.value === 'invoice_ocr' ||
      (feature.value === 'cash_voucher_ocr' && cashDirection.value === 'receipt')
  )
  const currentStatusLabel = computed(() =>
    isDirectRecognition.value ? '可直接上传' : '需业务上下文'
  )
  const currentStatusType = computed(() => (isDirectRecognition.value ? 'success' : 'warning'))
  const businessContext = computed<BusinessContext | null>(() => {
    if (feature.value === 'waybill_receipt_ocr') {
      return {
        eyebrow: '需绑定运单上下文',
        title: '从配送任务发起回单识别',
        description:
          '签收时间、实收数量与货损判断需要和具体运单逐项比对。选择配送任务后上传回单，系统才可生成可信的复核建议。',
        helper: '原始回单与识别建议会保留为业务证据，确认后才进入正式数据。',
        icon: 'ri:route-line',
        actionLabel: '前往配送管理',
        steps: [
          { title: '选择配送任务', description: '锁定承运商、车辆与货物明细' },
          { title: '上传签收回单', description: '识别签收信息和异常数量' },
          { title: '人工对比确认', description: '复核后写入运单业务记录' }
        ]
      }
    }

    if (feature.value === 'waybill_expense_ocr') {
      return {
        eyebrow: '需绑定具体运单',
        title: '从运单费用发起票据识别',
        description:
          '先关联运单与费用项目，再上传油票、路桥票等费用票据。识别结果会回填到费用草稿，避免形成无法追溯的孤立单据。',
        helper: '系统不会绕过费用归属与审批规则，最终金额仍需业务人员复核。',
        icon: 'ri:gas-station-line',
        actionLabel: '前往运单费用',
        steps: [
          { title: '选择运单与费用项', description: '明确票据的业务归属' },
          { title: '上传费用票据', description: '提取金额、日期与服务商' },
          { title: '校验后提交', description: '确认重复票据和金额异常' }
        ]
      }
    }

    if (feature.value === 'cash_voucher_ocr' && cashDirection.value === 'payment') {
      return {
        eyebrow: '需绑定已审批付款申请',
        title: '从付款执行环节识别付款凭证',
        description:
          '付款凭证必须关联已审批申请、额度与付款账户。请先进入付款申请，再从执行付款环节上传凭证，确保资金链路完整可审计。',
        helper: '仅具备对应业务权限的人员可执行付款，AI 不会扩大当前账号权限。',
        icon: 'ri:secure-payment-line',
        actionLabel: '前往付款申请',
        steps: [
          { title: '选择已审批申请', description: '校验金额、账户与审批状态' },
          { title: '上传付款凭证', description: '提取流水号、日期与金额' },
          { title: '人工复核入账', description: '确认无误后完成资金记录' }
        ]
      }
    }

    return null
  })

  function getScenarioStatus(value: RecognitionFeature): string {
    if (value === 'invoice_ocr') return '直接上传识别'
    if (value === 'cash_voucher_ocr') return '收款直传 · 付款关联'
    return '从业务单据发起'
  }

  function selectFeature(value: RecognitionFeature): void {
    feature.value = value
  }

  function handleCreated(result: AnalyzeResult): void {
    emit('created', result.artifactId)
    void drawerRef.value?.handleClose()
  }

  function goBusinessContext(): void {
    void drawerRef.value?.handleClose()

    if (feature.value === 'waybill_receipt_ocr') {
      void router.push('/tms/delivery-management')
      return
    }

    if (feature.value === 'cash_voucher_ocr') {
      void router.push(financePaths.paymentApplication)
      return
    }

    void router.push(financePaths.waybillCost)
  }

  function resetContent(): void {
    invoiceImages.value = []
    cashImages.value = []
    invoiceDirection.value = 'output'
    cashDirection.value = 'receipt'
    invoicePanelRef.value?.reset()
    cashPanelRef.value?.reset()
  }

  async function handleOpen(initialFeature: RecognitionFeature = 'invoice_ocr'): Promise<void> {
    feature.value = initialFeature
    await drawerRef.value?.handleOpen(initialFeature, {
      title: '发起智能识别',
      subtitle: '选择识别场景，上传业务材料并进入人工复核',
      size: 'xl',
      contentHeight: 'calc(100vh - 148px)',
      showConfirmButton: false,
      showFullscreenButton: true,
      scrollbarAlways: true,
      onReset: resetContent,
      drawerProps: {
        appendToBody: true,
        class: 'recognition-workbench-drawer',
        resizable: true,
        closeOnClickModal: false
      }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .recognition-runner {
    min-height: clamp(520px, calc(100vh - 196px), 760px);
    container-type: inline-size;

    &__layout {
      display: grid;
      grid-template-columns: minmax(210px, 224px) minmax(0, 1fr);
      gap: 12px;
      min-height: inherit;
    }

    &__sidebar,
    &__workspace-head,
    &__context {
      margin-bottom: 0;
    }

    &__sidebar {
      display: flex;
      flex-direction: column;
      padding: 16px;
    }

    &__sidebar-head {
      padding: 2px 3px 15px;

      > span {
        font-size: 9px;
        font-weight: 700;
        color: var(--theme-color);
        letter-spacing: 0.14em;
      }

      h3 {
        margin: 5px 0 4px;
        font-size: 16px;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        font-size: 11px;
        line-height: 1.55;
        color: var(--art-text-gray-500);
      }
    }

    &__switcher {
      display: grid;
      gap: 7px;

      button {
        display: grid;
        grid-template-columns: 36px minmax(0, 1fr) 20px;
        gap: 9px;
        align-items: center;
        min-width: 0;
        min-height: 58px;
        padding: 9px;
        text-align: left;
        cursor: pointer;
        background: transparent;
        border: 1px solid transparent;
        border-radius: var(--el-border-radius-base);
        transition:
          color 0.18s ease,
          background-color 0.18s ease,
          border-color 0.18s ease,
          box-shadow 0.18s ease;

        &:hover {
          background: var(--art-gray-50);
          border-color: var(--art-card-border);
        }

        &.is-active {
          background: color-mix(in srgb, var(--theme-color) 7%, var(--art-main-bg-color));
          border-color: color-mix(in srgb, var(--theme-color) 42%, transparent);
        }

        &:focus-visible {
          outline: 2px solid color-mix(in srgb, var(--theme-color) 64%, transparent);
          outline-offset: 2px;
        }
      }
    }

    &__scene-icon {
      display: grid;
      place-items: center;
      width: 36px;
      height: 36px;
      font-size: 18px;
      color: var(--art-text-gray-500);
      background: var(--art-gray-50);
      border-radius: calc(var(--el-border-radius-base) - 1px);
    }

    &__scene-copy,
    &__scene-copy strong,
    &__scene-copy small {
      display: block;
      min-width: 0;
    }

    &__scene-copy strong {
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 13px;
      color: var(--art-text-gray-800);
      white-space: nowrap;
    }

    &__scene-copy small {
      margin-top: 3px;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 10px;
      color: var(--art-text-gray-400);
      white-space: nowrap;
    }

    &__scene-state {
      justify-self: center;
      font-size: 16px;
      color: var(--art-text-gray-400);
    }

    &__switcher button.is-active &__scene-icon,
    &__switcher button.is-active &__scene-state,
    &__switcher button.is-active &__scene-copy strong {
      color: var(--theme-color);
    }

    &__switcher button.is-active &__scene-icon {
      background: color-mix(in srgb, var(--theme-color) 11%, transparent);
    }

    &__governance {
      display: flex;
      gap: 9px;
      align-items: flex-start;
      padding: 12px;
      margin-top: auto;
      color: var(--art-text-gray-500);
      background: var(--art-gray-50);
      border-radius: var(--el-border-radius-base);

      > svg {
        flex: 0 0 auto;
        margin-top: 1px;
        font-size: 17px;
        color: var(--theme-color);
      }

      strong,
      span {
        display: block;
      }

      strong {
        margin-bottom: 3px;
        font-size: 11px;
        color: var(--art-text-gray-700);
      }

      span {
        font-size: 10px;
        line-height: 1.55;
      }
    }

    &__workspace {
      display: flex;
      flex-direction: column;
      gap: 12px;
      min-width: 0;
    }

    &__workspace-head {
      display: grid;
      grid-template-columns: 44px minmax(0, 1fr) auto;
      gap: 11px 13px;
      align-items: center;
      padding: 15px 16px 12px;
    }

    &__workspace-icon {
      display: grid;
      place-items: center;
      width: 44px;
      height: 44px;
      font-size: 22px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 9%, transparent);
      border-radius: var(--custom-radius);
    }

    &__workspace-copy {
      min-width: 0;

      > span {
        font-size: 10px;
        color: var(--art-text-gray-400);
      }

      h2 {
        margin: 2px 0 3px;
        font-size: 17px;
        line-height: 1.3;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        line-height: 1.5;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }
    }

    &__workspace-meta {
      display: flex;
      flex-direction: column;
      gap: 5px;
      align-items: flex-end;

      small {
        font-size: 10px;
        color: var(--art-text-gray-400);
      }
    }

    &__direction {
      display: flex;
      grid-column: 2 / -1;
      gap: 12px;
      align-items: center;
      justify-content: flex-end;
      padding-top: 10px;
      font-size: 11px;
      color: var(--art-text-gray-500);
      border-top: 1px dashed var(--art-card-border);
    }

    &__panel {
      display: flex;
      flex: 1;
      flex-direction: column;
      min-width: 0;
      min-height: 360px;
      margin-bottom: 0;
    }

    &__context {
      display: flex;
      flex: 1;
      flex-direction: column;
      justify-content: center;
      min-height: 360px;
      padding: 22px;
    }

    &__context-hero {
      display: flex;
      gap: 14px;
      align-items: flex-start;

      > span {
        display: grid;
        flex: 0 0 48px;
        place-items: center;
        width: 48px;
        height: 48px;
        font-size: 23px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 9%, transparent);
        border-radius: var(--custom-radius);
      }

      small {
        font-size: 10px;
        font-weight: 600;
        color: var(--theme-color);
      }

      h3 {
        margin: 4px 0 6px;
        font-size: 17px;
        color: var(--art-text-gray-900);
      }

      p {
        max-width: 620px;
        margin: 0;
        font-size: 12px;
        line-height: 1.7;
        color: var(--art-text-gray-500);
      }
    }

    &__flow {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 10px;
      padding: 0;
      margin: 24px 0;
      list-style: none;

      li {
        display: flex;
        gap: 9px;
        align-items: flex-start;
        min-width: 0;
        padding: 13px;
        background: var(--art-gray-50);
        border-radius: var(--el-border-radius-base);

        > span {
          display: grid;
          flex: 0 0 22px;
          place-items: center;
          width: 22px;
          height: 22px;
          font-size: 10px;
          font-weight: 700;
          color: var(--theme-color);
          background: color-mix(in srgb, var(--theme-color) 10%, transparent);
          border-radius: 50%;
        }

        strong,
        small {
          display: block;
        }

        strong {
          font-size: 11px;
          color: var(--art-text-gray-700);
        }

        small {
          margin-top: 4px;
          font-size: 10px;
          line-height: 1.5;
          color: var(--art-text-gray-400);
        }
      }
    }

    &__context-action {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      padding-top: 15px;
      border-top: 1px solid var(--art-card-border);

      > div {
        display: flex;
        gap: 6px;
        align-items: flex-start;
        max-width: 500px;
        font-size: 10px;
        line-height: 1.55;
        color: var(--art-text-gray-400);

        svg {
          flex: 0 0 auto;
          margin-top: 1px;
          font-size: 14px;
        }
      }
    }

    &__footer {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      width: 100%;

      > span {
        display: flex;
        gap: 6px;
        align-items: center;
        font-size: 11px;
        color: var(--art-text-gray-400);

        svg {
          flex: 0 0 auto;
          font-size: 14px;
        }
      }

      > div {
        display: flex;
      }
    }
  }

  :global(.recognition-workbench-drawer) {
    box-sizing: border-box;
    max-width: 100vw;
  }

  :global([data-box-mode='border-mode']) .recognition-runner__sidebar,
  :global([data-box-mode='border-mode']) .recognition-runner__workspace-head,
  :global([data-box-mode='border-mode']) .recognition-runner__context {
    box-shadow: none;
  }

  :global([data-box-mode='shadow-mode']) .recognition-runner__switcher button:hover,
  :global([data-box-mode='shadow-mode']) .recognition-runner__switcher button:focus-visible,
  :global([data-box-mode='shadow-mode']) .recognition-runner__switcher button.is-active {
    box-shadow: 0 7px 20px color-mix(in srgb, var(--theme-color) 10%, transparent);
  }

  @container (width <= 760px) {
    .recognition-runner {
      &__layout {
        grid-template-columns: 1fr;
      }

      &__sidebar {
        min-height: auto;
      }

      &__switcher {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__governance {
        margin-top: 14px;
      }
    }
  }

  @container (width <= 520px) {
    .recognition-runner {
      &__switcher {
        grid-template-columns: 1fr;
      }

      &__workspace-head {
        grid-template-columns: 40px minmax(0, 1fr);
      }

      &__workspace-icon {
        width: 40px;
        height: 40px;
      }

      &__workspace-meta {
        flex-direction: row;
        grid-column: 2;
        align-items: center;
      }

      &__direction {
        flex-direction: column;
        grid-column: 1 / -1;
        align-items: stretch;
      }

      &__flow {
        grid-template-columns: 1fr;
      }

      &__context-action {
        flex-direction: column;
        align-items: stretch;

        .el-button {
          width: 100%;
        }
      }
    }
  }

  @media (width <= 640px) {
    .recognition-runner__footer {
      flex-direction: column;
      align-items: flex-end;

      > span {
        align-self: flex-start;
      }
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .recognition-runner__switcher button {
      transition: none;
    }
  }
</style>
