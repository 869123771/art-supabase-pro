<template>
  <div class="sql-console-container art-full-height">
    <el-splitter v-model="splitRatio" layout="vertical">
      <!-- 上部分：SQL 编辑器 -->
      <el-splitter-panel>
        <div class="sql-editor-section">
          <Editor ref="editorRef" v-model="sqlCode" @execute="handleExecute" />
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
                content="美化 SQL(ctrl + shift + f)"
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
                <ArtTable :loading="executing" :data="result.rows" :columns="tableColumns" border />
              </div>
            </template>
          </div>
        </div>
      </el-splitter-panel>
    </el-splitter>
  </div>
</template>

<script setup lang="ts">
  import { ref, computed } from 'vue'
  import { ElMessage } from 'element-plus'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import { executeSql } from '@/api/data-center'
  import Editor from './modules/editor.vue'
  import { isObject } from 'lodash-es'

  interface EditorInstance {
    format: () => Promise<void>
    clear: () => void
    getSqlToExecute: () => string
  }

  const sqlCode = ref('SELECT * FROM app_users LIMIT 10;')
  const executing = ref(false)
  const result = ref<Api.DataCenter.SqlConsole.SqlExecuteResponse | null>(null)
  const splitRatio = ref(0.6) // 默认上部分占60%
  const editorRef = ref<EditorInstance | null>(null)

  const tabs = ref({
    active: 'result',
    list: [{ name: 'result', label: '结果' }]
  })

  // 动态生成表格列配置
  const tableColumns = computed(() => {
    if (!result.value || !result.value.columns || result.value.columns.length === 0) {
      return []
    }

    return result.value.columns.map((column) => ({
      prop: column.name,
      label: column.name,
      minWidth: 120,
      showOverflowTooltip: true,
      formatter: (row: any) => {
        const value = row[column.name]
        if (isObject(value)) {
          return JSON.stringify(value)
        }
        return value
      }
    }))
  })

  // 执行 SQL
  const handleExecute = async (sql?: string) => {
    const sqlToExecute = sql || editorRef.value?.getSqlToExecute() || sqlCode.value

    if (!sqlToExecute || !sqlToExecute.trim()) {
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
    editorRef.value?.format()
  }

  // 清空编辑器
  const handleClear = () => {
    editorRef.value?.clear()
    result.value = null
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

      .error-message {
        padding: 16px;

        pre {
          white-space: pre-wrap;
          word-break: break-word;
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
          .el-table__inner-wrapper {
            &::before {
              background-color: transparent;
            }
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
        text-align: center;
      }
    }
  }
</style>
