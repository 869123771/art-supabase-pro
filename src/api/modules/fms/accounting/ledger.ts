import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

export async function fetchSubjectBalanceReport(params: Api.Fms.SubjectBalanceReportParams) {
  return await responseHandle<Api.Fms.SubjectBalanceReportRecord[]>(
    () =>
      supabase.rpc('fms_subject_balance_report', {
        p_account_set_id: params.accountSetId,
        p_fiscal_year: params.fiscalYear,
        p_period_from: params.periodFrom ?? 1,
        p_period_to: params.periodTo ?? 12,
        p_subject_id: params.subjectId || null,
        p_hide_zero: params.hideZero ?? false
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchGeneralLedgerReport(
  params: Api.Fms.LedgerReportParams & { subjectId: string }
) {
  return await responseHandle<Api.Fms.GeneralLedgerReportRecord[]>(
    () =>
      supabase.rpc('fms_general_ledger_report', {
        p_account_set_id: params.accountSetId,
        p_fiscal_year: params.fiscalYear,
        p_subject_id: params.subjectId,
        p_period_from: params.periodFrom ?? 1,
        p_period_to: params.periodTo ?? 12
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchSubsidiaryLedgerReport(params: Api.Fms.SubsidiaryLedgerReportParams) {
  return await responseHandle<Api.Fms.SubsidiaryLedgerReportRecord[]>(
    () =>
      supabase.rpc('fms_subsidiary_ledger_report', {
        p_account_set_id: params.accountSetId,
        p_fiscal_year: params.fiscalYear,
        p_subject_id: params.subjectId,
        p_period_from: params.periodFrom ?? 1,
        p_period_to: params.periodTo ?? 12,
        p_auxiliary_type_id: params.auxiliaryTypeId || null,
        p_auxiliary_item_id: params.auxiliaryItemId || null
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}
