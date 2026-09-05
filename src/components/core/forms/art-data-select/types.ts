/* eslint-disable @typescript-eslint/no-explicit-any -- ArtDataSelect 是通用选择器，需要兼容没有索引签名的业务 DTO；后续可在组件泛型化时进一步收紧。 */
import type { Component } from 'vue'
import type { DictColumnOption } from '@/types/component'
import type { ArtDialogSize } from '@/components/core/dialogs/art-dialog/types'

export type DataSelectKey = string | number
export type DataSelectMode = 'table' | 'tree'
export type DataSelectModelValue = DataSelectKey | DataSelectKey[] | undefined
export type MaybePromise<T> = T | Promise<T>

export interface DataSelectRecord {
  [key: string]: any
}

export interface DataSelectColumn {
  prop: string
  label: string
  width?: string | number
  minWidth?: string | number
  align?: 'left' | 'center' | 'right'
  formatter?: (row: DataSelectRecord) => string | number | Component
  dict?: DictColumnOption<DataSelectRecord>
  tagType?:
    | 'primary'
    | 'success'
    | 'info'
    | 'warning'
    | 'danger'
    | ((row: DataSelectRecord) => 'primary' | 'success' | 'info' | 'warning' | 'danger')
}

export interface DataSelectFilterOption {
  label: string
  value: string | number
}

export interface DataSelectFetchParams {
  keyword: string
  page: number
  pageSize: number
  filters: Record<string, string | number | undefined>
}

export interface DataSelectFetchResult {
  data?: DataSelectRecord[]
  list?: DataSelectRecord[]
  records?: DataSelectRecord[]
  total?: number
  [key: string]: unknown
}

export type DataSelectApiFn = (
  params: DataSelectFetchParams
) => MaybePromise<DataSelectFetchResult | DataSelectRecord[]>

export interface ArtDataSelectProps {
  modelValue?: DataSelectModelValue
  selectedData?: DataSelectRecord[]
  mode?: DataSelectMode
  multiple?: boolean
  data?: DataSelectRecord[]
  apiFn?: DataSelectApiFn
  columns?: DataSelectColumn[]
  title?: string
  subtitle?: string
  placeholder?: string
  searchPlaceholder?: string
  filterPlaceholder?: string
  filterKey?: string
  filterOptions?: DataSelectFilterOption[]
  rowKey?: string | ((row: DataSelectRecord) => DataSelectKey)
  labelKey?: string | ((row: DataSelectRecord) => string)
  descriptionKey?: string | ((row: DataSelectRecord) => string)
  disabledKey?: string | ((row: DataSelectRecord) => boolean)
  childrenKey?: string
  resultField?: string
  totalField?: string
  dialogWidth?: string | number | ArtDialogSize
  fullscreen?: boolean
  pageSize?: number
  pageSizes?: number[]
  showPagination?: boolean
  showSearch?: boolean
  showSelectedPanel?: boolean
  clearable?: boolean
  disabled?: boolean
  reserveSelected?: boolean
  treeCheckStrictly?: boolean
  maxTagCount?: number
  emptyText?: string
  emptyDescription?: string
}

export interface ArtDataSelectMultipleProps extends Omit<
  ArtDataSelectProps,
  'mode' | 'multiple' | 'modelValue'
> {
  modelValue?: DataSelectKey[]
}

export interface ArtDataSelectSingleProps extends Omit<
  ArtDataSelectProps,
  'mode' | 'multiple' | 'modelValue'
> {
  modelValue?: DataSelectKey
}

export interface ArtDataSelectEmits {
  (e: 'update:modelValue', value: DataSelectModelValue): void
  (e: 'update:selectedData', value: DataSelectRecord[]): void
  (e: 'change', value: DataSelectModelValue, rows: DataSelectRecord[]): void
  (e: 'confirm', value: DataSelectModelValue, rows: DataSelectRecord[]): void
  (e: 'clear'): void
  (e: 'open'): void
  (e: 'close'): void
  /** Raw diagnostic cause; the component owns inline recovery feedback, not a toast. */
  (e: 'load-error', error: unknown): void
}

export interface ArtDataSelectExpose {
  open: () => Promise<void>
  close: () => void
  clear: () => void
  reload: () => Promise<void>
}
