import { canEditField } from '@/utils/field-permission'

export type VehicleInsurance = Api.Vms.VehicleManage.VehicleInsurance
export type VehicleInsuranceFieldKey = Api.Vms.VehicleManage.VehicleInsuranceFieldKey

export const EDITABLE_VEHICLE_INSURANCE_ACCESS: Api.Vms.VehicleManage.VehicleInsuranceFieldAccessMap =
  {
    policyNumbers: 'edit',
    premiumAmounts: 'edit',
    documents: 'edit'
  }

type SensitivePayloadKey =
  | 'commercialPolicyNo'
  | 'compulsoryPolicyNo'
  | 'commercialPremium'
  | 'compulsoryPremium'
  | 'attachments'

const SENSITIVE_PAYLOAD_KEYS: Record<VehicleInsuranceFieldKey, SensitivePayloadKey[]> = {
  policyNumbers: ['commercialPolicyNo', 'compulsoryPolicyNo'],
  premiumAmounts: ['commercialPremium', 'compulsoryPremium'],
  documents: ['attachments']
}

export function sanitizeVehicleInsurancePayload(params: VehicleInsurance): VehicleInsurance {
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
  const result: VehicleInsurance = payload

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void isRecordOwner

  if (params.id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (canEditField(fieldAccess, field as VehicleInsuranceFieldKey)) return
      keys.forEach((key) => delete result[key])
    })
  }

  return result
}
