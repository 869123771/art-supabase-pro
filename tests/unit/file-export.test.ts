import assert from 'node:assert/strict'
import test from 'node:test'
import { buildExcelFilename, buildExcelRows, downloadBlob } from '../../src/utils/file'

test('Excel rows preserve column policy and format supported values', () => {
  const rows = buildExcelRows(
    [{ name: '测试', amount: 0, enabled: false, createdAt: new Date('2026-09-10T00:00:00Z') }],
    [
      { key: 'name', title: '名称' },
      { key: 'amount', title: '金额' },
      { key: 'enabled', title: '启用' },
      { key: 'createdAt', title: '日期', formatter: () => '2026-09-10' }
    ],
    { autoIndex: true, indexColumnTitle: '序号' }
  )

  assert.deepEqual(rows, [{ 序号: '1', 名称: '测试', 金额: '0', 启用: '否', 日期: '2026-09-10' }])
})

test('Excel filename policy supports stable date, timestamp and no suffix', () => {
  const now = new Date('2026-09-10T07:08:09.123Z')
  assert.equal(buildExcelFilename('报表', 'date', now), '报表_2026-09-10.xlsx')
  assert.equal(buildExcelFilename('报表', 'datetime', now), '报表_2026-09-10T07-08-09-123Z.xlsx')
  assert.equal(buildExcelFilename('报表', false, now), '报表.xlsx')
})

test('blob downloads release their temporary URL after triggering the browser download', async () => {
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document')
  const originalCreateObjectUrl = Object.getOwnPropertyDescriptor(URL, 'createObjectURL')
  const originalRevokeObjectUrl = Object.getOwnPropertyDescriptor(URL, 'revokeObjectURL')
  const events: string[] = []
  const anchor = {
    href: '',
    download: '',
    target: '',
    rel: '',
    click: () => events.push('click')
  }

  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      createElement: () => anchor,
      body: {
        appendChild: () => events.push('append'),
        removeChild: () => events.push('remove')
      }
    }
  })
  Object.defineProperty(URL, 'createObjectURL', {
    configurable: true,
    value: () => 'blob:download-test'
  })
  Object.defineProperty(URL, 'revokeObjectURL', {
    configurable: true,
    value: (url: string) => events.push(`revoke:${url}`)
  })

  try {
    downloadBlob(new Blob(['report']), 'report.csv')
    await new Promise((resolve) => setTimeout(resolve, 5))

    assert.equal(anchor.href, 'blob:download-test')
    assert.equal(anchor.download, 'report.csv')
    assert.deepEqual(events, ['append', 'click', 'remove', 'revoke:blob:download-test'])
  } finally {
    if (originalDocument) Object.defineProperty(globalThis, 'document', originalDocument)
    else delete (globalThis as { document?: unknown }).document
    if (originalCreateObjectUrl)
      Object.defineProperty(URL, 'createObjectURL', originalCreateObjectUrl)
    if (originalRevokeObjectUrl)
      Object.defineProperty(URL, 'revokeObjectURL', originalRevokeObjectUrl)
  }
})
