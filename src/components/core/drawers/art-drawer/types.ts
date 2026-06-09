import type { Ref } from 'vue'
import type { DrawerPropsPublic } from 'element-plus'
import type {
  ArtOverlayExpose,
  ArtOverlayOptions,
  ArtScrollOptions
} from '@/hooks/core/useArtOverlay'

export interface ArtDrawerOptions<TData = unknown> extends ArtOverlayOptions<
  TData,
  ArtDrawerExpose<TData>
> {
  title?: string
  size?: string | number
  direction?: 'ltr' | 'rtl' | 'ttb' | 'btt'
  drawerProps?: Partial<DrawerPropsPublic> & Record<string, unknown>
}

export type ArtDrawerProps<TData = unknown> = ArtDrawerOptions<TData> &
  Partial<Omit<DrawerPropsPublic, 'modelValue' | 'title' | 'size' | 'direction'>>

export interface ArtDrawerExpose<TData = unknown> extends ArtOverlayExpose<
  TData,
  ArtDrawerOptions<TData>
> {
  drawerRef: Readonly<Ref<unknown>>
  scrollbarRef: Readonly<Ref<unknown>>
  handleOpen: (data?: TData, options?: ArtDrawerOptions<TData>) => Promise<void>
  getDrawerInstance: () => unknown
  scrollTo: (options: ArtScrollOptions) => void
}

export type { ArtScrollOptions }
