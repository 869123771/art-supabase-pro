import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

export interface VmsCarrierReference {
  id: string
  carrierCode?: string
  companyName: string
  enabled?: boolean
  contactName?: string
  contactPhone?: string
  fieldAccess?: Api.Tms.BasicData.CarrierFieldAccessMap
  isRecordOwner?: boolean
}

export interface VmsDriverReference {
  id: string
  carrierId?: string | null
  driverName: string
  phone?: string
  driverType?: 'primary' | 'secondary'
  licenseType?: string
  licenseExpireDate?: string | null
  enabled?: boolean
  fieldAccess?: Api.Tms.BasicData.DriverFieldAccessMap
  isRecordOwner?: boolean
}

export interface VmsHrEmployeeReference {
  id: string
  employeeNo: string
  employeeName: string
  organizationId?: string | null
  jobTitle?: string | null
  employmentStatus: Api.Hr.EmploymentStatus
}

interface CarrierReferenceParams {
  carrierCode?: string
  companyName?: string
  excludeId?: string
  includeDisabled?: boolean
  ids?: string[]
  maxRows?: number
}

interface DriverReferenceParams {
  carrierId?: string | null
  driverName?: string
  driverType?: 'primary' | 'secondary'
  ids?: string[]
  includeDisabled?: boolean
  maxRows?: number
}

const { supabase, responseHandle } = useSupabase()

/**
 * VMS consumer adapter for TMS-owned carrier data.
 *
 * The database RPC is the integration contract; VMS never imports the TMS
 * transport implementation and only receives tenant-scoped, masked fields.
 */
export async function fetchVmsCarrierReferences(
  params: CarrierReferenceParams = {},
  options?: ApiRequestOptions
) {
  const {
    carrierCode,
    companyName,
    excludeId,
    includeDisabled = false,
    ids,
    maxRows = 200
  } = params

  return await responseHandle<VmsCarrierReference[]>(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_carrier_options_secure', {
          p_exclude_id: excludeId || null,
          p_include_disabled: includeDisabled,
          p_keyword: String(companyName || carrierCode || '').trim() || null,
          p_ids: ids?.length ? ids : null,
          p_max_rows: maxRows
        }),
        options
      ),
    { showErrorMessage: true }
  )
}

export async function fetchVmsDriverReferences(
  params: DriverReferenceParams = {},
  options?: ApiRequestOptions
) {
  const { carrierId, driverName, driverType, ids, includeDisabled = false, maxRows = 200 } = params

  return await responseHandle<VmsDriverReference[]>(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_driver_options_secure', {
          p_carrier_id: carrierId || null,
          p_driver_name: String(driverName ?? '').trim() || null,
          p_driver_type: driverType || null,
          p_ids: ids?.length ? ids : null,
          p_include_disabled: includeDisabled,
          p_max_rows: maxRows
        }),
        options
      ),
    { showErrorMessage: true }
  )
}

/** HR-owned read model exposed specifically for VMS use cases. */
export async function fetchVmsHrEmployeeReferences(
  params: { keyword?: string; maxRows?: number } = {},
  options?: ApiRequestOptions
) {
  return await responseHandle<VmsHrEmployeeReference[]>(
    () =>
      withRequestOptions(
        supabase.rpc('vms_list_hr_employee_options_secure', {
          p_keyword: String(params.keyword ?? '').trim() || null,
          p_max_rows: params.maxRows ?? 100
        }),
        options
      ),
    { showErrorMessage: true }
  )
}
