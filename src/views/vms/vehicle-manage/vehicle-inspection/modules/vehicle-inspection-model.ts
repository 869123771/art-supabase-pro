import { canEditField } from '@/utils/field-permission'

export type VehicleInspection = Api.Vms.VehicleManage.VehicleInspection
export type VehicleInspectionFieldKey = Api.Vms.VehicleManage.VehicleInspectionFieldKey

export const EDITABLE_VEHICLE_INSPECTION_ACCESS: Api.Vms.VehicleManage.VehicleInspectionFieldAccessMap =
  {
    inspectionIdentifiers: 'edit',
    monetaryAmounts: 'edit',
    documents: 'edit'
  }

type SensitivePayloadKey =
  'inspectionNo' | 'compulsoryPolicyNo' | 'inspectionAmount' | 'compulsoryPremium' | 'attachments'

const SENSITIVE_PAYLOAD_KEYS: Record<VehicleInspectionFieldKey, SensitivePayloadKey[]> = {
  inspectionIdentifiers: ['inspectionNo', 'compulsoryPolicyNo'],
  monetaryAmounts: ['inspectionAmount', 'compulsoryPremium'],
  documents: ['attachments']
}

export function sanitizeVehicleInspectionPayload(params: VehicleInspection): VehicleInspection {
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
  const result: VehicleInspection = payload

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void isRecordOwner

  if (params.id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (canEditField(fieldAccess, field as VehicleInspectionFieldKey)) return
      keys.forEach((key) => delete result[key])
    })
  }

  return result
}
