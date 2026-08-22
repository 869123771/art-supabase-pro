import { canEditField } from '@/utils/field-permission'

export type VehicleRoutineInspectionRecord = Api.Vms.VehicleManage.VehicleRoutineInspectionRecord
export type VehicleRoutineInspectionFieldKey =
  Api.Vms.VehicleManage.VehicleRoutineInspectionFieldKey

export const EDITABLE_VEHICLE_ROUTINE_INSPECTION_ACCESS: Api.Vms.VehicleManage.VehicleRoutineInspectionFieldAccessMap =
  {
    responsiblePeople: 'edit',
    inspectionFindings: 'edit',
    remediationDetails: 'edit',
    documents: 'edit'
  }

type SensitivePayloadKey =
  | 'inspector'
  | 'driverName'
  | 'checkResult'
  | 'checkCondition'
  | 'handlingMethod'
  | 'remark'
  | 'attachments'

const SENSITIVE_PAYLOAD_KEYS: Record<VehicleRoutineInspectionFieldKey, SensitivePayloadKey[]> = {
  responsiblePeople: ['inspector', 'driverName'],
  inspectionFindings: ['checkResult', 'checkCondition'],
  remediationDetails: ['handlingMethod', 'remark'],
  documents: ['attachments']
}

export function sanitizeVehicleRoutineInspectionPayload(
  params: VehicleRoutineInspectionRecord
): VehicleRoutineInspectionRecord {
  const {
    tenantId,
    createBy,
    createTime,
    updateBy,
    updateTime,
    fieldAccess,
    isRecordOwner,
    attachmentsMasked,
    ...payload
  } = params
  const result: VehicleRoutineInspectionRecord = payload

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void isRecordOwner
  void attachmentsMasked

  if (params.id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (canEditField(fieldAccess, field as VehicleRoutineInspectionFieldKey)) return
      keys.forEach((key) => delete result[key])
    })
  }

  return result
}
