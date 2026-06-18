import type { Ref } from 'vue'
import type { DialogPropsPublic } from 'element-plus'
import type {
  ArtOverlayExpose,
  ArtOverlayOptions,
  ArtScrollOptions
} from '@/hooks/core/useArtOverlay'

export interface ArtDialogOptions<TData = unknown> extends ArtOverlayOptions<
  TData,
  ArtDialogExpose<TData>
> {
  title?: string
  subtitle?: string
  width?: string | number
  fullscreen?: boolean
  showFullscreenButton?: boolean
  fullscreenText?: string
  exitFullscreenText?: string
  contentMaxHeight?: string | number
  dialogProps?: Partial<DialogPropsPublic> & Record<string, unknown>
}

export type ArtDialogProps<TData = unknown> = ArtDialogOptions<TData> &
  Partial<Omit<DialogPropsPublic, 'modelValue' | 'title' | 'width'>>

export interface ArtDialogExpose<TData = unknown> extends ArtOverlayExpose<
  TData,
  ArtDialogOptions<TData>
> {
  dialogRef: Readonly<Ref<unknown>>
  scrollbarRef: Readonly<Ref<unknown>>
  fullscreen: Readonly<Ref<boolean>>
  handleOpen: (data?: TData, options?: ArtDialogOptions<TData>) => Promise<void>
  getDialogInstance: () => unknown
  setFullscreen: (value: boolean) => void
  toggleFullscreen: () => void
  scrollTo: (options: ArtScrollOptions) => void
}

export type { ArtScrollOptions }
