import assert from 'node:assert/strict'
import test from 'node:test'
import {
  calculatePayableLine,
  calculatePaymentPlans,
  validatePaymentPlans,
  payableCostDifference,
  roundPayable
} from '../../src/utils/finance/payable'
import type { PurchasePayableLine } from '../../src/api/purchase-payable.types'

const line: PurchasePayableLine = {
  id: 'line',
  sourceLineId: null,
  lineNo: 10,
  materialCode: 'MAT',
  materialDescription: '物料',
  projectName: null,
  constructionNo: null,
  unitName: '件',
  quantity: 2,
  unitPrice: 100,
  taxInclusiveUnitPrice: 113,
  taxRate: 13,
  amount: 200,
  taxAmount: 26,
  totalAmount: 226
}
const settings = { inputTaxInclusivePrice: true, inputAmount: false, discountIncludesTax: true }
test('金额舍入与数据库一致，正负半分均远离零且不丢失外币折算尾分', () => {
  assert.equal(roundPayable(1.005), 1.01)
  assert.equal(roundPayable(-1.005), -1.01)
  assert.equal(roundPayable(0.03 * 1.5), 0.05)
})
test('部分到票数量调整沿用已带入的基本单位换算比例', () => {
  const changed = calculatePayableLine(
    { ...line, quantity: 1, baseQuantity: 20 },
    settings,
    'quantity',
    2
  )
  assert.equal(changed.baseQuantity, 10)
  assert.equal(changed.totalAmount, 113)
  assert.equal(calculatePayableLine({ ...changed, taxRate: 9 }, settings).baseQuantity, 10)
})

test('应付含税价与不含税价双向换算', () => {
  const taxed = calculatePayableLine(
    { ...line, taxInclusiveUnitPrice: 113 },
    settings,
    'taxInclusiveUnitPrice'
  )
  assert.equal(taxed.unitPrice, 100)
  assert.equal(taxed.totalAmount, 226)
  const net = calculatePayableLine({ ...line, unitPrice: 200 }, settings, 'unitPrice')
  assert.equal(net.taxInclusiveUnitPrice, 226)
  assert.equal(net.totalAmount, 452)
})
test('含税折扣换算为净额后计算税额，保持价税恒等', () => {
  const result = calculatePayableLine(
    { ...line, discountMethod: 'rate', discountValue: 10 },
    settings
  )
  assert.equal(result.discountAmount, 22.6)
  assert.equal(result.amount, 180)
  assert.equal(result.taxAmount, 23.4)
  assert.equal(result.totalAmount, 203.4)
})
test('赠品清零与100%折扣均不保留应付余额', () => {
  const gift = calculatePayableLine({ ...line, gift: true }, settings)
  assert.deepEqual([gift.amount, gift.taxAmount, gift.totalAmount], [0, 0, 0])
  const discounted = calculatePayableLine(
    { ...line, discountMethod: 'rate', discountValue: 100 },
    settings
  )
  assert.equal(discounted.totalAmount, 0)
})
test('录入含税金额时保留价税合计，按税率拆分', () => {
  const result = calculatePayableLine(
    { ...line, totalAmount: 339 },
    { ...settings, inputAmount: true }
  )
  assert.equal(result.amount, 300)
  assert.equal(result.taxAmount, 39)
  assert.equal(result.totalAmount, 339)
})
test('付款计划开关在比例与金额间转换并拒绝不平衡计划', () => {
  const plans = [
    {
      dueDate: '2026-11-21',
      ratio: 30,
      amount: 0,
      sourceDocumentNo: '',
      contractNo: '',
      remark: ''
    },
    {
      dueDate: '2026-12-21',
      ratio: 70,
      amount: 0,
      sourceDocumentNo: '',
      contractNo: '',
      remark: ''
    }
  ]
  const calculated = calculatePaymentPlans(plans, 1130, true)
  assert.deepEqual(
    calculated.map((plan) => plan.amount),
    [339, 791]
  )
  assert.equal(validatePaymentPlans(calculated, 1130), null)
  assert.ok(validatePaymentPlans(calculated, 1000))
  assert.ok(validatePaymentPlans([{ ...calculated[0], dueDate: '' }], 339))
  assert.equal(calculatePaymentPlans(calculated, 1130, false)[0].ratio, 30)
})
test('成本差异覆盖两张单据税额是否计入成本的四种组合', () => {
  const estimate = { amount: 100, totalAmount: 113, taxExcludedFromCost: true }
  const finance = { amount: 110, totalAmount: 124.3, taxExcludedFromCost: true }
  assert.equal(payableCostDifference(estimate, finance), 10)
  assert.equal(payableCostDifference(estimate, { ...finance, taxExcludedFromCost: false }), 24.3)
  assert.equal(payableCostDifference({ ...estimate, taxExcludedFromCost: false }, finance), -3)
  assert.equal(
    payableCostDifference(
      { ...estimate, taxExcludedFromCost: false },
      { ...finance, taxExcludedFromCost: false }
    ),
    11.3
  )
})
test('双方税额计入成本时，净额相同仍确认税额变化产生的成本差', () => {
  const estimate = { amount: 100, totalAmount: 113, taxExcludedFromCost: false }
  const finance = { amount: 100, totalAmount: 109, taxExcludedFromCost: false }
  assert.equal(payableCostDifference(estimate, finance), -4)
  assert.equal(payableCostDifference(finance, estimate), 4)
})
test('付款比例尾差进入末期，非法日期和非有限金额不可保存', () => {
  const plan = {
    dueDate: '2026-11-21',
    ratio: 0,
    amount: 0,
    sourceDocumentNo: '',
    contractNo: '',
    remark: ''
  }
  const result = calculatePaymentPlans(
    [
      { ...plan, ratio: 33.3333 },
      { ...plan, ratio: 33.3333 },
      { ...plan, ratio: 33.3334 }
    ],
    0.01,
    true
  )
  assert.deepEqual(
    result.map((item) => item.amount),
    [0, 0, 0.01]
  )
  assert.equal(validatePaymentPlans(result, 0.01), null)
  assert.ok(validatePaymentPlans([{ ...plan, dueDate: '2026-02-30' }], 0))
  assert.ok(validatePaymentPlans([{ ...plan, amount: Number.POSITIVE_INFINITY }], 0))
})
