<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <div v-if="detail" class="ai-run-detail">
      <section class="ai-run-detail__hero">
        <div class="ai-run-detail__hero-icon">
          <ArtSvgIcon icon="ri:brain-2-line" />
        </div>
        <div class="ai-run-detail__hero-copy">
          <div>
            <ArtDictDisplay dict-code="aiRunFeature" :value="detail.feature" display="text" />
            <ArtDictDisplay dict-code="aiRunStatus" :value="detail.status" display="tag" />
          </div>
          <strong>{{ detail.model }}</strong>
          <span>{{ detail.id }}</span>
        </div>
      </section>

      <section class="ai-run-detail__metrics">
        <div>
          <span>总耗时</span>
          <strong>{{ formatDuration(detail.latencyMs) }}</strong>
        </div>
        <div>
          <span>输入 Token</span>
          <strong>{{ formatNumber(detail.inputTokens) }}</strong>
        </div>
        <div>
          <span>输出 Token</span>
          <strong>{{ formatNumber(detail.outputTokens) }}</strong>
        </div>
        <div>
          <span>工具调用</span>
          <strong>{{ detail.toolCallDetails.length }}</strong>
        </div>
      </section>

      <ArtSectionTitle title="运行信息" />
      <ElDescriptions :column="2" border class="ai-run-detail__descriptions">
        <ElDescriptionsItem label="功能场景">
          <ArtDictDisplay dict-code="aiRunFeature" :value="detail.feature" display="text" />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="运行状态">
          <ArtDictDisplay dict-code="aiRunStatus" :value="detail.status" display="tag" />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="开始时间">{{
          formatDateTime(detail.startedAt)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="结束时间">
          {{ formatDateTime(detail.finishedAt) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="提示词版本">{{
          detail.promptVersion || '--'
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="执行模式">{{ executionMode }}</ElDescriptionsItem>
        <ElDescriptionsItem label="创建用户">{{ detail.createBy || '--' }}</ElDescriptionsItem>
        <ElDescriptionsItem label="用户反馈">{{ feedbackLabel }}</ElDescriptionsItem>
      </ElDescriptions>

      <template v-if="detail.errorCode || detail.errorMessage">
        <ArtSectionTitle title="失败诊断" />
        <div class="ai-run-detail__error">
          <div>
            <ArtSvgIcon icon="ri:error-warning-line" />
            <strong>{{ detail.errorCode || 'server_error' }}</strong>
          </div>
          <p>{{ detail.errorMessage || '未记录错误详情' }}</p>
        </div>
      </template>

      <template v-if="detail.toolCallDetails.length">
        <ArtSectionTitle title="工具调用" />
        <div class="ai-run-detail__tools">
          <article v-for="tool in detail.toolCallDetails" :key="tool.id">
            <header>
              <div>
                <ArtSvgIcon icon="ri:function-line" />
                <strong>{{ tool.toolName }}</strong>
              </div>
              <div>
                <span>{{ formatDuration(tool.latencyMs) }}</span>
                <ElTag :type="tool.status === 'succeeded' ? 'success' : 'danger'" size="small">
                  {{ tool.status === 'succeeded' ? '成功' : '失败' }}
                </ElTag>
              </div>
            </header>
            <ElCollapse>
              <ElCollapseItem title="查看调用参数与结果摘要">
                <div class="ai-run-detail__json-grid">
                  <div
                    ><span>调用参数</span><pre>{{ formatJson(tool.arguments) }}</pre>
                  </div>
                  <div
                    ><span>结果摘要</span><pre>{{ formatJson(tool.resultSummary) }}</pre>
                  </div>
                </div>
              </ElCollapseItem>
            </ElCollapse>
          </article>
        </div>
      </template>

      <template v-if="detail.messages.length">
        <ArtSectionTitle title="对话记录" />
        <div class="ai-run-detail__messages">
          <article
            v-for="message in detail.messages"
            :key="message.id"
            :class="{ 'is-user': message.role === 'user' }"
          >
            <div class="ai-run-detail__message-avatar">
              <ArtSvgIcon
                :icon="message.role === 'user' ? 'ri:user-3-line' : 'ri:sparkling-2-fill'"
              />
            </div>
            <div>
              <header>
                <strong>{{ message.role === 'user' ? '用户' : 'AI 助手' }}</strong>
                <time>{{ formatDateTime(message.createTime) }}</time>
              </header>
              <p>{{ message.content }}</p>
            </div>
          </article>
        </div>
      </template>

      <ArtSectionTitle title="上下文与元数据" />
      <ElCollapse class="ai-run-detail__metadata">
        <ElCollapseItem title="页面上下文">
          <pre>{{ formatJson(detail.conversation?.context ?? {}) }}</pre>
        </ElCollapseItem>
        <ElCollapseItem title="运行元数据">
          <pre>{{ formatJson(detail.metadata) }}</pre>
        </ElCollapseItem>
      </ElCollapse>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchAiRunDetail, type AiRunDetail } from '@/api/ai-operations'

  defineOptions({ name: 'AiRunDetailDrawer' })

  interface OpenData {
    id: string
  }

  const drawerRef = ref<ArtDrawerExpose<OpenData>>()
  const detail = shallowRef<AiRunDetail>()

  const executionMode = computed(() => {
    const value = detail.value?.metadata?.executionMode
    return typeof value === 'string' ? value : '--'
  })
  const feedbackLabel = computed(() => {
    const rating = detail.value?.feedback?.[0]?.rating
    if (rating === 1) return '有帮助'
    if (rating === -1) return '需要改进'
    return '暂无反馈'
  })

  async function handleOpen(data: OpenData): Promise<void> {
    detail.value = undefined
    await drawerRef.value?.handleOpen(data, {
      title: 'AI 运行详情',
      size: '760px',
      showFooter: false,
      contentHeight: 'calc(100vh - 78px)',
      loading: true,
      drawerProps: {
        appendToBody: true,
        closeOnClickModal: false,
        resizable: true
      },
      onOpen: async (openData, api) => {
        api.setLoading(true)
        try {
          detail.value = await fetchAiRunDetail(openData.id)
        } finally {
          api.setLoading(false)
        }
      },
      onReset: () => {
        detail.value = undefined
      }
    })
  }

  function formatDuration(value?: number | null): string {
    if (!value && value !== 0) return '--'
    return value >= 1000 ? `${(value / 1000).toFixed(value >= 10_000 ? 1 : 2)} s` : `${value} ms`
  }

  function formatNumber(value?: number | null): string {
    return Number(value ?? 0).toLocaleString('zh-CN')
  }

  function formatDateTime(value?: string | null): string {
    return value ? dayjs(value).format('YYYY-MM-DD HH:mm:ss') : '--'
  }

  function formatJson(value: unknown): string {
    return JSON.stringify(value ?? {}, null, 2)
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .ai-run-detail {
    display: grid;
    gap: 18px;
    padding-bottom: 24px;

    &__hero {
      display: flex;
      gap: 14px;
      align-items: center;
      padding: 18px;
      background: linear-gradient(135deg, var(--el-color-primary-light-9), var(--el-bg-color));
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: var(--el-border-radius-base);
    }

    &__hero-icon,
    &__message-avatar {
      display: grid;
      flex-shrink: 0;
      place-items: center;
    }

    &__hero-icon {
      width: 48px;
      height: 48px;
      font-size: 23px;
      color: var(--el-color-white);
      background: linear-gradient(145deg, var(--el-color-primary), #7259e7);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 10px 24px rgb(64 116 255 / 22%);
    }

    &__hero-copy {
      display: grid;
      gap: 5px;
      min-width: 0;

      > div {
        display: flex;
        gap: 8px;
        align-items: center;
      }

      > strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 16px;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }

      > span {
        font-family: Consolas, monospace;
        font-size: 11px;
        color: var(--el-text-color-placeholder);
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;

      > div {
        display: grid;
        gap: 6px;
        padding: 14px;
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      span {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 17px;
        color: var(--el-text-color-primary);
      }
    }

    &__descriptions {
      :deep(.el-descriptions__label) {
        width: 112px;
      }
    }

    &__error {
      padding: 14px 16px;
      color: var(--el-color-danger);
      background: var(--el-color-danger-light-9);
      border: 1px solid var(--el-color-danger-light-7);
      border-radius: var(--el-border-radius-base);

      > div {
        display: flex;
        gap: 7px;
        align-items: center;
      }

      p {
        margin: 8px 0 0;
        line-height: 1.7;
        overflow-wrap: anywhere;
      }
    }

    &__tools {
      display: grid;
      gap: 10px;

      > article {
        padding: 13px 15px;
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);

        > header,
        > header > div {
          display: flex;
          gap: 8px;
          align-items: center;
          justify-content: space-between;
        }
      }
    }

    &__json-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;

      span {
        display: block;
        margin-bottom: 6px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }
    }

    &__messages {
      display: grid;
      gap: 14px;

      > article {
        display: flex;
        gap: 10px;

        &.is-user {
          .ai-run-detail__message-avatar {
            color: var(--el-color-primary);
            background: var(--el-color-primary-light-9);
          }
        }

        > div:last-child {
          min-width: 0;
        }

        header {
          display: flex;
          gap: 9px;
          align-items: center;
          margin-bottom: 5px;

          time {
            font-size: 10px;
            color: var(--el-text-color-placeholder);
          }
        }

        p {
          padding: 10px 12px;
          margin: 0;
          line-height: 1.7;
          overflow-wrap: anywhere;
          white-space: pre-wrap;
          background: var(--el-fill-color-lighter);
          border-radius: var(--el-border-radius-base);
        }
      }
    }

    &__message-avatar {
      width: 30px;
      height: 30px;
      color: #7259e7;
      background: color-mix(in srgb, #7259e7 10%, var(--el-bg-color));
      border-radius: var(--el-border-radius-small);
    }

    pre {
      max-width: 100%;
      padding: 12px;
      margin: 0;
      overflow: auto;
      font-family: Consolas, monospace;
      font-size: 11px;
      line-height: 1.6;
      color: var(--el-text-color-regular);
      white-space: pre-wrap;
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);
    }

    @media (width <= 640px) {
      &__metrics,
      &__json-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__descriptions {
        :deep(.el-descriptions__body .el-descriptions__table) {
          table-layout: auto;
        }
      }
    }
  }
</style>
