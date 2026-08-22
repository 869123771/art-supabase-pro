import { canEditField } from '@/utils/field-permission'

export type VehicleMaintenanceRecord = Api.Vms.VehicleManage.VehicleMaintenanceRecord
export type VehicleMaintenanceFieldKey = Api.Vms.VehicleManage.VehicleMaintenanceFieldKey

export const EDITABLE_VEHICLE_MAINTENANCE_ACCESS: Api.Vms.VehicleManage.VehicleMaintenanceFieldAccessMap =
  {
    maintenanceIdentifiers: 'edit',
    totalCost: 'edit',
    maintenanceItems: 'edit',
    documents: 'edit'
  }

type SensitivePayloadKey = 'maintenanceNo' | 'costAmount' | 'items' | 'attachments'

const SENSITIVE_PAYLOAD_KEYS: Record<VehicleMaintenanceFieldKey, SensitivePayloadKey[]> = {
  maintenanceIdentifiers: ['maintenanceNo'],
  totalCost: ['costAmount'],
  maintenanceItems: ['items'],
  documents: ['attachments']
}

export function sanitizeVehicleMaintenancePayload(
  params: VehicleMaintenanceRecord
): VehicleMaintenanceRecord {
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
  const result: VehicleMaintenanceRecord = payload

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void isRecordOwner

  if (params.id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (canEditField(fieldAccess, field as VehicleMaintenanceFieldKey)) return
      keys.forEach((key) => delete result[key])
    })
  }

  return result
}
