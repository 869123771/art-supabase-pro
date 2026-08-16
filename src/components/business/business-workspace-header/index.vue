<template>
  <section class="business-workspace-header art-card-xs">
    <header class="business-workspace-header__hero">
      <div class="business-workspace-header__identity">
        <div class="business-workspace-header__brand" aria-hidden="true">
          <ArtSvgIcon :icon="icon" />
        </div>
        <div class="business-workspace-header__copy">
          <span>{{ eyebrow }}</span>
          <h1>{{ title }}</h1>
          <p>{{ description }}</p>
        </div>
      </div>

      <div
        v-if="tags.length || $slots.actions"
        class="business-workspace-header__aside"
        aria-label="业务特性与操作"
      >
        <div v-if="tags.length" class="business-workspace-header__tags">
          <ElTag
            v-for="tag in tags"
            :key="tag.label"
            :type="tag.type"
            :effect="tag.effect ?? 'plain'"
            round
          >
            {{ tag.label }}
          </ElTag>
        </div>
        <div v-if="$slots.actions" class="business-workspace-header__actions">
          <slot name="actions" />
        </div>
      </div>
    </header>

    <div v-if="metrics.length" class="business-workspace-header__metrics" aria-label="业务概览">
      <article v-for="metric in metrics" :key="metric.label">
        <div
          class="business-workspace-header__metric-icon"
          :class="`is-${metric.tone ?? 'primary'}`"
        >
          <ArtSvgIcon :icon="metric.icon" />
        </div>
        <div class="business-workspace-header__metric-copy">
          <span>{{ metric.label }}</span>
          <strong>{{ metric.value }}</strong>
          <small>{{ metric.description }}</small>
        </div>
      </article>
    </div>
  </section>
</template>

<script setup lang="ts">
  import type { TagProps } from 'element-plus'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  export interface BusinessWorkspaceTag {
    label: string
    type?: TagProps['type']
    effect?: TagProps['effect']
  }

  export interface BusinessWorkspaceMetric {
    label: string
    value: string | number
    description: string
    icon: string
    tone?: 'primary' | 'success' | 'warning' | 'danger' | 'info'
  }

  withDefaults(
    defineProps<{
      title: string
      description: string
      icon: string
      eyebrow?: string
      tags?: BusinessWorkspaceTag[]
      metrics?: BusinessWorkspaceMetric[]
    }>(),
    {
      eyebrow: 'BUSINESS OPERATIONS',
      tags: () => [],
      metrics: () => []
    }
  )
</script>

<style lang="scss">
  .business-workspace-page {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;

    > .art-table-query,
    > .el-tabs,
    > .business-workspace-content {
      flex: 1;
      min-height: 0;
    }
  }
</style>

<style scoped lang="scss">
  .business-workspace-header {
    flex: 0 0 auto;
    min-width: 0;
    overflow: hidden;

    &__hero,
    &__identity,
    &__aside,
    &__tags,
    &__actions,
    &__metrics article,
    &__brand,
    &__metric-icon {
      display: flex;
      align-items: center;
    }

    &__hero {
      gap: 20px;
      justify-content: space-between;
      padding: 20px 24px 18px;
      background:
        linear-gradient(115deg, transparent 62%, var(--el-color-primary-light-9)),
        radial-gradient(circle at 84% 0%, var(--el-color-success-light-9), transparent 34%);
    }

    &__identity,
    &__copy {
      min-width: 0;
    }

    &__copy {
      > span {
        display: block;
        margin-bottom: 3px;
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.14em;
      }

      h1 {
        margin: 0 0 3px;
        font-size: 22px;
        line-height: 1.35;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__brand {
      flex: 0 0 50px;
      justify-content: center;
      width: 50px;
      height: 50px;
      margin-right: 16px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), var(--el-color-primary-dark-2));
      border-radius: var(--custom-radius);

      :deep(svg) {
        width: 23px;
        height: 23px;
      }
    }

    &__aside {
      flex: none;
      flex-direction: column;
      gap: 10px;
      align-items: flex-end;
    }

    &__tags,
    &__actions {
      flex: none;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      border-top: 1px solid var(--el-border-color-lighter);

      article {
        gap: 12px;
        min-width: 0;
        padding: 14px 24px;

        &:not(:last-child) {
          border-right: 1px solid var(--el-border-color-lighter);
        }
      }
    }

    &__metric-copy {
      display: grid;
      min-width: 0;

      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      strong {
        margin: 1px 0;
        font-size: 20px;
        font-variant-numeric: tabular-nums;
        line-height: 1.25;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 11px;
      }
    }

    &__metric-icon {
      flex: 0 0 38px;
      justify-content: center;
      width: 38px;
      height: 38px;
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 18px;
        height: 18px;
      }

      &.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
      }

      &.is-danger {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
      }

      &.is-info {
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
      }
    }

    @media (width <= 900px) {
      &__hero {
        align-items: flex-start;
      }

      &__aside {
        flex-direction: column;
        align-items: flex-end;
      }

      &__metrics article {
        padding-inline: 16px;
      }
    }

    @media (width <= 640px) {
      &__hero {
        flex-direction: column;
        padding: 18px;
      }

      &__aside {
        align-items: flex-start;
        width: 100%;
        margin-left: 66px;
      }

      &__tags,
      &__actions {
        justify-content: flex-start;
      }

      &__metrics {
        grid-template-columns: 1fr;

        article:not(:last-child) {
          border-right: 0;
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }
    }
  }
</style>
