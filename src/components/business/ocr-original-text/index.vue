<template>
  <section class="ocr-original-text" aria-label="OCR 原始识别内容">
    <header class="ocr-original-text__header">
      <div class="ocr-original-text__title">
        <span aria-hidden="true"><ArtSvgIcon icon="ri:text-snippet" /></span>
        <div>
          <strong>{{ title }}</strong>
          <small>{{ description }}</small>
        </div>
      </div>
      <div class="ocr-original-text__meta">
        <span>{{ normalizedText.length.toLocaleString('zh-CN') }} 字</span>
        <ElButton link type="primary" :disabled="!normalizedText" @click="copyText">
          <ArtSvgIcon icon="ri:file-copy-line" />复制原文
        </ElButton>
      </div>
    </header>

    <ElInput
      :model-value="normalizedText"
      type="textarea"
      readonly
      resize="none"
      :rows="rows"
      :placeholder="emptyText"
      aria-label="识别结果原文"
    />
    <p v-if="!normalizedText" class="ocr-original-text__empty">
      <ArtSvgIcon icon="ri:information-line" />{{ emptyText }}
    </p>
  </section>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'OcrOriginalText' })

  const props = withDefaults(
    defineProps<{
      text?: string | null
      title?: string
      description?: string
      emptyText?: string
      rows?: number
    }>(),
    {
      text: '',
      title: '识别结果',
      description: 'OCR 原始文字已单独留存，应用到表单后仍可据此复核。',
      emptyText: '未识别到可展示的文字；请结合原图人工核对。',
      rows: 6
    }
  )

  const normalizedText = computed(() => props.text?.trim() ?? '')

  async function copyText(): Promise<void> {
    if (!normalizedText.value) return
    try {
      await navigator.clipboard.writeText(normalizedText.value)
      ElMessage.success('识别原文已复制')
    } catch {
      ElMessage.warning('复制失败，请在文本框中手动选择复制')
    }
  }
</script>

<style scoped lang="scss">
  .ocr-original-text {
    display: grid;
    gap: 10px;
    min-width: 0;
    padding: 12px;
    background: color-mix(in srgb, var(--theme-color) 3%, var(--default-box-color));
    border: 1px solid color-mix(in srgb, var(--theme-color) 12%, var(--art-card-border));
    border-radius: var(--el-border-radius-base);

    &__header,
    &__title,
    &__meta {
      display: flex;
      align-items: center;
    }

    &__header {
      gap: 12px;
      justify-content: space-between;
    }

    &__title {
      gap: 9px;
      min-width: 0;

      > span {
        display: grid;
        flex: 0 0 30px;
        place-items: center;
        width: 30px;
        height: 30px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 10%, transparent);
        border-radius: var(--el-border-radius-small);
      }

      > div,
      strong,
      small {
        display: block;
        min-width: 0;
      }

      strong {
        font-size: 13px;
        color: var(--art-text-gray-900);
      }

      small {
        margin-top: 2px;
        font-size: 11px;
        line-height: 1.45;
        color: var(--art-text-gray-500);
      }
    }

    &__meta {
      flex: 0 0 auto;
      gap: 8px;

      > span {
        font-size: 11px;
        color: var(--art-text-gray-400);
        white-space: nowrap;
      }
    }

    &__empty {
      display: flex;
      gap: 6px;
      align-items: center;
      margin: -2px 0 0;
      font-size: 11px;
      color: var(--art-text-gray-500);
    }

    :deep(.el-textarea__inner) {
      line-height: 1.75;
      color: var(--art-text-gray-800);
      background: var(--default-box-color);
      border-color: var(--art-card-border);
      box-shadow: none;
      white-space: pre-wrap;
    }

    @media (width <= 640px) {
      &__header {
        align-items: flex-start;
      }

      &__meta > span {
        display: none;
      }
    }
  }
</style>
