import { isJavaApi } from '@/config/api-provider'
import * as javaVehicleApi from '@/api/providers/java/vehicle'
import * as supabaseVehicleApi from '@/api/providers/supabase/vehicle'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'

const vehicleApi = isJavaApi ? javaVehicleApi : supabaseVehicleApi

export const fetchInsuranceCompanyList = vehicleApi.fetchInsuranceCompanyList
export const exportInsuranceCompanyList = vehicleApi.exportInsuranceCompanyList
export const addInsuranceCompany = vehicleApi.addInsuranceCompany
export const editInsuranceCompany = vehicleApi.editInsuranceCompany
export const deleteInsuranceCompany = vehicleApi.deleteInsuranceCompany
export const deleteInsuranceCompanyBatch = vehicleApi.deleteInsuranceCompanyBatch
export const importInsuranceCompanies = vehicleApi.importInsuranceCompanies

export const fetchSupplierList = vehicleApi.fetchSupplierList
export const exportSupplierList = vehicleApi.exportSupplierList
export const addSupplier = vehicleApi.addSupplier
export const editSupplier = vehicleApi.editSupplier
export const deleteSupplier = vehicleApi.deleteSupplier
export const deleteSupplierBatch = vehicleApi.deleteSupplierBatch
export const importSuppliers = vehicleApi.importSuppliers

export const fetchPartsCategoryList = vehicleApi.fetchPartsCategoryList
export const fetchPartsCategoryTree = vehicleApi.fetchPartsCategoryTree
export const exportPartsCategoryList = vehicleApi.exportPartsCategoryList
export const addPartsCategory = vehicleApi.addPartsCategory
export const editPartsCategory = vehicleApi.editPartsCategory
export const deletePartsCategory = vehicleApi.deletePartsCategory
export const deletePartsCategoryBatch = vehicleApi.deletePartsCategoryBatch
export const importPartsCategories = vehicleApi.importPartsCategories

export const fetchPartsList = vehicleApi.fetchPartsList
export const exportPartsList = vehicleApi.exportPartsList
export const addParts = vehicleApi.addParts
export const editParts = vehicleApi.editParts
export const deleteParts = vehicleApi.deleteParts
export const deletePartsBatch = vehicleApi.deletePartsBatch
export const importParts = vehicleApi.importParts
export const fetchSupplierOptions = vehicleApi.fetchSupplierOptions

export const fetchVehicleArchiveList = supabaseVehicleApi.fetchVehicleArchiveList
export const exportVehicleArchiveList = supabaseVehicleApi.exportVehicleArchiveList
export const fetchVehicleArchiveDetail = supabaseVehicleApi.fetchVehicleArchiveDetail
export const addVehicleArchive = supabaseVehicleApi.addVehicleArchive
export const editVehicleArchive = supabaseVehicleApi.editVehicleArchive
export const fetchVehicleArchiveDeletePreview = supabaseVehicleApi.fetchVehicleArchiveDeletePreview
export const deleteVehicleArchive = supabaseVehicleApi.deleteVehicleArchive
export const deleteVehicleArchiveBatch = supabaseVehicleApi.deleteVehicleArchiveBatch
export async function submitVehicleArchiveForApproval(id: string, plateNo: string) {
  return await startWorkflow({
    businessType: 'vehicle_archive',
    businessId: id,
    businessTitle: `车辆档案 ${plateNo}`
  })
}
export async function auditVehicleArchive(params: {
  id: string
  auditStatus: 'approved' | 'rejected'
  auditRemark?: string
}) {
  return await actWorkflowByBusiness({
    businessType: 'vehicle_archive',
    businessId: params.id,
    action: params.auditStatus === 'approved' ? 'approve' : 'reject',
    comment: params.auditRemark || null
  })
}
export async function auditVehicleArchiveBatch(params: {
  ids: string[]
  auditStatus: 'approved' | 'rejected'
  auditRemark?: string
}) {
  return await Promise.all(params.ids.map((id) => auditVehicleArchive({ ...params, id })))
}

export const fetchVehicleArchiveOptions = supabaseVehicleApi.fetchVehicleArchiveOptions
export const fetchVehicleReminderCompanyOptions =
  supabaseVehicleApi.fetchVehicleReminderCompanyOptions
export const fetchVehicleReminderInsuranceExpiryList =
  supabaseVehicleApi.fetchVehicleReminderInsuranceExpiryList
export const fetchVehicleReminderInsuranceRiskOverview =
  supabaseVehicleApi.fetchVehicleReminderInsuranceRiskOverview
export const fetchVehicleReminderInspectionExpiryList =
  supabaseVehicleApi.fetchVehicleReminderInspectionExpiryList
export const fetchVehicleReminderInspectionRiskOverview =
  supabaseVehicleApi.fetchVehicleReminderInspectionRiskOverview
export const fetchVehicleReminderMaintenanceExpiryList =
  supabaseVehicleApi.fetchVehicleReminderMaintenanceExpiryList
export const fetchVehicleReminderMaintenanceRiskOverview =
  supabaseVehicleApi.fetchVehicleReminderMaintenanceRiskOverview
export const fetchVehicleReminderPartServiceLifeList =
  supabaseVehicleApi.fetchVehicleReminderPartServiceLifeList
export const fetchVehicleReminderPartServiceLifeRiskOverview =
  supabaseVehicleApi.fetchVehicleReminderPartServiceLifeRiskOverview
export const fetchVehicleReminderVehicleServiceLifeList =
  supabaseVehicleApi.fetchVehicleReminderVehicleServiceLifeList
export const fetchVehicleReminderVehicleServiceLifeRiskOverview =
  supabaseVehicleApi.fetchVehicleReminderVehicleServiceLifeRiskOverview
export const createVehicleReminderWorkOrder = supabaseVehicleApi.createVehicleReminderWorkOrder
export const transitionVehicleReminderWorkOrder =
  supabaseVehicleApi.transitionVehicleReminderWorkOrder
export const fetchInsuranceCompanyOptions = supabaseVehicleApi.fetchInsuranceCompanyOptions

export const fetchVehicleInsuranceList = supabaseVehicleApi.fetchVehicleInsuranceList
export const exportVehicleInsuranceList = supabaseVehicleApi.exportVehicleInsuranceList
export const fetchVehicleInsuranceDetail = supabaseVehicleApi.fetchVehicleInsuranceDetail
export const addVehicleInsurance = supabaseVehicleApi.addVehicleInsurance
export const editVehicleInsurance = supabaseVehicleApi.editVehicleInsurance
export const deleteVehicleInsurance = supabaseVehicleApi.deleteVehicleInsurance
export const deleteVehicleInsuranceBatch = supabaseVehicleApi.deleteVehicleInsuranceBatch

export const fetchVehicleInspectionList = supabaseVehicleApi.fetchVehicleInspectionList
export const fetchVehicleInspectionDetail = supabaseVehicleApi.fetchVehicleInspectionDetail
export const exportVehicleInspectionList = supabaseVehicleApi.exportVehicleInspectionList
export const addVehicleInspection = supabaseVehicleApi.addVehicleInspection
export const editVehicleInspection = supabaseVehicleApi.editVehicleInspection
export const deleteVehicleInspection = supabaseVehicleApi.deleteVehicleInspection
export const deleteVehicleInspectionBatch = supabaseVehicleApi.deleteVehicleInspectionBatch

export const fetchVehicleRoutineInspectionList =
  supabaseVehicleApi.fetchVehicleRoutineInspectionList
export const exportVehicleRoutineInspectionList =
  supabaseVehicleApi.exportVehicleRoutineInspectionList
export const fetchVehicleRoutineInspectionDetail =
  supabaseVehicleApi.fetchVehicleRoutineInspectionDetail
export const addVehicleRoutineInspection = supabaseVehicleApi.addVehicleRoutineInspection
export const editVehicleRoutineInspection = supabaseVehicleApi.editVehicleRoutineInspection
export const deleteVehicleRoutineInspection = supabaseVehicleApi.deleteVehicleRoutineInspection
export const deleteVehicleRoutineInspectionBatch =
  supabaseVehicleApi.deleteVehicleRoutineInspectionBatch

export const fetchVehicleMileageList = supabaseVehicleApi.fetchVehicleMileageList
export const exportVehicleMileageList = supabaseVehicleApi.exportVehicleMileageList

export const fetchVehicleViolationList = supabaseVehicleApi.fetchVehicleViolationList
export const exportVehicleViolationList = supabaseVehicleApi.exportVehicleViolationList

export const fetchVehicleAccidentList = supabaseVehicleApi.fetchVehicleAccidentList
export const exportVehicleAccidentList = supabaseVehicleApi.exportVehicleAccidentList
export const fetchVehicleAccidentDetail = supabaseVehicleApi.fetchVehicleAccidentDetail
export const addVehicleAccident = supabaseVehicleApi.addVehicleAccident
export const editVehicleAccident = supabaseVehicleApi.editVehicleAccident
export const deleteVehicleAccident = supabaseVehicleApi.deleteVehicleAccident
export const deleteVehicleAccidentBatch = supabaseVehicleApi.deleteVehicleAccidentBatch

export const fetchVehicleMaintenanceList = supabaseVehicleApi.fetchVehicleMaintenanceList
export const exportVehicleMaintenanceList = supabaseVehicleApi.exportVehicleMaintenanceList
export const fetchVehicleMaintenanceDetail = supabaseVehicleApi.fetchVehicleMaintenanceDetail
export const addVehicleMaintenance = supabaseVehicleApi.addVehicleMaintenance
export const editVehicleMaintenance = supabaseVehicleApi.editVehicleMaintenance
export const deleteVehicleMaintenance = supabaseVehicleApi.deleteVehicleMaintenance
export const deleteVehicleMaintenanceBatch = supabaseVehicleApi.deleteVehicleMaintenanceBatch

export const fetchVehiclePartUsageList = supabaseVehicleApi.fetchVehiclePartUsageList
export const fetchVehiclePartUsageDetail = supabaseVehicleApi.fetchVehiclePartUsageDetail
export const addVehiclePartUsage = supabaseVehicleApi.addVehiclePartUsage
export const editVehiclePartUsage = supabaseVehicleApi.editVehiclePartUsage
export const deleteVehiclePartUsage = supabaseVehicleApi.deleteVehiclePartUsage
export const deleteVehiclePartUsageBatch = supabaseVehicleApi.deleteVehiclePartUsageBatch

export const analyzeVehicleHealthByAi = supabaseVehicleApi.analyzeVehicleHealthByAi
