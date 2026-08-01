import type { ColInfo } from 'xlsx'
import { openFilePreview, type FilePreviewTarget } from '@/hooks/core/useFilePreview'

export type ExcelCellValue = string | number | boolean | null | undefined | Date

export type ExcelRecord = Record<string, unknown>

export interface ExcelColumn<TRecord extends ExcelRecord = ExcelRecord> {
  key: keyof TRecord | string
  title: string
  width?: number
  required?: boolean
  formatter?: (value: unknown, row: TRecord, index: number) => ExcelCellValue
}

export interface ExportExcelOptions<TRecord extends ExcelRecord = ExcelRecord> {
  data: TRecord[]
  columns: ExcelColumn<TRecord>[]
  filename?: string
  sheetName?: string
  autoIndex?: boolean
  indexColumnTitle?: string
  maxRows?: number
}

const formatExcelCellValue = (value: unknown): string => {
  if (value === null || value === undefined) return ''
  if (value instanceof Date) return value.toLocaleDateString('zh-CN')
  if (typeof value === 'boolean') return value ? '是' : '否'
  return String(value)
}

const calculateExcelColumnWidths = (
  rows: Record<string, string>[],
  columns: ExcelColumn[]
): ColInfo[] => {
  if (!rows.length) return []

  const sampleSize = Math.min(rows.length, 100)
  const titles = Object.keys(rows[0])

  return titles.map((title) => {
    const configuredWidth = columns.find((column) => column.title === title)?.width
    if (configuredWidth) return { wch: configuredWidth }

    const maxLength = Math.max(
      title.length,
      ...rows.slice(0, sampleSize).map((row) => String(row[title] || '').length)
    )
    return { wch: Math.min(Math.max(maxLength + 2, 8), 50) }
  })
}

export const buildExcelRows = <TRecord extends ExcelRecord>(
  data: TRecord[],
  columns: ExcelColumn<TRecord>[],
  options: Pick<ExportExcelOptions<TRecord>, 'autoIndex' | 'indexColumnTitle'> = {}
): Record<string, string>[] => {
  return data.map((row, index) => {
    const output: Record<string, string> = {}

    if (options.autoIndex) {
      output[options.indexColumnTitle || '序号'] = String(index + 1)
    }

    columns.forEach((column) => {
      const value = row[column.key]
      const formattedValue = column.formatter ? column.formatter(value, row, index) : value
      output[column.title] = formatExcelCellValue(formattedValue)
    })

    return output
  })
}

export const exportExcel = async <TRecord extends ExcelRecord>(
  options: ExportExcelOptions<TRecord>
): Promise<void> => {
  const {
    data,
    columns,
    filename = `export_${new Date().toISOString().slice(0, 10)}`,
    sheetName = 'Sheet1',
    autoIndex = false,
    indexColumnTitle = '序号',
    maxRows = 100000
  } = options

  if (!Array.isArray(data) || !data.length) {
    throw new Error('没有可导出的数据')
  }
  if (!Array.isArray(columns) || !columns.length) {
    throw new Error('没有可导出的列配置')
  }
  if (data.length > maxRows) {
    throw new Error(`导出数据不能超过 ${maxRows} 行`)
  }

  const [{ default: FileSaver }, XLSX] = await Promise.all([import('file-saver'), import('xlsx')])
  const rows = buildExcelRows(data, columns, { autoIndex, indexColumnTitle })
  const worksheet = XLSX.utils.json_to_sheet(rows)
  worksheet['!cols'] = calculateExcelColumnWidths(rows, columns as ExcelColumn[])

  const workbook = XLSX.utils.book_new()
  workbook.Props = {
    Title: filename,
    Subject: '数据导出',
    Author: 'Art Design Pro',
    CreatedDate: new Date(),
    ModifiedDate: new Date()
  }
  XLSX.utils.book_append_sheet(workbook, worksheet, sheetName)

  const buffer = XLSX.write(workbook, {
    bookType: 'xlsx',
    type: 'array',
    compression: true
  })
  const blob = new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  })

  FileSaver.saveAs(blob, `${filename}_${new Date().toISOString().slice(0, 10)}.xlsx`)
}

export async function importExcelFile(file: File): Promise<Array<Record<string, unknown>>> {
  const XLSX = await import('xlsx')
  return new Promise((resolve, reject) => {
    const reader = new FileReader()

    reader.onload = (event) => {
      try {
        const data = event.target?.result
        const workbook = XLSX.read(data, { type: 'array' })
        const firstSheetName = workbook.SheetNames[0]
        const worksheet = workbook.Sheets[firstSheetName]
        const rows = XLSX.utils.sheet_to_json(worksheet)
        resolve(rows as Array<Record<string, unknown>>)
      } catch (error) {
        reject(error)
      }
    }

    reader.onerror = (error) => reject(error)
    reader.readAsArrayBuffer(file)
  })
}

export const mapExcelRowsToRecords = <TRecord extends ExcelRecord>(
  rows: Array<Record<string, unknown>>,
  columns: ExcelColumn<TRecord>[]
): TRecord[] => {
  return rows
    .map((row) => {
      const output: Record<string, unknown> = {}

      columns.forEach((column) => {
        const key = String(column.key)
        const rawValue = row[column.title] ?? row[key]
        if (rawValue === undefined || rawValue === null) return

        output[key] = typeof rawValue === 'string' ? rawValue.trim() : rawValue
      })

      return output as TRecord
    })
    .filter((row) =>
      columns.every((column) => {
        if (!column.required) return true
        const value = row[String(column.key)]
        return value !== undefined && value !== null && String(value).trim() !== ''
      })
    )
}

export async function calcFileHash(file: File): Promise<string> {
  const buffer = await file.arrayBuffer()
  const hashBuffer = await crypto.subtle.digest('SHA-256', buffer)
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export type FileActionTarget = FilePreviewTarget

export const getFileExtension = (fileName?: string, suffix?: string): string => {
  const normalizedSuffix = suffix || fileName?.split('.').pop() || ''
  return normalizedSuffix.replace(/^\./, '').trim().toLowerCase()
}

export const viewFile = (url?: string): void => {
  if (!url) return
  window.open(url, '_blank', 'noopener,noreferrer')
}

export const downloadFile = (url?: string, filename = 'attachment'): void => {
  if (!url) return

  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.target = '_blank'
  link.rel = 'noopener noreferrer'
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
}

export const viewAttachment = (file: FileActionTarget): void => {
  openFilePreview(file)
}

export const downloadAttachment = (file: FileActionTarget): void => {
  downloadFile(file.url, file.name || 'attachment')
}

export function formatSize(size: number) {
  if (size < 1024) return size + ' B'
  if (size < 1024 * 1024) return (size / 1024).toFixed(2) + ' KB'
  if (size < 1024 * 1024 * 1024) return (size / 1024 / 1024).toFixed(2) + ' MB'
  return (size / 1024 / 1024 / 1024).toFixed(2) + ' GB'
}
