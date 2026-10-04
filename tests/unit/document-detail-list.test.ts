import assert from 'node:assert/strict'
import test from 'node:test'
import {
  documentGroupSpan,
  expandDocumentLines,
  groupDocumentLines,
  loadAllDocumentPages,
  loadAllLinePages,
  paginateDetailRows
} from '../../src/utils/business/document-detail-list'

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

test('both pagination formats keep reading full pages when the total is absent', async () => {
  const source = [1, 2, 3, 4]
  const ranges: number[] = []
  const documents = await loadAllDocumentPages(
    async ({ from = 0, to = 0, status }) => {
      assert.equal(status, 'ready')
      ranges.push(from)
      return { data: source.slice(from, to + 1) }
    },
    { from: 99, to: 99, status: 'ready' },
    2
  )
  const pages: number[] = []
  const lines = await loadAllLinePages(
    async ({ current, size, status }) => {
      assert.equal(status, 'ready')
      pages.push(current)
      return { data: source.slice((current - 1) * size, current * size), total: null }
    },
    { current: 99, size: 99, status: 'ready' },
    2
  )
  assert.deepEqual(documents, source)
  assert.deepEqual(lines, source)
  assert.deepEqual(ranges, [0, 2, 4])
  assert.deepEqual(pages, [1, 2, 3])
})

test('invalid batch sizes fail before either pagination format sends a request', async () => {
  let calls = 0
  const fetchPage = async () => {
    calls += 1
    return { data: [] }
  }
  for (const size of [0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    await assert.rejects(loadAllDocumentPages(fetchPage, {}, size), /正安全整数/)
    await assert.rejects(loadAllLinePages(fetchPage, { current: 1, size: 1 }, size), /正安全整数/)
  }
  assert.equal(calls, 0)
})

test('invalid counts and incomplete results cannot look like a complete document list', async () => {
  for (const total of [-1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    await assert.rejects(
      loadAllDocumentPages(async () => ({ data: [], total }), {}),
      /总数无效/
    )
  }
  await assert.rejects(
    loadAllDocumentPages(async () => ({ data: [1], total: 2 }), {}, 2),
    /未完整加载/
  )
  const cause = new Error('second page failed')
  await assert.rejects(
    loadAllLinePages(
      async ({ current }) => (current === 1 ? { data: [1], total: 2 } : { error: cause }),
      { current: 1, size: 1 },
      1
    ),
    (error) => error === cause
  )
})

test('large later pages preserve every row without argument overflow', async () => {
  const data = Array.from({ length: 400_000 }, (_, index) => index)
  const result = await loadAllLinePages(
    async ({ current, size }) => ({
      data: data.slice((current - 1) * size, current * size),
      total: data.length
    }),
    { current: 1, size: 1 },
    200_000
  )
  assert.deepEqual(result, data)
})
