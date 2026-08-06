<template>
  <ArtDrawer ref="drawerRef" class="project-assistant-history" size="sm" :show-footer="false">
    <div class="project-assistant-history__toolbar">
      <ElInput
        :model-value="query"
        clearable
        placeholder="搜索会话标题"
        @update:model-value="emit('update:query', String($event))"
        @input="emit('search')"
      >
        <template #prefix><ArtSvgIcon icon="ri:search-line" /></template>
      </ElInput>
    </div>

    <ArtAsyncState
      :loading="loading"
      :loading-mode="items.length ? 'mask' : 'skeleton'"
      :error="error"
      :empty="!loading && !error && !items.length"
      empty-text="暂无项目助手会话"
      min-height="320px"
      @retry="emit('retry')"
    >
      <ElScrollbar class="project-assistant-history__scroll">
        <div class="project-assistant-history__list">
          <article
            v-for="item in items"
            :key="item.id"
            :class="{ 'is-active': item.id === activeId }"
            @click="emit('select', item.id)"
          >
            <header>
              <strong>{{ item.title || '未命名会话' }}</strong>
              <ElButton
                text
                circle
                size="small"
                aria-label="重命名会话"
                @click.stop="emit('rename', item)"
              >
                <ArtSvgIcon icon="ri:edit-line" />
              </ElButton>
            </header>
            <p>{{ item.lastMessage?.content || '暂无消息摘要' }}</p>
            <footer>
              <span>{{ formatHistoryTime(item.updateTime) }}</span>
              <span v-if="item.lastRun">
                {{ item.lastRun.model }} · {{ formatDuration(item.lastRun.latencyMs) }}
              </span>
            </footer>
          </article>
        </div>
      </ElScrollbar>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import type { ProjectAssistantConversationSummary } from '@/types/supabase-ai-assistant'

  defineOptions({ name: 'ProjectAssistantHistoryDrawer' })

  defineProps<{
    query: string
    loading: boolean
    error: string
    items: ProjectAssistantConversationSummary[]
    activeId?: string
  }>()

  const emit = defineEmits<{
    'update:query': [value: string]
    search: []
    retry: []
    select: [conversationId: string]
    rename: [item: ProjectAssistantConversationSummary]
  }>()

  const drawerRef = ref<ArtDrawerExpose>()

  function formatDuration(value?: number | null): string {
    if (value == null) return '-'
    return value < 1000 ? `${value}ms` : `${(value / 1000).toFixed(1)}s`
  }

  function formatHistoryTime(value?: string): string {
    if (!value) return '-'
    return new Intl.DateTimeFormat('zh-CN', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    }).format(new Date(value))
  }

  async function handleOpen(): Promise<void> {
    await drawerRef.value?.handleOpen(undefined, {
      title: '会话历史',
      size: 'sm',
      showFooter: false,
      contentHeight: 'calc(100vh - 90px)',
      drawerProps: { appendToBody: true }
    })
  }

  function handleClose(): void {
    drawerRef.value?.handleClose()
  }

  defineExpose({ handleOpen, handleClose })
</script>

<style scoped lang="scss">
  :global(.project-assistant-history .el-drawer__header) {
    padding-bottom: var(--art-space-3);
    margin-bottom: 0;
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  :global(.project-assistant-history .el-drawer__body) {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-3);
    min-height: 0;
    padding-top: var(--art-space-3);
  }

  .project-assistant-history {
    &__toolbar {
      flex: 0 0 auto;
    }

    &__scroll {
      height: 100%;
    }

    &__list {
      display: flex;
      flex-direction: column;
      gap: var(--art-space-2);

      article {
        padding: var(--art-space-3);
        cursor: pointer;
        background: var(--el-fill-color-blank);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--art-surface-radius);
        transition: var(--el-transition-duration-fast);

        &:hover,
        &.is-active {
          background: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-6);
        }

        &.is-active {
          box-shadow: inset 3px 0 0 var(--el-color-primary);
        }

        header,
        footer {
          display: flex;
          gap: var(--art-space-2);
          align-items: center;
          justify-content: space-between;
        }

        header strong {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        p {
          display: -webkit-box;
          margin: var(--art-space-2) 0;
          overflow: hidden;
          -webkit-line-clamp: 2;
          font-size: 13px;
          color: var(--el-text-color-regular);
          -webkit-box-orient: vertical;
        }

        footer {
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }
    }
  }

  :deep(.art-async-state) {
    flex: 1;
    min-height: 0 !important;
  }
</style>
