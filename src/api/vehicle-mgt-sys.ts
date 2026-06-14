import { isJavaApi } from '@/config/api-provider'
import * as javaVehicleApi from '@/api/providers/java/vehicle'
import * as supabaseVehicleApi from '@/api/providers/supabase/vehicle'

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
export const deleteVehicleArchive = supabaseVehicleApi.deleteVehicleArchive
export const deleteVehicleArchiveBatch = supabaseVehicleApi.deleteVehicleArchiveBatch
export const auditVehicleArchive = supabaseVehicleApi.auditVehicleArchive
