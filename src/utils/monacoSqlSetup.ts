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
// @ts-ignore
self.MonacoEnvironment = {
  getWorker(_, label) {
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
let dbMetadata: any = {
  schemas: [],
  tables: [],
  functions: []
}

// 导出注册函数
export function registerSqlMetadata(metadata: any) {
  dbMetadata = metadata
  console.log('SQL Metadata Registered:', dbMetadata)
}

setupLanguageFeatures(LanguageIdEnum.PG, {
  completionItems: {
    enable: true,
    triggerCharacters: [' ', '.', '"'],
    completionService: async (model, position, context, suggestions) => {
      if (!suggestions) {
        return []
      }

      const { keywords, syntax } = suggestions
      const items: any[] = []

      // 添加默认关键字
      if (keywords) {
        items.push(
          ...keywords.map((kw: string) => ({
            label: kw,
            kind: monaco.languages.CompletionItemKind.Keyword,
            detail: 'Keyword',
            insertText: kw
          }))
        )
      }

      // 如果有语法提示，尝试匹配
      // 简单策略：总是把表名和字段名作为 Text 或 Field 提示出来
      // 更智能的策略需要分析 syntax 内容，但这里我们先全量提供，依靠 Monaco 的模糊匹配

      // 添加 Schema
      if (dbMetadata.schemas) {
        dbMetadata.schemas.forEach((schema: string) => {
          items.push({
            label: schema,
            kind: monaco.languages.CompletionItemKind.Module,
            detail: 'Schema',
            insertText: schema
          })
        })
      }

      // 添加表名
      if (dbMetadata.tables) {
        dbMetadata.tables.forEach((table: any) => {
          // 添加表名
          items.push({
            label: table.tableName,
            kind: monaco.languages.CompletionItemKind.Class,
            detail: `Table (${table.schema})`,
            insertText: table.tableName,
            documentation: `Schema: ${table.schema}`
          })

          // 添加全限定名 schema.table
          items.push({
            label: `${table.schema}.${table.tableName}`,
            kind: monaco.languages.CompletionItemKind.Class,
            detail: 'Table',
            insertText: `${table.schema}.${table.tableName}`
          })

          // 添加字段
          if (table.columns) {
            table.columns.forEach((col: any) => {
              items.push({
                label: col.name,
                kind: monaco.languages.CompletionItemKind.Field,
                detail: `Column (${table.tableName})`,
                insertText: col.name,
                documentation: `Type: ${col.dataType}, Table: ${table.tableName}`
              })
            })
          }
        })
      }

      return items
    }
  },
  diagnostics: { enable: false } // 可先关闭诊断聚焦补全
})
console.log('PGSQL 语言支持已加载（Monaco 0.31.0）。')
