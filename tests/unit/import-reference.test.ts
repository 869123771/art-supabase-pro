import assert from 'node:assert/strict'
import test from 'node:test'
import { requireUniqueImportReference } from '../../src/utils/business/import-reference'

test('import references retain the complete single record', () => {
  const record = { id: 'employee-test', employeeNo: 'EMP-001', tenantId: 'tenant-test' }
  assert.equal(requireUniqueImportReference([record], '员工工号：EMP-001'), record)
})
test('missing or incomplete import references block business writes', () => {
  for (const records of [[], [{ id: '' }], [{}]])
    assert.throws(
      () => requireUniqueImportReference(records, '员工工号：EMP-001'),
      /未找到员工工号：EMP-001/
    )
})
test('ambiguous import identifiers never silently select the first record', () => {
  assert.throws(
    () => requireUniqueImportReference([{ id: 'one' }, { id: 'two' }], '启用仓库编码：WH-001'),
    /存在多个匹配记录/
  )
})
