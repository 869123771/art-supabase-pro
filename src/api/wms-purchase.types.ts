export type WmsPurchaseKind =
  'initial_inbound' | 'initial_return' | 'purchase_inbound' | 'purchase_return'

export type WmsPurchaseStatus = 'draft' | 'submitted' | 'approved'

export interface WmsPurchaseOption {
  id: string
  name: string
  code: string
  tenantId: string
  documentTypeId?: string
}

export interface WmsPurchaseOrganization {
  id: string
  tenantId: string
  organizationCode: string
  organizationName: string
  organizationType: string
  status: string
  enabledOn: string | null
  initializationClosedAt: string | null
}

export interface WmsPurchaseMaterial extends WmsPurchaseOption {
  description: string | null
  specificationModel: string | null
  inventoryUnitId: string | null
  baseUnitId: string | null
  auxiliaryUnitId: string | null
  auxiliaryUnit2Id: string | null
  unitConversions: Array<{ sourceUnitId: string; sourceFactor: number; baseFactor: number }>
  serialManagementEnabled: boolean
}

export interface WmsPurchaseWarehouse {
  id: string
  tenantId: string
  organizationId: string
  warehouseCode: string
  warehouseName: string
  status: string
}

export interface WmsPurchaseBin {
  id: string
  warehouseId: string
  binCode: string
  binName: string
  status: string
}

export interface WmsPurchaseUnit {
  id: string
  tenantId: string
  unitCode: string
  unitName: string
}

export interface WmsPurchaseSourceBatch {
  id: string
  batchNo: string
  quantity: number
  binId: string | null
  receivedAt: string | null
}

export interface WmsPurchaseLine {
  id?: string
  lineNo: number
  materialId: string
  material?: WmsPurchaseMaterial | null
  projectId: string | null
  project?: WmsPurchaseOption | null
  constructionNo: string | null
  gift: boolean
  inventoryUnitId: string
  quantity: number
  baseUnitId: string | null
  baseQuantity: number
  unitPrice: number
  taxInclusiveUnitPrice: number
  priceBasis?: 'untaxed' | 'taxed'
  taxRate: number
  discountMethod: 'none' | 'rate' | 'amount'
  unitDiscountRate: number
  discountAmount: number
  amount: number
  taxAmount: number
  totalAmount: number
  batchNo: string | null
  sourceBatchId: string | null
  movementId?: string | null
  warehouseId: string | null
  binId: string | null
  stockType: string
  ownerType: 'self' | 'supplier' | 'customer'
  ownerId: string | null
  stockStatus: string
  keeperId: string | null
  auxiliaryUnitId: string | null
  auxiliaryQuantity: number | null
  auxiliaryUnit2Id: string | null
  auxiliaryQuantity2: number | null
  productionDate: string | null
  expiryDate: string | null
  trackingNo: string | null
  sourceDocument: string | null
  sourceLineNo: string | null
  remark: string | null
  serialNos: string[]
}

export interface WmsPurchaseDocument {
  id: string
  tenantId: string
  organizationId: string
  organization?: { organizationName: string; organizationCode: string } | null
  supplier?: { supplierName: string; supplierCode: string } | null
  purchaser?: { employeeName: string } | null
  keeper?: { employeeName: string } | null
  kind: WmsPurchaseKind
  documentNo: string
  documentTypeId: string
  businessTypeId: string
  businessDate: string
  accountingDate: string
  supplierId: string
  purchaserId: string | null
  purchaseDepartmentId: string | null
  keeperId: string | null
  warehouseId: string | null
  status: WmsPurchaseStatus
  isInitialization: boolean
  remark: string | null
  createTime: string
  updateTime: string
  approvedAt: string | null
  lines: WmsPurchaseLine[]
}

export interface WmsPurchaseListRow {
  documentId: string
  tenantId: string
  organizationId: string
  kind: WmsPurchaseKind
  documentNo: string
  businessDate: string
  accountingDate: string
  supplierId: string
  supplierCode: string
  supplierName: string
  status: WmsPurchaseStatus
  lineId: string
  lineNo: number
  materialId: string
  materialCode: string
  materialName: string
  materialDescription: string
  specificationModel: string | null
  projectId: string | null
  projectName: string | null
  inventoryUnitName: string | null
  quantity: number
  batchNo: string | null
  warehouseName: string | null
  binName: string | null
  stockType: string
  stockStatus: string
  unitPrice: number
  taxInclusiveUnitPrice: number
  taxRate: number
  discountAmount: number
  amount: number
  taxAmount: number
  totalAmount: number
  gift: boolean
  documentRemark: string | null
}

export interface WmsPurchasePayload extends Omit<
  WmsPurchaseDocument,
  | 'id'
  | 'documentNo'
  | 'accountingDate'
  | 'status'
  | 'createTime'
  | 'updateTime'
  | 'approvedAt'
  | 'organization'
  | 'supplier'
  | 'purchaser'
  | 'keeper'
> {
  id?: string
}

export interface WmsInitializationStatusRow extends WmsPurchaseOrganization {
  initializationStatus: 'initialized' | 'not_initialized'
}
