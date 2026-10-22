export interface WriteoffAmountRow {
  id: string
  availableAmount: number
  writeoffAmount?: number
}
export function allocatePayableWriteoff(
  primary: WriteoffAmountRow[],
  secondary: WriteoffAmountRow[]
): Array<{ payableId: string; paymentLineId: string; amount: number }> {
  const toCents = (row: WriteoffAmountRow) => {
    const value = row.writeoffAmount ?? row.availableAmount
    if (!Number.isFinite(value) || value <= 0 || value > row.availableAmount)
      throw new Error('本次核销金额须大于零，且不能超过允许核销金额')
    return Math.round(value * 100)
  }
  if (!primary.length || !secondary.length) throw new Error('请分别选择财务应付和付款明细')
  const main = primary.map((row) => ({ id: row.id, remaining: toCents(row) }))
  const side = secondary.map((row) => ({ id: row.id, remaining: toCents(row) }))
  if (
    main.reduce((sum, row) => sum + row.remaining, 0) !==
    side.reduce((sum, row) => sum + row.remaining, 0)
  )
    throw new Error('主辅方本次核销金额合计须一致，请调整选中行金额')
  const items: Array<{ payableId: string; paymentLineId: string; amount: number }> = []
  let sideIndex = 0
  for (const row of main) {
    while (row.remaining > 0) {
      const payment = side[sideIndex]
      const amount = Math.min(row.remaining, payment.remaining)
      items.push({ payableId: row.id, paymentLineId: payment.id, amount: amount / 100 })
      row.remaining -= amount
      payment.remaining -= amount
      if (!payment.remaining) sideIndex += 1
    }
  }
  return items
}
