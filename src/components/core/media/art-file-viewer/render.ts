import { h, type VNode } from 'vue'
import type { FilePreviewTarget } from '@/hooks/core/useFilePreview'
import ArtAttachmentLink from './attachment-link.vue'

export const renderAttachmentLink = <T extends FilePreviewTarget>(row: T): VNode =>
  h(ArtAttachmentLink, { file: row })
