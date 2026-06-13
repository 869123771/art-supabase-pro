import type { Component } from 'vue'

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
  [key: string]: any
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
  dialogWidth?: string | number
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
}

export interface ArtDataSelectExpose {
  open: () => Promise<void>
  close: () => void
  clear: () => void
  reload: () => Promise<void>
}
