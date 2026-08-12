import { useSupabase } from '@/hooks'
import { withRequestOptions, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { startWorkflow } from '@/api/workflow'

type Contract = Api.Tms.BasicData.Contract
type ContractSearchParams = Api.Tms.BasicData.ContractSearchParams
type ContractTransportDetail = Api.Tms.BasicData.ContractTransportDetail
type ContractDetailSelectorItem = Api.Tms.BasicData.ContractDetailSelectorItem
type ContractDetailSelectorSearchParams = Api.Tms.BasicData.ContractDetailSelectorSearchParams

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const CONTRACT_SELECT = `
  *,
  carrier:tms_carrier!tms_contract_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  ),
  customer:tms_customer!tms_contract_customer_id_fkey(
    id,
    customer_code,
    customer_name,
    contact_name,
    contact_phone
  )
`

const normalizeTransportDetail = (value: unknown): ContractTransportDetail | null => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const detail = value as Record<string, unknown>
  const cargoDescription = String(detail.cargoDescription ?? '').trim()
  const cargoCode = String(detail.cargoCode ?? '').trim()
  const unit = String(detail.unit ?? '').trim()
  if (!cargoDescription || !cargoCode || !unit) return null

  const contractQuantity = Number(detail.contractQuantity)
  const transportUnitPrice = Number(detail.transportUnitPrice)
  const freight = Number(detail.freight)
  if (
    [contractQuantity, transportUnitPrice, freight].some(
      (item) => !Number.isFinite(item) || item < 0
    )
  ) {
    return null
  }

  return {
    cargoId: detail.cargoId ? String(detail.cargoId) : null,
    cargoDescription,
    cargoCode,
    contractQuantity,
    unit,
    transportUnitPrice,
    freight
  }
}

const normalizeContractRecord = (record: Contract): Contract => ({
  ...record,
  transportDetails: Array.isArray(record.transportDetails)
    ? record.transportDetails
        .map((item: unknown) => normalizeTransportDetail(item))
        .filter((item): item is ContractTransportDetail => item !== null)
    : [],
  attachments: Array.isArray(record.attachments) ? record.attachments : []
})

const applyContractFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: ContractSearchParams
): TQuery => {
  const {
    contractStatus,
    businessContractType,
    contractCategory,
    customerId,
    carrierId,
    billingMethod,
    keyword,
    createTimeRange,
    recordId
  } = params
  if (recordId) query = query.eq('id', recordId)
  if (contractStatus) query = query.eq('contract_status', contractStatus)
  if (businessContractType) query = query.eq('business_contract_type', businessContractType)
  if (contractCategory) query = query.eq('contract_category', contractCategory)
  if (customerId) query = query.eq('customer_id', customerId)
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (billingMethod) query = query.eq('billing_method', billingMethod)
  if (keyword) {
    query = query.or(
      `contract_name.ilike.%${keyword}%,contract_no.ilike.%${keyword}%,paper_contract_no.ilike.%${keyword}%,mnemonic_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,transport_route.ilike.%${keyword}%,handler.ilike.%${keyword}%`
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
    .range(from, to)
  query = applyContractFilters(query, params)
  const result = await responseHandle<Contract[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: (result.data ?? []).map(normalizeContractRecord) }
}

export async function fetchAvailableContractDetailList(
  params: ContractDetailSelectorSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  const keyword = String(params.keyword ?? '').trim()
  const query = supabase.rpc('tms_list_available_contract_details', {
    p_keyword: keyword || null
  })
  const result = await responseHandle<ContractDetailSelectorItem[]>(
    () => withRequestOptions(query, options),
    { ignoreCheck: true, showErrorMessage: true }
  )
  const details = result.data ?? []
  return {
    ...result,
    data: details.slice(from, to + 1),
    total: details.length
  }
}

export async function exportContractList(
  params: ContractSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_contract')
    .select(CONTRACT_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyContractFilters(query, params)
  const result = await responseHandle<Contract[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: (result.data ?? []).map(normalizeContractRecord) }
}

export async function fetchContractDetail(id: string) {
  const result = await responseHandle<Contract | null>(
    () => supabase.from('tms_contract').select(CONTRACT_SELECT).eq('id', id).maybeSingle(),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return { ...result, data: result.data ? normalizeContractRecord(result.data) : null }
}

export async function addContract(params: Contract) {
  return await responseHandle<Pick<Contract, 'id'>>(
    () => supabase.from('tms_contract').insert(keysToSnakeDeep(params)).select('id').single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function submitContractForApproval(contract: Contract) {
  if (!contract.id) throw new Error('合同 ID 不能为空')
  return await startWorkflow({
    businessType: 'tms_contract',
    businessId: contract.id,
    businessTitle: `合同 ${contract.contractNo || contract.contractName || contract.id}`
  })
}

export async function editContract(params: Contract) {
  const { id } = params
  const data = { ...params }
  delete data.id
  delete data.carrier
  delete data.customer
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
