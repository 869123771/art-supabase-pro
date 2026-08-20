import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { startWorkflow } from '@/api/workflow'

type Contract = Api.Tms.BasicData.Contract
type ContractSearchParams = Api.Tms.BasicData.ContractSearchParams
type ContractTransportDetail = Api.Tms.BasicData.ContractTransportDetail
type ContractDetailSelectorItem = Api.Tms.BasicData.ContractDetailSelectorItem
type ContractDetailSelectorSearchParams = Api.Tms.BasicData.ContractDetailSelectorSearchParams
type ContractFieldAccessMap = Api.Tms.BasicData.ContractFieldAccessMap
type SensitiveNumber = Api.Tms.BasicData.SensitiveNumber

interface SecureContractListPayload {
  records: Contract[]
  total: number
  fieldAccess: ContractFieldAccessMap
}

interface ImportContractResult {
  count: number
  ids: string[]
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const CONTRACT_PAYLOAD_KEYS = [
  'contractNo',
  'contractName',
  'paperContractNo',
  'mnemonicCode',
  'contractCategory',
  'transportMode',
  'businessContractType',
  'customerId',
  'carrierId',
  'contactName',
  'waybillNo',
  'customerSignatory',
  'billingMethod',
  'contractAmount',
  'transportUnitPrice',
  'roadConsumptionRate',
  'lossDeductionPrice',
  'signTime',
  'effectiveDate',
  'expiryDate',
  'isCompleted',
  'agreedTransportQuantity',
  'transportRoute',
  'shipperName',
  'payerName',
  'consigneeName',
  'specialTransportRequirements',
  'otherDeductionTerms',
  'handler',
  'contractDescription',
  'transportDetails',
  'attachments'
] as const satisfies readonly (keyof Contract)[]

const normalizeSensitiveNumber = (value: unknown): SensitiveNumber | undefined => {
  if (value === undefined) return undefined
  if (value === null) return null
  if (typeof value === 'string' && value.trim() === '***') return '***'
  const numberValue = Number(value)
  return Number.isFinite(numberValue) ? numberValue : undefined
}

const normalizeTransportDetail = (value: unknown): ContractTransportDetail | null => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const detail = value as Record<string, unknown>
  const cargoDescription = String(detail.cargoDescription ?? '').trim()
  const cargoCode = String(detail.cargoCode ?? '').trim()
  const unit = String(detail.unit ?? '').trim()
  if (!cargoDescription || !cargoCode || !unit) return null

  const contractQuantity = Number(detail.contractQuantity)
  if (!Number.isFinite(contractQuantity) || contractQuantity < 0) return null

  const transportUnitPrice = normalizeSensitiveNumber(detail.transportUnitPrice)
  const freight = normalizeSensitiveNumber(detail.freight)
  return {
    cargoId: detail.cargoId ? String(detail.cargoId) : null,
    cargoDescription,
    cargoCode,
    contractQuantity,
    unit,
    ...(transportUnitPrice === undefined ? {} : { transportUnitPrice }),
    ...(freight === undefined ? {} : { freight })
  }
}

const normalizeContractRecord = (record: Contract): Contract => ({
  ...record,
  transportDetails: Array.isArray(record.transportDetails)
    ? record.transportDetails
        .map((item: unknown) => normalizeTransportDetail(item))
        .filter((item): item is ContractTransportDetail => item !== null)
    : [],
  attachments: Array.isArray(record.attachments) ? record.attachments : undefined
})

const toContractPayload = (contract: Contract): Record<string, unknown> =>
  Object.fromEntries(
    CONTRACT_PAYLOAD_KEYS.filter((key) => contract[key] !== undefined).map((key) => [
      key,
      contract[key]
    ])
  )

const toContractListRpcParams = (
  params: ContractSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_contract_status: params.contractStatus || null,
    p_business_contract_type: params.businessContractType || null,
    p_contract_category: params.contractCategory || null,
    p_customer_id: params.customerId || null,
    p_carrier_id: params.carrierId || null,
    p_billing_method: params.billingMethod || null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_create_time_from: params.createTimeRange?.[0]
      ? `${params.createTimeRange[0]}T00:00:00`
      : null,
    p_create_time_to: params.createTimeRange?.[1]
      ? `${params.createTimeRange[1]}T23:59:59.999`
      : null,
    p_record_id: params.recordId || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchContractList(params: ContractSearchParams, options?: ApiRequestOptions) {
  const query = supabase.rpc('tms_list_contracts_secure', toContractListRpcParams(params, 'list'))
  const result = await responseHandle<SecureContractListPayload>(
    () => withRequestOptions(query, options),
    { showErrorMessage: true }
  )
  return {
    data: (result.data?.records ?? []).map(normalizeContractRecord),
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
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
    { showErrorMessage: true }
  )
  const details = result.data ?? []
  return { ...result, data: details.slice(from, to + 1), total: details.length }
}

export async function exportContractList(
  params: ContractSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureContractListPayload>(
    () => supabase.rpc('tms_list_contracts_secure', toContractListRpcParams(params, 'export')),
    { showErrorMessage: true }
  )
  return {
    data: (result.data?.records ?? []).map(normalizeContractRecord),
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchContractDetail(id: string) {
  const result = await responseHandle<Contract | null>(
    () => supabase.rpc('tms_get_contract_secure', { p_id: id }),
    { showErrorMessage: true }
  )
  return { ...result, data: result.data ? normalizeContractRecord(result.data) : null }
}

export async function addContract(params: Contract) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_contract_secure', {
        p_payload: keysToSnakeDeep(toContractPayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
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
  if (!params.id) throw new Error('合同 ID 不能为空')
  return await responseHandle<Contract>(
    () =>
      supabase.rpc('tms_update_contract_secure', {
        p_id: params.id,
        p_payload: keysToSnakeDeep(toContractPayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteContract(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_contract_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteContractBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('tms_delete_contracts_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

export async function importContracts(rows: Contract[]) {
  const payload = rows.map((row) => keysToSnakeDeep(toContractPayload(row)))
  return await responseHandle<ImportContractResult>(
    () => supabase.rpc('tms_import_contracts_secure', { p_rows: payload }),
    { showMessage: true, breakReturn: true }
  )
}
