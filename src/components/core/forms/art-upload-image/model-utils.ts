export type UploadImageModelValue = string | string[] | null | undefined

/**
 * 将上传组件的单双值模型统一为独立的 URL 快照，供同步判断使用。
 */
export function normalizeUploadModelUrls(value: UploadImageModelValue): string[] {
  if (!value) return []
  return Array.isArray(value) ? [...value] : [value]
}

/**
 * 只有 URL 内容或顺序真正变化时才需要重建上传列表。
 */
export function shouldSyncUploadFileList(
  value: UploadImageModelValue,
  lastSyncedUrls: readonly string[]
): boolean {
  const nextUrls = normalizeUploadModelUrls(value)
  return (
    nextUrls.length !== lastSyncedUrls.length ||
    nextUrls.some((url, index) => url !== lastSyncedUrls[index])
  )
}
