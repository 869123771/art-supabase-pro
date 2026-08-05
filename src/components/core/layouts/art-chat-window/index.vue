<template>
  <ArtDrawer
    ref="drawerRef"
    :show-footer="false"
    :drawer-props="drawerProps"
    @opened="scrollToBottom"
  >
    <template #header="{ api }">
      <header class="art-ai-assistant__header" :class="{ 'is-project-mode': isProjectMode }">
        <div class="art-ai-assistant__identity">
          <div class="art-ai-assistant__brand-icon">
            <ArtSvgIcon :icon="assistantIcon" />
          </div>
          <div class="art-ai-assistant__identity-copy">
            <div class="art-ai-assistant__title-row">
              <strong>{{ assistantTitle }}</strong>
              <span>只读模式</span>
            </div>
            <div class="art-ai-assistant__status">
              <span class="art-ai-assistant__connection">
                <i :class="{ 'is-offline': !isOnline }"></i>
                {{ isOnline ? '服务已连接' : '网络已断开' }}
              </span>
              <em>·</em>
              <span class="art-ai-assistant__page">{{ pageTitle }}</span>
            </div>
          </div>
        </div>

        <div class="art-ai-assistant__header-actions">
          <ElSegmented
            v-if="userStore.isPlatformSuper"
            v-model="assistantMode"
            :options="assistantModeOptions"
            size="small"
            class="art-ai-assistant__mode-switch"
          />
          <ElTooltip v-if="isProjectMode" content="进入 Supabase AI 工作台" placement="bottom">
            <ArtIconButton
              icon="ri:fullscreen-line"
              circle
              aria-label="进入 Supabase AI 工作台"
              class="art-ai-assistant__header-button"
              @click="openProjectWorkbench"
            />
          </ElTooltip>
          <ElTooltip content="新建对话" placement="bottom">
            <ArtIconButton
              icon="ri:chat-new-line"
              circle
              aria-label="新建对话"
              class="art-ai-assistant__header-button"
              @click="resetConversation"
            />
          </ElTooltip>
          <ElTooltip content="关闭" placement="bottom">
            <ArtIconButton
              icon="ri:close-line"
              circle
              :aria-label="`关闭 ${assistantTitle}`"
              class="art-ai-assistant__header-button"
              @click="api.handleClose()"
            />
          </ElTooltip>
        </div>
      </header>
    </template>

    <div class="art-ai-assistant" :class="{ 'is-project-mode': isProjectMode }">
      <ElScrollbar ref="scrollbarRef" class="art-ai-assistant__messages">
        <div class="art-ai-assistant__conversation">
          <section v-if="showWelcome" class="art-ai-assistant__welcome">
            <div class="art-ai-assistant__welcome-mark">
              <ArtSvgIcon :icon="assistantIcon" />
            </div>
            <span class="art-ai-assistant__eyebrow">{{ assistantEyebrow }}</span>
            <h2>{{ welcomeTitle }}</h2>
            <p>{{ welcomeDescription }}</p>
            <div class="art-ai-assistant__context-pill">
              <ArtSvgIcon icon="ri:focus-3-line" />
              <span>正在关注</span>
              <strong>{{ pageTitle }}</strong>
            </div>

            <div class="art-ai-assistant__prompt-grid">
              <button
                v-for="suggestion in suggestions"
                :key="suggestion.label"
                type="button"
                class="art-ai-assistant__prompt-card"
                :disabled="!isOnline"
                @click="sendSuggestion(suggestion.label)"
              >
                <span class="art-ai-assistant__prompt-icon">
                  <ArtSvgIcon :icon="suggestion.icon" />
                </span>
                <span>
                  <strong>{{ suggestion.label }}</strong>
                  <small>{{ suggestion.description }}</small>
                </span>
                <ArtSvgIcon icon="ri:arrow-right-up-line" />
              </button>
            </div>

            <div class="art-ai-assistant__capabilities">
              <span><ArtSvgIcon icon="ri:shield-check-line" /> 权限隔离</span>
              <span><ArtSvgIcon icon="ri:database-2-line" /> {{ dataCapabilityLabel }}</span>
              <span><ArtSvgIcon icon="ri:eye-line" /> 不修改数据</span>
            </div>
          </section>

          <template v-else>
            <article
              v-for="message in state.messages"
              :key="message.id"
              class="art-ai-assistant__message"
              :class="{
                'is-user': message.role === 'user',
                'is-error': message.isError
              }"
            >
              <ElAvatar
                v-if="message.role === 'user'"
                :size="32"
                :src="userAvatar"
                class="art-ai-assistant__avatar"
              />
              <div v-else class="art-ai-assistant__assistant-avatar">
                <ArtSvgIcon :icon="assistantIcon" />
              </div>

              <div class="art-ai-assistant__message-body">
                <div class="art-ai-assistant__message-meta">
                  <span>{{ message.role === 'user' ? userName : assistantTitle }}</span>
                  <time>{{ message.time }}</time>
                </div>
                <div class="art-ai-assistant__bubble">{{ message.content }}</div>

                <div v-if="message.tools?.length" class="art-ai-assistant__tools">
                  <span
                    v-for="tool in message.tools"
                    :key="tool.name"
                    :class="{ 'is-failed': tool.status === 'failed' }"
                  >
                    <ArtSvgIcon
                      :icon="
                        tool.status === 'succeeded' ? 'ri:check-line' : 'ri:error-warning-line'
                      "
                    />
                    {{ tool.status === 'succeeded' ? '已查询' : '查询失败' }} ·
                    {{ getToolLabel(tool.name) }}
                  </span>
                </div>

                <div v-if="message.isError" class="art-ai-assistant__retry">
                  <ElButton
                    size="small"
                    plain
                    :icon="Refresh"
                    :disabled="state.sending || !isOnline"
                    @click="retryMessage(message)"
                  >
                    重新尝试
                  </ElButton>
                </div>

                <div
                  v-else-if="message.role === 'assistant' && message.runId"
                  class="art-ai-assistant__feedback"
                >
                  <ArtAiFeedback
                    :run-id="message.runId"
                    :context-label="assistantTitle"
                    compact
                    @submitted="message.feedback = $event.rating"
                  />
                </div>
              </div>
            </article>

            <article v-if="state.sending" class="art-ai-assistant__message">
              <div class="art-ai-assistant__assistant-avatar">
                <ArtSvgIcon :icon="assistantIcon" />
              </div>
              <div class="art-ai-assistant__message-body">
                <div class="art-ai-assistant__message-meta">
                  <span>{{ assistantTitle }}</span>
                  <span>正在处理</span>
                </div>
                <div class="art-ai-assistant__thinking">
                  <ArtSvgIcon icon="ri:loader-4-line" />
                  <span>{{ thinkingText }}</span>
                </div>
              </div>
            </article>
          </template>
        </div>
      </ElScrollbar>

      <footer class="art-ai-assistant__composer">
        <div class="art-ai-assistant__composer-box">
          <ElInput
            v-model="state.input"
            type="textarea"
            :autosize="{ minRows: 2, maxRows: 6 }"
            :maxlength="4000"
            resize="none"
            :placeholder="composerPlaceholder"
            :disabled="state.sending || !isOnline"
            @keydown.enter.exact.prevent="sendMessage"
          />
          <div class="art-ai-assistant__composer-actions">
            <div class="art-ai-assistant__composer-meta">
              <span><ArtSvgIcon icon="ri:shield-check-line" /> 只读安全模式</span>
              <span>{{ state.input.length }} / 4000</span>
              <span class="art-ai-assistant__keyboard-hint">Shift + Enter 换行</span>
            </div>
            <ElButton
              type="primary"
              :icon="Promotion"
              :loading="state.sending"
              :disabled="!state.input.trim() || !isOnline"
              @click="sendMessage"
            >
              发送
            </ElButton>
          </div>
        </div>
        <p>{{ footerNotice }}</p>
      </footer>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { Promotion, Refresh } from '@element-plus/icons-vue'
  import { useNetwork, useWindowSize } from '@vueuse/core'
  import type { ScrollbarInstance } from 'element-plus'
  import { useRoute, useRouter } from 'vue-router'
  import { chatWithAiAssistant } from '@/api/ai-assistant'
  import { chatWithProjectAssistant } from '@/api/supabase-ai-assistant'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import type {
    AiAssistantMessageRole,
    AiAssistantPageContext,
    AiAssistantToolResult
  } from '@/types/ai-assistant'
  import { mittBus } from '@/utils/sys'
  import meAvatar from '@/assets/images/avatar/avatar5.webp'

  defineOptions({ name: 'ArtChatWindow' })

  interface ChatMessage {
    id: string
    role: AiAssistantMessageRole
    content: string
    time: string
    runId?: string
    tools?: AiAssistantToolResult[]
    feedback?: -1 | 1
    isError?: boolean
    retryContent?: string
  }

  interface AssistantState {
    sending: boolean
    input: string
    conversationId?: string
    routePath?: string
    messages: ChatMessage[]
  }

  interface PromptSuggestion {
    label: string
    description: string
    icon: string
  }

  const MOBILE_BREAKPOINT = 640
  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { width } = useWindowSize()
  const { isOnline } = useNetwork()
  const drawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const scrollbarRef = ref<ScrollbarInstance>()
  const isMobile = computed(() => width.value < MOBILE_BREAKPOINT)
  const assistantMode = ref<'business' | 'project'>('business')
  const assistantModeOptions = [
    { label: '业务助手', value: 'business' },
    { label: 'Supabase', value: 'project' }
  ]
  const isProjectMode = computed(() => assistantMode.value === 'project')
  const assistantTitle = computed(() => (isProjectMode.value ? 'Supabase 管理助手' : 'AI 业务助理'))
  const assistantIcon = computed(() =>
    isProjectMode.value ? 'ri:database-2-line' : 'ri:sparkling-2-fill'
  )
  const assistantEyebrow = computed(() =>
    isProjectMode.value ? 'SUPABASE PROJECT COPILOT' : 'ART BUSINESS COPILOT'
  )
  const welcomeTitle = computed(() =>
    isProjectMode.value ? '想了解项目里的什么？' : '今天想了解什么？'
  )
  const welcomeDescription = computed(() =>
    isProjectMode.value
      ? '我可以只读查看数据库对象、DDL、外键关系和 Edge Function 元数据，并生成变更方案。'
      : '我会结合当前页面和你的数据权限，查询订单、运输经营情况与车辆临期事项。'
  )
  const dataCapabilityLabel = computed(() =>
    isProjectMode.value ? '项目实时元数据' : '实时业务数据'
  )
  const thinkingText = computed(() =>
    isProjectMode.value ? '正在读取并分析项目元数据…' : '正在查询并整理业务数据…'
  )
  const composerPlaceholder = computed(() =>
    isProjectMode.value
      ? '询问数据库、函数、RLS 或 Edge Function，Enter 发送'
      : '输入业务问题，Enter 发送，Shift + Enter 换行'
  )
  const footerNotice = computed(() =>
    isProjectMode.value
      ? '当前为只读安全模式：不会执行 DDL、DML 或任意 SQL。'
      : 'AI 生成内容可能存在偏差，关键业务信息请以系统记录为准。'
  )
  const drawerProps = {
    appendToBody: true,
    closeOnClickModal: false,
    showClose: false,
    class: 'art-ai-assistant-drawer'
  }
  const pageTitle = computed(() => {
    const title = route.meta.title
    if (typeof title === 'string' && title) return title
    return typeof route.name === 'string' ? route.name : '当前页面'
  })
  const userName = computed(
    () =>
      userStore.getUserInfo.nickName ||
      userStore.getUserInfo.userName ||
      userStore.getUserInfo.email ||
      '当前用户'
  )
  const userAvatar = computed(() => userStore.getUserInfo.avatar || meAvatar)
  const state = reactive<AssistantState>({
    sending: false,
    input: '',
    conversationId: undefined,
    routePath: undefined,
    messages: []
  })

  const suggestions = computed<PromptSuggestion[]>(() => {
    if (isProjectMode.value) {
      return [
        {
          label: '概览当前 Supabase 项目',
          description: '统计数据库对象和项目能力',
          icon: 'ri:dashboard-3-line'
        },
        {
          label: '列出 public schema 的表',
          description: '查看表、说明和对象目录',
          icon: 'ri:table-2'
        },
        {
          label: '检查 RLS 策略概况',
          description: '查看策略对象并提示安全风险',
          icon: 'ri:shield-keyhole-line'
        },
        {
          label: '列出项目 Edge Functions',
          description: '查看函数状态和 JWT 校验配置',
          icon: 'ri:cloud-line'
        }
      ]
    }
    const items: PromptSuggestion[] = [
      {
        label: '总结最近订单',
        description: '查看最新订单、线路、状态和费用',
        icon: 'ri:file-list-3-line'
      },
      {
        label: '查看近 30 天运输概览',
        description: '汇总订单量、状态分布与费用',
        icon: 'ri:line-chart-line'
      },
      {
        label: '查询 30 天内车辆到期事项',
        description: '检查保险、年检和服务期限',
        icon: 'ri:alarm-warning-line'
      }
    ]
    if (getRecordId()) {
      items.unshift({
        label: '总结当前订单',
        description: '基于当前记录提炼关键信息',
        icon: 'ri:focus-3-line'
      })
    } else {
      items.unshift({
        label: '这个页面可以做什么？',
        description: '了解当前页面和可用能力',
        icon: 'ri:compass-3-line'
      })
    }
    return items
  })
  const showWelcome = computed(() => state.messages.length === 0 && !state.sending)

  function formatCurrentTime(): string {
    return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  }

  function getRecordId(): string | undefined {
    const candidate = route.params.id ?? route.query.id
    if (Array.isArray(candidate)) return candidate[0]
    return typeof candidate === 'string' && candidate ? candidate : undefined
  }

  function getPageContext(): AiAssistantPageContext {
    return {
      routeName: typeof route.name === 'string' ? route.name : undefined,
      routePath: route.path,
      pageTitle: pageTitle.value,
      recordId: getRecordId(),
      query: { ...route.query }
    }
  }

  function scrollToBottom(): void {
    nextTick(() => scrollbarRef.value?.setScrollTop(Number.MAX_SAFE_INTEGER))
  }

  function resetConversation(): void {
    Object.assign(state, {
      sending: false,
      input: '',
      conversationId: undefined,
      routePath: route.fullPath,
      messages: []
    })
    scrollToBottom()
  }

  async function openProjectWorkbench(): Promise<void> {
    await drawerRef.value?.handleClose()
    await router.push('/data-center/supabase-ai-assistant')
  }

  function openChat(): void {
    if (state.routePath && state.routePath !== route.fullPath) resetConversation()
    state.routePath = route.fullPath
    void drawerRef.value?.handleOpen(
      {},
      {
        size: isMobile.value ? '100%' : userStore.isPlatformSuper ? '680px' : '600px',
        showFooter: false,
        resetOnClose: false,
        drawerProps
      }
    )
  }

  function sendSuggestion(suggestion: string): void {
    state.input = suggestion
    void sendMessage()
  }

  function retryMessage(message: ChatMessage): void {
    if (!message.retryContent || state.sending) return
    state.messages = state.messages.filter((item) => item.id !== message.id)
    state.input = message.retryContent
    void sendMessage()
  }

  async function sendMessage(): Promise<void> {
    const content = state.input.trim()
    if (!content || state.sending || !isOnline.value) return

    state.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content,
      time: formatCurrentTime()
    })
    state.input = ''
    state.sending = true
    scrollToBottom()

    try {
      const chat = isProjectMode.value ? chatWithProjectAssistant : chatWithAiAssistant
      const response = await chat({
        conversationId: state.conversationId,
        context: getPageContext(),
        messages: state.messages
          .filter((message) => !message.isError)
          .map((message) => ({ role: message.role, content: message.content }))
      })
      state.conversationId = response.conversationId
      state.messages.push({
        id: crypto.randomUUID(),
        role: 'assistant',
        content: response.message,
        time: formatCurrentTime(),
        runId: response.runId,
        tools: response.tools
      })
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'AI 助手暂时不可用'
      state.messages.push({
        id: crypto.randomUUID(),
        role: 'assistant',
        content: getFriendlyErrorMessage(errorMessage),
        time: formatCurrentTime(),
        isError: true,
        retryContent: content
      })
    } finally {
      state.sending = false
      scrollToBottom()
    }
  }

  function getFriendlyErrorMessage(message: string): string {
    if (message.includes('超时') || message.toLowerCase().includes('timeout')) {
      return '这次请求没有在规定时间内完成。高频业务查询已启用快速通道，你可以重新尝试。'
    }
    return `暂时无法完成这次请求：${message}`
  }

  function getToolLabel(name: string): string {
    const labels: Record<string, string> = {
      get_order_detail: '订单详情',
      get_recent_orders: '最近订单',
      get_transport_overview: '运输概览',
      get_vehicle_expiries: '车辆到期',
      get_project_overview: '项目概览',
      list_database_objects: '数据库对象',
      get_database_object_detail: '对象定义',
      get_table_relationships: '外键关系',
      list_edge_functions: 'Edge Functions'
    }
    return labels[name] ?? name
  }

  watch(
    () => route.fullPath,
    (path) => {
      if (state.routePath && state.routePath !== path) resetConversation()
    }
  )
  watch(assistantMode, resetConversation)
  onMounted(() => mittBus.on('openChat', openChat))
  onUnmounted(() => mittBus.off('openChat', openChat))
</script>

<style scoped lang="scss">
  :global(.art-ai-assistant-drawer .el-drawer__header) {
    position: relative;
    z-index: 2;
    padding: 0;
    margin-bottom: 0;
    border-bottom: 1px solid var(--el-border-color-lighter);
    box-shadow: 0 4px 18px rgb(31 45 61 / 4%);
  }

  :global(.art-ai-assistant-drawer .el-drawer__body) {
    padding: 0;
  }

  :global(.art-ai-assistant-drawer .art-drawer__content) {
    height: 100%;
  }

  :global(.art-ai-assistant-drawer) {
    border-left: 1px solid var(--el-border-color-extra-light);
    box-shadow: -18px 0 55px rgb(22 34 51 / 16%) !important;
  }

  .art-ai-assistant {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    background:
      radial-gradient(circle at 92% 2%, var(--el-color-primary-light-8), transparent 28%),
      linear-gradient(180deg, var(--el-color-primary-light-9), transparent 190px),
      var(--el-bg-color);

    &__header {
      display: flex;
      gap: 18px;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      min-height: 78px;
      padding: 13px 20px;
      background:
        linear-gradient(105deg, transparent 35%, var(--el-color-primary-light-9)),
        var(--el-bg-color);

      &::after {
        position: absolute;
        right: 28%;
        bottom: -1px;
        left: 28%;
        height: 1px;
        pointer-events: none;
        content: '';
        background: linear-gradient(
          90deg,
          transparent,
          var(--el-color-primary-light-6),
          transparent
        );
      }
    }

    &__identity,
    &__title-row,
    &__status,
    &__header-actions,
    &__tools,
    &__feedback,
    &__composer-actions,
    &__composer-meta,
    &__capabilities,
    &__context-pill,
    &__thinking {
      display: flex;
      align-items: center;
    }

    &__identity {
      gap: 12px;
      min-width: 0;
    }

    &__brand-icon,
    &__welcome-mark,
    &__assistant-avatar,
    &__prompt-icon {
      display: grid;
      flex-shrink: 0;
      place-items: center;
      color: var(--el-color-white);
      background: linear-gradient(145deg, var(--el-color-primary), #7559e8);
    }

    &__brand-icon {
      width: 42px;
      height: 42px;
      font-size: 20px;
      border-radius: var(--el-border-radius-base);
      box-shadow:
        0 8px 22px rgb(64 116 255 / 22%),
        0 0 0 5px var(--el-color-primary-light-9);
    }

    &__identity-copy {
      min-width: 0;
    }

    &__title-row {
      gap: 8px;

      strong {
        font-size: 16px;
        color: var(--el-text-color-primary);
      }

      > span {
        padding: 2px 8px;
        font-size: 10px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border: 1px solid var(--el-color-primary-light-8);
        border-radius: 999px;
      }
    }

    &__status {
      gap: 6px;
      min-width: 0;
      margin-top: 4px;
      font-size: 12px;
      color: var(--el-text-color-secondary);

      em {
        font-style: normal;
        color: var(--el-text-color-placeholder);
      }
    }

    &__connection {
      display: inline-flex;
      gap: 5px;
      align-items: center;

      i {
        box-sizing: content-box;
        width: 7px;
        height: 7px;
        background: var(--el-color-success);
        border: 2px solid var(--el-color-success-light-8);
        border-radius: 50%;

        &.is-offline {
          background: var(--el-color-danger);
          border-color: var(--el-color-danger-light-8);
        }
      }
    }

    &__page {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__header-actions {
      flex-shrink: 0;
      gap: 3px;
    }

    &__header-button {
      font-size: 18px;

      &:hover {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }
    }

    &__mode-switch {
      padding: 3px;
      margin-right: 4px;
      background: var(--el-fill-color-light);
      border: 1px solid var(--el-border-color-extra-light);
      border-radius: var(--el-border-radius-base);

      :deep(.el-segmented__item-selected) {
        box-shadow: 0 4px 12px rgb(64 116 255 / 16%);
      }
    }

    &__messages {
      flex: 1;
      min-height: 0;
    }

    &__conversation {
      min-height: 100%;
      padding: 26px 24px 34px;
    }

    &__welcome {
      display: flex;
      flex-direction: column;
      align-items: center;
      max-width: 536px;
      padding-top: clamp(24px, 6vh, 66px);
      margin: 0 auto;
      text-align: center;

      h2 {
        margin: 10px 0 8px;
        font-size: 26px;
        font-weight: 650;
        color: var(--el-text-color-primary);
        letter-spacing: -0.5px;
      }

      > p {
        max-width: 430px;
        margin: 0;
        line-height: 1.7;
        color: var(--el-text-color-secondary);
      }
    }

    &__welcome-mark {
      position: relative;
      width: 58px;
      height: 58px;
      font-size: 28px;
      border-radius: var(--el-border-radius-base);
      box-shadow:
        0 14px 32px rgb(64 116 255 / 28%),
        0 0 0 9px rgb(64 116 255 / 7%);

      &::before {
        position: absolute;
        inset: -18px;
        z-index: -1;
        content: '';
        background: radial-gradient(circle, var(--el-color-primary-light-8), transparent 70%);
        border: 1px solid var(--el-color-primary-light-8);
        border-radius: 50%;
      }
    }

    &__eyebrow {
      margin-top: 18px;
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.18em;
    }

    &__context-pill {
      gap: 6px;
      max-width: 100%;
      padding: 7px 11px;
      margin-top: 18px;
      font-size: 12px;
      color: var(--el-text-color-regular);
      background: color-mix(in srgb, var(--el-bg-color) 88%, var(--el-color-primary));
      border: 1px solid var(--el-border-color-lighter);
      border-radius: 999px;
      box-shadow: 0 5px 14px rgb(31 45 61 / 5%);

      > svg {
        color: var(--el-color-primary);
      }

      > span {
        color: var(--el-text-color-secondary);
      }

      strong {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__prompt-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 11px;
      width: 100%;
      margin-top: 26px;
    }

    &__prompt-card {
      position: relative;
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 11px;
      align-items: center;
      min-height: 88px;
      padding: 14px 13px;
      overflow: hidden;
      font: inherit;
      color: var(--el-text-color-primary);
      text-align: left;
      cursor: pointer;
      background:
        linear-gradient(125deg, var(--el-color-primary-light-9), transparent 62%),
        var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 5px 16px rgb(31 45 61 / 4%);
      transition:
        border-color 0.2s ease,
        box-shadow 0.2s ease,
        transform 0.2s ease;

      &::before {
        position: absolute;
        top: 0;
        bottom: 0;
        left: 0;
        width: 3px;
        content: '';
        background: linear-gradient(180deg, var(--el-color-primary-light-3), transparent);
        opacity: 0;
        transition: opacity 0.2s ease;
      }

      &:hover:not(:disabled) {
        border-color: var(--el-color-primary-light-5);
        box-shadow: 0 12px 26px rgb(64 116 255 / 12%);
        transform: translateY(-2px);

        &::before {
          opacity: 1;
        }

        > svg,
        > :deep(svg) {
          color: var(--el-color-primary);
          transform: translate(1px, -1px);
        }
      }

      &:disabled {
        cursor: not-allowed;
        opacity: 0.55;
      }

      > span:nth-child(2) {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      strong {
        font-size: 13px;
        line-height: 1.45;
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      > svg,
      > :deep(svg) {
        color: var(--el-text-color-placeholder);
        transition:
          color 0.2s ease,
          transform 0.2s ease;
      }
    }

    &__prompt-icon {
      width: 34px;
      height: 34px;
      font-size: 16px;
      background: linear-gradient(
        145deg,
        var(--el-color-primary-light-8),
        var(--el-color-primary-light-9)
      );
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: var(--el-border-radius-small);

      :deep(svg) {
        color: var(--el-color-primary);
      }
    }

    &__capabilities {
      flex-wrap: wrap;
      gap: 14px;
      justify-content: center;
      margin-top: 24px;
      font-size: 11px;
      color: var(--el-text-color-placeholder);

      span {
        display: inline-flex;
        gap: 4px;
        align-items: center;

        svg {
          color: var(--el-color-primary-light-3);
        }
      }
    }

    &__message {
      display: flex;
      gap: 10px;
      align-items: flex-start;
      margin-bottom: 24px;

      &.is-user {
        flex-direction: row-reverse;

        .art-ai-assistant__message-body {
          align-items: flex-end;
        }

        .art-ai-assistant__bubble {
          color: var(--el-color-white);
          background: linear-gradient(
            145deg,
            var(--el-color-primary-light-3),
            var(--el-color-primary)
          );
          border-color: transparent;
          box-shadow: 0 8px 20px rgb(64 116 255 / 16%);
        }
      }

      &.is-error {
        .art-ai-assistant__bubble {
          color: var(--el-color-danger-dark-2);
          background: var(--el-color-danger-light-9);
          border-color: var(--el-color-danger-light-7);
        }
      }
    }

    &__avatar,
    &__assistant-avatar {
      flex-shrink: 0;
    }

    &__assistant-avatar {
      width: 32px;
      height: 32px;
      font-size: 15px;
      border-radius: var(--el-border-radius-small);
      box-shadow: 0 6px 16px rgb(64 116 255 / 18%);
    }

    &__message-body {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      max-width: min(84%, 470px);
    }

    &__message-meta {
      display: flex;
      gap: 8px;
      align-items: center;
      margin-bottom: 6px;
      font-size: 11px;
      color: var(--el-text-color-secondary);

      span:first-child {
        font-weight: 600;
        color: var(--el-text-color-regular);
      }
    }

    &__bubble {
      padding: 12px 14px;
      line-height: 1.75;
      color: var(--el-text-color-primary);
      overflow-wrap: anywhere;
      white-space: pre-wrap;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 5px 18px rgb(31 45 61 / 5%);
    }

    &__tools {
      flex-wrap: wrap;
      gap: 6px;
      margin-top: 8px;

      > span {
        display: inline-flex;
        gap: 4px;
        align-items: center;
        padding: 4px 8px;
        font-size: 10px;
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
        border-radius: 999px;

        &.is-failed {
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
        }
      }
    }

    &__feedback {
      gap: 2px;
      margin-top: 7px;
      font-size: 10px;
      color: var(--el-text-color-placeholder);
    }

    &__feedback-button {
      font-size: 13px;

      &.is-active {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-negative {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
      }
    }

    &__retry {
      margin-top: 8px;
    }

    &__thinking {
      gap: 8px;
      padding: 11px 13px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      background: linear-gradient(90deg, var(--el-color-primary-light-9), var(--el-bg-color));
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: var(--el-border-radius-base);

      > :deep(svg) {
        color: var(--el-color-primary);
        animation: assistant-rotate 1s linear infinite;
      }
    }

    &__composer {
      position: relative;
      padding: 13px 20px 15px;
      background:
        linear-gradient(180deg, var(--el-color-primary-light-9), transparent 80%),
        var(--el-bg-color);
      border-top: 1px solid var(--el-border-color-lighter);

      &::before {
        position: absolute;
        top: -18px;
        right: 0;
        left: 0;
        height: 18px;
        pointer-events: none;
        content: '';
        background: linear-gradient(transparent, var(--el-bg-color));
      }

      > p {
        margin: 9px 0 0;
        font-size: 10px;
        color: var(--el-text-color-placeholder);
        text-align: center;
      }
    }

    &__composer-box {
      padding: 9px 9px 8px 12px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 9px 28px rgb(31 45 61 / 8%);
      transition:
        border-color 0.2s ease,
        box-shadow 0.2s ease;

      &:focus-within {
        border-color: var(--el-color-primary-light-5);
        box-shadow:
          0 10px 30px rgb(64 116 255 / 12%),
          0 0 0 3px var(--el-color-primary-light-9);
      }

      :deep(.el-textarea__inner) {
        min-height: 60px !important;
        padding: 3px 2px 8px;
        line-height: 1.65;
        background: transparent;
        border: 0;
        box-shadow: none;
      }
    }

    &__composer-actions {
      gap: 12px;
      justify-content: space-between;

      > .el-button {
        min-width: 82px;
        height: 36px;
        margin: 0;
        font-weight: 600;
        border-radius: var(--el-border-radius-base);
        box-shadow: 0 7px 16px rgb(64 116 255 / 20%);
      }
    }

    &__composer-meta {
      gap: 10px;
      min-width: 0;
      font-size: 10px;
      color: var(--el-text-color-placeholder);

      span {
        display: inline-flex;
        gap: 4px;
        align-items: center;
      }
    }

    &__keyboard-hint {
      color: var(--el-text-color-placeholder);
    }
  }

  @keyframes assistant-rotate {
    to {
      transform: rotate(360deg);
    }
  }

  @media (width <= 640px) {
    .art-ai-assistant {
      &__header {
        padding: 12px 14px;
      }

      &__conversation {
        padding: 20px 14px 24px;
      }

      &__prompt-grid {
        grid-template-columns: 1fr;
      }

      &__welcome {
        padding-top: 18px;
      }

      &__composer {
        padding: 12px;
      }

      &__keyboard-hint {
        display: none !important;
      }

      &__message-body {
        max-width: 87%;
      }
    }
  }
</style>
