import type { ColumnOption } from '@/types'

export type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
export type VehiclePartUsage = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage
export type VehicleInsurance = Api.VehicleMgtSys.VehicleManage.VehicleInsurance
export type VehicleInspection = Api.VehicleMgtSys.VehicleManage.VehicleInspection
export type VehicleViolationRecord = Api.VehicleMgtSys.VehicleManage.VehicleViolationRecord
export type VehicleAccidentRecord = Api.VehicleMgtSys.VehicleManage.VehicleAccidentRecord
export type VehicleMaintenanceRecord = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceRecord
export type VehicleRoutineInspectionRecord =
  Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionRecord
export type VehicleMileageRecord = Api.VehicleMgtSys.VehicleManage.VehicleMileageRecord
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
