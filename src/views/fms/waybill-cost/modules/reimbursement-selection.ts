import { cloneDeep, uniq } from 'lodash-es'
import { toRaw } from 'vue'

export interface ReimbursementExpenseCandidate {
  id?: string
  waybillId?: string
  auditStatus?: string
  settlementStatus?: string
  reimbursementId?: string | null
  expensePaymentId?: string | null
  fieldAccess?: Api.Fms.WaybillCostFieldAccessMap
  expenseItem?: {
    reimbursementAllowed?: boolean
  } | null
}

export interface ReimbursementSelectionValidation {
  valid: boolean
  message: string
}

const invalid = (message: string): ReimbursementSelectionValidation => ({
  valid: false,
  message
})

export function cloneReimbursementExpenses<T extends ReimbursementExpenseCandidate>(
  expenses: T[]
): T[] {
  return cloneDeep(toRaw(expenses))
}

export function validateReimbursementSelection(
  expenses: ReimbursementExpenseCandidate[]
): ReimbursementSelectionValidation {
  if (!expenses.length) return invalid('请先选择要转报销的运单费用')

  if (
    expenses.some(
      (item) =>
        item.fieldAccess && !['read', 'edit'].includes(item.fieldAccess.costAmounts ?? 'hidden')
    )
  ) {
    return invalid('当前字段权限不足，无法读取所选费用金额并转报销')
  }

  if (expenses.some((item) => !item.id || !item.waybillId)) {
    return invalid('所选费用缺少有效的运单信息，请刷新列表后重试')
  }

  const waybillIds = uniq(expenses.map((item) => item.waybillId))
  if (waybillIds.length !== 1) {
    return invalid(`请选择同一个运单下的费用，当前选择包含 ${waybillIds.length} 个运单`)
  }

  const unapprovedCount = expenses.filter((item) => item.auditStatus !== 'approved').length
  if (unapprovedCount) {
    return invalid(`有 ${unapprovedCount} 笔费用尚未审核通过，请先完成费用审核`)
  }

  const occupiedCount = expenses.filter(
    (item) =>
      item.settlementStatus !== 'unsettled' ||
      Boolean(item.reimbursementId) ||
      Boolean(item.expensePaymentId)
  ).length
  if (occupiedCount) {
    return invalid(`有 ${occupiedCount} 笔费用已进入报销或支付流程，请刷新列表后重新选择`)
  }

  const forbiddenCount = expenses.filter(
    (item) => item.expenseItem?.reimbursementAllowed === false
  ).length
  if (forbiddenCount) {
    return invalid(`有 ${forbiddenCount} 笔费用项目不允许报销，请调整费用项目后重试`)
  }

  return { valid: true, message: '' }
}
