import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import {
  VEHICLE_REMINDER_VIEWS,
  fetchVehicleReminderViewList,
  fetchVehicleReminderViewRiskOverview
} from './reminders'
import {
  type VehicleArchive,
  type VehicleArchiveSearchParams,
  type VehicleArchiveWritePayload,
  type VehicleArchiveDeletePreview,
  type VehicleReminderSearchParams,
  type VehicleReminderCompanyOption
} from './types'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

interface VehicleArchiveWriteOptions {
  showMessage?: boolean
}

interface SecureVehicleArchivePayload {
  records: VehicleArchive[]
  total: number
  fieldAccess?: Api.Vms.ArchiveManage.VehicleArchiveFieldAccessMap
}

const startOfDay = (value?: string): string | null => (value ? `${value}T00:00:00` : null)
const endOfDay = (value?: string): string | null => (value ? `${value}T23:59:59.999` : null)

const createVehicleArchiveRpcParams = (
  params: VehicleArchiveSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = Math.max(params.from ?? 0, 0)
  const requestedTo = params.maxRows ? from + Math.max(params.maxRows, 1) - 1 : params.to
  const to = Math.max(requestedTo ?? 9, from)
  return {
    p_from: from,
    p_to: to,
    p_record_id: params.recordId || null,
    p_carrier_id: params.carrierId || null,
    p_plate_no: String(params.plateNo ?? '').trim() || null,
    p_company_name: String(params.companyName ?? '').trim() || null,
    p_vehicle_type: params.vehicleType || null,
    p_manufacturer: String(params.manufacturer ?? '').trim() || null,
    p_vin: String(params.vin ?? '').trim() || null,
    p_operation_status: params.operationStatus || null,
    p_audit_status: params.auditStatus || null,
    p_audit_statuses: params.auditStatuses?.length ? params.auditStatuses : null,
    p_create_time_from: startOfDay(params.createTimeRange?.[0]),
    p_create_time_to: endOfDay(params.createTimeRange?.[1]),
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchVehicleArchiveList(
  params: VehicleArchiveSearchParams,
  options?: ApiRequestOptions
) {
  const result = await responseHandle<SecureVehicleArchivePayload>(
    () =>
      withRequestOptions(
        supabase.rpc(
          'vms_list_vehicle_archives_secure',
          createVehicleArchiveRpcParams(params, 'list')
        ),
        options
      ),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportVehicleArchiveList(
  params: VehicleArchiveSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureVehicleArchivePayload>(
    () =>
      supabase.rpc(
        'vms_list_vehicle_archives_secure',
        createVehicleArchiveRpcParams({ ...params, maxRows: params.maxRows ?? 10000 }, 'export')
      ),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchVehicleArchiveDetail(id: string) {
  return await responseHandle<VehicleArchive | null>(
    () => supabase.rpc('vms_get_vehicle_archive_secure', { p_id: id }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function addVehicleArchive(
  params: VehicleArchiveWritePayload,
  options: VehicleArchiveWriteOptions = {}
) {
  const result = await responseHandle<string>(
    () => supabase.rpc('vms_create_vehicle_archive_secure', { p_payload: keysToSnakeDeep(params) }),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editVehicleArchive(
  params: VehicleArchiveWritePayload,
  options: VehicleArchiveWriteOptions = {}
) {
  const { id, ...payload } = params
  if (!id) throw new Error('缺少车辆档案 ID')
  return await responseHandle<VehicleArchive>(
    () =>
      supabase.rpc('vms_update_vehicle_archive_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(payload)
      }),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
}

export async function fetchVehicleArchiveDeletePreview(id: string) {
  return await responseHandle<VehicleArchiveDeletePreview>(
    () => supabase.rpc('vms_get_vehicle_archive_delete_preview_secure', { p_id: id }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function deleteVehicleArchive(id: string) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_archives_secure', { p_ids: [id] }),
    { showMessage: true, message: '删除成功', breakReturn: true }
  )
}

export async function deleteVehicleArchiveBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_archives_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

// 车辆管理选项
export async function fetchVehicleArchiveOptions(
  params: Partial<Pick<VehicleArchive, 'carrierId' | 'plateNo' | 'companyName'>> = {},
  options?: ApiRequestOptions
) {
  const { carrierId, plateNo, companyName } = params
  return await responseHandle<Api.Vms.VehicleManage.VehicleOption[]>(
    () =>
      withRequestOptions(
        supabase.rpc('vms_list_vehicle_archive_options_secure', {
          p_carrier_id: carrierId || null,
          p_plate_no: String(plateNo ?? '').trim() || null,
          p_company_name: String(companyName ?? '').trim() || null,
          p_ids: null,
          p_max_rows: 200
        }),
        options
      ),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function fetchVehicleReminderCompanyOptions() {
  const results = await Promise.all(
    VEHICLE_REMINDER_VIEWS.map((viewName) =>
      responseHandle<VehicleReminderCompanyOption[]>(
        () =>
          supabase
            .from(viewName)
            .select('company_name')
            .not('company_name', 'is', null)
            .neq('company_name', '')
            .order('company_name', { ascending: true }),
        { ignoreCheck: true, showErrorMessage: true }
      )
    )
  )

  const companyNames = new Set<string>()
  results.forEach((result) => {
    const rows = result.data ?? []
    rows.forEach((item) => {
      if (item.companyName) companyNames.add(item.companyName)
    })
  })

  return {
    data: [...companyNames]
      .sort((first, second) => first.localeCompare(second, 'zh-CN'))
      .map((companyName) => ({ companyName })),
    error: null
  }
}

export async function fetchVehicleReminderInsuranceExpiryList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_insurance_expiry',
    'insurance',
    params,
    'days',
    options
  )
}

export async function fetchVehicleReminderInsuranceRiskOverview(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewRiskOverview(
    'vehicle_reminder_insurance_expiry',
    params,
    options
  )
}

export async function fetchVehicleReminderInspectionExpiryList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_inspection_expiry',
    'inspection',
    params,
    'days',
    options
  )
}

export async function fetchVehicleReminderInspectionRiskOverview(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewRiskOverview(
    'vehicle_reminder_inspection_expiry',
    params,
    options
  )
}

export async function fetchVehicleReminderVehicleServiceLifeList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_vehicle_service_life',
    'vehicle',
    params,
    'days',
    options
  )
}

export async function fetchVehicleReminderVehicleServiceLifeRiskOverview(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewRiskOverview(
    'vehicle_reminder_vehicle_service_life',
    params,
    options
  )
}

export async function fetchVehicleReminderMaintenanceExpiryList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_maintenance_expiry',
    'maintenance',
    params,
    'expired',
    options
  )
}

export async function fetchVehicleReminderMaintenanceRiskOverview(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewRiskOverview(
    'vehicle_reminder_maintenance_expiry',
    params,
    options
  )
}

export async function fetchVehicleReminderPartServiceLifeList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_part_service_life',
    'part',
    params,
    'expired',
    options
  )
}

export async function fetchVehicleReminderPartServiceLifeRiskOverview(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewRiskOverview(
    'vehicle_reminder_part_service_life',
    params,
    options
  )
}

export async function fetchInsuranceCompanyOptions(_params?: unknown, options?: ApiRequestOptions) {
  const query = supabase
    .from('vehicle_insurance_company')
    .select('id, company_name, contact_person, contact_phone')
    .order('company_name', { ascending: true })
    .limit(200)

  return await responseHandle<Api.Vms.VehicleManage.InsuranceCompanyOption[]>(
    () => withRequestOptions(query, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}
