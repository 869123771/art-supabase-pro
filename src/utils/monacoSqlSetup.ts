import * as monaco from 'monaco-editor'
import { loader } from '@guolao/vue-monaco-editor'
import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'
import jsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker'
import cssWorker from 'monaco-editor/esm/vs/language/css/css.worker?worker'
import htmlWorker from 'monaco-editor/esm/vs/language/html/html.worker?worker'
import tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker'
import PgSQLWorker from 'monaco-sql-languages/esm/languages/pgsql/pgsql.worker?worker'
import {
  buildJoinSuggestions,
  buildSqlTemplateSuggestions,
  extractSqlAliases,
  getColumnsForSqlContext,
  resolveTableRef
} from './sqlWorkbench'

loader.config({ monaco })

import 'monaco-sql-languages/esm/languages/pgsql/pgsql.contribution'
import { LanguageIdEnum, setupLanguageFeatures } from 'monaco-sql-languages'

// Monaco 在 Vite 里需要手动分发不同语言的 worker。
// 这里把 pgsql worker 单独接进来，避免 SQL 提示和解析退化成纯文本。
self.MonacoEnvironment = {
  getWorker(_: any, label: string) {
    if (label === 'json') return new jsonWorker()
    if (label === 'css' || label === 'scss' || label === 'less') return new cssWorker()
    if (label === 'html' || label === 'handlebars' || label === 'razor') return new htmlWorker()
    if (label === 'typescript' || label === 'javascript') return new tsWorker()
    if (label === 'pgsql') return new PgSQLWorker()
    return new editorWorker()
  }
}

let dbMetadata: Api.DataCenter.SqlConsole.DatabaseMetadata = {
  schemas: [],
  tables: [],
  functions: [],
  columns: [],
  foreignKeys: []
}

export function registerSqlMetadata(metadata: Api.DataCenter.SqlConsole.DatabaseMetadata | any) {
  if (!metadata) return

  if (Array.isArray(metadata)) {
    dbMetadata.tables = metadata
    return
  }

  dbMetadata = {
    schemas: metadata.schemas || [],
    tables: metadata.tables || [],
    functions: metadata.functions || [],
    columns: metadata.columns || [],
    foreignKeys: metadata.foreignKeys || []
  }
}

function createRange(model: monaco.editor.ITextModel, position: monaco.Position) {
  const word = model.getWordUntilPosition(position)
  return {
    startLineNumber: position.lineNumber,
    endLineNumber: position.lineNumber,
    startColumn: word.startColumn,
    endColumn: word.endColumn
  }
}

function buildTableCompletionItems(range: monaco.IRange) {
  return dbMetadata.tables.flatMap((table) => {
    const schemaName = table.tableSchema || 'public'
    const columnsPreview = table.columns
      .slice(0, 6)
      .map((column) => `${column.name} ${column.dataType}`)
      .join(', ')
    const alias = table.tableName
      .split('_')
      .filter(Boolean)
      .map((item) => item[0])
      .join('')
      .toLowerCase()

    return [
      {
        label: table.tableName,
        kind: monaco.languages.CompletionItemKind.Class,
        detail: `TABLE ${schemaName}`,
        insertText: table.tableName,
        documentation: {
          value: `**${schemaName}.${table.tableName}**\n\n${columnsPreview || 'No columns loaded'}`
        },
        range,
        sortText: `30_${table.tableName}`
      },
      {
        label: `${schemaName}.${table.tableName}`,
        kind: monaco.languages.CompletionItemKind.Class,
        detail: 'Qualified table',
        insertText: `${schemaName}.${table.tableName} ${alias || 't'}`,
        range,
        sortText: `31_${table.tableName}`
      }
    ]
  })
}

function buildFunctionCompletionItems(range: monaco.IRange) {
  return dbMetadata.functions.map((fn) => ({
    label: fn.routineName,
    kind: monaco.languages.CompletionItemKind.Function,
    detail: `${fn.routineSchema}.${fn.routineName}() -> ${fn.returnType}`,
    insertText: `${fn.routineName}($1)`,
    insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
    range,
    sortText: `40_${fn.routineName}`
  }))
}

function buildSchemaCompletionItems(range: monaco.IRange) {
  return dbMetadata.schemas.map((schema) => ({
    label: schema,
    kind: monaco.languages.CompletionItemKind.Module,
    detail: 'Schema',
    insertText: schema,
    range,
    sortText: `50_${schema}`
  }))
}

function buildKeywordCompletionItems(range: monaco.IRange, keywords: string[] = []) {
  return keywords.map((keyword) => ({
    label: keyword,
    kind: monaco.languages.CompletionItemKind.Keyword,
    detail: 'Keyword',
    insertText: keyword,
    range,
    sortText: `80_${keyword}`
  }))
}

function buildColumnCompletionItems(
  range: monaco.IRange,
  sql: string,
  aliasOnly?: string
): monaco.languages.CompletionItem[] {
  const aliases = extractSqlAliases(sql)

  if (aliasOnly) {
    const table = resolveTableRef(aliasOnly, dbMetadata, aliases)
    if (!table) return []

    return table.columns.map((column) => ({
      label: column.name,
      kind: monaco.languages.CompletionItemKind.Field,
      detail: `${table.tableName}.${column.name} ${column.dataType}`,
      insertText: column.name,
      documentation: `Table: ${table.tableSchema}.${table.tableName}\nColumn: ${column.name}\nType: ${column.dataType}`,
      range,
      sortText: `00_${column.name}`
    }))
  }

  return getColumnsForSqlContext(sql, dbMetadata).map(({ alias, table, column }) => ({
    label: `${alias}.${column.name}`,
    kind: monaco.languages.CompletionItemKind.Field,
    detail: `${table.tableName}.${column.name} ${column.dataType}`,
    insertText: `${alias}.${column.name}`,
    documentation: `Table: ${table.tableSchema}.${table.tableName}\nColumn: ${column.name}\nType: ${column.dataType}`,
    range,
    sortText: `05_${alias}.${column.name}`
  }))
}

function buildJoinCompletionItems(range: monaco.IRange, sql: string) {
  return buildJoinSuggestions(sql, dbMetadata).map((item, index) => ({
    label: item.label,
    kind: monaco.languages.CompletionItemKind.Snippet,
    detail: item.detail,
    documentation: item.documentation,
    insertText: item.insertText,
    range,
    sortText: `10_${index}`,
    insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet
  }))
}

function buildTemplateCompletionItems(range: monaco.IRange) {
  return buildSqlTemplateSuggestions(dbMetadata).map((item, index) => ({
    label: item.label,
    kind: monaco.languages.CompletionItemKind.Snippet,
    detail: item.detail,
    documentation: item.documentation,
    insertText: item.insertText,
    range,
    sortText: `01_${index}`,
    insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet
  }))
}

setupLanguageFeatures(LanguageIdEnum.PG, {
  completionItems: {
    enable: true,
    triggerCharacters: [' ', '.', '('],
    completionService: async (
      model: monaco.editor.ITextModel,
      position: monaco.Position,
      context: monaco.languages.CompletionContext,
      suggestions: any
    ) => {
      const range = createRange(model, position)
      const fullSql = model.getValue()
      const lineContent = model.getLineContent(position.lineNumber)
      const textBeforeCursor = model.getValueInRange(
        new monaco.Range(1, 1, position.lineNumber, position.column)
      )
      const items: monaco.languages.CompletionItem[] = []
      const keywords = suggestions?.keywords || []

      const indexToCheck = position.column - 2
      const charBefore = indexToCheck >= 0 ? lineContent.charAt(indexToCheck) : ''
      const isDotTrigger = context.triggerCharacter === '.' || charBefore === '.'

      // a. 点号补全只返回别名下的列，避免把全库字段全塞进来。
      if (isDotTrigger) {
        const textBeforeDot = textBeforeCursor.slice(0, -1)
        const aliasMatch = textBeforeDot.match(/([a-zA-Z0-9_"]+)\s*$/)
        const alias = aliasMatch?.[1]?.replace(/"/g, '')

        if (alias) {
          return buildColumnCompletionItems(range, fullSql, alias)
        }
      }

      const upperBeforeCursor = textBeforeCursor.toUpperCase()
      const wantsTemplates =
        /^\s*$/.test(textBeforeCursor) ||
        /\b(SELECT|WITH|INSERT|UPDATE|DELETE)\s*$/i.test(textBeforeCursor)
      const wantsTables = /\b(FROM|JOIN|UPDATE|INTO)\s+[a-zA-Z0-9_."-]*$/i.test(textBeforeCursor)
      const wantsJoin = /\bJOIN\s+[a-zA-Z0-9_."-]*$/i.test(textBeforeCursor)
      const wantsSelectColumns =
        /\bSELECT\s+[^;]*$/i.test(textBeforeCursor) && /\bFROM\b/i.test(upperBeforeCursor)

      // b. 空白位置和语句开头优先给整句模板，接近 Cursor / DataGrip 的起手体验。
      if (wantsTemplates) {
        items.push(...buildTemplateCompletionItems(range))
      }

      // c. JOIN 上下文优先给可直接落地的关联语句，而不是只给表名。
      if (wantsJoin) {
        items.push(...buildJoinCompletionItems(range, fullSql))
      }

      if (wantsTables) {
        items.push(...buildTableCompletionItems(range))
      }

      if (wantsSelectColumns) {
        items.push(...buildColumnCompletionItems(range, fullSql))
      }

      items.push(...buildFunctionCompletionItems(range))
      items.push(...buildSchemaCompletionItems(range))
      items.push(...buildTableCompletionItems(range))
      items.push(...buildKeywordCompletionItems(range, keywords))

      return items
    }
  },
  diagnostics: false
})
