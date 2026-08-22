import { canEditField } from '@/utils/field-permission'

export type Supplier = Api.Vms.BasicInfo.Supplier
export type SupplierFieldKey = Api.Vms.BasicInfo.SupplierFieldKey

export const EDITABLE_SUPPLIER_ACCESS: Api.Vms.BasicInfo.SupplierFieldAccessMap = {
  contactDetails: 'edit',
  addressDetails: 'edit',
  internalNotes: 'edit'
}

type SensitivePayloadKey = 'contactPerson' | 'contactPhone' | 'region' | 'addressDetail' | 'remark'

const SENSITIVE_PAYLOAD_KEYS: Record<SupplierFieldKey, SensitivePayloadKey[]> = {
  contactDetails: ['contactPerson', 'contactPhone'],
  addressDetails: ['region', 'addressDetail'],
  internalNotes: ['remark']
}

export function sanitizeSupplierPayload(params: Supplier): Supplier {
  const {
    tenantId,
    createBy,
    createTime,
    updateBy,
    updateTime,
    fieldAccess,
    isRecordOwner,
    ...payload
  } = params
  const result: Supplier = payload

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void isRecordOwner

  if (params.id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (canEditField(fieldAccess, field as SupplierFieldKey)) return
      keys.forEach((key) => delete result[key])
    })
  }
  return result
}
