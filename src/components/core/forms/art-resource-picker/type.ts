import type { DialogEmits } from 'element-plus'

export interface Resource {
  id?: number
  storageMode?: number
  originName?: string
  objectName?: string
  hash?: string
  mimeType?: string
  storagePath?: string
  suffix?: string
  sizeByte?: number
  sizeInfo?: string
  url?: string
}

export interface FileType {
  value: string
  label: string | (() => string)
  suffix: string
  icon?: string
  [key: string]: any
}

// 定义 Props 类型
export interface ResourcePanelProps {
  multiple?: boolean
  limit?: number
  pageSize?: number
  showAction?: boolean
  dbClickConfirm?: boolean
  defaultFileType?: string
  fileTypes?: FileType[]
}

export interface ResourcePanelEmits {
  cancel: () => void
  confirm: (value: Resource[]) => void
}

export interface ResourcePickerProps extends ResourcePanelProps {
  visible: boolean
}
export interface ResourcePickerEmits extends ResourcePanelEmits, DialogEmits {}
