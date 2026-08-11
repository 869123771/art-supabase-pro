<template>
  <section v-if="mode === 'initial'" class="ai-planner__empty art-card-xs">
    <div class="ai-planner__empty-main">
      <div class="ai-planner__empty-visual" aria-hidden="true">
        <span><ArtSvgIcon icon="ri:code-box-line" /></span>
        <strong><ArtSvgIcon icon="ri:sparkling-2-line" /></strong>
        <span><ArtSvgIcon icon="ri:database-2-line" /></span>
      </div>
      <div class="ai-planner__empty-copy">
        <span class="ai-planner__empty-eyebrow">READY FOR FIRST ANALYSIS</span>
        <h2>让 AI 为项目排出下一步</h2>
        <p>综合当前代码结构、Supabase 能力和历史反馈，生成带证据、风险与验收标准的可执行建议。</p>
        <div class="ai-planner__empty-badges">
          <span><ArtSvgIcon icon="ri:shield-check-line" />只读分析</span>
          <span><ArtSvgIcon icon="ri:file-copy-2-line" />一键复制 Prompt</span>
          <span><ArtSvgIcon icon="ri:history-line" />反馈持续优化</span>
        </div>
        <ElButton
          type="primary"
          size="large"
          :loading="generating"
          :disabled="generationDisabled"
          @click="emit('generate')"
        >
          <ArtSvgIcon icon="ri:sparkling-2-line" />生成第一批项目建议
        </ElButton>
      </div>
    </div>

    <div class="ai-planner__empty-flow" aria-label="AI 项目规划流程">
      <article>
        <span>01</span>
        <div>
          <strong>读取项目现状</strong>
          <p>识别代码结构、现有能力和运行边界</p>
        </div>
      </article>
      <article>
        <span>02</span>
        <div>
          <strong>评估机会优先级</strong>
          <p>综合影响、投入、风险和置信度排序</p>
        </div>
      </article>
      <article>
        <span>03</span>
        <div>
          <strong>交付执行 Prompt</strong>
          <p>输出可直接交给 Codex 的任务与验收标准</p>
        </div>
      </article>
    </div>
  </section>

  <div v-else class="ai-planner__filtered-empty art-card-xs">
    <div class="ai-planner__filtered-empty-icon">
      <ArtSvgIcon icon="ri:search-eye-line" />
    </div>
    <div>
      <strong>没有符合当前筛选条件的建议</strong>
      <p>可以调整关键词、批次或能力类别，或者清除全部筛选条件。</p>
    </div>
    <ElButton type="primary" plain @click="emit('reset-filters')">
      <ArtSvgIcon icon="ri:filter-off-line" />清除筛选
    </ElButton>
  </div>
</template>

<script setup lang="ts">
  defineProps<{
    mode: 'initial' | 'filtered'
    generating?: boolean
    generationDisabled?: boolean
  }>()

  const emit = defineEmits<{
    generate: []
    'reset-filters': []
  }>()
</script>

<style scoped lang="scss">
  .ai-planner {
    &__empty {
      position: relative;
      display: grid;
      grid-template-columns: minmax(0, 1.15fr) minmax(360px, 0.85fr);
      gap: 34px;
      align-items: center;
      min-height: 300px;
      padding: 30px 34px;
      overflow: hidden;
      background:
        radial-gradient(circle at 12% 18%, rgb(99 102 241 / 11%), transparent 27%),
        radial-gradient(circle at 92% 88%, rgb(59 130 246 / 8%), transparent 24%),
        var(--art-main-bg-color);
      border-color: var(--el-color-primary-light-8);
    }

    &__empty-main {
      display: flex;
      gap: 24px;
      align-items: center;
      min-width: 0;
    }

    &__empty-visual {
      position: relative;
      display: grid;
      flex: 0 0 116px;
      place-items: center;
      width: 116px;
      height: 116px;

      &::before,
      &::after {
        position: absolute;
        content: '';
        border: 1px dashed var(--el-color-primary-light-5);
        border-radius: 50%;
      }

      &::before {
        inset: 8px;
      }

      &::after {
        inset: 24px;
        opacity: 0.7;
      }

      strong,
      span {
        position: absolute;
        z-index: 1;
        display: grid;
        place-items: center;
        color: var(--el-color-primary);
        background: var(--art-main-bg-color);
        border: 1px solid var(--el-color-primary-light-8);
        border-radius: 50%;
        box-shadow: var(--el-box-shadow-lighter);
      }

      strong {
        width: 56px;
        height: 56px;
        color: white;
        background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
        border: 0;

        :deep(svg) {
          width: 27px;
          height: 27px;
        }
      }

      span {
        width: 34px;
        height: 34px;

        &:first-child {
          top: 0;
          left: 4px;
        }

        &:last-child {
          right: 0;
          bottom: 4px;
        }
      }
    }

    &__empty-copy {
      min-width: 0;

      h2 {
        margin: 5px 0 8px;
        font-size: 22px;
        color: var(--art-text-gray-900);
      }

      > p {
        max-width: 620px;
        margin: 0 0 16px;
        line-height: 1.75;
        color: var(--art-text-gray-600);
      }

      :deep(.el-button) {
        margin-top: 18px;
      }
    }

    &__empty-eyebrow {
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.14em;
    }

    &__empty-badges {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        padding: 5px 9px;
        font-size: 11px;
        color: var(--art-text-gray-600);
        background: color-mix(in srgb, var(--art-main-bg-color) 92%, var(--el-color-primary));
        border: 1px solid var(--el-border-color-lighter);
        border-radius: 999px;

        :deep(svg) {
          width: 14px;
          height: 14px;
          color: var(--el-color-primary);
        }
      }
    }

    &__empty-flow {
      display: grid;
      gap: 10px;

      article {
        display: grid;
        grid-template-columns: 34px minmax(0, 1fr);
        gap: 12px;
        align-items: center;
        min-width: 0;
        padding: 14px 15px;
        background: color-mix(in srgb, var(--art-main-bg-color) 96%, var(--el-color-primary));
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);

        > span {
          display: grid;
          place-items: center;
          width: 32px;
          height: 32px;
          font-size: 11px;
          font-weight: 700;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 50%;
        }

        strong {
          display: block;
          margin-bottom: 3px;
          color: var(--art-text-gray-800);
        }

        p {
          margin: 0;
          font-size: 12px;
          line-height: 1.55;
          color: var(--art-text-gray-500);
        }
      }
    }

    &__filtered-empty {
      display: flex;
      gap: 16px;
      align-items: center;
      min-height: 150px;
      padding: 26px 30px;

      > div:nth-child(2) {
        flex: 1;
        min-width: 0;
      }

      strong {
        color: var(--art-text-gray-800);
      }

      p {
        margin: 5px 0 0;
        color: var(--art-text-gray-500);
      }
    }

    &__filtered-empty-icon {
      display: grid;
      flex: 0 0 46px;
      place-items: center;
      width: 46px;
      height: 46px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 22px;
        height: 22px;
      }
    }
  }

  @media (width <= 1100px) {
    .ai-planner__empty {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  @media (width <= 680px) {
    .ai-planner {
      &__empty {
        padding: 24px 20px;
      }

      &__empty-main,
      &__filtered-empty {
        flex-direction: column;
        align-items: flex-start;
      }

      &__empty-visual {
        flex-basis: 96px;
        width: 96px;
        height: 96px;
      }
    }
  }
</style>
