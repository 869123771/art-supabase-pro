const movementTypeLabels: Record<string, string> = {
  initial_stock_in: '期初库存',
  initial_purchase_in: '期初采购入库',
  initial_purchase_return: '期初采购退料',
  purchase_in: '采购入库',
  purchase_return: '采购退货',
  production_in: '生产入库',
  production_return: '生产退料',
  material_issue: '生产领料',
  other_in: '其他入库',
  other_out: '其他出库',
  sales_out: '销售出库',
  sales_return: '销售退货',
  transfer: '直接调拨',
  transfer_in: '调拨入库',
  transfer_out: '调拨出库',
  project_transfer: '项目调拨',
  count_gain: '盘盈',
  count_loss: '盘亏',
  adjustment: '库存调整',
  adjustment_in: '调整调入',
  adjustment_out: '调整调出'
}

export function formatWmsMovementType(value?: string | null): string {
  if (!value) return '—'
  return movementTypeLabels[value] || value
}
