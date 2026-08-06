import assert from 'node:assert/strict'
import test from 'node:test'
import {
  inferAiBankBatchMapping,
  normalizeAiBankBatchRows
} from '../../supabase/functions/_shared/ai-bank-statement-batch-contract'

const counterparties = [
  { id: 'customer-1', name: '杭州示例科技有限公司', direction: 'receipt' as const }
]
const statementCandidates = [
  {
    statementId: 'statement-1',
    statementNo: 'CS202608-001',
    counterpartyId: 'customer-1',
    counterpartyName: '杭州示例科技有限公司',
    periodStart: '2026-08-01',
    periodEnd: '2026-08-31',
    statementAmount: 1000,
    settledAmount: 0,
    outstandingAmount: 1000
  }
]

test('bank batch infers common Chinese bank headers', () => {
  const mapping = inferAiBankBatchMapping([
    '交易日期',
    '贷方金额',
    '对方户名',
    '银行流水号',
    '摘要'
  ])
  assert.equal(mapping.transactionDate, '交易日期')
  assert.equal(mapping.receiptAmount, '贷方金额')
  assert.equal(mapping.counterpartyName, '对方户名')
})

test('bank batch normalizes and matches a ready receipt row', () => {
  const rows = normalizeAiBankBatchRows(
    [
      {
        交易日期: '2026/08/06',
        贷方金额: '1,000.00',
        对方户名: '杭州示例科技有限公司',
        银行流水号: 'BANK-001'
      }
    ],
    {
      mapping: inferAiBankBatchMapping(['交易日期', '贷方金额', '对方户名', '银行流水号']),
      counterparties,
      statementCandidates,
      existingReferences: new Set()
    }
  )
  assert.equal(rows[0].status, 'ready')
  assert.equal(rows[0].direction, 'receipt')
  assert.equal(rows[0].amount, 1000)
  assert.equal(rows[0].allocations[0].statementId, 'statement-1')
})

test('bank batch blocks an existing bank reference', () => {
  const rows = normalizeAiBankBatchRows(
    [
      {
        交易日期: '2026-08-06',
        贷方金额: 500,
        对方户名: '杭州示例科技有限公司',
        流水号: 'BANK-001'
      }
    ],
    {
      mapping: inferAiBankBatchMapping(['交易日期', '贷方金额', '对方户名', '流水号']),
      counterparties,
      statementCandidates,
      existingReferences: new Set(['receipt:BANK-001'])
    }
  )
  assert.equal(rows[0].status, 'duplicate')
})
