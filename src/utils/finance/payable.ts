import type {
  PayablePaymentPlan,
  PurchasePayableDocument,
  PurchasePayableLine
} from '@/api/purchase-payable.types'
import { round } from 'lodash-es'

export const payableStatusLabels = { draft: '暂存', submitted: '已提交', approved: '已审核' }
export const roundPayable = (value: number, digits = 2): number =>
  Math.sign(value) * round(Math.abs(value), digits)

export function calculatePayableLine(
  line: PurchasePayableLine,
  settings: Pick<
    PurchasePayableDocument,
    'inputTaxInclusivePrice' | 'inputAmount' | 'discountIncludesTax' | 'basis'
  >,
  changed: 'unitPrice' | 'taxInclusiveUnitPrice' | 'quantity' | 'amount' = 'quantity',
  previousQuantity?: number
): PurchasePayableLine {
  const taxFactor = 1 + Number(line.taxRate ?? 0) / 100
  let unitPrice = Number(line.unitPrice || 0)
  if (changed === 'taxInclusiveUnitPrice')
    unitPrice = Number(line.taxInclusiveUnitPrice || 0) / taxFactor
  const taxInclusiveUnitPrice = unitPrice * taxFactor
  const quantity = Number(line.quantity || 0)
  const discountValue = Number(line.discountValue || 0)
  const priceBase = settings.discountIncludesTax === false ? unitPrice : taxInclusiveUnitPrice
  const discountAmount =
    line.discountMethod === 'rate'
      ? (quantity * priceBase * discountValue) / 100
      : line.discountMethod === 'unit'
        ? quantity * discountValue
        : 0
  const discountNet =
    settings.discountIncludesTax === false ? discountAmount : discountAmount / taxFactor
  const amountEntry = settings.inputAmount || settings.basis === 'amount'
  const grossEntry = amountEntry && settings.inputTaxInclusivePrice !== false
  let amount = quantity * unitPrice - discountNet
  let totalAmount: number
  if (amountEntry) {
    if (grossEntry && changed !== 'amount') amount = Number(line.totalAmount || 0) / taxFactor
    else amount = Number(line.amount || 0)
  }
  amount = roundPayable(amount)
  const taxAmount = roundPayable(amount * (taxFactor - 1))
  totalAmount = roundPayable(amount + taxAmount)
  if (grossEntry && changed !== 'amount') totalAmount = roundPayable(Number(line.totalAmount || 0))
  return {
    ...line,
    baseQuantity:
      changed === 'quantity' &&
      previousQuantity &&
      previousQuantity > 0 &&
      line.baseQuantity !== undefined
        ? roundPayable((line.baseQuantity * quantity) / previousQuantity, 6)
        : line.baseQuantity,
    unitPrice: roundPayable(unitPrice, 4),
    taxInclusiveUnitPrice: roundPayable(taxInclusiveUnitPrice, 4),
    discountAmount: roundPayable(discountAmount),
    amount: line.gift ? 0 : amount,
    taxAmount: line.gift ? 0 : grossEntry ? roundPayable(totalAmount - amount) : taxAmount,
    totalAmount: line.gift ? 0 : totalAmount
  }
}

export function calculatePaymentPlans(
  plans: PayablePaymentPlan[],
  total: number,
  byRatio: boolean
): PayablePaymentPlan[] {
  const calculated = plans.map((plan) => ({
    ...plan,
    ratio: byRatio ? plan.ratio : total ? roundPayable((plan.amount / total) * 100, 6) : 0,
    amount: byRatio ? roundPayable((total * plan.ratio) / 100) : roundPayable(plan.amount)
  }))
  if (
    byRatio &&
    calculated.length &&
    roundPayable(
      plans.reduce((sum, plan) => sum + plan.ratio, 0),
      6
    ) === 100
  ) {
    const last = calculated[calculated.length - 1]
    last.amount = roundPayable(
      total - calculated.slice(0, -1).reduce((sum, plan) => sum + plan.amount, 0)
    )
  }
  return calculated
}

export function validatePaymentPlans(plans: PayablePaymentPlan[], total: number): string | null {
  if (!plans.length) return null
  if (
    plans.some(
      (plan) => !isValidPlanDate(plan.dueDate) || plan.amount < 0 || !Number.isFinite(plan.amount)
    )
  )
    return '请填写每期到期日期及有效的应付金额'
  if (roundPayable(plans.reduce((sum, plan) => sum + plan.amount, 0) - total) !== 0)
    return '付款计划金额合计必须等于单据价税合计'
  return null
}

function isValidPlanDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const date = new Date(`${value}T00:00:00Z`)
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
}

export function payableCostDifference(
  estimated: { amount: number; totalAmount: number; taxExcludedFromCost: boolean },
  financial: { amount: number; totalAmount: number; taxExcludedFromCost: boolean }
): number {
  return roundPayable(
    (financial.taxExcludedFromCost ? financial.amount : financial.totalAmount) -
      (estimated.taxExcludedFromCost ? estimated.amount : estimated.totalAmount)
  )
}
