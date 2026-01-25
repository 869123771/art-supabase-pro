<template>
  <div class="sql-console-container art-full-height">
    <el-splitter v-model="splitRatio" layout="vertical">
      <!-- 上部分：SQL 编辑器 -->
      <el-splitter-panel>
        <div class="sql-editor-section">
          <div class="editor-wrapper">
            <vue-monaco-editor
              ref="editorRef"
              :wrapperStyle="{ height: '100%' }"
              v-model:value="sqlCode"
              language="pgsql"
              :theme="editorTheme"
              :options="editorOptions"
              @keydown="handleKeyDown"
              @editor-mounted="handleEditorMounted"
            />
          </div>
        </div>
      </el-splitter-panel>

      <!-- 下部分：工具条和结果展示 -->
      <el-splitter-panel>
        <div class="result-section">
          <div class="tabs-header">
            <el-tabs v-model="tabs.active" class="result-tabs">
              <el-tab-pane
                v-for="{ label, name } in tabs.list"
                :key="name"
                :name="name"
                :label="label"
              >
              </el-tab-pane>
            </el-tabs>
            <div class="tabs-actions">
              <div class="execution-info" v-if="result?.durationMs">
                <span class="duration">耗时: {{ result.durationMs }}ms</span>
              </div>
              <el-tooltip
                v-if="!executing"
                content="执行(shift + enter)"
                placement="top"
                :offset="8"
                :show-arrow="false"
              >
                <ArtIconButton @click="handleExecute" icon="ri-play-line" class="!size-6.5" />
              </el-tooltip>
              <el-tooltip v-else content="执行中" placement="top" :offset="8" :show-arrow="false">
                <ArtIconButton
                  @click="handleExecute"
                  icon="ri-loader-2-line"
                  :loading="executing"
                  class="!size-6.5 animate-spin duration-[3000ms]"
                />
              </el-tooltip>
              <el-tooltip
                content="美化 SQL(ctrl + shift + f)"
                placement="top"
                :offset="8"
                :show-arrow="false"
              >
                <ArtIconButton @click="handleFormat" icon="ri-magic-line" class="!size-6.5" />
              </el-tooltip>
              <el-tooltip content="清空" placement="top" :offset="8" :show-arrow="false">
                <ArtIconButton @click="handleClear" icon="ri-close-line" class="!size-6.5" />
              </el-tooltip>
            </div>
          </div>
          <div class="tabs-content">
            <div v-if="!result" class="empty-state">
              <ArtSvgIcon
                v-if="executing"
                :loading="executing"
                icon="ri-loader-2-line"
                class="size-[30px] animate-spin duration-[3000ms]"
              ></ArtSvgIcon>
              <el-empty v-else description="执行 SQL 后将在此显示结果" />
            </div>
            <template v-else>
              <!-- 错误信息 -->
              <div v-if="result.status === 'error'" class="error-message">
                <pre>{{ result.errorMessage }}</pre>
              </div>

              <!-- 查询结果表格 -->
              <div
                v-if="result.status === 'ok' && result.rows && result.rows.length > 0"
                class="result-table"
              >
                <ArtTable :loading="executing" :data="result.rows" :columns="tableColumns" border>
                </ArtTable>
              </div>
            </template>
          </div>
        </div>
      </el-splitter-panel>
    </el-splitter>
  </div>
</template>

<script setup lang="ts">
  import { ref, onMounted, computed } from 'vue'
  import { ElMessage } from 'element-plus'
  import VueMonacoEditor from '@guolao/vue-monaco-editor'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import { fetchDatabaseMetadata, executeSql } from '@/api/data-center'
  import { registerSqlMetadata } from '@/utils/monacoSqlSetup'
  import { useSettingStore } from '@/store/modules/setting'

  const settingStore = useSettingStore()
  const sqlCode = ref('SELECT * FROM app_users LIMIT 10;')
  const executing = ref(false)
  const result = ref<Api.DataCenter.SqlConsole.SqlExecuteResponse | null>(null)
  const splitRatio = ref(0.6) // 默认上部分占60%
  const editorRef = ref<any>(null)
  let editorInstance: any = null

  const editorOptions = ref({
    automaticLayout: true,
    minimap: { enabled: false },
    lineNumbers: 'on',
    roundedSelection: false,
    scrollBeyondLastLine: false,
    readOnly: false,
    // SQL 相关提示选项（确保开启）
    suggestOnTriggerCharacters: true,
    quickSuggestions: true,
    wordBasedSuggestions: true
  })

  const tabs = ref({
    active: 'result',
    list: [{ name: 'result', label: '结果' }]
  })

  const editorTheme = computed(() => {
    return settingStore.systemThemeType === 'dark' ? 'vs-dark' : 'vs'
  })

  // 动态生成表格列配置
  const tableColumns = computed(() => {
    if (!result.value || !result.value.columns || result.value.columns.length === 0) {
      return []
    }

    return result.value.columns.map((column) => ({
      prop: column.name,
      label: column.name,
      minWidth: 120
    }))
  })

  // 编辑器挂载完成
  const handleEditorMounted = (editor: any) => {
    editorInstance = editor
  }

  // 获取选中的 SQL 或整个 SQL
  const getSelectedSql = () => {
    if (editorInstance) {
      const selection = editorInstance.getSelection()
      if (selection && !selection.isEmpty()) {
        return editorInstance.getValueInRange(selection)
      }
    }
    return sqlCode.value
  }

  // 执行 SQL
  const handleExecute = async () => {
    const sqlToExecute = getSelectedSql()

    if (!sqlToExecute.trim()) {
      ElMessage.warning('请输入 SQL 查询')
      return
    }

    executing.value = true
    result.value = null

    try {
      const { data, error } = await executeSql({ query: sqlToExecute })
      if (error) {
        result.value = {
          status: 'error',
          errorMessage: error.message || '执行 SQL 时发生错误',
          durationMs: error.durationMs,
          queryText: sqlToExecute
        }
      } else {
        result.value = data
      }
    } finally {
      executing.value = false
    }
  }

  // 格式化 SQL
  const handleFormat = async () => {
    if (!sqlCode.value.trim()) {
      return
    }

    try {
      const { format } = await import('sql-formatter')
      const formattedSql = format(sqlCode.value, {
        language: 'postgresql',
        indent: '  ',
        uppercase: true,
        linesBetweenQueries: 1
      })
      sqlCode.value = formattedSql
    } catch (error) {
      console.error('SQL 格式化失败:', error)
      ElMessage.error('SQL 格式化失败')
    }
  }

  // 清空编辑器
  const handleClear = () => {
    sqlCode.value = ''
    result.value = null
  }

  // 键盘快捷键
  const handleKeyDown = (event: KeyboardEvent) => {
    // Ctrl+Enter 或 Cmd+Enter 执行
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
      event.preventDefault()
      handleExecute()
    }
    // Shift+Enter 执行
    if (event.shiftKey && event.key === 'Enter') {
      event.preventDefault()
      handleExecute()
    }
    // Ctrl+Shift+F 格式化
    if ((event.ctrlKey || event.metaKey) && event.shiftKey && event.key === 'F') {
      event.preventDefault()
      handleFormat()
    }
  }

  onMounted(async () => {
    try {
      const metadata = await fetchDatabaseMetadata()
      registerSqlMetadata(metadata)
    } catch (error) {
      console.error('Failed to load database metadata:', error)
    }
  })
</script>

<style scoped lang="scss">
  .sql-console-container {
    width: 100%;
    padding: 0;
    margin: 0;

    .sql-editor-section {
      width: 100%;
      height: 100%;
      display: flex;
      flex-direction: column;
      min-height: 0;

      .editor-wrapper {
        flex: 1;
        border: 1px solid var(--el-border-color);
        border-radius: 0 0 4px 4px;
        min-height: 0;
        overflow: hidden;
      }
    }
  }

  .result-section {
    width: 100%;
    height: 100%;
    border: 1px solid var(--el-border-color);
    border-radius: 4px;
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

      .error-message {
        padding: 16px;

        pre {
          white-space: pre-wrap;
          word-break: break-word;
          font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', 'Consolas', monospace;
          color: var(--el-color-error);
          margin: 0;
        }
      }

      .result-table {
        height: 100%;
        .art-table {
          height: 100% !important;
        }
        :deep(.el-table) {
          margin: 0;
        }
      }

      .empty-result {
        padding: 40px;
        text-align: center;
      }
    }
  }
</style>
