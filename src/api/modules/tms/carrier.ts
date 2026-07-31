import { useSupabase } from '@/hooks'
import { withRequestOptions, type SupabaseQueryLike } from '@/api/modules/tms/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { attachCarrierRelationCounts } from './carrier-relations'

type Carrier = Api.Tms.BasicData.Carrier
type CarrierSearchParams = Api.Tms.BasicData.CarrierSearchParams
type CarrierOption = Api.Tms.BasicData.CarrierOption

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

const applyDateRange = (query: SupabaseQueryLike, dateRange?: string[]): SupabaseQueryLike => {
  if (dateRange?.[0]) query = query.gte('create_time', `${dateRange[0]}T00:00:00`)
  if (dateRange?.[1]) query = query.lte('create_time', `${dateRange[1]}T23:59:59.999`)
  return query
}

const applyCarrierFilters = (
  query: SupabaseQueryLike,
  params: CarrierSearchParams
): SupabaseQueryLike => {
  const { carrierType, enabled, signedContract, keyword, createTimeRange } = params
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
  return applyDateRange(query, createTimeRange)
}

export async function fetchCarrierList(params: CarrierSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_carrier')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike

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
    .limit(maxRows) as unknown as SupabaseQueryLike

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

export async function fetchCarrierOptions(
  params: Partial<Pick<CarrierOption, 'carrierCode' | 'companyName'>> = {},
  options?: ApiRequestOptions
) {
  const { carrierCode, companyName } = params
  let query = supabase
    .from('tms_carrier')
    .select('id, carrier_code, company_name, contact_name, contact_phone')
    .eq('enabled', true)
    .order('company_name', { ascending: true })
    .limit(200)

  const keyword = companyName || carrierCode
  if (keyword) {
    query = query.or(
      `company_name.ilike.%${keyword}%,carrier_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%`
    )
  }

  return await responseHandle<CarrierOption[]>(
    () => withRequestOptions(query as unknown as SupabaseQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
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
  return await responseHandle(() => supabase.from('tms_carrier').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteCarrierBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_carrier').delete().in('id', ids), {
    showMessage: true
  })
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
