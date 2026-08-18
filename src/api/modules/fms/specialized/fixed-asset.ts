import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

export async function fetchAssetCategoryList(accountSetId?: string) {
  let query = supabase.from('fms_asset_category').select('*').order('sort').order('category_code')
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  return await responseHandle<Api.Fms.AssetCategoryRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchFixedAssetList(params: Api.Fms.FixedAssetSearchParams = {}) {
  const { accountSetId, categoryId, from = 0, keyword, status, to = 19 } = params
  let query = supabase
    .from('fms_fixed_asset')
    .select(
      '*, category:fms_asset_category!fms_fixed_asset_category_fkey(id,category_code,category_name)',
      {
        count: 'exact'
      }
    )
    .order('asset_no')
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (categoryId) query = query.eq('category_id', categoryId)
  if (status) query = query.eq('status', status)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `asset_no.ilike.%${value}%,asset_name.ilike.%${value}%,serial_no.ilike.%${value}%,location.ilike.%${value}%`
    )
  }
  return await responseHandle<Api.Fms.FixedAssetRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchAssetDepreciationRuns(accountSetId?: string) {
  let query = supabase
    .from('fms_asset_depreciation_run')
    .select('*, period:fms_accounting_period!fms_asset_depreciation_run_period_fkey(*)')
    .order('create_time', { ascending: false })
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  return await responseHandle<Api.Fms.AssetDepreciationRunRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchAssetDepreciationLines(runId: string) {
  return await responseHandle<Api.Fms.AssetDepreciationLineRecord[]>(
    () =>
      supabase
        .from('fms_asset_depreciation_line')
        .select(
          '*, asset:fms_fixed_asset!fms_asset_depreciation_line_asset_fkey(id,asset_no,asset_name)'
        )
        .eq('run_id', runId)
        .order('create_time'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchFixedAssetSummary(accountSetId?: string, periodId?: string) {
  return await responseHandle<Api.Fms.FixedAssetSummary>(
    () =>
      supabase
        .rpc('fms_fixed_asset_summary', {
          p_account_set_id: accountSetId || null,
          p_period_id: periodId || null
        })
        .single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveAssetCategory(payload: Api.Fms.SaveAssetCategoryPayload) {
  return await responseHandle<Api.Fms.AssetCategoryRecord>(
    () => supabase.rpc('save_fms_asset_category', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '资产类别已更新' : '资产类别已创建'
    }
  )
}

export async function deleteAssetCategory(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_asset_category', { p_category_id: id }),
    { breakReturn: true, showMessage: true, message: '资产类别已删除' }
  )
}

export async function saveFixedAsset(payload: Api.Fms.SaveFixedAssetPayload) {
  return await responseHandle<Api.Fms.FixedAssetRecord>(
    () => supabase.rpc('save_fms_fixed_asset', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '资产卡片已更新' : '资产卡片已创建'
    }
  )
}

export async function deleteFixedAsset(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_fixed_asset', { p_asset_id: id }),
    {
      breakReturn: true,
      showMessage: true,
      message: '资产草稿已删除'
    }
  )
}

export async function actFixedAsset(
  id: string,
  action: Api.Fms.FixedAssetAction,
  payload: { actionDate?: string; amount?: number; reason?: string } = {}
) {
  return await responseHandle<Api.Fms.FixedAssetRecord>(
    () =>
      supabase.rpc('act_fms_fixed_asset', { p_asset_id: id, p_action: action, p_payload: payload }),
    { breakReturn: true, showMessage: true, message: '资产状态已更新' }
  )
}

export async function calculateAssetDepreciation(periodId: string, remark?: string) {
  return await responseHandle<Api.Fms.AssetDepreciationRunRecord>(
    () =>
      supabase.rpc('calculate_fms_asset_depreciation', {
        p_accounting_period_id: periodId,
        p_remark: remark || null
      }),
    { breakReturn: true, showMessage: true, message: '本期折旧已计算' }
  )
}

export async function actAssetDepreciationRun(
  id: string,
  action: 'post' | 'cancel',
  reason?: string
) {
  return await responseHandle<Api.Fms.AssetDepreciationRunRecord>(
    () =>
      supabase.rpc('act_fms_asset_depreciation_run', {
        p_run_id: id,
        p_action: action,
        p_reason: reason || null
      }),
    { breakReturn: true, showMessage: true, message: '折旧批次状态已更新' }
  )
}
