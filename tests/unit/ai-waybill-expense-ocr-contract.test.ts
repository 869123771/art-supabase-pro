import assert from 'node:assert/strict'
import test from 'node:test'
import { normalizeAiWaybillExpenseResponse } from '../../supabase/functions/_shared/ai-waybill-expense-ocr-contract'

test('waybill expense OCR preserves normalized original text separately from fields', () => {
  const result = normalizeAiWaybillExpenseResponse({
    rawText: '加油站小票\r\n金额：￥268.00',
    summary: '识别到一张加油票据',
    confidence: 0.9,
    fieldConfidence: { amount: 0.95 },
    warnings: [],
    expense: {
      amount: 268,
      occurredOn: '2026-08-15'
    }
  })

  assert.equal(result.rawText, '加油站小票\n金额：￥268.00')
  assert.equal(result.expense.amount, 268)
})
