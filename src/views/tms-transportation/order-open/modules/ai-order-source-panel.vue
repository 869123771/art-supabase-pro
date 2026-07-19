<template>
  <section class="ai-order-source art-card-xs">
    <ArtSectionTitle>提供开单资料</ArtSectionTitle>
    <p class="ai-order-source__hint">
      粘贴客户聊天、运输委托内容，或上传最多 4 张订单图片。AI
      只生成草稿，不会自动保存订单。不知道怎么写？
      <ElButton
        class="ai-order-source__example-button"
        type="primary"
        link
        :loading="generatingExample"
        :disabled="analyzing"
        @click="emit('generate-example')"
      >
        AI生成示例
      </ElButton>
    </p>

    <ArtForm
      v-model="model"
      :items="items"
      :span="24"
      label-width="0"
      root-class="ai-order-source__form"
      :show-reset="false"
      :show-submit="false"
    />

    <div class="ai-order-source__upload">
      <ArtSectionTitle :show-line="false">订单图片</ArtSectionTitle>
      <ArtUploadImage v-model="model.imageUrls" title="上传订单" :size="96" :limit="4" multiple />
    </div>

    <div class="ai-order-source__actions">
      <ElButton
        type="primary"
        :loading="analyzing"
        :disabled="generatingExample"
        @click="emit('analyze')"
      >
        <ArtSvgIcon icon="ri:sparkling-2-line" />
        开始智能识别
      </ElButton>
      <span>文字和图片至少提供一项</span>
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
        rows: 7,
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
    padding: 16px;

    &__hint {
      margin: 8px 0 14px;
      line-height: 1.6;
      color: var(--el-text-color-secondary);
    }

    &__example-button {
      height: auto;
      padding: 0 2px;
      font-weight: 500;
      vertical-align: baseline;
    }

    &__upload {
      display: grid;
      gap: 12px;
      margin-top: 4px;
    }

    &__actions {
      display: flex;
      gap: 12px;
      align-items: center;
      margin-top: 16px;

      span {
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.ai-order-source__form) {
      padding: 0;

      .el-form-item {
        margin-bottom: 0;
      }
    }
  }
</style>
