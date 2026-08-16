import assert from 'node:assert/strict'
import test from 'node:test'
import {
  buildInvoicePayload,
  createInitialInvoiceForm,
  normalizeInvoiceNo
} from '../../src/views/finance/invoice-management/modules/invoice-dialog-model'

test('invoice number normalization removes whitespace and uppercases text', () => {
  assert.equal(normalizeInvoiceNo(' ab 12 3456 '), 'AB123456')
})

test('invoice payload owns counterparty mapping and text normalization', () => {
  const form = createInitialInvoiceForm()
  Object.assign(form, {
    direction: 'input',
    counterpartyId: 'carrier-1',
    invoiceRecordNo: ' INV-1 ',
    invoiceNo: ' fp 123456 ',
    invoiceTitle: ' 供应商发票 ',
    remark: ' '
  })

  const payload = buildInvoicePayload({
    form,
    statementLinks: [{ statementId: 'statement-1', linkedAmount: 100 }],
    mergeDuplicate: false
  })

  assert.equal(payload.customerId, null)
  assert.equal(payload.carrierId, 'carrier-1')
  assert.equal(payload.invoiceRecordNo, 'INV-1')
  assert.equal(payload.invoiceNo, 'FP123456')
  assert.equal(payload.invoiceTitle, '供应商发票')
  assert.equal(payload.remark, null)
})
