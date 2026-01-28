import * as monaco from 'monaco-editor'
import { loader } from '@guolao/vue-monaco-editor'
import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'
import jsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker'
import cssWorker from 'monaco-editor/esm/vs/language/css/css.worker?worker'
import htmlWorker from 'monaco-editor/esm/vs/language/html/html.worker?worker'
import tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker'
import PgSQLWorker from 'monaco-sql-languages/esm/languages/pgsql/pgsql.worker?worker'

// 0. 配置 loader 使用本地 monaco 实例
loader.config({ monaco })

// 1. 导入贡献文件，自动注册语言
import 'monaco-sql-languages/esm/languages/pgsql/pgsql.contribution'
// 2. 从主入口导入设置函数
import { LanguageIdEnum, setupLanguageFeatures } from 'monaco-sql-languages'

// 配置 Monaco Worker
// @ts-expect-error: MonacoEnvironment is added to window by monaco-editor loader
self.MonacoEnvironment = {
  getWorker(_: any, label: string) {
    if (label === 'json') {
      return new jsonWorker()
    }
    if (label === 'css' || label === 'scss' || label === 'less') {
      return new cssWorker()
    }
    if (label === 'html' || label === 'handlebars' || label === 'razor') {
      return new htmlWorker()
    }
    if (label === 'typescript' || label === 'javascript') {
      return new tsWorker()
    }
    if (label === 'pgsql') {
      return new PgSQLWorker()
    }
    return new editorWorker()
  }
}

// 3. 配置启用补全
// 存储元数据
let dbMetadata: Api.DataCenter.SqlConsole.DatabaseMetadata = {
  schemas: [],
  tables: [],
  functions: [],
  columns: []
}

// 导出注册函数
export function registerSqlMetadata(metadata: any) {
  if (!metadata) return

  if (Array.isArray(metadata)) {
    dbMetadata.tables = metadata
  } else {
    // 确保结构完整
    dbMetadata = {
      schemas: metadata.schemas || [],
      tables: metadata.tables || [],
      functions: metadata.functions || [],
      columns: metadata.columns || []
    }
  }
  console.log('SQL Metadata Registered:', dbMetadata)
}

function findTableByAlias(
  sql: string,
  alias: string
): Api.DataCenter.SqlConsole.TableMetadata | undefined {
  if (!dbMetadata.tables) return undefined

  // 1. 尝试直接匹配表名 (如果 alias 本身就是表名)
  const directMatch = dbMetadata.tables.find((t) => t.tableName === alias)
  if (directMatch) return directMatch

  // 2. 尝试解析 alias
  // 匹配模式: FROM tableName alias 或 JOIN tableName alias
  // 忽略大小写
  // \b 单词边界
  // 捕获组 1: 表名
  const regex = new RegExp(`\\b([a-zA-Z0-9_]+)\\s+(?:AS\\s+)?${alias}\\b`, 'i')
  const match = sql.match(regex)

  if (match) {
    const tableName = match[1]
    return dbMetadata.tables.find((t) => t.tableName === tableName)
  }

  return undefined
}

setupLanguageFeatures(LanguageIdEnum.PG, {
  completionItems: {
    enable: true,
    triggerCharacters: [' ', '.', '"'],
    completionService: async (
      model: monaco.editor.ITextModel,
      position: monaco.Position,
      context: monaco.languages.CompletionContext,
      suggestions: any
    ) => {
      const items: any[] = []
      const { keywords } = suggestions || {}

      const word = model.getWordUntilPosition(position)
      const range = {
        startLineNumber: position.lineNumber,
        endLineNumber: position.lineNumber,
        startColumn: word.startColumn,
        endColumn: word.endColumn
      }

      // 获取当前行内容
      const lineContent = model.getLineContent(position.lineNumber)

      // 确定检查点号的位置
      // 如果当前在输入单词中，检查单词前的字符
      // 如果不在单词中（刚输入点号），检查光标前的字符
      let indexToCheck = position.column - 2
      if (word.word.length > 0) {
        indexToCheck = word.startColumn - 2
      }

      const charBefore = indexToCheck >= 0 ? lineContent.charAt(indexToCheck) : ''
      const isDotTrigger = context.triggerCharacter === '.' || charBefore === '.'

      if (isDotTrigger) {
        // 尝试获取点号前的别名
        if (indexToCheck >= 0) {
          // 提取点号前的单词
          // 从 indexToCheck - 1 开始向前找 (indexToCheck 是点号的位置)
          const textBeforeDot = lineContent.substring(0, indexToCheck)
          // 简单的正则提取最后一个单词
          const match = textBeforeDot.match(/([a-zA-Z0-9_]+)\s*$/)
          if (match) {
            const alias = match[1]
            const fullSql = model.getValue()
            const table = findTableByAlias(fullSql, alias)

            if (table && table.columns) {
              // 如果找到了表，只返回该表的字段
              table.columns.forEach((col) => {
                items.push({
                  label: col.name,
                  kind: monaco.languages.CompletionItemKind.Field,
                  detail: col.dataType, // 右侧显示字段类型
                  insertText: col.name,
                  documentation: `Table: ${table.tableName}\nColumn: ${col.name}\nType: ${col.dataType}`,
                  range: range,
                  sortText: '00' + col.name // 保证排在最前
                })
              })
              return items
            }
          }
        }
      }

      // 如果不是点号触发，或者没找到对应的表，返回默认建议
      // 1. 关键字
      if (keywords) {
        items.push(
          ...keywords.map((kw: string) => ({
            label: kw,
            kind: monaco.languages.CompletionItemKind.Keyword,
            detail: 'Keyword',
            insertText: kw,
            range: range,
            sortText: '90' + kw // 关键字放后面
          }))
        )
      }

      // 2. Schema
      if (dbMetadata.schemas) {
        dbMetadata.schemas.forEach((schema: string) => {
          items.push({
            label: schema,
            kind: monaco.languages.CompletionItemKind.Module,
            detail: 'Schema',
            insertText: schema,
            range: range,
            sortText: '80' + schema
          })
        })
      }

      // 3. 表名
      if (dbMetadata.tables) {
        dbMetadata.tables.forEach((table: Api.DataCenter.SqlConsole.TableMetadata) => {
          const schemaName = table.tableSchema || 'public'
          // 构建表结构的简要描述
          const columnsPreview = table.columns
            ? `(${table.columns.map((c) => `${c.name} ${c.dataType}`).join(', ')})`
            : ''

          // 表名
          items.push({
            label: table.tableName,
            kind: monaco.languages.CompletionItemKind.Class,
            detail: `TABLE${columnsPreview}`, // 右侧显示表结构预览
            insertText: table.tableName,
            documentation: {
              value: `**Table**: ${schemaName}.${table.tableName}\n\n**Columns**:\n${table.columns
                ?.map((c) => `- \`${c.name}\`: ${c.dataType}`)
                .join('\n')}`
            },
            range: range,
            sortText: '50' + table.tableName
          })

          // schema.table
          items.push({
            label: `${schemaName}.${table.tableName}`,
            kind: monaco.languages.CompletionItemKind.Class,
            detail: 'Table',
            insertText: `${schemaName}.${table.tableName}`,
            range: range,
            sortText: '60' + table.tableName
          })
        })
      }

      // 注意：这里不再默认添加所有字段，避免重复和干扰

      return items
    }
  },
  diagnostics: { enable: false } // 可先关闭诊断聚焦补全
})

console.log('PGSQL 语言支持已加载（Monaco 0.31.0）。')
