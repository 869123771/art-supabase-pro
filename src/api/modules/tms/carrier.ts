import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import { normalizeBooleanFilter, withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import type { QueryResult } from '@/types/api/response'

type Carrier = Api.Tms.BasicData.Carrier
type CarrierSearchParams = Api.Tms.BasicData.CarrierSearchParams
type CarrierOption = Api.Tms.BasicData.CarrierOption

interface CarrierOptionParams extends Partial<Pick<CarrierOption, 'carrierCode' | 'companyName'>> {
  excludeId?: string
  includeDisabled?: boolean
  ids?: string[]
  maxRows?: number
}

interface SecureListPayload<TRecord, TAccess extends Record<string, string>> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

interface SecureImportResult {
  count: number
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const CARRIER_PAYLOAD_KEYS = [
  'parentUnitId',
  'carrierCode',
  'companyName',
  'carrierType',
  'businessLicenseNo',
  'taxRegistrationNo',
  'legalRepresentative',
  'region',
  'addressDetail',
  'postalCode',
  'enabled',
  'businessLicenseUrl',
  'contactName',
  'contactPhone',
  'contactDepartment',
  'contactPosition',
  'contactEmail',
  'contactQq',
  'invoiceTitle',
  'taxNo',
  'bankName',
  'bankAccountName',
  'bankAccount',
  'signedContract',
  'contractAttachmentUrl',
  'remark'
] as const satisfies readonly (keyof Carrier)[]

const pickPayload = <TRecord extends object, TKey extends Extract<keyof TRecord, string>>(
  record: TRecord,
  keys: readonly TKey[]
): Record<string, unknown> =>
  Object.fromEntries(
    keys.filter((key) => record[key] !== undefined).map((key) => [key, record[key]])
  )

const toCarrierListRpcParams = (
  params: CarrierSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_record_id: params.recordId || null,
    p_carrier_type: params.carrierType || null,
    p_enabled: normalizeBooleanFilter(params.enabled) ?? null,
    p_signed_contract: normalizeBooleanFilter(params.signedContract) ?? null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_create_time_from: params.createTimeRange?.[0]
      ? `${params.createTimeRange[0]}T00:00:00`
      : null,
    p_create_time_to: params.createTimeRange?.[1]
      ? `${params.createTimeRange[1]}T23:59:59.999`
      : null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchCarrierList(params: CarrierSearchParams, options?: ApiRequestOptions) {
  const result = await responseHandle<
    SecureListPayload<Carrier, Api.Tms.BasicData.CarrierFieldAccessMap>
  >(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_carriers_secure', toCarrierListRpcParams(params, 'list')),
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

export async function exportCarrierList(
  params: CarrierSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<
    SecureListPayload<Carrier, Api.Tms.BasicData.CarrierFieldAccessMap>
  >(() => supabase.rpc('tms_list_carriers_secure', toCarrierListRpcParams(params, 'export')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCarrierDetail(id: string) {
  return await responseHandle<Carrier | null>(
    () => supabase.rpc('tms_get_carrier_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function analyzeCarrierPerformanceByAi(
  carrierId: string
): Promise<QueryResult<Api.Tms.BasicData.CarrierPerformanceAdvisorResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.BasicData.CarrierPerformanceAdvisorResponse>(
      'ai-carrier-performance-advisor',
      { body: { carrierId } }
    )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function fetchCarrierOptions(
  params: CarrierOptionParams = {},
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
  return await responseHandle<CarrierOption[]>(
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

export async function addCarrier(params: Carrier) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_carrier_secure', {
        p_payload: keysToSnakeDeep(pickPayload(params, CARRIER_PAYLOAD_KEYS))
      }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editCarrier(params: Carrier) {
  const { id, ...data } = params
  if (!id) throw new Error('承运商 ID 不能为空')
  return await responseHandle<Carrier>(
    () =>
      supabase.rpc('tms_update_carrier_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(pickPayload(data, CARRIER_PAYLOAD_KEYS))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrier(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_carrier_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrierBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('tms_delete_carriers_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

export async function importCarriers(rows: Carrier[]) {
  return await responseHandle<SecureImportResult>(
    () =>
      supabase.rpc('tms_import_carriers_secure', {
        p_rows: rows.map((row) => keysToSnakeDeep(pickPayload(row, CARRIER_PAYLOAD_KEYS)))
      }),
    { showMessage: true, breakReturn: true }
  )
}
