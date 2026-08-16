<template>
  <ArtPageShell
    class="project-assistant-shell"
    :loading="initialLoading"
    loading-mode="skeleton"
    :error="pageError"
    min-height="720px"
    @retry="loadInitialData"
  >
    <div
      class="project-assistant business-workspace-page art-full-height"
      :class="{ 'is-focus-mode': focusMode }"
    >
      <BusinessWorkspaceHeader
        v-if="!focusMode"
        eyebrow="SUPABASE PROJECT COPILOT"
        title="Supabase AI 助手"
        description="统一洞察 Database、RLS、Auth、Storage、Realtime 与 Edge Functions，并生成可审计的治理方案。"
        icon="ri:database-2-line"
        :tags="[
          {
            label: assistantMode === 'controlled_write' ? '管理员受控变更' : '只读安全模式',
            type: assistantMode === 'controlled_write' ? 'warning' : 'success',
            effect: 'light'
          },
          { label: `项目：${overview?.projectRef || 'ckbftoopuyophiebamwy'}`, type: 'info' }
        ]"
      >
        <template #actions>
          <ElButton plain type="primary" @click="openCapabilityCenter">
            <ArtSvgIcon icon="ri:radar-line" /> 全域能力
          </ElButton>
        </template>
      </BusinessWorkspaceHeader>

      <section v-if="!focusMode" class="project-assistant__stats art-card-xs">
        <button
          v-for="stat in stats"
          :key="stat.type"
          type="button"
          :class="{ 'is-active': filters.objectType === stat.type }"
          :aria-pressed="filters.objectType === stat.type"
          @click="selectStat(stat.type)"
        >
          <span><ArtSvgIcon :icon="stat.icon" /></span>
          <div
            ><strong>{{ stat.value }}</strong
            ><small>{{ stat.label }}</small></div
          >
        </button>
      </section>

      <section class="project-assistant__workspace">
        <ElSplitter class="project-assistant__splitter" lazy>
          <ElSplitterPanel size="280px" min="240px" max="400px" collapsible>
            <ProjectAssistantObjectBrowser
              :focus-mode="focusMode"
              :schemas="schemas"
              :objects="objects"
              :selected-object="selectedObject"
              :filters="filters"
              :loading="loading.objects"
              :load-source="objectLoadSource"
              :error="errors.objects"
              @toggle-focus="toggleFocusMode"
              @refresh="loadObjects('refresh')"
              @filter="loadObjects('filter')"
              @select="selectObject"
              @update:keyword="filters.keyword = $event"
              @update:schema="filters.schema = $event"
              @update:object-type="filters.objectType = $event"
            />
          </ElSplitterPanel>

          <ElSplitterPanel min="380px">
            <ProjectAssistantObjectDetail
              :selected-object="selectedObject"
              :detail="detail"
              :relationships="relationships"
              :loading="loading"
              :errors="errors"
              :assistant-mode="assistantMode"
              :can-edit-description="canEditSelectedDescription"
              :chat-sending="chat.sending"
              @analyze="runObjectAnalysis"
              @edit-description="editObjectDescription"
              @copy-ddl="copyDdl"
              @retry="selectObject"
            />
          </ElSplitterPanel>

          <ElSplitterPanel size="390px" min="320px" max="540px" collapsible>
            <ProjectAssistantChatPanel
              ref="chatPanelRef"
              :chat="chat"
              :active-chat-object="activeChatObject"
              :assistant-status="assistantStatus"
              :assistant-status-label="assistantStatusLabel"
              :assistant-mode="assistantMode"
              :can-use-controlled-write="canUseControlledWrite"
              :chat-phase="chatPhase"
              :chat-suggestions="chatSuggestions"
              :quick-actions="quickActions"
              @open-history="openHistory"
              @export-conversation="exportConversation"
              @reset="resetChat"
              @toggle-context="toggleContextLock"
              @suggest="sendSuggestion"
              @copy-message="copyMessage"
              @retry-message="retryMessage"
              @feedback="handleMessageFeedback"
              @update-input="chat.input = $event"
              @toggle-mode="toggleAssistantMode"
              @send="sendMessage"
              @stop="stopGeneration"
            />
          </ElSplitterPanel>
        </ElSplitter>
      </section>

      <ProjectAssistantHistoryDrawer
        ref="historyDrawerRef"
        v-model:query="history.query"
        :loading="history.loading"
        :error="history.error"
        :items="history.items"
        :active-id="chat.conversationId"
        @search="scheduleHistorySearch"
        @retry="loadHistory"
        @select="restoreConversation"
        @rename="renameConversation"
      />

      <ProjectCapabilityCenterDrawer
        ref="capabilityCenterRef"
        @analyze="analyzePlatformCapability"
      />
    </div>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useStorage } from '@vueuse/core'
  import { ElMessage } from 'element-plus'
  import { updateProjectObjectDescription } from '@/api/supabase-ai-assistant'
  import type {
    ProjectAssistantConversationSummary,
    ProjectAssistantSafetyMode,
    ProjectEdgeFunctionResult,
    ProjectObjectType
  } from '@/types/supabase-ai-assistant'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import ProjectCapabilityCenterDrawer from './modules/capability-center-drawer.vue'
  import ProjectAssistantChatPanel from './modules/project-assistant-chat-panel.vue'
  import ProjectAssistantHistoryDrawer from './modules/project-assistant-history-drawer.vue'
  import ProjectAssistantObjectBrowser from './modules/project-assistant-object-browser.vue'
  import ProjectAssistantObjectDetail from './modules/project-assistant-object-detail.vue'
  import {
    getProjectAssistantStats,
    type ProjectAssistantChatMessage
  } from './modules/project-assistant-presenter'
  import { useProjectAssistantCatalog } from './modules/use-project-assistant-catalog'
  import { useProjectAssistantChat } from './modules/use-project-assistant-chat'

  defineOptions({ name: 'SupabaseAiAssistant' })

  const { promptText, confirmAction } = useArtFeedback()

  interface CapabilityCenterExpose {
    handleOpen: (data: { edgeFunctions: ProjectEdgeFunctionResult | null }) => Promise<void>
  }

  interface HistoryDrawerExpose {
    handleOpen: () => Promise<void>
    handleClose: () => void
  }

  interface ChatPanelExpose {
    scrollToBottom: () => void
  }

  const {
    detail,
    edgeFunctions,
    errors,
    filters,
    initialLoading,
    loadInitialData,
    loadObjects,
    loading,
    objectLoadSource,
    objects,
    overview,
    pageError,
    relationships,
    schemas,
    selectedObject,
    selectObject
  } = useProjectAssistantCatalog()
  const chatPanelRef = ref<ChatPanelExpose>()
  const historyDrawerRef = ref<HistoryDrawerExpose>()
  const capabilityCenterRef = ref<CapabilityCenterExpose>()
  const focusMode = useStorage('supabase-ai-assistant:focus-mode', false)
  const assistantMode = useStorage<ProjectAssistantSafetyMode>(
    'supabase-ai-assistant:safety-mode',
    'read_only'
  )
  const {
    activeChatObject,
    analyzePlatformCapability,
    assistantStatus,
    assistantStatusLabel,
    canUseControlledWrite,
    chat,
    chatPhase,
    chatSuggestions,
    copyMessage,
    exportConversation,
    history,
    loadAssistantCapabilities,
    loadHistory,
    quickActions,
    renameConversation: renameConversationTitle,
    resetChat,
    restoreConversation: restoreHistoryConversation,
    retryMessage,
    runObjectAnalysis,
    scheduleHistorySearch,
    sendMessage,
    sendSuggestion,
    stopGeneration,
    toggleContextLock
  } = useProjectAssistantChat({
    assistantMode,
    overview,
    selectedObject,
    scrollToBottom: scrollChatToBottom
  })
  const canEditSelectedDescription = computed(
    () =>
      canUseControlledWrite.value &&
      ['table', 'view', 'materialized_view'].includes(selectedObject.value?.objectType || '')
  )
  const stats = computed(() => getProjectAssistantStats(overview.value, edgeFunctions.value))

  function selectStat(type: ProjectObjectType): void {
    if (type === 'all') {
      chat.input = '列出项目 Edge Functions，并指出未启用 JWT 校验的函数'
      void sendMessage()
      return
    }
    filters.objectType = type
    void loadObjects('filter')
  }

  async function toggleAssistantMode(): Promise<boolean> {
    if (assistantMode.value === 'controlled_write') {
      assistantMode.value = 'read_only'
      ElMessage.success('已切换为只读安全模式')
      return false
    }
    if (!canUseControlledWrite.value) {
      ElMessage.warning('仅平台超级管理员可开启受控变更模式')
      return false
    }
    try {
      await confirmAction(
        '受控变更模式允许执行已确认的白名单操作，并会记录操作者、SQL、结果与耗时。是否继续？',
        '开启管理员受控变更',
        {
          type: 'warning',
          confirmButtonText: '确认开启',
          cancelButtonText: '保持只读'
        }
      )
      assistantMode.value = 'controlled_write'
      ElMessage.success('受控变更模式已开启')
      return true
    } catch {
      // 用户取消后保持只读模式。
      return false
    }
  }

  async function editObjectDescription(): Promise<void> {
    const target = selectedObject.value
    if (!target || !canEditSelectedDescription.value) return
    if (assistantMode.value !== 'controlled_write') {
      const enabled = await toggleAssistantMode()
      if (!enabled) return
    }
    try {
      const description = await promptText(
        `为 ${target.schemaName}.${target.objectName} 填写数据库对象说明；留空将清除 COMMENT。`,
        '编辑对象说明',
        {
          allowEmpty: true,
          initialValue: detail.value?.description || target.description || '',
          maxLength: 500,
          maxLengthMessage: '对象说明不能超过 500 个字符',
          multiline: true,
          placeholder: '请输入对象用途、数据范围或业务含义',
          confirmButtonText: '下一步',
          type: 'info'
        }
      )
      await confirmAction(
        `即将写入 ${target.schemaName}.${target.objectName} 的数据库 COMMENT，此操作会记录审计日志。`,
        '确认执行变更',
        {
          type: 'warning',
          confirmButtonText: '确认写入',
          cancelButtonText: '返回检查'
        }
      )
      const response = await updateProjectObjectDescription({
        objectType: target.objectType as 'table' | 'view' | 'materialized_view',
        schema: target.schemaName,
        name: target.objectName,
        description: description || null,
        safetyMode: 'controlled_write',
        confirmed: true
      })
      target.description = response.object.description
      if (detail.value) detail.value.description = response.object.description
      ElMessage.success('对象说明已写入数据库并记录审计')
    } catch (error) {
      if (error !== 'cancel' && error !== 'close') {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '对象说明更新失败'))
      }
    }
  }

  async function copyDdl(): Promise<void> {
    if (!detail.value?.ddl) return
    await navigator.clipboard.writeText(detail.value.ddl)
    ElMessage.success('DDL 已复制')
  }

  async function openHistory(): Promise<void> {
    await historyDrawerRef.value?.handleOpen()
    await loadHistory()
  }

  async function restoreConversation(conversationId: string): Promise<void> {
    if (await restoreHistoryConversation(conversationId)) historyDrawerRef.value?.handleClose()
  }

  async function renameConversation(item: ProjectAssistantConversationSummary): Promise<void> {
    try {
      const title = await promptText('请输入新的会话标题', '重命名会话', {
        initialValue: item.title,
        maxLength: 80,
        maxLengthMessage: '会话标题不能超过 80 个字符',
        emptyMessage: '会话标题不能为空',
        placeholder: '请输入会话标题',
        type: 'info'
      })
      await renameConversationTitle(item, title)
    } catch (error) {
      if (error !== 'cancel' && error !== 'close') {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '会话重命名失败'))
      }
    }
  }

  function openCapabilityCenter(): void {
    void capabilityCenterRef.value?.handleOpen({ edgeFunctions: edgeFunctions.value })
  }

  function handleMessageFeedback(message: ProjectAssistantChatMessage, rating: -1 | 1): void {
    message.feedback = rating
  }

  function scrollChatToBottom(): void {
    chatPanelRef.value?.scrollToBottom()
  }

  function toggleFocusMode(): void {
    focusMode.value = !focusMode.value
    nextTick(() => window.dispatchEvent(new Event('resize')))
  }

  onMounted(async () => {
    await Promise.all([loadInitialData(), loadAssistantCapabilities()])
  })
</script>

<style scoped lang="scss">
  .project-assistant-shell {
    height: var(--art-full-height);
    min-height: 720px;

    :deep(> .art-async-state) {
      height: 100%;
    }
  }

  .project-assistant {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-height: 720px;
    overflow: hidden;
    background: var(--art-main-bg-color);

    &__hero {
      position: relative;
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 104px;
      padding: 17px 22px;
      overflow: hidden;
      background:
        linear-gradient(105deg, transparent 42%, var(--el-color-primary-light-9) 100%),
        var(--default-box-color);

      &::after {
        position: absolute;
        top: -64px;
        right: 8%;
        width: 180px;
        height: 180px;
        pointer-events: none;
        content: '';
        background: radial-gradient(circle, var(--el-color-primary-light-8), transparent 68%);
        border-radius: 50%;
      }

      h1 {
        margin: 4px 0;
        font-size: 22px;
        line-height: 1.35;
        letter-spacing: -0.3px;
        text-wrap: balance;
      }

      p {
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
      }
    }

    &__eyebrow {
      display: flex;
      gap: 6px;
      align-items: center;
      font-size: 12px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 1.1px;
    }

    &__safety {
      z-index: 1;
      display: flex;
      flex-direction: column;
      gap: 7px;
      align-items: flex-end;
      font-size: 12px;
      color: var(--el-text-color-secondary);

      :deep(.el-tag) {
        border-color: var(--el-color-success-light-7);
      }
    }

    &__hero-actions {
      display: flex;
      gap: 8px;
      align-items: center;

      .el-button {
        height: 28px;
        margin: 0;
        border-radius: 999px;
      }
    }

    &__stats {
      display: grid;
      grid-template-columns: repeat(6, minmax(110px, 1fr));
      padding: 7px;

      button {
        position: relative;
        display: flex;
        gap: 10px;
        align-items: center;
        padding: 10px 13px;
        text-align: left;
        touch-action: manipulation;
        cursor: pointer;
        background: transparent;
        border: 0;
        border-radius: var(--el-border-radius-base);
        transition:
          color 0.2s ease,
          background-color 0.2s ease,
          transform 0.2s ease;

        &:hover {
          background: var(--el-color-primary-light-9);
          transform: translateY(-1px);
        }

        &:focus-visible {
          outline: 2px solid var(--el-color-primary-light-3);
          outline-offset: 1px;
        }

        &.is-active {
          color: var(--el-color-primary);
          background: linear-gradient(135deg, var(--el-color-primary-light-9), transparent);

          &::after {
            position: absolute;
            right: 14px;
            bottom: 5px;
            left: 14px;
            height: 2px;
            content: '';
            background: linear-gradient(90deg, var(--el-color-primary), transparent);
            border-radius: 999px;
          }
        }

        > span {
          display: grid;
          place-items: center;
          width: 32px;
          height: 32px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: var(--el-border-radius-base);
        }

        strong,
        small {
          display: block;
        }

        strong {
          font-size: 17px;
          font-variant-numeric: tabular-nums;
        }

        small {
          margin-top: 2px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__workspace {
      flex: 1;
      min-height: 0;
    }

    &.is-focus-mode {
      gap: 8px;

      .project-assistant__workspace {
        min-height: 640px;
      }
    }

    &__splitter {
      height: 100%;

      :deep(.el-splitter-panel) {
        min-width: 0;
        overflow: hidden;
      }

      :deep(.el-splitter-bar) {
        width: 14px;
        cursor: col-resize;
      }

      :deep(.el-splitter-bar::before) {
        position: absolute;
        top: 12px;
        bottom: 12px;
        left: 50%;
        width: 1px;
        content: '';
        background: var(--el-border-color-lighter);
        transform: translateX(-50%);
        transition: background-color 0.18s ease;
      }

      :deep(.el-splitter-bar__dragger) {
        width: 14px;
        height: 64px;
        border-radius: 999px;
        transition:
          background-color 0.18s ease,
          box-shadow 0.18s ease;
      }

      :deep(.el-splitter-bar__dragger::before) {
        width: 3px;
        height: 30px;
        background: var(--el-border-color);
        border-radius: 999px;
      }

      :deep(.el-splitter-bar:hover::before),
      :deep(.el-splitter-bar:has(.el-splitter-bar__dragger-active)::before) {
        background: var(--el-color-primary-light-6);
      }

      :deep(.el-splitter-bar:hover .el-splitter-bar__dragger),
      :deep(.el-splitter-bar__dragger-active) {
        background: var(--el-color-primary-light-9);
        box-shadow: 0 4px 14px rgb(64 128 255 / 16%);
      }

      :deep(.el-splitter-bar:hover .el-splitter-bar__dragger::before),
      :deep(.el-splitter-bar__dragger-active::before) {
        background: var(--el-color-primary);
      }

      :deep(.el-splitter-bar__collapse-icon) {
        width: 20px;
        height: 30px;
        color: var(--el-text-color-secondary);
        background: var(--el-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-small);
        box-shadow: 0 5px 14px rgb(0 0 0 / 8%);
        opacity: 0.9;
        transition:
          color 0.18s ease,
          background-color 0.18s ease,
          border-color 0.18s ease,
          opacity 0.18s ease;
      }

      :deep(.el-splitter-bar__collapse-icon:hover) {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-color: var(--el-color-primary-light-6);
        opacity: 1;
      }
    }

    @media (width <= 1280px) {
      &__workspace {
        min-height: 560px;
      }

      &__stats {
        grid-template-columns: repeat(3, 1fr);
      }
    }

    @media (width <= 900px) {
      min-height: auto;
      overflow: visible;

      &__hero {
        flex-direction: column;
        gap: var(--art-space-3);
        align-items: flex-start;
      }

      &__safety {
        align-items: flex-start;

        > span {
          display: none;
        }
      }

      &__stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__workspace {
        height: auto;
      }

      &__splitter {
        display: block;
        height: auto;

        :deep(.el-splitter-panel) {
          width: 100% !important;
          height: 560px;
          margin-bottom: 12px;
          overflow: visible;
        }

        :deep(.el-splitter-bar) {
          display: none;
        }

        :deep(.el-splitter-panel:has(.project-assistant-object-browser)) {
          height: 420px;
        }

        :deep(.el-splitter-panel:has(.project-assistant__detail)) {
          height: 600px;
        }

        :deep(.el-splitter-panel:has(.project-assistant__chat)) {
          height: 680px;
        }
      }
    }

    @media (width <= 640px) {
      gap: var(--art-space-3);

      &__hero {
        min-height: auto;
        padding: var(--art-space-4);

        h1 {
          font-size: 20px;
        }

        p {
          font-size: 13px;
        }
      }

      &__stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--art-space-1);
        padding: var(--art-space-2);

        button {
          min-width: 0;
          min-height: 64px;
          padding-inline: var(--art-space-2);

          > span {
            flex: 0 0 auto;
          }

          > div {
            min-width: 0;

            small {
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
          }
        }
      }

      &__safety,
      &__hero-actions {
        width: 100%;
      }

      &__hero-actions {
        flex-wrap: wrap;
      }
    }
  }

  @media (width <= 640px) {
    .project-assistant-shell {
      height: auto;
      min-height: 0;
    }
  }
</style>
