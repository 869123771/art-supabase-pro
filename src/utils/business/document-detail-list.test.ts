import assert from 'node:assert/strict'
import test from 'node:test'
import {
  documentGroupSpan,
  expandDocumentLines,
  groupDocumentLines,
  loadAllDocumentPages,
  loadAllLinePages,
  paginateDetailRows
} from './document-detail-list'

test('line pagination counts every detail and keeps its document visible at a page boundary', async () => {
  const documents = [
    { id: 'one', lines: [{ id: 'a' }, { id: 'b' }, { id: 'c' }] },
    { id: 'two', lines: [{ id: 'd' }] }
  ]
  const loaded = await loadAllDocumentPages(
    async ({ from = 0, to = 0 }) => ({
      data: documents.slice(from, to + 1),
      total: documents.length
    }),
    { from: 0, to: 0 },
    1
  )
  const rows = expandDocumentLines(
    loaded,
    (document) => document.lines,
    (line) => line.id
  )
  const page = paginateDetailRows(rows, 2, 3)

  assert.equal(page.total, 4)
  assert.deepEqual(
    page.data.map((row) => row.detailRowId),
    ['one:c', 'two:d']
  )
  assert.equal(page.data[0]?.detailGroupStart, true)
  assert.equal(page.data[1]?.detailGroupStart, true)
})

test('document mode groups line pages before pagination', async () => {
  const source = [
    { documentId: 'one', lineId: 'a' },
    { documentId: 'one', lineId: 'b' },
    { documentId: 'two', lineId: 'c' }
  ]
  const lines = await loadAllLinePages(
    async ({ current, size }) => ({
      data: source.slice((current - 1) * size, current * size),
      total: source.length
    }),
    { current: 1, size: 1 },
    2
  )
  const groups = groupDocumentLines(lines, (line) => line.documentId)
  assert.deepEqual(
    groups.map((group) => group.lines.length),
    [2, 1]
  )
})

test('repeated document cells merge while detail cells stay separate', () => {
  const rows = [{ id: 'one' }, { id: 'one' }, { id: 'two' }]
  const lineProperties = new Set(['materialCode'])
  assert.deepEqual(documentGroupSpan(rows, 0, 'documentNo', lineProperties), [2, 1])
  assert.deepEqual(documentGroupSpan(rows, 1, 'documentNo', lineProperties), [0, 0])
  assert.deepEqual(documentGroupSpan(rows, 1, 'materialCode', lineProperties), [1, 1])
  assert.deepEqual(documentGroupSpan(rows, 2, 'documentNo', lineProperties), [1, 1])
})
