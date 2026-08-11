<template>
  <section class="ai-planner__hero art-card-xs">
    <div class="ai-planner__hero-copy">
      <div class="ai-planner__brand"><ArtSvgIcon icon="ri:compass-3-line" /></div>
      <div>
        <span class="ai-planner__eyebrow">PROJECT NEXT STEP</span>
        <h1>AI 项目规划台</h1>
        <p>结合当前代码、Supabase 能力与历史反馈，生成可直接交给 Codex 的下一步提示词。</p>
        <div class="ai-planner__access-note">
          <ArtSvgIcon :icon="canManageWorkflow ? 'ri:admin-line' : 'ri:shield-check-line'" />
          <span>
            {{
              canManageWorkflow
                ? '管理员规划模式：可推进建议状态'
                : '普通用户只读分析：可查询、生成与复用建议，不修改业务数据'
            }}
          </span>
        </div>
      </div>
    </div>
    <div class="ai-planner__controls">
      <ElSelect v-model="focus" class="ai-planner__select" placeholder="关注方向">
        <ElOption label="综合平衡" value="balanced" />
        <ElOption
          v-for="item in categoryOptions"
          :key="String(item.value)"
          :label="String(item.label)"
          :value="String(item.value)"
        />
      </ElSelect>
      <ElSelect v-model="effort" class="ai-planner__select" placeholder="工作量">
        <ElOption
          v-for="item in effortOptions"
          :key="String(item.value)"
          :label="String(item.label)"
          :value="String(item.value)"
        />
      </ElSelect>
      <ElButton
        type="primary"
        :loading="generating"
        :disabled="capabilities !== null && !capabilities.providerConfigured"
        @click="emit('generate')"
      >
        <ArtSvgIcon icon="ri:sparkling-2-line" />
        生成下一步
      </ElButton>
    </div>
  </section>

  <ElAlert
    v-if="capabilities && !capabilities.providerConfigured"
    class="ai-planner__alert"
    title="尚未配置 AI 模型服务"
    description="请在 Supabase Edge Function Secrets 中设置 AI_API_KEY、AI_BASE_URL 和 AI_MODEL。密钥只保存在服务端，不会进入浏览器或数据库。"
    type="warning"
    show-icon
    :closable="false"
  />

  <section class="ai-planner__decision-grid" :class="{ 'has-priority': prioritySuggestion }">
    <section v-if="prioritySuggestion" class="ai-planner__priority art-card-xs">
      <div class="ai-planner__priority-main">
        <div class="ai-planner__priority-icon"><ArtSvgIcon icon="ri:focus-3-line" /></div>
        <div>
          <span class="ai-planner__priority-eyebrow">AI PRIORITY</span>
          <strong>建议优先推进：{{ prioritySuggestion.title }}</strong>
          <p>{{ prioritySuggestion.summary }}</p>
        </div>
      </div>
      <div class="ai-planner__priority-score">
        <div>
          <span>影响力</span>
          <strong>{{ prioritySuggestion.impact }}/5</strong>
        </div>
        <div>
          <span>置信度</span>
          <strong>{{ Math.round(prioritySuggestion.confidence * 100) }}%</strong>
        </div>
        <div>
          <span>投入</span>
          <strong>{{ effortLabel }}</strong>
        </div>
      </div>
      <div class="ai-planner__priority-actions">
        <ElButton
          :loading="pendingAction === 'copied'"
          :disabled="Boolean(pendingAction)"
          @click="emit('copy', prioritySuggestion)"
        >
          <ArtSvgIcon icon="ri:file-copy-line" />复制 Prompt
        </ElButton>
        <ElButton
          v-if="canManageWorkflow"
          type="primary"
          :loading="pendingAction === 'accepted'"
          :disabled="Boolean(pendingAction)"
          @click="emit('accept', prioritySuggestion)"
        >
          <ArtSvgIcon icon="ri:check-line" />采纳优先建议
        </ElButton>
      </div>
    </section>

    <section class="ai-planner__metrics">
      <article v-for="metric in metrics" :key="metric.label" class="art-card-xs">
        <div :class="['ai-planner__metric-icon', `is-${metric.tone}`]">
          <ArtSvgIcon :icon="metric.icon" />
        </div>
        <div>
          <span>{{ metric.label }}</span>
          <strong>{{ metric.value }}</strong>
          <small>{{ metric.hint }}</small>
        </div>
      </article>
    </section>
  </section>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type { DictMap } from '@/types/store'
  import type {
    AiPlannerCapabilities,
    AiPlannerEffort,
    AiProjectSuggestion,
    AiSuggestionCategory
  } from '@/types/ai-project-planner'
  import {
    getProjectPlannerDictLabel,
    type ProjectPlannerMetric,
    type SuggestionPendingAction
  } from './project-planner-view-model'

  interface Props {
    capabilities: AiPlannerCapabilities | null
    canManageWorkflow: boolean
    generating: boolean
    prioritySuggestion?: AiProjectSuggestion
    pendingAction?: SuggestionPendingAction
    metrics: ProjectPlannerMetric[]
    dictMap: DictMap
  }

  const props = defineProps<Props>()
  const focus = defineModel<'balanced' | AiSuggestionCategory>('focus', { required: true })
  const effort = defineModel<AiPlannerEffort>('effort', { required: true })
  const emit = defineEmits<{
    generate: []
    copy: [suggestion: AiProjectSuggestion]
    accept: [suggestion: AiProjectSuggestion]
  }>()

  const categoryOptions = computed(() => props.dictMap.aiSuggestionCategory ?? [])
  const effortOptions = computed(() => props.dictMap.aiSuggestionEffort ?? [])
  const effortLabel = computed(() =>
    props.prioritySuggestion
      ? getProjectPlannerDictLabel(
          props.dictMap,
          'aiSuggestionEffort',
          props.prioritySuggestion.effort
        )
      : '—'
  )
</script>

<style scoped lang="scss">
  .ai-planner {
    &__hero {
      display: flex;
      gap: 24px;
      align-items: center;
      justify-content: space-between;
      padding: 26px 28px;
      background:
        radial-gradient(circle at 86% 18%, rgb(99 102 241 / 13%), transparent 30%),
        var(--art-main-bg-color);

      p {
        color: var(--art-text-gray-500);
      }

      h1 {
        margin: 3px 0 5px;
        font-size: 24px;
        color: var(--art-text-gray-900);
      }
    }

    &__hero-copy,
    &__controls {
      display: flex;
      gap: 12px;
      align-items: center;
    }

    &__brand {
      display: grid;
      flex: 0 0 58px;
      place-items: center;
      width: 58px;
      height: 58px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
      border-radius: var(--custom-radius);
      box-shadow: 0 10px 28px rgb(99 102 241 / 20%);

      :deep(svg) {
        width: 28px;
        height: 28px;
      }
    }

    &__eyebrow {
      font-size: 11px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.14em;
    }

    &__access-note {
      display: inline-flex;
      gap: 7px;
      align-items: center;
      margin-top: 8px;
      font-size: 12px;
      color: var(--el-color-success);

      :deep(svg) {
        flex: 0 0 auto;
        width: 15px;
        height: 15px;
      }
    }

    &__select {
      width: 142px;
    }

    &__alert {
      margin: 0;
    }

    &__decision-grid {
      display: grid;
      grid-template-columns: 1fr;
      gap: 16px;
      min-width: 0;

      &.has-priority {
        grid-template-columns: minmax(0, 1.45fr) minmax(360px, 0.75fr);

        .ai-planner__priority {
          grid-template-columns: minmax(0, 1fr);
          grid-row: 1;
          grid-column: 1;
          gap: 15px;
          align-content: center;

          .ai-planner__priority-score {
            padding: 13px 0;
            border-top: 1px solid var(--el-border-color-lighter);
            border-bottom: 1px solid var(--el-border-color-lighter);
          }
        }

        .ai-planner__metrics {
          grid-template-columns: repeat(2, minmax(0, 1fr));
          grid-row: 1;
          grid-column: 2;
        }
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;

      article {
        display: flex;
        gap: 14px;
        align-items: center;
        min-width: 0;
        padding: 19px 20px;

        > div:last-child {
          min-width: 0;
        }
      }

      span,
      small {
        display: block;
        font-size: 12px;
      }

      strong {
        display: block;
        margin: 2px 0;
        font-size: 23px;
        color: var(--art-text-gray-900);
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }
    }

    &__metric-icon {
      display: grid;
      place-items: center;
      width: 42px;
      height: 42px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }

      &.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }
    }

    &__priority {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto auto;
      gap: 24px;
      align-items: center;
      padding: 18px 20px;
      background:
        radial-gradient(circle at 78% 0%, rgb(99 102 241 / 10%), transparent 34%),
        linear-gradient(110deg, var(--el-color-primary-light-9), var(--art-main-bg-color) 46%);
      border-color: var(--el-color-primary-light-8);
    }

    &__priority-main,
    &__priority-score,
    &__priority-actions {
      display: flex;
      align-items: center;
    }

    &__priority-main {
      min-width: 0;

      > div:last-child {
        min-width: 0;
      }

      strong,
      p,
      span {
        display: block;
      }

      strong {
        margin: 2px 0 4px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 15px;
        color: var(--art-text-gray-900);
        white-space: nowrap;
      }

      p {
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }
    }

    &__priority-icon {
      display: grid;
      flex: 0 0 42px;
      place-items: center;
      width: 42px;
      height: 42px;
      margin-right: 13px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 21px;
        height: 21px;
      }
    }

    &__priority-eyebrow {
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.12em;
    }

    &__priority-score {
      gap: 18px;

      > div {
        display: grid;
        gap: 2px;
        min-width: 54px;
      }

      span {
        font-size: 11px;
        color: var(--art-text-gray-400);
      }

      strong {
        font-size: 13px;
        color: var(--art-text-gray-800);
      }
    }

    &__priority-actions {
      gap: 8px;

      :deep(.el-button + .el-button) {
        margin-left: 0;
      }
    }
  }

  @media (width <= 1100px) {
    .ai-planner {
      &__hero {
        flex-direction: column;
        align-items: flex-start;
      }

      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__decision-grid.has-priority {
        grid-template-columns: 1fr;

        .ai-planner__priority,
        .ai-planner__metrics {
          grid-column: 1;
        }

        .ai-planner__priority {
          grid-row: 1;
        }

        .ai-planner__metrics {
          grid-row: 2;
        }
      }

      &__priority {
        grid-template-columns: minmax(0, 1fr);
        gap: 14px;
      }
    }
  }

  @media (width <= 680px) {
    .ai-planner {
      &__hero-copy,
      &__controls,
      &__priority-actions {
        flex-direction: column;
        align-items: stretch;
        width: 100%;
      }

      &__hero-copy {
        align-items: flex-start;
      }

      &__select {
        width: 100%;
      }

      &__metrics,
      &__decision-grid.has-priority .ai-planner__metrics {
        grid-template-columns: 1fr;
      }

      &__priority-score {
        flex-wrap: wrap;
      }
    }
  }
</style>
