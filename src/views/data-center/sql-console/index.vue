<template>
  <div class="sql-console-container">
    <!-- SQL 编辑器区域 -->
    <div class="sql-editor-section">
      <div class="editor-header">
        <span class="title">SQL 编辑器</span>
        <div class="actions">
          <el-button type="primary" :loading="executing" @click="handleExecute">
            <el-icon><VideoPlay /></el-icon>
            执行 (Ctrl+Enter)
          </el-button>
          <el-button @click="handleClear">清空</el-button>
        </div>
      </div>
      <div class="editor-wrapper">
        <vue-monaco-editor
          :wrapperStyle="{ height: '100%' }"
          v-model:value="sqlCode"
          language="pgsql"
          theme="vs-dark"
          :options="editorOptions"
          @keydown="handleKeyDown"
        />
      </div>
    </div>

    <!-- 结果展示区域 -->
    <div v-if="result" class="result-section">
      <div class="result-header">
        <div class="result-info">
          <el-tag :type="result.status === 'ok' ? 'success' : 'danger'">
            {{ result.status === 'ok' ? '成功' : '错误' }}
          </el-tag>
          <span v-if="result.command_tag" class="command-tag">
            {{ result.command_tag }}
          </span>
          <span v-if="result.row_count !== undefined" class="row-count">
            行数: {{ result.row_count }}
          </span>
          <span v-if="result.duration_ms !== undefined" class="duration">
            耗时: {{ result.duration_ms }}ms
          </span>
        </div>
        <el-button size="small" @click="result = null">关闭</el-button>
      </div>

      <!-- 错误信息 -->
      <div v-if="result.status === 'error'" class="error-message">
        <el-alert type="error" :closable="false">
          <template #title> <strong>错误:</strong> {{ result.error_message }} </template>
        </el-alert>
      </div>

      <!-- 查询结果表格 -->
      <div
        v-if="result.status === 'ok' && result.rows && result.rows.length > 0"
        class="result-table"
      >
        <el-table :data="result.rows" border stripe max-height="400" style="width: 100%">
          <el-table-column
            v-for="(value, key) in result.rows[0]"
            :key="key"
            :prop="key"
            :label="key"
            min-width="120"
          />
        </el-table>
      </div>

      <!-- 空结果提示 -->
      <div
        v-if="result.status === 'ok' && (!result.rows || result.rows.length === 0)"
        class="empty-result"
      >
        <el-empty description="查询成功，但没有返回数据" />
      </div>

      <!-- Notices 和 Warnings -->
      <div v-if="result.notices && result.notices.length > 0" class="notices">
        <el-alert
          v-for="(notice, index) in result.notices"
          :key="index"
          type="info"
          :title="notice"
          :closable="false"
          style="margin-top: 8px"
        />
      </div>
      <div v-if="result.warnings && result.warnings.length > 0" class="warnings">
        <el-alert
          v-for="(warning, index) in result.warnings"
          :key="index"
          type="warning"
          :title="warning"
          :closable="false"
          style="margin-top: 8px"
        />
      </div>

      <!-- 执行的 SQL -->
      <div v-if="result.query_text" class="query-text">
        <el-collapse>
          <el-collapse-item title="查看执行的 SQL" name="sql">
            <pre>{{ result.query_text }}</pre>
          </el-collapse-item>
        </el-collapse>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { ref, onMounted } from 'vue'
  import { ElMessage } from 'element-plus'
  import { VideoPlay } from '@element-plus/icons-vue'
  import VueMonacoEditor from '@guolao/vue-monaco-editor'
  import { fetchDatabaseMetadata, executeSql } from '@/api/data-center'
  import { registerSqlMetadata } from '@/utils/monacoSqlSetup'

  const sqlCode = ref('SELECT * FROM app_users LIMIT 10;')
  const executing = ref(false)
  const result = ref<Api.DataCenter.SqlConsole.SqlExecuteResponse | null>(null)

  const editorOptions = ref({
    automaticLayout: true,
    minimap: { enabled: true },
    lineNumbers: 'on',
    roundedSelection: false,
    scrollBeyondLastLine: false,
    readOnly: false,
    // SQL 相关提示选项（确保开启）
    suggestOnTriggerCharacters: true,
    quickSuggestions: true,
    wordBasedSuggestions: true
  })

  // 执行 SQL
  const handleExecute = async () => {
    if (!sqlCode.value.trim()) {
      ElMessage.warning('请输入 SQL 查询')
      return
    }

    executing.value = true
    result.value = null

    try {
      const response = await executeSql({ query: sqlCode.value })
      result.value = response

      if (response.status === 'ok') {
        ElMessage.success('SQL 执行成功')
      } else {
        ElMessage.error(response.error_message || 'SQL 执行失败')
      }
    } catch (error: any) {
      result.value = {
        status: 'error',
        error_message: error.message || '执行 SQL 时发生错误',
        query_text: sqlCode.value
      }
      ElMessage.error(error.message || '执行 SQL 时发生错误')
    } finally {
      executing.value = false
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
    display: flex;
    flex-direction: column;
    height: 100vh;
    gap: 16px;
    padding: 16px;
  }

  .sql-editor-section {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }

  .editor-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    background: var(--el-bg-color);
    border: 1px solid var(--el-border-color);
    border-bottom: none;
    border-radius: 4px 4px 0 0;

    .title {
      font-weight: 600;
      font-size: 14px;
    }

    .actions {
      display: flex;
      gap: 8px;
    }
  }

  .editor-wrapper {
    flex: 1;
    border: 1px solid var(--el-border-color);
    border-radius: 0 0 4px 4px;
    min-height: 0;
    overflow: hidden;
  }

  .result-section {
    border: 1px solid var(--el-border-color);
    border-radius: 4px;
    background: var(--el-bg-color);
    max-height: 50vh;
    display: flex;
    flex-direction: column;
  }

  .result-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    border-bottom: 1px solid var(--el-border-color);

    .result-info {
      display: flex;
      align-items: center;
      gap: 12px;
      font-size: 12px;

      .command-tag,
      .row-count,
      .duration {
        color: var(--el-text-color-secondary);
      }
    }
  }

  .error-message {
    padding: 16px;
  }

  .result-table {
    padding: 16px;
    overflow: auto;
    flex: 1;
  }

  .empty-result {
    padding: 40px;
    text-align: center;
  }

  .notices,
  .warnings {
    padding: 0 16px 16px;
  }

  .query-text {
    padding: 16px;
    border-top: 1px solid var(--el-border-color);

    pre {
      margin: 0;
      padding: 12px;
      background: var(--el-fill-color-light);
      border-radius: 4px;
      font-size: 12px;
      overflow-x: auto;
    }
  }
</style>
