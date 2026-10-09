/** Imported identifiers must resolve to one complete record before a business write. */
export function requireUniqueImportReference<T extends { id?: string }>(
  records: readonly T[],
  description: string
): T {
  const [record] = records
  if (!record?.id) throw new Error(`未找到${description}`)
  if (records.length !== 1) throw new Error(`${description}存在多个匹配记录，请核对编号后重新导入`)
  return record
}
