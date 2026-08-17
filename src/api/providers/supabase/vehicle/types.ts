export type InsuranceCompany = Api.Vms.BasicInfo.InsuranceCompany
export type InsuranceCompanySearchParams = Api.Vms.BasicInfo.InsuranceCompanySearchParams
export type Supplier = Api.Vms.BasicInfo.Supplier
export type SupplierSearchParams = Api.Vms.BasicInfo.SupplierSearchParams
export type PartsCategory = Api.Vms.BasicInfo.PartsCategory
export type PartsCategorySearchParams = Api.Vms.BasicInfo.PartsCategorySearchParams
export type Parts = Api.Vms.BasicInfo.Parts
export type PartsSearchParams = Api.Vms.BasicInfo.PartsSearchParams

export type VehicleArchive = Api.Vms.ArchiveManage.VehicleArchive
export type VehicleArchiveSearchParams = Api.Vms.ArchiveManage.VehicleArchiveSearchParams
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

export type VehicleInsurance = Api.Vms.VehicleManage.VehicleInsurance
export type VehicleInsuranceSearchParams = Api.Vms.VehicleManage.VehicleInsuranceSearchParams
export type VehicleInspection = Api.Vms.VehicleManage.VehicleInspection
export type VehicleInspectionSearchParams = Api.Vms.VehicleManage.VehicleInspectionSearchParams
export type VehicleRoutineInspectionRecord = Api.Vms.VehicleManage.VehicleRoutineInspectionRecord
export type VehicleRoutineInspectionSearchParams =
  Api.Vms.VehicleManage.VehicleRoutineInspectionSearchParams
export type VehicleMileageRecord = Api.Vms.VehicleManage.VehicleMileageRecord
export type VehicleMileageSearchParams = Api.Vms.VehicleManage.VehicleMileageSearchParams
export type VehicleViolationRecord = Api.Vms.VehicleManage.VehicleViolationRecord
export type VehicleViolationSearchParams = Api.Vms.VehicleManage.VehicleViolationSearchParams
export type VehicleAccidentRecord = Api.Vms.VehicleManage.VehicleAccidentRecord
export type VehicleAccidentSearchParams = Api.Vms.VehicleManage.VehicleAccidentSearchParams
export type VehicleMaintenanceRecord = Api.Vms.VehicleManage.VehicleMaintenanceRecord
export type VehicleMaintenanceSearchParams = Api.Vms.VehicleManage.VehicleMaintenanceSearchParams
export type VehiclePartUsage = Api.Vms.VehicleManage.VehiclePartUsage
export type VehiclePartUsageSearchParams = Api.Vms.VehicleManage.VehiclePartUsageSearchParams

export type VehicleReminderRow = Api.Vms.ReminderManage.VehicleReminderRow
export type VehicleReminderSearchParams = Api.Vms.ReminderManage.VehicleReminderSearchParams

export interface VehicleReminderCompanyOption {
  companyName: string
}
