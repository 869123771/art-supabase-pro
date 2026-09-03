const ABSOLUTE_PROTOCOL_PATTERN = /^[a-z][a-z\d+.-]*:/i

export function normalizeEditorUrl(rawValue: string, allowedProtocols: string[]): string {
  const value = rawValue.trim()
  if (!value) return ''
  if (value.startsWith('/') || value.startsWith('#')) return value

  const candidate = ABSOLUTE_PROTOCOL_PATTERN.test(value) ? value : `https://${value}`

  try {
    const parsedUrl = new URL(candidate)
    return allowedProtocols.includes(parsedUrl.protocol) ? parsedUrl.href : ''
  } catch {
    return ''
  }
}

export function isAcceptedFileType(file: File, accept: string): boolean {
  const acceptedTypes = accept
    .split(',')
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean)

  if (acceptedTypes.length === 0) return true

  const mimeType = file.type.toLowerCase()
  const fileName = file.name.toLowerCase()

  return acceptedTypes.some((acceptedType) => {
    if (acceptedType.endsWith('/*')) return mimeType.startsWith(acceptedType.slice(0, -1))
    if (acceptedType.startsWith('.')) return fileName.endsWith(acceptedType)
    return mimeType === acceptedType
  })
}

/** @deprecated Use `isAcceptedFileType` for images and other uploaded files. */
export const isAcceptedImageType = isAcceptedFileType
