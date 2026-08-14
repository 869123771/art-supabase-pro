export interface WorkflowBusinessContract {
  businessType: string
  label: string
  domain: 'transport' | 'finance' | 'master_data'
  riskLevel: 'high' | 'medium'
  owner: string
  fields: Api.Workflow.WorkflowContextField[]
  routePath: (businessId: string) => string
}

const contracts: Record<string, WorkflowBusinessContract> = {
  generic: {
    businessType: 'generic',
    label: '通用审批',
    domain: 'master_data',
    riskLevel: 'medium',
    owner: '平台管理',
    fields: [],
    routePath: () => '/workflow/workbench'
  },
  tms_waybill_cost: {
    businessType: 'tms_waybill_cost',
    label: '运单费用',
    domain: 'finance',
    riskLevel: 'high',
    owner: '运输财务',
    fields: [
      { key: 'amount', label: '费用金额', valueType: 'number', help: '本次费用金额' },
      { key: 'expenseItemName', label: '费用项目', valueType: 'text' },
      { key: 'payeeName', label: '收款方', valueType: 'text' },
      { key: 'waybillNo', label: '运单号', valueType: 'text' },
      { key: 'occurredOn', label: '发生日期', valueType: 'date' }
    ],
    routePath: (businessId) =>
      `/tms-transportation/finance-center/waybill-cost/detail/${businessId}`
  },
  tms_expense_reimbursement: {
    businessType: 'tms_expense_reimbursement',
    label: '费用报销',
    domain: 'finance',
    riskLevel: 'high',
    owner: '财务审批',
    fields: [
      { key: 'totalAmount', label: '报销金额', valueType: 'number' },
      { key: 'itemCount', label: '费用笔数', valueType: 'number' },
      { key: 'reimbursementNo', label: '报销单号', valueType: 'text' },
      { key: 'payeeName', label: '收款人', valueType: 'text' },
      { key: 'paymentMethod', label: '付款方式', valueType: 'text' },
      { key: 'plannedPaymentDate', label: '计划付款日期', valueType: 'date' }
    ],
    routePath: () => '/tms-transportation/finance-center/expense-reimbursement'
  },
  tms_invoice: {
    businessType: 'tms_invoice',
    label: '发票',
    domain: 'finance',
    riskLevel: 'high',
    owner: '财务',
    fields: [
      { key: 'totalAmount', label: '价税合计', valueType: 'number' },
      { key: 'direction', label: '发票方向', valueType: 'text' },
      { key: 'invoiceType', label: '发票类型', valueType: 'text' },
      { key: 'invoiceNo', label: '发票号码', valueType: 'text' },
      { key: 'taxRate', label: '税率', valueType: 'number' },
      { key: 'counterpartyName', label: '交易对方', valueType: 'text' }
    ],
    routePath: () => '/tms-transportation/finance-center/invoice-management'
  },
  tms_carrier_payment_application: {
    businessType: 'tms_carrier_payment_application',
    label: '承运商付款申请',
    domain: 'finance',
    riskLevel: 'high',
    owner: '应付结算',
    fields: [
      { key: 'amount', label: '申请付款金额', valueType: 'number' },
      { key: 'applicationNo', label: '付款申请单号', valueType: 'text' },
      { key: 'carrierId', label: '承运商ID', valueType: 'text' },
      { key: 'carrierName', label: '承运商名称', valueType: 'text' },
      { key: 'plannedPaymentDate', label: '计划付款日期', valueType: 'date' },
      { key: 'statementCount', label: '对账单数量', valueType: 'number' }
    ],
    routePath: () => '/tms-transportation/finance-center/payment-application'
  },
  tms_carrier_statement: {
    businessType: 'tms_carrier_statement',
    label: '承运商结算',
    domain: 'finance',
    riskLevel: 'high',
    owner: '应付结算',
    fields: [
      { key: 'statementAmount', label: '对账金额', valueType: 'number' },
      { key: 'costCount', label: '费用明细数', valueType: 'number' },
      { key: 'statementNo', label: '对账单号', valueType: 'text' },
      { key: 'carrierId', label: '承运商ID', valueType: 'text' },
      { key: 'carrierName', label: '承运商名称', valueType: 'text' },
      { key: 'settledAmount', label: '已结算金额', valueType: 'number' }
    ],
    routePath: () => '/tms-transportation/finance-center/carrier-settlement'
  },
  tms_customer_statement: {
    businessType: 'tms_customer_statement',
    label: '客户结算',
    domain: 'finance',
    riskLevel: 'high',
    owner: '应收结算',
    fields: [
      { key: 'statementAmount', label: '对账金额', valueType: 'number' },
      { key: 'waybillCount', label: '运单数量', valueType: 'number' },
      { key: 'statementNo', label: '对账单号', valueType: 'text' },
      { key: 'customerId', label: '客户ID', valueType: 'text' },
      { key: 'customerName', label: '客户名称', valueType: 'text' },
      { key: 'settledAmount', label: '已结算金额', valueType: 'number' }
    ],
    routePath: () => '/tms-transportation/finance-center/customer-settlement'
  },
  tms_contract: {
    businessType: 'tms_contract',
    label: '运输合同',
    domain: 'transport',
    riskLevel: 'high',
    owner: '合同管理',
    fields: [
      { key: 'businessContractType', label: '业务合同分类', valueType: 'text' },
      { key: 'contractCategory', label: '合同类别', valueType: 'text' },
      { key: 'transportMode', label: '运输方式', valueType: 'text' },
      { key: 'contractAmount', label: '合同金额', valueType: 'number' },
      { key: 'contractNo', label: '合同编号', valueType: 'text' },
      { key: 'carrierId', label: '承运商ID', valueType: 'text' },
      { key: 'customerId', label: '客户ID', valueType: 'text' },
      { key: 'partyName', label: '合同相对方', valueType: 'text' },
      { key: 'billingMethod', label: '计费方式', valueType: 'text' },
      { key: 'signTime', label: '签订时间', valueType: 'date' },
      { key: 'effectiveDate', label: '生效日期', valueType: 'date' },
      { key: 'expiryDate', label: '到期日期', valueType: 'date' },
      { key: 'isCompleted', label: '是否完成', valueType: 'boolean' },
      { key: 'handler', label: '经办人', valueType: 'text' }
    ],
    routePath: (businessId) => `/tms-transportation/basic-data/contract-detail/${businessId}`
  },
  vehicle_archive: {
    businessType: 'vehicle_archive',
    label: '车辆档案',
    domain: 'master_data',
    riskLevel: 'medium',
    owner: '车辆管理',
    fields: [
      { key: 'plateNo', label: '车牌号', valueType: 'text' },
      { key: 'vehicleType', label: '车辆类型', valueType: 'text' },
      { key: 'companyName', label: '所属单位', valueType: 'text' },
      { key: 'approvedLoadMass', label: '核定载质量', valueType: 'number' },
      { key: 'operationType', label: '营运类型', valueType: 'text' },
      { key: 'isNewEnergy', label: '新能源车辆', valueType: 'boolean' }
    ],
    routePath: (businessId) => `/vehicle-manage-system/vehicle-archive-detail/${businessId}`
  }
}

export const workflowBusinessContracts = Object.values(contracts).filter(
  (contract) => contract.businessType !== 'generic'
)

export function getWorkflowBusinessContract(businessType: string): WorkflowBusinessContract {
  return contracts[businessType] ?? contracts.generic
}

export function getWorkflowContextFields(
  businessType: string
): Api.Workflow.WorkflowContextField[] {
  return getWorkflowBusinessContract(businessType).fields
}
