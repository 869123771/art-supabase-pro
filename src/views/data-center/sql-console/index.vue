<template>
  <div class="sql-console-page art-full-height business-workspace-page">
    <BusinessWorkspaceHeader
      eyebrow="DATABASE WORKBENCH"
      title="SQL 工作台"
      description="在受控权限范围内编写、执行与诊断 SQL，并通过 AI 辅助生成和修复语句。"
      icon="ri:terminal-box-line"
    />
    <section class="sql-console-container business-workspace-content art-card-xs">
      <el-splitter v-model="splitRatio" layout="vertical">
        <el-splitter-panel>
          <div class="sql-editor-section">
            <Editor
              ref="editorRef"
              v-model="sqlCode"
              @execute="handleExecute"
              @ai-request="openAiDialog(aiErrorContext ? 'fix' : 'generate')"
            />
          </div>
        </el-splitter-panel>

        <el-splitter-panel>
          <div class="result-section">
            <div class="tabs-header">
              <el-tabs v-model="tabs.active" class="result-tabs">
                <el-tab-pane
                  v-for="{ label, name } in tabs.list"
                  :key="name"
                  :name="name"
                  :label="label"
                />
              </el-tabs>
              <div class="tabs-actions">
                <div class="execution-info" v-if="result?.durationMs">
                  <span class="duration">耗时 {{ result.durationMs }}ms</span>
                </div>
                <el-tooltip
                  content="AI 写 SQL (Ctrl/Cmd + I)"
                  placement="top"
                  :offset="8"
                  :show-arrow="false"
                >
                  <ArtIconButton
                    @click="openAiDialog(aiErrorContext ? 'fix' : 'generate')"
                    icon="ri-robot-2-line"
                    class="!size-6.5"
                  />
                </el-tooltip>
                <el-tooltip
                  v-if="!executing"
                  content="执行 (Shift + Enter)"
                  placement="top"
                  :offset="8"
                  :show-arrow="false"
                >
                  <ArtIconButton
                    @click="() => handleExecute()"
                    icon="ri-play-line"
                    class="!size-6.5"
                  />
                </el-tooltip>
                <el-tooltip v-else content="执行中" placement="top" :offset="8" :show-arrow="false">
                  <ArtIconButton
                    @click="() => handleExecute()"
                    icon="ri-loader-2-line"
                    :loading="executing"
                    class="size-6.5! animate-spin duration-3000"
                  />
                </el-tooltip>
                <el-tooltip
                  content="格式化 SQL (Ctrl/Cmd + Shift + F)"
                  placement="top"
                  :offset="8"
                  :show-arrow="false"
                >
                  <ArtIconButton @click="handleFormat" icon="ri-magic-line" class="size-6.5!" />
                </el-tooltip>
                <el-tooltip content="清空" placement="top" :offset="8" :show-arrow="false">
                  <ArtIconButton @click="handleClear" icon="ri-close-line" class="size-6.5!" />
                </el-tooltip>
              </div>
            </div>
            <ElScrollbar class="tabs-content">
              <div class="tabs-content__inner">
                <div v-if="!result" class="empty-state">
                  <ArtSvgIcon
                    v-if="executing"
                    :loading="executing"
                    icon="ri-loader-2-line"
                    class="size-[30px] animate-spin duration-3000"
                  />
                  <ArtEmptyState
                    v-else
                    title="等待执行 SQL"
                    description="执行后将在这里展示查询结果、耗时与错误信息"
                    size="compact"
                    :visual-size="76"
                  />
                </div>
                <template v-else>
                  <div v-if="result.status === 'error'" class="error-panel">
                    <div class="error-toolbar">
                      <el-tag type="danger" effect="light" round>执行失败</el-tag>
                      <el-button size="small" text type="primary" @click="openAiDialog('fix')">
                        AI 修复这条 SQL
                      </el-button>
                    </div>
                    <pre class="error-message">{{ result.errorMessage }}</pre>
                    <pre v-if="errorCaretPreview" class="error-caret">{{ errorCaretPreview }}</pre>
                  </div>

                  <div
                    v-if="result.status === 'ok' && result.rows && result.rows.length > 0"
                    class="result-table"
                  >
                    <ResultTable
                      :loading="executing"
                      :data="result.rows"
                      :columns="result.columns"
                    />
                  </div>

                  <div v-else-if="result.status === 'ok'" class="empty-result">
                    <ArtEmptyState
                      title="执行成功，暂无数据行"
                      description="当前语句没有返回记录，可以调整查询条件后重新执行"
                      size="compact"
                      :visual-size="76"
                    />
                  </div>
                </template>
              </div>
            </ElScrollbar>
          </div>
        </el-splitter-panel>
      </el-splitter>
    </section>

    <ArtDialog ref="aiDialogRef">
      <div class="ai-panel">
        <el-segmented
          v-model="aiDialog.mode"
          :options="[
            { label: '生成 SQL', value: 'generate' },
            { label: '修复 SQL', value: 'fix' }
          ]"
        />
        <el-input
          v-model="aiDialog.prompt"
          type="textarea"
          :rows="8"
          resize="none"
          placeholder="例如：查出最近 30 天注册且已启用的用户，按创建时间倒序"
        />
        <div v-if="aiDialog.summary" class="ai-summary">{{ aiDialog.summary }}</div>
      </div>
    </ArtDialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { useMemoize } from '@vueuse/core'
  import { ElMessage } from 'element-plus'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import { executeSql, fetchDatabaseMetadata, generateSqlByAi } from '@/api/data-center'
  import Editor from './modules/editor.vue'
  import ResultTable from './modules/result-table.vue'
  import {
    buildCaretDiagnostic,
    parseSqlErrorLocation,
    type SqlErrorLocation
  } from '@/utils/sqlWorkbench'

  interface EditorInstance {
    format: () => Promise<void>
    clear: () => void
    getSqlToExecute: () => string
    setSql: (value: string) => void
    focus: () => void
    clearErrorMarkers: () => void
    applyErrorMarker: (location: SqlErrorLocation | null, message: string) => void
  }

  interface SqlConsoleError {
    message?: string
    durationMs?: number
  }

  const normalizeSqlConsoleError = (error: unknown): SqlConsoleError => {
    if (!error || typeof error !== 'object') return {}
    const record = error as Record<string, unknown>
    return {
      message: typeof record.message === 'string' ? record.message : undefined,
      durationMs: typeof record.durationMs === 'number' ? record.durationMs : undefined
    }
  }

  const sqlCode = ref('SELECT * FROM sys_user LIMIT 10;')
  const executing = ref(false)
  const result = ref<Api.DataCenter.SqlConsole.SqlExecuteResponse | null>(null)
  const splitRatio = ref(0.6)
  const editorRef = ref<EditorInstance | null>(null)
  const aiDialogRef = ref<ArtDialogExpose>()
  const getMetadata = useMemoize(fetchDatabaseMetadata)
  const sqlErrorLocation = ref<SqlErrorLocation | null>(null)

  const tabs = ref({
    active: 'result',
    list: [{ name: 'result', label: '结果' }]
  })

  const aiDialog = ref({
    mode: 'generate' as 'generate' | 'fix',
    prompt: '',
    summary: ''
  })

  const aiErrorContext = computed(() => result.value?.status === 'error')

  // 把后端错误里的 LINE / ^ 信息整理成可读预览，方便在结果面板快速判断问题。
  const errorCaretPreview = computed(() => {
    if (!result.value?.queryText || !sqlErrorLocation.value) return ''
    return buildCaretDiagnostic(result.value.queryText, sqlErrorLocation.value)
  })

  // 执行逻辑同时负责清空旧标记，并在失败时把错误位置重新画回 Monaco。
  const handleExecute = async (sql?: string) => {
    const sqlToExecute = sql || editorRef.value?.getSqlToExecute() || sqlCode.value

    if (!sqlToExecute || !sqlToExecute.trim()) {
      ElMessage.warning('请输入 SQL 查询')
      return
    }

    executing.value = true
    result.value = null
    sqlErrorLocation.value = null
    editorRef.value?.clearErrorMarkers()

    try {
      const { data, error } = await executeSql({ query: sqlToExecute })
      if (error) {
        const sqlError = normalizeSqlConsoleError(error)
        const errorMessage = sqlError.message || '执行 SQL 时发生错误'
        const location = parseSqlErrorLocation(errorMessage)
        sqlErrorLocation.value = location
        editorRef.value?.applyErrorMarker(location, errorMessage)
        result.value = {
          status: 'error',
          errorMessage,
          durationMs: sqlError.durationMs,
          queryText: sqlToExecute
        }
        return
      }

      result.value = data
      sqlErrorLocation.value = null
      editorRef.value?.clearErrorMarkers()
    } finally {
      executing.value = false
    }
  }

  const handleFormat = async () => {
    editorRef.value?.format()
  }

  const handleClear = () => {
    editorRef.value?.clear()
    editorRef.value?.clearErrorMarkers()
    sqlErrorLocation.value = null
    result.value = null
  }

  const openAiDialog = (mode: 'generate' | 'fix' = 'generate') => {
    // 用户填写提示词时并行预取 schema，生成按钮不再额外串行等待元数据。
    void getMetadata()
    aiDialog.value.mode = mode
    aiDialog.value.summary = ''

    if (mode === 'fix') {
      aiDialog.value.prompt = result.value?.errorMessage
        ? `修复这条 PostgreSQL，并解释改动原因。\n\n错误信息：${result.value.errorMessage}`
        : '修复这条 PostgreSQL，并解释改动原因。'
      void openAiDialogRef(mode)
      return
    }

    aiDialog.value.prompt = ''
    void openAiDialogRef(mode)
  }

  const openAiDialogRef = (mode: 'generate' | 'fix') =>
    aiDialogRef.value?.handleOpen(undefined, {
      title: 'AI SQL 助手',
      size: 'md',
      contentMaxHeight: '60vh',
      confirmText: mode === 'fix' ? '修复 SQL' : '生成 SQL',
      onConfirm: handleAiGenerate
    })

  // AI 生成会带上当前 schema 摘要，避免模型在表名和关联关系上瞎猜。
  const handleAiGenerate = async (): Promise<boolean> => {
    if (!aiDialog.value.prompt.trim()) {
      ElMessage.warning('请输入需求描述')
      return false
    }

    try {
      const metadata = await getMetadata()
      const aiResponse = await generateSqlByAi({
        prompt: aiDialog.value.prompt,
        mode: aiDialog.value.mode,
        currentSql: sqlCode.value,
        metadata
      })
      const { data, error } = aiResponse

      if (error || !data?.sql) {
        const aiError = normalizeSqlConsoleError(error)
        ElMessage.error(
          aiError.message || 'AI SQL 功能未配置。请在 Supabase Edge Function 中配置模型密钥。'
        )
        return false
      }

      editorRef.value?.setSql(data.sql)
      editorRef.value?.clearErrorMarkers()
      sqlErrorLocation.value = null
      aiDialog.value.summary = data.summary || ''
      const warnings = (data.warnings ?? []).filter(Boolean)
      if (warnings.length) {
        ElMessage.warning({
          message: `AI SQL 已写入编辑器，请确认：${warnings.join('；')}`,
          duration: 6000,
          showClose: true
        })
      } else {
        ElMessage.success(
          data.model ? `AI SQL 已写入编辑器（${data.model}）` : 'AI SQL 已写入编辑器'
        )
      }
      return true
    } catch {
      return false
    }
  }
</script>

<style scoped lang="scss">
  .sql-console-container {
    width: 100%;
    height: 100%;
    min-height: 0;
    padding: 0;
    margin: 0;
    overflow: hidden;

    .sql-editor-section {
      display: flex;
      flex-direction: column;
      width: 100%;
      height: 100%;
      min-height: 0;
    }
  }

  .result-section {
    position: relative;
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100%;
    background: var(--el-bg-color);

    > .tabs-header {
      display: flex;
      flex-shrink: 0;
      align-items: center;
      justify-content: space-between;
      height: 40px;
      padding-right: 16px;
      border-bottom: 1px solid var(--el-border-color);

      .result-tabs {
        flex: 1;

        :deep(.el-tabs__header) {
          margin: 0;

          .el-tabs__nav-wrap {
            padding: 0 1rem;

            &::after {
              display: none;
            }
          }
        }

        :deep(.el-tabs__content) {
          display: none;
        }
      }

      .tabs-actions {
        display: flex;
        gap: 8px;
        align-items: center;

        .execution-info {
          margin-right: 12px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    > .tabs-content {
      position: relative;
      flex: 1;
      min-height: 0;

      :deep(.el-scrollbar__view) {
        min-height: 100%;
      }

      .tabs-content__inner {
        min-height: 100%;
      }

      .empty-state {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100%;
        padding: 40px;

        :deep(.el-empty) {
          height: 100%;
          padding: 0;

          .el-empty__image {
            height: 80%;
          }
        }
      }

      .error-panel {
        padding: 16px;

        .error-toolbar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 12px;
        }

        .error-message,
        .error-caret {
          margin: 0;
          font-family: Consolas, 'Courier New', monospace;
          line-height: 1.6;
          color: var(--el-color-error);
          overflow-wrap: anywhere;
          white-space: pre-wrap;
        }

        .error-caret {
          padding: 12px;
          margin-top: 12px;
          background: color-mix(in srgb, var(--el-color-error) 6%, transparent);
          border-radius: var(--el-border-radius-base);
        }
      }

      .result-table {
        height: 100%;

        :deep(.art-table) {
          height: 100% !important;
        }

        :deep(.el-table) {
          margin: 0;

          &::before {
            width: 0;
          }

          .el-table__inner-wrapper {
            &::before,
            &::after {
              background-color: transparent;
            }

            .el-table__border-left-patch {
              background-color: transparent;
            }
          }
        }
      }

      .empty-result {
        padding: 40px;
      }
    }
  }

  .ai-panel {
    display: flex;
    flex-direction: column;
    gap: 16px;

    .ai-summary {
      padding: 12px 14px;
      line-height: 1.6;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);
    }
  }
</style>
