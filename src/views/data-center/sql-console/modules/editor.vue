<template>
  <div class="editor-wrapper">
    <vue-monaco-editor
      ref="editorRef"
      :wrapperStyle="{ height: '100%' }"
      :value="modelValue"
      :language="language"
      :theme="editorTheme"
      :options="editorOptions as any"
      @update:value="handleChange"
      @keydown="handleKeyDown"
      @mount="handleEditorMounted"
    />
    <div v-if="!modelValue" class="editor-placeholder">请输入Postgre SQL 进行查询</div>
  </div>
</template>

<script setup lang="ts">
  import { ref, computed, onMounted } from 'vue'
  import { ElMessage } from 'element-plus'
  import VueMonacoEditor from '@guolao/vue-monaco-editor'
  import { fetchDatabaseMetadata } from '@/api/data-center'
  import { registerSqlMetadata } from '@/utils/monacoSqlSetup'
  import { useSettingStore } from '@/store/modules/setting'

  const props = withDefaults(
    defineProps<{
      modelValue: string
      language?: string
      readOnly?: boolean
    }>(),
    {
      language: 'pgsql',
      readOnly: false
    }
  )

  const emit = defineEmits<{
    (e: 'update:modelValue', value: string): void
    (e: 'execute', sql: string): void
  }>()

  const settingStore = useSettingStore()

  const editorRef = ref<any>(null)

  let editorInstance: any = null

  const editorOptions = ref({
    automaticLayout: true,
    minimap: { enabled: false },
    fontSize: 13,
    border: false,
    lineNumbers: 'on',
    roundedSelection: false,
    scrollBeyondLastLine: false,
    readOnly: props.readOnly,
    fixedOverflowWidgets: true, // 修复提示框被遮挡问题
    // SQL 相关提示选项（确保开启）
    suggestOnTriggerCharacters: true,
    quickSuggestions: true,
    wordBasedSuggestions: true
  })

  const editorTheme = computed(() => {
    return settingStore.systemThemeType === 'dark' ? 'vs-dark' : 'vs'
  })

  const handleChange = (val: string) => {
    emit('update:modelValue', val)
  }

  const handleEditorMounted = (editor: any) => {
    editorInstance = editor

    // 注册右键菜单 Run Query
    editor.addAction({
      id: 'run-query-action',
      label: 'Run Query',
      keybindings: [
        // Ctrl+Enter / Cmd+Enter
        2048 | 3
      ],
      contextMenuGroupId: '1_modification',
      contextMenuOrder: 2,
      run: () => {
        triggerExecute()
      }
    })
  }

  // 获取选中的 SQL 或整个 SQL
  const getSelectedSql = () => {
    if (editorInstance) {
      const selection = editorInstance.getSelection()
      const model = editorInstance.getModel()
      if (selection && model && !selection.isEmpty()) {
        return model.getValueInRange(selection)
      }
    }
    return props.modelValue
  }

  const triggerExecute = () => {
    const sql = getSelectedSql()
    if (!sql.trim()) {
      ElMessage.warning('请输入 SQL 查询')
      return
    }
    emit('execute', sql)
  }

  const handleKeyDown = (event: KeyboardEvent) => {
    // Ctrl+Enter 或 Cmd+Enter 执行
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
      event.preventDefault()
      triggerExecute()
    }
    // Shift+Enter 执行
    if (event.shiftKey && event.key === 'Enter') {
      event.preventDefault()
      triggerExecute()
    }
    // Ctrl+Shift+F 格式化
    if ((event.ctrlKey || event.metaKey) && event.shiftKey && event.key === 'F') {
      event.preventDefault()
      handleFormat()
    }
  }

  const handleFormat = async () => {
    if (!props.modelValue.trim()) {
      return
    }

    try {
      const { format } = await import('sql-formatter')
      const formattedSql = format(props.modelValue, {
        language: 'postgresql',
        tabWidth: 2,
        keywordCase: 'upper',
        linesBetweenQueries: 1
      })
      emit('update:modelValue', formattedSql)
    } catch (error) {
      console.error('SQL 格式化失败:', error)
      ElMessage.error('SQL 格式化失败')
    }
  }

  const handleClear = () => {
    emit('update:modelValue', '')
  }

  defineExpose({
    format: handleFormat,
    clear: handleClear,
    getSqlToExecute: getSelectedSql
  })

  onMounted(async () => {
    try {
      const metadata: Api.DataCenter.SqlConsole.DatabaseMetadata = await fetchDatabaseMetadata()
      registerSqlMetadata(metadata)
    } catch (error) {
      console.error('Failed to load database metadata:', error)
    }
  })
</script>

<style scoped lang="scss">
  .editor-wrapper {
    flex: 1;
    min-height: 0;
    overflow: hidden;
    position: relative; // 确保 placeholder 绝对定位基于此容器
    height: 100%;

    .editor-placeholder {
      position: absolute;
      top: 0;
      left: 63px; // 避开行号
      color: #6e7681;
      font-family: Consolas, 'Courier New', monospace;
      font-size: 13px;
      pointer-events: none; // 让点击穿透到编辑器
      z-index: 10;
    }
  }
</style>

<style lang="scss">
  // 全局 Monaco Editor 样式覆盖
  // 注意：开启 fixedOverflowWidgets: true 后，suggest-widget 会被移动到 body 下，
  // 此时不再是 .monaco-editor 的子元素，所以需要直接选中 .suggest-widget
  .suggest-widget {
    z-index: 99999 !important;
    // 确保有背景色，防止透明
    background-color: var(--el-bg-color-overlay) !important;
    border: 1px solid var(--el-border-color-lighter) !important;
    box-shadow: var(--el-box-shadow-light) !important;

    // 提示列表样式优化
    .monaco-list {
      // 选中行背景色 - 使用 Element Plus 主题色 (浅色)
      .monaco-list-row.focused {
        background-color: var(--el-color-primary-light-9) !important;
        color: var(--el-text-color-primary) !important;

        // 选中项文字颜色优化
        .monaco-highlighted-label {
          color: var(--el-color-primary);
        }
      }

      // 将提示详情（类型信息）右对齐
      // 使用 Flex 布局实现，避免修改 position 导致虚拟滚动失效
      .monaco-list-row {
        .monaco-icon-label {
          width: 100% !important;

          .monaco-icon-label-container {
            width: 100% !important;
            display: flex !important;

            // 名字部分：自然生长，但不要挤占描述
            .monaco-icon-name-container {
              flex: 0 1 auto !important;
              overflow: hidden;
              text-overflow: ellipsis;
            }

            // 描述部分（类型）：强制靠右
            .monaco-icon-description-container {
              flex: 1 0 auto !important; // 允许占据剩余空间
              text-align: right !important;
              margin-left: auto !important;
              padding-left: 10px;
              opacity: 0.6;
              white-space: nowrap;
            }
          }
        }
      }
    }

    // 右侧详情框样式
    .details {
      z-index: 99999 !important;
      border: 1px solid var(--el-border-color-lighter) !important;
      background-color: var(--el-bg-color-overlay) !important;
      box-shadow: var(--el-box-shadow-light) !important;
    }
  }
</style>
