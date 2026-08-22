import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

type Asset = Api.Fms.FixedAssetRecord

interface FixedAssetListPayload {
  records: Asset[]
  total: number
  fieldAccess: Api.Fms.FixedAssetFieldAccessMap
}

interface DepreciationRunListPayload {
  records: Api.Fms.AssetDepreciationRunRecord[]
  fieldAccess: Api.Fms.FixedAssetFieldAccessMap
}

interface DepreciationLineListPayload {
  records: Api.Fms.AssetDepreciationLineRecord[]
  fieldAccess: Api.Fms.FixedAssetFieldAccessMap
}

export async function fetchAssetCategoryList(accountSetId?: string) {
  return await responseHandle<Api.Fms.AssetCategoryRecord[]>(
    () =>
      supabase.rpc('fms_list_asset_categories_secure', {
        p_account_set_id: accountSetId || null,
        p_tenant_id: null
      }),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function fetchFixedAssetList(params: Api.Fms.FixedAssetSearchParams = {}) {
  const { accountSetId, categoryId, from = 0, keyword, status, to = 19 } = params
  const result = await responseHandle<FixedAssetListPayload>(
    () =>
      supabase.rpc('fms_list_fixed_assets_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_category_id: categoryId || null,
        p_status: status || null,
        p_keyword: keyword?.trim() || null,
        p_tenant_id: null
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchFixedAssetDetail(id: string) {
  return await responseHandle<Asset>(
    () => supabase.rpc('fms_get_fixed_asset_secure', { p_asset_id: id }),
    { showErrorMessage: true }
  )
}

export async function fetchAssetDepreciationRuns(accountSetId?: string) {
  const result = await responseHandle<DepreciationRunListPayload>(
    () =>
      supabase.rpc('fms_list_asset_depreciation_runs_secure', {
        p_account_set_id: accountSetId || null,
        p_tenant_id: null
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchAssetDepreciationLines(runId: string) {
  const result = await responseHandle<DepreciationLineListPayload>(
    () => supabase.rpc('fms_list_asset_depreciation_lines_secure', { p_run_id: runId }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchFixedAssetSummary(accountSetId?: string, periodId?: string) {
  return await responseHandle<Api.Fms.FixedAssetSummary>(
    () =>
      supabase.rpc('fms_fixed_asset_summary_secure', {
        p_account_set_id: accountSetId || null,
        p_period_id: periodId || null,
        p_tenant_id: null
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveAssetCategory(payload: Api.Fms.SaveAssetCategoryPayload) {
  return await responseHandle<Api.Fms.AssetCategoryRecord>(
    () => supabase.rpc('save_fms_asset_category_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '资产类别已更新' : '资产类别已创建'
    }
  )
}

export async function deleteAssetCategory(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_asset_category_secure', { p_category_id: id }),
    { breakReturn: true, showMessage: true, message: '资产类别已删除' }
  )
}

export async function saveFixedAsset(payload: Api.Fms.SaveFixedAssetPayload) {
  return await responseHandle<Api.Fms.FixedAssetRecord>(
    () => supabase.rpc('save_fms_fixed_asset_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '资产卡片已更新' : '资产卡片已创建'
    }
  )
}

export async function deleteFixedAsset(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_fixed_asset_secure', { p_asset_id: id }),
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
  payload: {
    actionDate?: string
    amount?: number
    fundAccountId?: string
    referenceNo?: string
    reason?: string
  } = {}
) {
  return await responseHandle<Api.Fms.FixedAssetRecord>(
    () =>
      supabase.rpc('act_fms_fixed_asset_secure', {
        p_asset_id: id,
        p_action: action,
        p_payload: payload
      }),
    { breakReturn: true, showMessage: true, message: '资产状态已更新' }
  )
}

export async function calculateAssetDepreciation(periodId: string, remark?: string) {
  return await responseHandle<Api.Fms.AssetDepreciationRunRecord>(
    () =>
      supabase.rpc('calculate_fms_asset_depreciation_secure', {
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
      supabase.rpc('act_fms_asset_depreciation_run_secure', {
        p_run_id: id,
        p_action: action,
        p_reason: reason || null
      }),
    { breakReturn: true, showMessage: true, message: '折旧批次状态已更新' }
  )
}
