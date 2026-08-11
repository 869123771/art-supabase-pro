<template>
  <section class="ai-order-source art-card-xs">
    <div class="ai-order-source__heading">
      <div>
        <ArtSectionTitle :show-line="false">提供开单资料</ArtSectionTitle>
        <p>支持客户聊天、运输委托和订单截图，文字与图片至少提供一项。</p>
      </div>
      <ElButton
        class="ai-order-source__example-button"
        type="primary"
        plain
        :loading="generatingExample"
        :disabled="analyzing"
        @click="emit('generate-example')"
      >
        <ArtSvgIcon icon="ri:magic-line" />
        AI生成示例
      </ElButton>
    </div>

    <div class="ai-order-source__input-area">
      <div>
        <span class="ai-order-source__field-label">文字资料</span>
        <ArtForm
          v-model="model"
          :items="items"
          :span="24"
          label-width="0"
          root-class="ai-order-source__form"
          :show-reset="false"
          :show-submit="false"
        />
      </div>

      <div class="ai-order-source__upload">
        <span class="ai-order-source__field-label">订单图片</span>
        <ArtUploadImage v-model="model.imageUrls" title="上传订单" :size="88" :limit="4" multiple />
        <small>最多 4 张，建议上传清晰完整的委托单</small>
      </div>
    </div>

    <div class="ai-order-source__actions">
      <span>
        <ArtSvgIcon icon="ri:shield-check-line" />
        识别结果仅生成订单草稿
      </span>
      <ElButton
        type="primary"
        size="large"
        :loading="analyzing"
        :disabled="generatingExample"
        @click="emit('analyze')"
      >
        <ArtSvgIcon icon="ri:sparkling-2-line" />
        开始智能识别
      </ElButton>
    </div>
  </section>
</template>

<script setup lang="ts">
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import { AI_ORDER_PROMPT_PLACEHOLDER } from './ai-order-examples'
  import type { AiOrderInputModel } from './ai-order-types'

  defineOptions({ name: 'TmsAiOrderSourcePanel' })

  const model = defineModel<AiOrderInputModel>({ required: true })
  const { analyzing = false, generatingExample = false } = defineProps<{
    analyzing?: boolean
    generatingExample?: boolean
  }>()
  const emit = defineEmits<{ analyze: []; 'generate-example': [] }>()

  const items: FormItem[] = [
    {
      label: '',
      key: 'prompt',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 8,
        maxlength: 8000,
        showWordLimit: true,
        resize: 'none',
        placeholder: AI_ORDER_PROMPT_PLACEHOLDER
      }
    }
  ]
</script>

<style scoped lang="scss">
  .ai-order-source {
    min-width: 0;
    padding: 18px;

    &__heading {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 16px;

      p {
        margin: 6px 0 0;
        line-height: 1.55;
        color: var(--el-text-color-secondary);
      }
    }

    &__example-button {
      flex: none;
      font-weight: 500;
    }

    &__input-area {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 112px;
      gap: 16px;
      align-items: start;
      min-width: 0;
    }

    &__field-label {
      display: block;
      margin-bottom: 8px;
      font-size: 13px;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    &__upload {
      display: grid;
      justify-items: start;

      small {
        margin-top: 8px;
        font-size: 11px;
        line-height: 1.45;
        color: var(--el-text-color-placeholder);
      }
    }

    &__actions {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      padding-top: 14px;
      margin-top: 16px;
      border-top: 1px solid var(--el-border-color-lighter);

      span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.ai-order-source__form) {
      padding: 0;

      .el-form-item {
        margin-bottom: 0;
      }

      .el-textarea__inner {
        line-height: 1.7;
      }
    }

    @media (width <= 520px) {
      &__heading,
      &__actions {
        flex-direction: column;
        align-items: stretch;
      }

      &__input-area {
        grid-template-columns: 1fr;
      }

      &__upload {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
