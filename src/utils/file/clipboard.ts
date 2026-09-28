import dayjs from 'dayjs'

/** Prefer clipboard items so pasted screenshots work in browsers with an empty files list. */
export function getClipboardFiles(clipboardData: DataTransfer | null): File[] {
  const itemFiles = Array.from(clipboardData?.items ?? [])
    .filter((item) => item.kind === 'file')
    .map((item) => item.getAsFile())
    .filter((file): file is File => file !== null)

  return itemFiles.length ? itemFiles : Array.from(clipboardData?.files ?? [])
}

function getClipboardFileExtension(mimeType: string): string {
  const knownExtensions: Record<string, string> = {
    'application/msword': 'doc',
    'application/pdf': 'pdf',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.ms-powerpoint': 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
    'audio/mpeg': 'mp3',
    'image/jpeg': 'jpg',
    'image/svg+xml': 'svg',
    'image/x-icon': 'ico',
    'text/plain': 'txt',
    'video/quicktime': 'mov'
  }
  return knownExtensions[mimeType] ?? mimeType.split('/')[1]?.split('+')[0] ?? 'bin'
}

/** Clipboard screenshots often have only a generic browser-generated name. */
export function createNamedClipboardFile(file: File, index: number, total: number): File {
  const originalName = file.name.trim()
  if (originalName && !/^(?:image|blob)(?:\.[^.]+)?$/i.test(originalName)) return file

  const timestamp = dayjs().format('YYYYMMDD_HHmmss')
  const sequence = total > 1 ? `_${index + 1}` : ''
  const extension = getClipboardFileExtension(file.type)
  const prefix = file.type.startsWith('image/') ? '粘贴图片' : '粘贴文件'
  return new File([file], `${prefix}_${timestamp}${sequence}.${extension}`, {
    type: file.type,
    lastModified: Date.now()
  })
}
