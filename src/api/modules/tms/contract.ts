import { useSupabase } from '@/hooks'
import { withRequestOptions, type SupabaseQueryLike } from '@/api/modules/tms/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Contract = Api.Tms.BasicData.Contract
type ContractSearchParams = Api.Tms.BasicData.ContractSearchParams

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const CONTRACT_SELECT = `
  *,
  carrier:tms_carrier!tms_contract_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  )
`

const applyContractFilters = (
  query: SupabaseQueryLike,
  params: ContractSearchParams
): SupabaseQueryLike => {
  const { contractStatus, carrierId, billingMethod, keyword, createTimeRange } = params
  if (contractStatus) query = query.eq('contract_status', contractStatus)
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (billingMethod) query = query.eq('billing_method', billingMethod)
  if (keyword) {
    query = query.or(
      `contract_name.ilike.%${keyword}%,contract_no.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,waybill_no.ilike.%${keyword}%,handler.ilike.%${keyword}%`
    )
  }
  if (createTimeRange?.[0]) query = query.gte('create_time', `${createTimeRange[0]}T00:00:00`)
  if (createTimeRange?.[1]) {
    query = query.lte('create_time', `${createTimeRange[1]}T23:59:59.999`)
  }
  return query
}

export async function fetchContractList(params: ContractSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_contract')
    .select(CONTRACT_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyContractFilters(query, params)
  return await responseHandle<Contract[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportContractList(
  params: ContractSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_contract')
    .select(CONTRACT_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyContractFilters(query, params)
  return await responseHandle<Contract[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchContractDetail(id: string) {
  return await responseHandle<Contract | null>(
    () => supabase.from('tms_contract').select(CONTRACT_SELECT).eq('id', id).maybeSingle(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function addContract(params: Contract) {
  return await responseHandle(() => supabase.from('tms_contract').insert(keysToSnakeDeep(params)), {
    showMessage: true,
    breakReturn: true
  })
}

export async function editContract(params: Contract) {
  const { id } = params
  const data = { ...params }
  delete data.id
  delete data.carrier
  return await responseHandle(
    () => supabase.from('tms_contract').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteContract(id: string) {
  return await responseHandle(() => supabase.from('tms_contract').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteContractBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_contract').delete().in('id', ids), {
    showMessage: true
  })
}

export async function importContracts(rows: Contract[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_contract')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,contract_no' }),
    { showMessage: true, breakReturn: true }
  )
}
