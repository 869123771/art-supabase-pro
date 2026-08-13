import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import {
  applyCreateTimeRange,
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import type { QueryResult } from '@/types/api/response'
import { attachCarrierRelationCounts } from './carrier-relations'

type Carrier = Api.Tms.BasicData.Carrier
type CarrierSearchParams = Api.Tms.BasicData.CarrierSearchParams
type CarrierOption = Api.Tms.BasicData.CarrierOption

interface CarrierOptionParams extends Partial<Pick<CarrierOption, 'carrierCode' | 'companyName'>> {
  excludeId?: string
  includeDisabled?: boolean
  maxRows?: number
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const applyCarrierFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: CarrierSearchParams
): TQuery => {
  const { carrierType, enabled, signedContract, keyword, createTimeRange, recordId } = params
  if (recordId) query = query.eq('id', recordId)
  if (carrierType) query = query.eq('carrier_type', carrierType)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  const signedContractValue = normalizeBooleanFilter(signedContract)
  if (signedContractValue !== undefined) query = query.eq('signed_contract', signedContractValue)
  if (keyword) {
    query = query.or(
      `company_name.ilike.%${keyword}%,carrier_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%`
    )
  }
  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchCarrierList(params: CarrierSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_carrier')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCarrierFilters(query, params)
  const result = await responseHandle<Carrier[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })

  return await attachCarrierRelationCounts(result)
}

export async function exportCarrierList(
  params: CarrierSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_carrier')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyCarrierFilters(query, params)
  return await responseHandle<Carrier[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierDetail(id: string) {
  return await responseHandle<Carrier | null>(
    () => supabase.from('tms_carrier').select('*').eq('id', id).maybeSingle(),
    { ignoreCheck: true, showErrorMessage: true }
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
  const { carrierCode, companyName, excludeId, includeDisabled = false, maxRows = 200 } = params
  let query = supabase
    .from('tms_carrier')
    .select('id, carrier_code, company_name, enabled, contact_name, contact_phone')
    .order('company_name', { ascending: true })
    .limit(maxRows)

  if (!includeDisabled) query = query.eq('enabled', true)
  if (excludeId) query = query.neq('id', excludeId)

  const keyword = companyName || carrierCode
  if (keyword) {
    query = query.or(
      `company_name.ilike.%${keyword}%,carrier_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%`
    )
  }

  return await responseHandle<CarrierOption[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCarrier(params: Carrier) {
  return await responseHandle(() => supabase.from('tms_carrier').insert(keysToSnakeDeep(params)), {
    showMessage: true,
    breakReturn: true
  })
}

export async function editCarrier(params: Carrier) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_carrier').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrier(id: string) {
  return await responseHandle(
    () => supabase.from('tms_carrier').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteCarrierBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_carrier').delete({ count: 'exact' }).in('id', ids),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function importCarriers(rows: Carrier[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_carrier')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,carrier_code' }),
    { showMessage: true, breakReturn: true }
  )
}
