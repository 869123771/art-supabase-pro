import { useSupabase } from '@/hooks'

type Subject = Api.Fms.SubjectRecord
type Currency = Api.Fms.CurrencyRecord
type ExchangeRate = Api.Fms.ExchangeRateRecord
type AuxiliaryType = Api.Fms.AuxiliaryTypeRecord
type AuxiliaryItem = Api.Fms.AuxiliaryItemRecord
type OpeningBalance = Api.Fms.OpeningBalanceRecord

interface OpeningBalanceListPayload {
  records?: OpeningBalance[]
  fieldAccess?: Api.Fms.OpeningBalanceFieldAccessMap
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const SUBJECT_SELECT = `
  *,
  auxiliaryConfigs:fms_subject_auxiliary_type(
    id,
    auxiliary_type_id,
    is_required,
    sort,
    auxiliaryType:fms_auxiliary_type(id, type_code, type_name, source_type, is_enabled)
  )
`

async function saveRecord<T extends { id?: string }>(
  table: string,
  payload: T,
  message: { create: string; update: string }
) {
  const { id, ...values } = payload
  const writeValues = keysToSnakeDeep({ ...values }) as Record<string, unknown>
  const query = id
    ? supabase.from(table).update(writeValues, { count: 'exact' }).eq('id', id)
    : supabase.from(table).insert(writeValues)

  return await responseHandle<T>(() => query.select('*').single(), {
    breakReturn: true,
    requireAffected: Boolean(id),
    showMessage: true,
    message: id ? message.update : message.create
  })
}

export async function fetchSubjectList(accountSetId: string) {
  return await responseHandle<Subject[]>(
    () =>
      supabase
        .from('fms_subject')
        .select(SUBJECT_SELECT)
        .eq('account_set_id', accountSetId)
        .order('subject_code', { ascending: true }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveSubject(payload: Api.Fms.SaveSubjectPayload) {
  return await responseHandle<Subject>(
    () => supabase.rpc('save_fms_subject', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '会计科目已更新' : '会计科目已创建'
    }
  )
}

export async function setSubjectEnabled(id: string, isEnabled: boolean) {
  return await saveRecord(
    'fms_subject',
    { id, isEnabled },
    {
      create: '',
      update: isEnabled ? '会计科目已启用' : '会计科目已停用'
    }
  )
}

export async function fetchCurrencyList(accountSetId: string) {
  return await responseHandle<Currency[]>(
    () =>
      supabase
        .from('fms_currency')
        .select('*')
        .eq('account_set_id', accountSetId)
        .order('is_base', { ascending: false })
        .order('sort', { ascending: true }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveCurrency(payload: Api.Fms.SaveCurrencyPayload) {
  return await saveRecord('fms_currency', payload, {
    create: '核算币种已创建',
    update: '核算币种已更新'
  })
}

export async function setCurrencyEnabled(id: string, isEnabled: boolean) {
  return await saveRecord(
    'fms_currency',
    { id, isEnabled },
    { create: '', update: isEnabled ? '核算币种已启用' : '核算币种已停用' }
  )
}

export async function fetchExchangeRateList(accountSetId: string) {
  return await responseHandle<ExchangeRate[]>(
    () =>
      supabase
        .from('fms_exchange_rate')
        .select('*, currency:fms_currency(id, currency_code, currency_name)')
        .eq('account_set_id', accountSetId)
        .order('rate_date', { ascending: false }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveExchangeRate(payload: Api.Fms.SaveExchangeRatePayload) {
  return await saveRecord('fms_exchange_rate', payload, {
    create: '汇率已维护',
    update: '汇率已更新'
  })
}

export async function fetchAuxiliaryTypeList(accountSetId: string) {
  return await responseHandle<AuxiliaryType[]>(
    () =>
      supabase
        .from('fms_auxiliary_type')
        .select('*')
        .eq('account_set_id', accountSetId)
        .order('sort', { ascending: true })
        .order('type_code', { ascending: true }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveAuxiliaryType(payload: Api.Fms.SaveAuxiliaryTypePayload) {
  return await saveRecord('fms_auxiliary_type', payload, {
    create: '辅助核算类型已创建',
    update: '辅助核算类型已更新'
  })
}

export async function setAuxiliaryTypeEnabled(id: string, isEnabled: boolean) {
  return await saveRecord(
    'fms_auxiliary_type',
    { id, isEnabled },
    { create: '', update: isEnabled ? '辅助核算类型已启用' : '辅助核算类型已停用' }
  )
}

export async function deleteAuxiliaryType(id: string) {
  return await responseHandle<AuxiliaryType>(
    () => supabase.rpc('delete_fms_auxiliary_type', { p_id: id }),
    {
      breakReturn: true,
      showMessage: true,
      message: '辅助核算维度已删除'
    }
  )
}

export async function syncAuxiliaryItems(accountSetId: string, auxiliaryTypeId: string) {
  return await responseHandle<Api.Fms.AuxiliarySyncResult>(
    () =>
      supabase
        .rpc('sync_fms_auxiliary_items', {
          p_account_set_id: accountSetId,
          p_auxiliary_type_id: auxiliaryTypeId
        })
        .single(),
    { breakReturn: true, showMessage: true, message: '辅助核算主数据已同步' }
  )
}

export async function fetchAuxiliaryItemList(accountSetId: string, auxiliaryTypeId?: string) {
  let query = supabase
    .from('fms_auxiliary_item')
    .select('*')
    .eq('account_set_id', accountSetId)
    .order('sort', { ascending: true })
    .order('item_code', { ascending: true })
  if (auxiliaryTypeId) query = query.eq('auxiliary_type_id', auxiliaryTypeId)
  return await responseHandle<AuxiliaryItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function saveAuxiliaryItem(payload: Api.Fms.SaveAuxiliaryItemPayload) {
  return await saveRecord('fms_auxiliary_item', payload, {
    create: '辅助核算项目已创建',
    update: '辅助核算项目已更新'
  })
}

export async function setAuxiliaryItemEnabled(id: string, isEnabled: boolean) {
  return await saveRecord(
    'fms_auxiliary_item',
    { id, isEnabled },
    { create: '', update: isEnabled ? '辅助核算项目已启用' : '辅助核算项目已停用' }
  )
}

export async function fetchOpeningBalanceList(accountSetId: string, fiscalYear: number) {
  const result = await responseHandle<OpeningBalanceListPayload>(
    () =>
      supabase.rpc('fms_list_opening_balances_secure', {
        p_account_set_id: accountSetId,
        p_fiscal_year: fiscalYear
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return {
    ...result,
    data: result.data?.records ?? [],
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function saveOpeningBalance(payload: Api.Fms.SaveOpeningBalancePayload) {
  return await responseHandle<OpeningBalance>(
    () => supabase.rpc('save_fms_opening_balance_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '科目期初余额已更新' : '科目期初余额已录入'
    }
  )
}

export async function deleteOpeningBalance(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_opening_balance_secure', { p_balance_id: id }),
    {
      breakReturn: true,
      showMessage: true,
      message: '期初余额记录已删除'
    }
  )
}

export async function fetchOpeningBalanceSummary(accountSetId: string, fiscalYear: number) {
  return await responseHandle<Api.Fms.OpeningBalanceSummary>(
    () =>
      supabase.rpc('fms_opening_balance_summary_secure', {
        p_account_set_id: accountSetId,
        p_fiscal_year: fiscalYear
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function setOpeningBalanceStatus(
  accountSetId: string,
  fiscalYear: number,
  status: Api.Fms.OpeningBalanceStatus,
  reason?: string | null
) {
  return await responseHandle<Api.Fms.OpeningBalanceControlRecord>(
    () =>
      supabase.rpc('set_fms_opening_balance_status_secure', {
        p_account_set_id: accountSetId,
        p_fiscal_year: fiscalYear,
        p_status: status,
        p_reason: reason || null
      }),
    {
      breakReturn: true,
      showMessage: true,
      message: status === 'confirmed' ? '期初余额已确认' : '期初余额已反确认'
    }
  )
}
