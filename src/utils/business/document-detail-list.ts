export interface DocumentPage<T> {
  data?: T[] | null
  total?: number | null
  error?: unknown
}

export type DetailListRow<TDocument, TLine> = TDocument & {
  detailRowId: string
  detailLine: TLine
  detailGroupStart: boolean
}

/** Load documents before line pagination so a page never silently drops sibling lines. */
export async function loadAllDocumentPages<
  TDocument,
  TQuery extends { from?: number; to?: number }
>(
  fetchPage: (query: TQuery) => Promise<DocumentPage<TDocument>>,
  query: TQuery,
  batchSize = 500
): Promise<TDocument[]> {
  const first = await fetchPage({ ...query, from: 0, to: batchSize - 1 })
  if (first.error) throw first.error
  const documents = [...(first.data ?? [])]
  for (let from = batchSize; from < (first.total ?? documents.length); from += batchSize) {
    const page = await fetchPage({ ...query, from, to: from + batchSize - 1 })
    if (page.error) throw page.error
    documents.push(...(page.data ?? []))
  }
  return documents
}

export function expandDocumentLines<TDocument extends { id: string }, TLine>(
  documents: TDocument[],
  getLines: (document: TDocument) => TLine[],
  getLineId: (line: TLine, index: number) => string
): DetailListRow<TDocument, TLine>[] {
  return documents.flatMap((document) =>
    getLines(document).map((line, index) => ({
      ...document,
      detailRowId: `${document.id}:${getLineId(line, index)}`,
      detailLine: line,
      detailGroupStart: index === 0
    }))
  )
}

export function paginateDetailRows<TDocument, TLine>(
  rows: DetailListRow<TDocument, TLine>[],
  from = 0,
  to = 49
): { data: DetailListRow<TDocument, TLine>[]; total: number } {
  const data = rows.slice(from, to + 1)
  if (data[0]) data[0] = { ...data[0], detailGroupStart: true }
  return { data, total: rows.length }
}

export async function loadAllLinePages<TLine, TQuery extends { current: number; size: number }>(
  fetchPage: (query: TQuery) => Promise<DocumentPage<TLine>>,
  query: TQuery,
  batchSize = 500
): Promise<TLine[]> {
  const first = await fetchPage({ ...query, current: 1, size: batchSize })
  if (first.error) throw first.error
  const lines = [...(first.data ?? [])]
  for (let current = 2; (current - 1) * batchSize < (first.total ?? lines.length); current++) {
    const page = await fetchPage({ ...query, current, size: batchSize })
    if (page.error) throw page.error
    lines.push(...(page.data ?? []))
  }
  return lines
}

export function groupDocumentLines<TLine>(
  lines: TLine[],
  getDocumentId: (line: TLine) => string
): Array<{ first: TLine; lines: TLine[] }> {
  const groups = new Map<string, { first: TLine; lines: TLine[] }>()
  for (const line of lines) {
    const id = getDocumentId(line)
    const group = groups.get(id)
    if (group) group.lines.push(line)
    else groups.set(id, { first: line, lines: [line] })
  }
  return [...groups.values()]
}

/** Merge repeated document fields while keeping every material cell independent. */
export function documentGroupSpan<T extends { documentId?: string; id?: string }>(
  rows: T[],
  rowIndex: number,
  property: string | undefined,
  lineProperties: ReadonlySet<string>,
  getDocumentId: (row: T) => string = (row) => row.documentId || row.id || ''
): [number, number] {
  if (!property || lineProperties.has(property) || !rows[rowIndex]) return [1, 1]
  const documentId = getDocumentId(rows[rowIndex])
  if (!documentId) return [1, 1]
  if (rowIndex > 0 && getDocumentId(rows[rowIndex - 1]) === documentId) return [0, 0]
  let count = 1
  while (rowIndex + count < rows.length && getDocumentId(rows[rowIndex + count]) === documentId) {
    count += 1
  }
  return [count, 1]
}
