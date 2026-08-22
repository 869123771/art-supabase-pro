import { canEditField } from '@/utils/field-permission'

export type VehiclePartUsage = Api.Vms.VehicleManage.VehiclePartUsage
export type VehiclePartUsageFieldKey = Api.Vms.VehicleManage.VehiclePartUsageFieldKey

export const EDITABLE_VEHICLE_PART_USAGE_ACCESS: Api.Vms.VehicleManage.VehiclePartUsageFieldAccessMap =
  {
    supplierDetails: 'edit',
    traceabilityTag: 'edit',
    lifecycleLimits: 'edit',
    dispositionNotes: 'edit'
  }

type SensitivePayloadKey =
  | 'supplierId'
  | 'supplierName'
  | 'supplierContact'
  | 'rfidEnabled'
  | 'rfidTag'
  | 'enableMode'
  | 'enableDate'
  | 'warrantyMode'
  | 'warrantyMileage'
  | 'warrantyDuration'
  | 'serviceMileageEnabled'
  | 'serviceMileage'
  | 'serviceYearsEnabled'
  | 'serviceYears'
  | 'usedMileage'
  | 'scrapReason'
  | 'remark'

const SENSITIVE_PAYLOAD_KEYS: Record<VehiclePartUsageFieldKey, SensitivePayloadKey[]> = {
  supplierDetails: ['supplierId', 'supplierName', 'supplierContact'],
  traceabilityTag: ['rfidEnabled', 'rfidTag'],
  lifecycleLimits: [
    'enableMode',
    'enableDate',
    'warrantyMode',
    'warrantyMileage',
    'warrantyDuration',
    'serviceMileageEnabled',
    'serviceMileage',
    'serviceYearsEnabled',
    'serviceYears',
    'usedMileage'
  ],
  dispositionNotes: ['scrapReason', 'remark']
}

export function sanitizeVehiclePartUsagePayload(params: VehiclePartUsage): VehiclePartUsage {
  const {
    tenantId,
    createBy,
    createTime,
    updateBy,
    updateTime,
    fieldAccess,
    isRecordOwner,
    lifecycleLimitsMasked,
    ...payload
  } = params
  const result: VehiclePartUsage = payload

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void isRecordOwner
  void lifecycleLimitsMasked

  if (params.id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (canEditField(fieldAccess, field as VehiclePartUsageFieldKey)) return
      keys.forEach((key) => delete result[key])
    })
  }

  return result
}
