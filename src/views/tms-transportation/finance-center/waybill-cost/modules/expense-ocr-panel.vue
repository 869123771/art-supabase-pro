<template>
  <section class="expense-ocr art-card-xs">
    <header class="expense-ocr__header">
      <div class="expense-ocr__identity">
        <span class="expense-ocr__icon"><ArtSvgIcon icon="ri:scan-2-line" /></span>
        <div>
          <span class="expense-ocr__eyebrow">智能票据识别</span>
          <strong>上传票据后自动填写费用要素</strong>
          <small>识别结果仅写入当前草稿，保存前请人工核对金额与日期。</small>
        </div>
      </div>
      <ElButton
        type="primary"
        plain
        :loading="state.analyzing"
        :disabled="!enabled || !imageUrls.length"
        @click="handleAnalyze"
      >
        <ArtSvgIcon v-if="!state.analyzing" icon="ri:sparkling-2-line" />
        {{ state.result ? '重新识别' : '开始识别' }}
      </ElButton>
    </header>

    <div class="expense-ocr__body">
      <ArtUploadImage v-model="imageUrls" title="费用票据" :size="82" :limit="5" multiple />
      <div v-if="!enabled" class="expense-ocr__disabled">
        <ArtSvgIcon icon="ri:toggle-line" />
        <span><strong>智能识别已停用</strong><small>仍可上传图片并手工填写申报信息。</small></span>
      </div>
      <div v-else-if="!state.result" class="expense-ocr__guide">
        <span v-for="item in guideItems" :key="item.title">
          <ArtSvgIcon :icon="item.icon" />
          <span
            ><strong>{{ item.title }}</strong
            ><small>{{ item.description }}</small></span
          >
        </span>
      </div>
      <div v-else class="expense-ocr__result">
        <div>
          <span>
            <strong>识别完成</strong>
            <ElTag :type="confidenceType" effect="light" round>
              可信度 {{ confidencePercent }}%
            </ElTag>
          </span>
          <ElButton type="primary" @click="emit('apply', state.result)">应用到表单</ElButton>
        </div>
        <p>{{ state.result.summary }}</p>
        <small v-if="state.result.warnings.length">
          {{ state.result.warnings.slice(0, 2).join('；') }}
        </small>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { ElMessage } from 'element-plus'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import { analyzeWaybillExpenseByAi } from '@/api/tms'

  defineOptions({ name: 'TmsWaybillExpenseOcrPanel' })

  const props = defineProps<{ modelValue: string[]; enabled: boolean }>()
  const emit = defineEmits<{
    'update:modelValue': [value: string[]]
    apply: [result: Api.Tms.Finance.WaybillExpenseOcrAnalyzeResponse]
    failed: []
  }>()

  const guideItems = [
    { icon: 'ri:money-cny-circle-line', title: '金额日期', description: '票面金额、消费时间' },
    { icon: 'ri:gas-station-line', title: '消费信息', description: '服务商、收款方与支付渠道' },
    { icon: 'ri:file-text-line', title: '票据要素', description: '服务商、票号、地点与数量' }
  ]
  const state = reactive<{
    analyzing: boolean
    result?: Api.Tms.Finance.WaybillExpenseOcrAnalyzeResponse
  }>({ analyzing: false, result: undefined })
  const imageUrls = computed<string[]>({
    get: () => props.modelValue,
    set: (value) => {
      state.result = undefined
      emit('update:modelValue', value)
    }
  })
  const confidencePercent = computed(() => Math.round((state.result?.confidence ?? 0) * 100))
  const confidenceType = computed(() =>
    confidencePercent.value >= 85 ? 'success' : confidencePercent.value >= 65 ? 'warning' : 'danger'
  )

  async function handleAnalyze(): Promise<void> {
    if (!props.enabled || !imageUrls.value.length || state.analyzing) return
    state.analyzing = true
    try {
      const response = await analyzeWaybillExpenseByAi(imageUrls.value)
      if (response.error || !response.data) throw response.error || new Error('未返回识别结果')
      state.result = response.data
      ElMessage.success('票据识别完成，请核对后应用')
    } catch (error) {
      emit('failed')
      ElMessage.error(
        getFriendlySupabaseErrorMessage(error, '票据识别失败，请稍后重试或改为手工填写')
      )
    } finally {
      state.analyzing = false
    }
  }

  function reset(): void {
    state.analyzing = false
    state.result = undefined
  }

  defineExpose({ reset })
</script>

<style scoped lang="scss">
  .expense-ocr {
    padding: var(--art-space-4);
    margin-bottom: var(--art-space-4);

    &__header,
    &__identity,
    &__body,
    &__guide,
    &__guide > span,
    &__disabled,
    &__result > div,
    &__result > div > span {
      display: flex;
      align-items: center;
    }

    &__header {
      gap: var(--art-space-4);
      justify-content: space-between;
    }

    &__identity {
      gap: var(--art-space-3);
      min-width: 0;

      > div,
      > div > span {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }

      strong {
        color: var(--art-text-gray-900);
      }

      small {
        line-height: 1.5;
        color: var(--art-text-gray-500);
      }
    }

    &__icon {
      display: grid;
      flex: 0 0 40px;
      place-items: center;
      width: 40px;
      height: 40px;
      font-size: 20px;
      color: rgb(var(--ui-primary));
      background: rgb(var(--ui-primary) / 10%);
      border-radius: var(--el-border-radius-base);
    }

    &__eyebrow {
      font-size: 11px;
      font-weight: 700;
      color: rgb(var(--ui-primary));
      letter-spacing: 0.04em;
    }

    &__body {
      gap: var(--art-space-4);
      padding-top: var(--art-space-4);
      margin-top: var(--art-space-4);
      border-top: 1px solid var(--art-border-dashed-color);
    }

    &__guide {
      flex: 1;
      gap: var(--art-space-2);
      min-width: 0;

      > span {
        flex: 1;
        gap: var(--art-space-2);
        min-width: 0;
        padding: var(--art-space-3);
        background: rgb(var(--ui-primary) / 4%);
        border: 1px solid rgb(var(--ui-primary) / 12%);
        border-radius: var(--el-border-radius-base);

        > svg {
          flex: 0 0 auto;
          color: rgb(var(--ui-primary));
        }

        > span {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }

        strong,
        small {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        strong {
          font-size: 12px;
          color: var(--art-text-gray-800);
        }

        small {
          font-size: 11px;
          color: var(--art-text-gray-500);
        }
      }
    }

    &__disabled {
      gap: var(--art-space-2);
      color: var(--art-text-gray-500);

      span {
        display: flex;
        flex-direction: column;
      }
    }

    &__result {
      flex: 1;
      min-width: 0;

      > div {
        gap: var(--art-space-3);
        justify-content: space-between;

        > span {
          gap: var(--art-space-2);
        }
      }

      p,
      > small {
        display: block;
        margin: 6px 0 0;
        color: var(--art-text-gray-600);
      }

      > small {
        color: var(--el-color-warning-dark-2);
      }
    }

    @media (width <= 860px) {
      &__header,
      &__body,
      &__guide {
        flex-direction: column;
        align-items: stretch;
      }
    }
  }
</style>
