export type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
export type InsuranceCompanySearchParams = Api.VehicleMgtSys.BasicInfo.InsuranceCompanySearchParams
export type Supplier = Api.VehicleMgtSys.BasicInfo.Supplier
export type SupplierSearchParams = Api.VehicleMgtSys.BasicInfo.SupplierSearchParams
export type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory
export type PartsCategorySearchParams = Api.VehicleMgtSys.BasicInfo.PartsCategorySearchParams
export type Parts = Api.VehicleMgtSys.BasicInfo.Parts
export type PartsSearchParams = Api.VehicleMgtSys.BasicInfo.PartsSearchParams

export type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
export type VehicleArchiveSearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
export type VehicleArchiveWritePayload = Record<string, unknown> & { id?: string }

export interface VehicleArchiveDeleteRelatedCount {
  tableName: string
  label: string
  count: number
}

export interface VehicleArchiveDeletePreview {
  waybillCount: number
  relatedCounts: VehicleArchiveDeleteRelatedCount[]
  relatedTotal: number
}

export interface VehicleArchiveDeleteBase {
  carrierId?: string | null
}

export type VehicleInsurance = Api.VehicleMgtSys.VehicleManage.VehicleInsurance
export type VehicleInsuranceSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehicleInsuranceSearchParams
export type VehicleInspection = Api.VehicleMgtSys.VehicleManage.VehicleInspection
export type VehicleInspectionSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehicleInspectionSearchParams
export type VehicleRoutineInspectionRecord =
  Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionRecord
export type VehicleRoutineInspectionSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionSearchParams
export type VehicleMileageRecord = Api.VehicleMgtSys.VehicleManage.VehicleMileageRecord
export type VehicleMileageSearchParams = Api.VehicleMgtSys.VehicleManage.VehicleMileageSearchParams
export type VehicleViolationRecord = Api.VehicleMgtSys.VehicleManage.VehicleViolationRecord
export type VehicleViolationSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehicleViolationSearchParams
export type VehicleAccidentRecord = Api.VehicleMgtSys.VehicleManage.VehicleAccidentRecord
export type VehicleAccidentSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehicleAccidentSearchParams
export type VehicleMaintenanceRecord = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceRecord
export type VehicleMaintenanceSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceSearchParams
export type VehiclePartUsage = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage
export type VehiclePartUsageSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehiclePartUsageSearchParams

export type VehicleReminderRow = Api.VehicleMgtSys.ReminderManage.VehicleReminderRow
export type VehicleReminderSearchParams =
  Api.VehicleMgtSys.ReminderManage.VehicleReminderSearchParams

export interface VehicleReminderCompanyOption {
  companyName: string
}
