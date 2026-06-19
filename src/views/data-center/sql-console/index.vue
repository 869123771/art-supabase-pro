<template>
  <div class="sql-console-container art-full-height">
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
          <div class="tabs-content">
            <div v-if="!result" class="empty-state">
              <ArtSvgIcon
                v-if="executing"
                :loading="executing"
                icon="ri-loader-2-line"
                class="size-[30px] animate-spin duration-3000"
              />
              <el-empty v-else description="执行 SQL 后会在这里显示结果" />
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
                <ResultTable :loading="executing" :data="result.rows" :columns="result.columns" />
              </div>

              <div v-else-if="result.status === 'ok'" class="empty-result">
                <el-empty description="语句执行成功，但没有返回数据行" />
              </div>
            </template>
          </div>
        </div>
      </el-splitter-panel>
    </el-splitter>

    <el-dialog v-model="aiDialog.visible" title="AI SQL 助手" width="640px" destroy-on-close>
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
      <template #footer>
        <el-button @click="aiDialog.visible = false">取消</el-button>
        <el-button type="primary" :loading="aiDialog.loading" @click="handleAiGenerate">
          {{ aiDialog.mode === 'fix' ? '修复 SQL' : '生成 SQL' }}
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { ElMessage } from 'element-plus'
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

  const sqlCode = ref('SELECT * FROM sys_user LIMIT 10;')
  const executing = ref(false)
  const result = ref<Api.DataCenter.SqlConsole.SqlExecuteResponse | null>(null)
  const splitRatio = ref(0.6)
  const editorRef = ref<EditorInstance | null>(null)
  const metadataCache = ref<Api.DataCenter.SqlConsole.DatabaseMetadata | null>(null)
  const sqlErrorLocation = ref<SqlErrorLocation | null>(null)

  const tabs = ref({
    active: 'result',
    list: [{ name: 'result', label: '结果' }]
  })

  const aiDialog = ref({
    visible: false,
    loading: false,
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

  async function ensureMetadata() {
    if (metadataCache.value) return metadataCache.value
    metadataCache.value = await fetchDatabaseMetadata()
    return metadataCache.value
  }

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
      const { data, error } = (await executeSql({ query: sqlToExecute })) as any
      if (error) {
        const errorMessage = error.message || '执行 SQL 时发生错误'
        const location = parseSqlErrorLocation(errorMessage)
        sqlErrorLocation.value = location
        editorRef.value?.applyErrorMarker(location, errorMessage)
        result.value = {
          status: 'error',
          errorMessage,
          durationMs: error.durationMs,
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
    aiDialog.value.visible = true
    aiDialog.value.mode = mode
    aiDialog.value.summary = ''

    if (mode === 'fix') {
      aiDialog.value.prompt = result.value?.errorMessage
        ? `修复这条 PostgreSQL，并解释改动原因。\n\n错误信息：${result.value.errorMessage}`
        : '修复这条 PostgreSQL，并解释改动原因。'
      return
    }

    aiDialog.value.prompt = ''
  }

  // AI 生成会带上当前 schema 摘要，避免模型在表名和关联关系上瞎猜。
  const handleAiGenerate = async () => {
    if (!aiDialog.value.prompt.trim()) {
      ElMessage.warning('请输入需求描述')
      return
    }

    aiDialog.value.loading = true

    try {
      const metadata = await ensureMetadata()
      const aiResponse = await generateSqlByAi({
        prompt: aiDialog.value.prompt,
        mode: aiDialog.value.mode,
        currentSql: sqlCode.value,
        metadata
      })
      const { data, error } = aiResponse

      if (error || !data?.sql) {
        ElMessage.error(
          (error as any)?.message ||
            'AI SQL 功能未配置。请在 Supabase Edge Function 中配置模型密钥。'
        )
        return
      }

      editorRef.value?.setSql(data.sql)
      editorRef.value?.clearErrorMarkers()
      sqlErrorLocation.value = null
      aiDialog.value.summary = data.summary || ''
      aiDialog.value.visible = false
      ElMessage.success('AI SQL 已写入编辑器')
    } finally {
      aiDialog.value.loading = false
    }
  }
</script>

<style scoped lang="scss">
  .sql-console-container {
    width: 100%;
    padding: 0;
    margin: 0;
    border: 1px solid var(--el-border-color);
    border-radius: var(--el-border-radius-base);

    .sql-editor-section {
      width: 100%;
      height: 100%;
      display: flex;
      flex-direction: column;
      min-height: 0;
    }
  }

  .result-section {
    width: 100%;
    height: 100%;
    background: var(--el-bg-color);
    display: flex;
    flex-direction: column;
    position: relative;

    > .tabs-header {
      flex-shrink: 0;
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding-right: 16px;
      border-bottom: 1px solid var(--el-border-color);
      height: 40px;

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
        align-items: center;
        gap: 8px;

        .execution-info {
          margin-right: 12px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    > .tabs-content {
      flex: 1;
      overflow: auto;
      position: relative;
      min-height: 0;

      .empty-state {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100%;
        padding: 40px;

        :deep(.el-empty) {
          padding: 0;
          height: 100%;

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
          white-space: pre-wrap;
          word-break: break-word;
          color: var(--el-color-error);
          margin: 0;
          font-family: Consolas, 'Courier New', monospace;
          line-height: 1.6;
        }

        .error-caret {
          margin-top: 12px;
          padding: 12px;
          border-radius: 6px;
          background: color-mix(in srgb, var(--el-color-error) 6%, transparent);
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
      border-radius: 6px;
      background: var(--el-fill-color-light);
      color: var(--el-text-color-secondary);
      line-height: 1.6;
    }
  }
</style>
