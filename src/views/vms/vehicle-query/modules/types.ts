import type { ColumnOption } from '@/types'

export type VehicleArchive = Api.Vms.ArchiveManage.VehicleArchive
export type VehiclePartUsage = Api.Vms.VehicleManage.VehiclePartUsage
export type VehicleInsurance = Api.Vms.VehicleManage.VehicleInsurance
export type VehicleInspection = Api.Vms.VehicleManage.VehicleInspection
export type VehicleViolationRecord = Api.Vms.VehicleManage.VehicleViolationRecord
export type VehicleAccidentRecord = Api.Vms.VehicleManage.VehicleAccidentRecord
export type VehicleMaintenanceRecord = Api.Vms.VehicleManage.VehicleMaintenanceRecord
export type VehicleRoutineInspectionRecord = Api.Vms.VehicleManage.VehicleRoutineInspectionRecord
export type VehicleMileageRecord = Api.Vms.VehicleManage.VehicleMileageRecord
export type VehicleDriver = Api.Tms.BasicData.DriverOption

export type VehicleQueryTabKey =
  | 'view'
  | 'archive'
  | 'driver'
  | 'parts'
  | 'insurance'
  | 'inspection'
  | 'violation'
  | 'accident'
  | 'maintenance'
  | 'routine'
  | 'mileage'
  | 'device'

export interface VehicleQueryTab {
  key: VehicleQueryTabKey
  label: string
}

export interface InfoItem {
  label: string
  value?: unknown
  dictCode?: string
  suffix?: string
}

export interface VehicleQueryPanelProps {
  vehicle: VehicleArchive
}

export interface VehicleQueryTableConfig<TRecord> {
  columns: ColumnOption<TRecord>[]
  data: TRecord[]
  loading?: boolean
  emptyHeight?: string
}

export interface VehicleQuerySummary {
  runningMileage?: number | null
  commercialExpireDate?: string
  compulsoryExpireDate?: string
  inspectionExpireDate?: string
  nextMaintenanceDate?: string | null
  nextMaintenanceMileage?: number | null
}
