import assert from 'node:assert/strict'
import test from 'node:test'
import { assessInvoiceCompliance } from '../../supabase/functions/_shared/invoice-compliance-audit-rules'

const now = new Date('2026-08-06T08:00:00.000Z')

function invoice(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'invoice-current',
    invoice_record_no: 'FP20260806001',
    direction: 'input',
    invoice_type: 'vat_special',
    counterparty_name_snapshot: '杭州安达运输有限公司',
    invoice_title: '示例物流科技有限公司',
    tax_number: '91330100TEST001',
    invoice_code: '033002600111',
    invoice_no: '12345678',
    issue_date: '2026-08-05',
    tax_rate: 6,
    amount_excluding_tax: 1000,
    tax_amount: 60,
    total_amount: 1060,
    linked_amount: 1060,
    unlinked_amount: 0,
    status: 'pending_review',
    attachments: [{ url: 'invoice.pdf' }],
    ...overrides
  }
}

function link(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    linked_amount: 1060,
    counterparty_name: '杭州安达运输有限公司',
    ...overrides
  }
}

test('invoice audit blocks duplicate invoice numbers', () => {
  const result = assessInvoiceCompliance(
    {
      invoice: invoice(),
      statementLinks: [link()],
      duplicateInvoices: [{ id: 'invoice-existing', status: 'issued' }]
    },
    { now }
  )

  assert.equal(result.riskLevel, 'critical')
  assert.equal(result.recommendation, 'block_for_verification')
  assert.equal(result.metrics.duplicateCount, 1)
  assert.ok(result.signals.some((item) => item.type === 'duplicate_invoice_number'))
})

test('invoice audit detects amount and tax formula inconsistencies', () => {
  const result = assessInvoiceCompliance(
    {
      invoice: invoice({ tax_amount: 30, total_amount: 1100, linked_amount: 1100 }),
      statementLinks: [link({ linked_amount: 1100 })]
    },
    { now }
  )

  assert.equal(result.recommendation, 'block_for_verification')
  assert.ok(result.signals.some((item) => item.type === 'amount_formula_mismatch'))
  assert.ok(result.signals.some((item) => item.type === 'tax_calculation_mismatch'))
})

test('invoice audit detects incomplete and imbalanced statement links', () => {
  const result = assessInvoiceCompliance(
    {
      invoice: invoice({ linked_amount: 500, unlinked_amount: 560 }),
      statementLinks: [link({ linked_amount: 400 })]
    },
    { now }
  )

  assert.equal(result.metrics.coverageRate, 500 / 1060)
  assert.ok(result.signals.some((item) => item.type === 'statement_amount_mismatch'))
  assert.ok(result.signals.some((item) => item.type === 'incomplete_statement_coverage'))
})

test('invoice audit reports missing evidence and tax identity', () => {
  const result = assessInvoiceCompliance(
    {
      invoice: invoice({ attachments: [], invoice_title: '', tax_number: '' }),
      statementLinks: [link()]
    },
    { now }
  )

  assert.ok(result.signals.some((item) => item.type === 'missing_attachment'))
  assert.ok(result.signals.some((item) => item.type === 'missing_tax_identity'))
})

test('invoice audit keeps a balanced and complete invoice in routine review', () => {
  const result = assessInvoiceCompliance({ invoice: invoice(), statementLinks: [link()] }, { now })

  assert.equal(result.riskLevel, 'low')
  assert.equal(result.recommendation, 'routine_review')
  assert.equal(result.signals.length, 0)
  assert.equal(result.metrics.coverageRate, 1)
})
