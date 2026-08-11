<template>
  <section class="workflow-business-snapshot" aria-label="审批决策信息">
    <header>
      <div>
        <span>决策信息包</span>
        <strong>{{ snapshot.title }}</strong>
        <small>{{ snapshot.subtitle || snapshot.businessNo || snapshot.businessId }}</small>
      </div>
      <RouterLink
        v-if="snapshot.routePath"
        class="workflow-business-snapshot__source-link"
        :to="snapshot.routePath"
      >
        查看业务原单<ArtSvgIcon icon="ri:arrow-right-up-line" aria-hidden="true" />
      </RouterLink>
    </header>

    <div v-if="snapshot.warnings.length" class="workflow-business-snapshot__warnings">
      <ElAlert
        v-for="warning in snapshot.warnings"
        :key="warning"
        :title="warning"
        type="warning"
        :closable="false"
        show-icon
      />
    </div>

    <div v-if="snapshot.metrics.length" class="workflow-business-snapshot__metrics">
      <article
        v-for="metric in snapshot.metrics"
        :key="metric.label"
        :class="`is-${metric.tone || 'primary'}`"
      >
        <small>{{ metric.label }}</small>
        <strong>{{ metric.value }}</strong>
      </article>
    </div>

    <dl v-if="snapshot.fields.length">
      <div v-for="field in snapshot.fields" :key="field.label">
        <dt>{{ field.label }}</dt>
        <dd>{{ field.value || '—' }}</dd>
      </div>
    </dl>

    <div v-if="snapshot.attachments.length" class="workflow-business-snapshot__attachments">
      <strong>业务附件（{{ snapshot.attachments.length }}）</strong>
      <a
        v-for="attachment in snapshot.attachments"
        :key="`${attachment.name}-${attachment.url}`"
        :href="attachment.url"
        target="_blank"
        rel="noopener noreferrer"
      >
        <ArtSvgIcon icon="ri:attachment-2" aria-hidden="true" />
        <span>{{ attachment.name }}</span>
        <small>{{ attachment.fileSize || attachment.fileType || '' }}</small>
      </a>
    </div>
  </section>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'WorkflowBusinessSnapshot' })

  defineProps<{ snapshot: Api.Workflow.WorkflowBusinessSnapshot }>()
</script>

<style scoped lang="scss">
  .workflow-business-snapshot {
    display: grid;
    gap: 14px;
    min-width: 0;
    padding: 16px;
    background: var(--el-fill-color-extra-light);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: calc(var(--el-border-radius-base) + 2px);

    > header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;

      > div {
        display: grid;
        gap: 3px;
        min-width: 0;
      }

      span,
      small {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    &__warnings {
      display: grid;
      gap: 8px;
    }

    &__source-link {
      display: inline-flex;
      flex: none;
      gap: 4px;
      align-items: center;
      padding: 5px 7px;
      font-size: 13px;
      color: var(--theme-color);
      text-decoration: none;
      border-radius: var(--el-border-radius-small);
      transition:
        color 0.18s ease,
        background-color 0.18s ease,
        box-shadow 0.18s ease;

      &:hover,
      &:focus-visible {
        background: color-mix(in srgb, var(--theme-color) 8%, transparent);
      }

      &:focus-visible {
        outline: none;
        box-shadow: var(--art-themed-action-focus-shadow);
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
      gap: 10px;

      article {
        display: grid;
        gap: 5px;
        min-width: 0;
        padding: 11px 12px;
        background: var(--el-bg-color);
        border-left: 3px solid var(--el-color-primary);
        border-radius: var(--el-border-radius-base);

        &.is-success {
          border-left-color: var(--el-color-success);
        }

        &.is-warning {
          border-left-color: var(--el-color-warning);
        }

        &.is-danger {
          border-left-color: var(--el-color-danger);
        }

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }
      }
    }

    dl {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 1px;
      margin: 0;
      overflow: hidden;
      background: var(--el-border-color-lighter);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      div {
        display: grid;
        grid-template-columns: 90px minmax(0, 1fr);
        gap: 8px;
        padding: 10px 12px;
        background: var(--el-bg-color);
      }

      dt {
        color: var(--el-text-color-secondary);
      }

      dd {
        min-width: 0;
        margin: 0;
        color: var(--el-text-color-primary);
        overflow-wrap: anywhere;
      }
    }

    &__attachments {
      display: grid;
      gap: 8px;

      > strong {
        font-size: 13px;
      }

      a {
        display: flex;
        gap: 8px;
        align-items: center;
        min-width: 0;
        padding: 9px 10px;
        color: var(--el-color-primary);
        background: var(--el-bg-color);
        border: 1px solid transparent;
        border-radius: var(--el-border-radius-base);
        transition:
          background-color 0.18s ease,
          border-color 0.18s ease,
          box-shadow 0.18s ease;

        &:hover,
        &:focus-visible {
          background: color-mix(in srgb, var(--theme-color) 6%, var(--el-bg-color));
          border-color: color-mix(in srgb, var(--theme-color) 18%, transparent);
        }

        &:focus-visible {
          outline: none;
          box-shadow: var(--art-themed-action-focus-shadow);
        }

        span {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }
    }
  }

  @media (width <= 640px) {
    .workflow-business-snapshot dl {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
