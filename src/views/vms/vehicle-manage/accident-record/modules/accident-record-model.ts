import { canEditField } from '@/utils/field-permission'

export type VehicleAccidentRecord = Api.Vms.VehicleManage.VehicleAccidentRecord
export type VehicleAccidentFieldKey = Api.Vms.VehicleManage.VehicleAccidentFieldKey

export const EDITABLE_VEHICLE_ACCIDENT_ACCESS: Api.Vms.VehicleManage.VehicleAccidentFieldAccessMap =
  {
    driverContact: 'edit',
    accidentLocation: 'edit',
    accidentNarrative: 'edit',
    lossAmounts: 'edit',
    documents: 'edit'
  }

type SensitivePayloadKey =
  | 'driverName'
  | 'driverPhone'
  | 'accidentLocation'
  | 'accidentLongitude'
  | 'accidentLatitude'
  | 'accidentSummary'
  | 'remark'
  | 'companyBearAmount'
  | 'economicLoss'
  | 'attachments'

const SENSITIVE_PAYLOAD_KEYS: Record<VehicleAccidentFieldKey, SensitivePayloadKey[]> = {
  driverContact: ['driverName', 'driverPhone'],
  accidentLocation: ['accidentLocation', 'accidentLongitude', 'accidentLatitude'],
  accidentNarrative: ['accidentSummary', 'remark'],
  lossAmounts: ['companyBearAmount', 'economicLoss'],
  documents: ['attachments']
}

export function sanitizeVehicleAccidentPayload(
  params: VehicleAccidentRecord
): VehicleAccidentRecord {
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
  const result: VehicleAccidentRecord = payload

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void isRecordOwner

  if (params.id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (canEditField(fieldAccess, field as VehicleAccidentFieldKey)) return
      keys.forEach((key) => delete result[key])
    })
  }

  return result
}
