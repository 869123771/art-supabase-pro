import { ElMessage } from 'element-plus'
import { openFilePreview, type FilePreviewTarget } from '@/hooks/core/useFilePreview'

export const previewAttachment = (file: FilePreviewTarget): void => {
  const result = openFilePreview(file)
  if (result === 'missing-url') ElMessage.warning('附件没有可用的预览地址')
  if (result === 'blocked') ElMessage.warning('浏览器阻止了新页签，请允许本站打开弹出式窗口')
}
