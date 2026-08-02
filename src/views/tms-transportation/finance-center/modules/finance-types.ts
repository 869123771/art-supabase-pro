export interface FinanceMetric {
  label: string
  value: string
  trend: string
  icon: string
  tone: 'primary' | 'success' | 'warning' | 'danger'
}
