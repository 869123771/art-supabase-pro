<template>
  <section class="voucher-ocr art-card-xs">
    <header class="voucher-ocr__header">
      <div class="voucher-ocr__identity">
        <span class="voucher-ocr__icon"><ArtSvgIcon icon="ri-bank-card-line" /></span>
        <div>
          <span class="voucher-ocr__eyebrow">AI 凭证识别</span>
          <h3>{{
            direction === 'receipt'
              ? '识别收款凭证并匹配客户对账单'
              : '识别付款凭证并匹配承运商对账单'
          }}</h3>
          <p>先预览识别与匹配依据，应用后仍需人工确认核销金额。</p>
        </div>
      </div>
      <ElButton
        type="primary"
        :loading="analyzing"
        :disabled="!imageUrls.length"
        @click="handleAnalyze"
      >
        <ArtSvgIcon v-if="!analyzing" icon="ri-sparkling-2-line" />
        {{ result ? '重新识别' : '识别并匹配' }}
      </ElButton>
    </header>

    <div class="voucher-ocr__body">
      <div class="voucher-ocr__upload">
        <ArtUploadImage v-model="imageUrls" title="上传凭证" :size="82" :limit="3" multiple />
        <div>
          <strong>{{
            imageUrls.length ? `已上传 ${imageUrls.length} 张凭证` : '上传 1–3 张凭证'
          }}</strong>
          <span>支持银行回单、转账截图和电子支付凭证。</span>
        </div>
      </div>

      <div v-if="!result" class="voucher-ocr__guide">
        <div v-for="item in guideItems" :key="item.title">
          <ArtSvgIcon :icon="item.icon" />
          <span
            ><strong>{{ item.title }}</strong
            ><small>{{ item.description }}</small></span
          >
        </div>
      </div>

      <div v-else class="voucher-ocr__result">
        <div class="voucher-ocr__result-head">
          <div>
            <strong>识别完成</strong>
            <ElTag :type="confidenceTagType" effect="light" round
              >可信度 {{ confidencePercent }}%</ElTag
            >
            <ElTag type="info" effect="plain" round>候选 {{ result.matches.length }} 条</ElTag>
          </div>
          <ElButton type="primary" plain @click="emit('apply', result)">{{ applyLabel }}</ElButton>
        </div>
        <p>{{ result.summary }}</p>
        <div class="voucher-ocr__fields">
          <span v-for="field in fields" :key="field.label">
            <small>{{ field.label }}</small>
            <strong :class="{ 'is-empty': field.empty }">{{ field.value }}</strong>
          </span>
        </div>
        <OcrOriginalText
          class="voucher-ocr__raw-text"
          :text="result.rawText"
          :min-rows="4"
          :max-rows="8"
        />
        <div v-if="result.matches.length" class="voucher-ocr__matches">
          <div v-for="match in result.matches.slice(0, 3)" :key="match.statementId">
            <span>
              <strong>{{ match.statementNo }}</strong>
              <small
                >{{ match.counterpartyName }} · 未结
                {{ formatMoney(match.outstandingAmount) }}</small
              >
            </span>
            <ElTag :type="match.score >= 80 ? 'success' : 'warning'" effect="light">
              匹配 {{ match.score }} 分
            </ElTag>
          </div>
        </div>
        <ElAlert
          v-else
          type="warning"
          :closable="false"
          show-icon
          title="未找到足够可信的未结对账单，请手工选择"
        />
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { ElMessage } from 'element-plus'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import OcrOriginalText from '@/components/business/ocr-original-text/index.vue'
  import { analyzeCashVoucherByAi } from '@/api/finance'

  defineOptions({ name: 'FinanceCashVoucherOcrPanel' })

  const props = defineProps<{
    modelValue: string[]
    direction: Api.Finance.CashDirection
    applyLabel?: string
  }>()
  const applyLabel = computed(() => props.applyLabel || '应用识别与推荐')
  const emit = defineEmits<{
    'update:modelValue': [value: string[]]
    apply: [result: Api.Finance.CashVoucherOcrAnalyzeResponse]
  }>()

  const guideItems = [
    { icon: 'ri-file-search-line', title: '凭证字段', description: '交易双方、日期、金额与流水号' },
    { icon: 'ri-links-line', title: '自动匹配', description: '金额、往来单位、账期与附言' },
    {
      icon: 'ri-shield-check-line',
      title: '人工确认',
      description: '只推荐不自动核销，保留审计记录'
    }
  ]
  const analyzing = ref(false)
  const result = ref<Api.Finance.CashVoucherOcrAnalyzeResponse>()
  const imageUrls = computed<string[]>({
    get: () => props.modelValue,
    set: (value) => {
      result.value = undefined
      emit('update:modelValue', value)
    }
  })
  const confidencePercent = computed(() => Math.round((result.value?.confidence ?? 0) * 100))
  const confidenceTagType = computed(() =>
    confidencePercent.value >= 85 ? 'success' : confidencePercent.value >= 65 ? 'warning' : 'danger'
  )
  const fields = computed(() => {
    const voucher = result.value?.voucher
    if (!voucher) return []
    const counterparty = props.direction === 'receipt' ? voucher.payerName : voucher.payeeName
    return [
      {
        label: props.direction === 'receipt' ? '付款方' : '收款方',
        value: counterparty || '未识别',
        empty: !counterparty
      },
      {
        label: '交易日期',
        value: voucher.transactionDate || '未识别',
        empty: !voucher.transactionDate
      },
      {
        label: '交易金额',
        value: voucher.amount === null ? '未识别' : formatMoney(voucher.amount),
        empty: voucher.amount === null
      },
      { label: '流水号', value: voucher.bankReference || '未识别', empty: !voucher.bankReference }
    ]
  })

  function formatMoney(value?: number | null): string {
    return `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  async function handleAnalyze(): Promise<void> {
    if (!imageUrls.value.length || analyzing.value) return
    analyzing.value = true
    try {
      const response = await analyzeCashVoucherByAi({
        action: 'analyze',
        imageUrls: imageUrls.value,
        direction: props.direction
      })
      if (response.error || !response.data) throw response.error || new Error('未返回识别结果')
      result.value = response.data
      ElMessage.success('凭证识别和对账单匹配完成，请核对后应用')
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, 'AI 凭证识别失败，请稍后重试'))
    } finally {
      analyzing.value = false
    }
  }

  function reset(): void {
    result.value = undefined
    analyzing.value = false
  }

  defineExpose({ reset })
</script>

<style scoped lang="scss">
  .voucher-ocr {
    padding: 16px;
    margin-bottom: 16px;
    box-shadow: inset 3px 0 0 rgb(var(--ui-primary) / 72%);

    &__header,
    &__identity,
    &__upload,
    &__result-head,
    &__result-head > div,
    &__guide > div,
    &__matches > div {
      display: flex;
      align-items: center;
    }

    &__header,
    &__result-head {
      gap: 16px;
      justify-content: space-between;
    }

    &__identity {
      gap: 10px;
      min-width: 0;

      h3 {
        margin: 1px 0 2px;
        font-size: 15px;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }
    }

    &__icon {
      display: grid;
      flex: 0 0 38px;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 19px;
      color: rgb(var(--ui-primary));
      background: rgb(var(--ui-primary) / 10%);
      border-radius: var(--el-border-radius-base);
    }

    &__eyebrow {
      font-size: 11px;
      font-weight: 600;
      color: rgb(var(--ui-primary));
      letter-spacing: 0.04em;
    }

    &__body {
      display: grid;
      grid-template-columns: minmax(250px, 0.8fr) minmax(0, 2fr);
      gap: 12px;
      padding-top: 12px;
      margin-top: 12px;
      border-top: 1px solid var(--art-border-dashed-color);
    }

    &__upload {
      gap: 10px;
      min-width: 0;

      > div {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      strong {
        font-size: 13px;
        color: var(--art-text-gray-800);
      }

      span {
        font-size: 12px;
        line-height: 1.5;
        color: var(--art-text-gray-500);
      }
    }

    &__guide {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 8px;

      > div {
        gap: 8px;
        min-width: 0;
        padding: 10px;
        background: rgb(var(--ui-primary) / 3%);
        border: 1px solid rgb(var(--ui-primary) / 10%);
        border-radius: var(--el-border-radius-base);

        > svg {
          flex: 0 0 auto;
          color: rgb(var(--ui-primary));
        }

        span {
          display: flex;
          flex-direction: column;
          gap: 3px;
          min-width: 0;
        }

        strong {
          font-size: 12px;
          color: var(--art-text-gray-800);
        }

        small {
          font-size: 11px;
          line-height: 1.45;
          color: var(--art-text-gray-500);
        }
      }
    }

    &__result {
      min-width: 0;

      > p {
        margin: 8px 0;
        font-size: 12px;
        color: var(--art-text-gray-600);
      }
    }

    &__result-head > div {
      gap: 8px;
    }

    &__fields {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
      margin-bottom: 8px;

      span {
        display: flex;
        flex-direction: column;
        gap: 3px;
        min-width: 0;
        padding: 8px 10px;
        background: var(--art-gray-50);
        border-radius: var(--el-border-radius-small);
      }

      small {
        font-size: 11px;
        color: var(--art-text-gray-500);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--art-text-gray-800);
        white-space: nowrap;

        &.is-empty {
          font-weight: 400;
          color: var(--art-text-gray-400);
        }
      }
    }

    &__matches {
      display: grid;
      gap: 6px;

      > div {
        gap: 12px;
        justify-content: space-between;
        padding: 8px 10px;
        background: var(--el-color-success-light-9);
        border-radius: var(--el-border-radius-small);

        > span {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }

        strong {
          font-size: 12px;
          color: var(--art-text-gray-800);
        }

        small {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 11px;
          color: var(--art-text-gray-500);
          white-space: nowrap;
        }
      }
    }

    &__raw-text {
      margin-bottom: 8px;
    }

    @media (width <= 900px) {
      &__body {
        grid-template-columns: 1fr;
      }

      &__guide,
      &__fields {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }
</style>
