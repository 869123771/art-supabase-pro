import { useSupabase } from '@/hooks'
import {
  applyCreateTimeRange,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { omit } from 'lodash-es'

type RiskPoint = Api.Smis.RiskControl.RiskPointRecord
type RiskPointSearchParams = Api.Smis.RiskControl.RiskPointSearchParams
type SiteRecord = Api.Smis.RiskControl.SiteRecord
type AreaRecord = Api.Smis.RiskControl.AreaRecord
type HazardSource = Api.Smis.RiskControl.HazardSourceRecord
type RiskAssessment = Api.Smis.RiskControl.RiskAssessmentRecord
type RiskAssessmentItem = Api.Smis.RiskControl.RiskAssessmentItemRecord
type ControlMeasure = Api.Smis.RiskControl.ControlMeasureRecord
type RiskAssessmentEvent = Api.Smis.RiskControl.RiskAssessmentEventRecord

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const riskPointSelect = `
  *,
  site:smis_site!smis_risk_point_site_tenant_fkey(id, site_code, site_name),
  area:smis_area!smis_risk_point_area_tenant_fkey(id, area_code, area_name),
  organization:sys_organization!smis_risk_point_organization_tenant_fkey(
    id, organization_code, organization_name
  ),
  responsible_user:sys_user!smis_risk_point_responsible_tenant_fkey(
    id, user_name, nick_name, user_email
  )
`

const assessmentSelect = `
  *,
  assessor_user:sys_user!smis_risk_assessment_assessor_tenant_fkey(
    id, user_name, nick_name, user_email
  ),
  reviewer_user:sys_user!smis_risk_assessment_reviewer_tenant_fkey(
    id, user_name, nick_name, user_email
  )
`

const assessmentItemSelect = `
  *,
  hazard_source:smis_hazard_source!smis_risk_assessment_item_source_tenant_fkey(
    id, risk_point_id, source_no, hazard_name, hazard_description, accident_type,
    possible_consequence, existing_controls, enabled, sort, remark
  ),
  control_measures:smis_control_measure!smis_control_measure_item_tenant_fkey(
    *,
    responsible_user:sys_user!smis_control_measure_responsible_tenant_fkey(
      id, user_name, nick_name, user_email
    )
  )
`

const applyRiskPointFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: RiskPointSearchParams
): TQuery => {
  if (params.siteId) query = query.eq('site_id', params.siteId)
  if (params.areaId) query = query.eq('area_id', params.areaId)
  if (params.status) query = query.eq('status', params.status)
  if (params.currentRiskLevel) query = query.eq('current_risk_level', params.currentRiskLevel)
  if (params.keyword?.trim()) {
    const keyword = params.keyword.trim()
    query = query.or(
      `risk_point_no.ilike.%${keyword}%,risk_point_name.ilike.%${keyword}%,operation_activity.ilike.%${keyword}%,risk_category.ilike.%${keyword}%`
    )
  }
  return applyCreateTimeRange(query, params.createTimeRange)
}

export async function fetchRiskPointList(
  params: RiskPointSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('smis_risk_point')
    .select(riskPointSelect, { count: 'exact' })
    .order('update_time', { ascending: false })
    .order('risk_point_no', { ascending: true })
    .range(from, to)
  query = applyRiskPointFilters(query, params)
  return await responseHandle<RiskPoint[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchSiteOptions() {
  const query = supabase
    .from('smis_site')
    .select('id, site_code, site_name, organization_id')
    .eq('enabled', true)
    .order('sort', { ascending: true })
    .order('site_name', { ascending: true })
    .limit(1000)
  return await responseHandle<SiteRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchAreaOptions(siteId?: string) {
  let query = supabase
    .from('smis_area')
    .select('id, site_id, parent_id, area_code, area_name')
    .eq('enabled', true)
    .order('sort', { ascending: true })
    .order('area_name', { ascending: true })
    .limit(2000)
  if (siteId) query = query.eq('site_id', siteId)
  return await responseHandle<AreaRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchSmisOrganizationOptions() {
  const query = supabase
    .from('sys_organization')
    .select('id, organization_code, organization_name')
    .eq('status', '1')
    .order('sort', { ascending: true })
    .order('organization_name', { ascending: true })
    .limit(1000)
  return await responseHandle<Api.SystemManage.OrganizationListItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchSmisUserOptions() {
  const query = supabase
    .from('sys_user')
    .select('id, user_name, nick_name, user_email, avatar')
    .eq('status', '1')
    .is('deleted_at', null)
    .order('nick_name', { ascending: true })
    .limit(1000)
  return await responseHandle<Api.SystemManage.UserListItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addRiskPoint(params: RiskPoint) {
  return await responseHandle<RiskPoint>(
    () =>
      supabase
        .from('smis_risk_point')
        .insert(keysToSnakeDeep(params))
        .select(riskPointSelect)
        .single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function editRiskPoint(params: RiskPoint) {
  const { id } = params
  const payload = omit(params, [
    'id',
    'currentRiskLevel',
    'createTime',
    'updateTime',
    'site',
    'area',
    'organization',
    'responsibleUser'
  ])
  return await responseHandle(
    () => supabase.from('smis_risk_point').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteRiskPoint(id: string) {
  return await responseHandle(
    () => supabase.from('smis_risk_point').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteRiskPointBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('smis_risk_point').delete({ count: 'exact' }).in('id', ids),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function addSite(params: SiteRecord) {
  return await responseHandle<SiteRecord>(
    () => supabase.from('smis_site').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function editSite(params: SiteRecord) {
  const { id } = params
  const payload = omit(params, ['id', 'createTime', 'updateTime'])
  return await responseHandle(
    () => supabase.from('smis_site').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function addArea(params: AreaRecord) {
  return await responseHandle<AreaRecord>(
    () => supabase.from('smis_area').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function editArea(params: AreaRecord) {
  const { id, ...payload } = params
  return await responseHandle(
    () => supabase.from('smis_area').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchHazardSourceList(riskPointId: string) {
  const query = supabase
    .from('smis_hazard_source')
    .select('*')
    .eq('risk_point_id', riskPointId)
    .order('sort', { ascending: true })
    .order('source_no', { ascending: true })
  return await responseHandle<HazardSource[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addHazardSource(params: HazardSource) {
  return await responseHandle<HazardSource>(
    () => supabase.from('smis_hazard_source').insert(keysToSnakeDeep(params)).select('*').single(),
    { showMessage: true, message: '危险源已新增', breakReturn: true }
  )
}

export async function editHazardSource(params: HazardSource) {
  const { id } = params
  const payload = omit(params, ['id', 'createTime', 'updateTime'])
  return await responseHandle(
    () => supabase.from('smis_hazard_source').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, message: '危险源已更新', breakReturn: true }
  )
}

export async function deleteHazardSource(id: string) {
  return await responseHandle(
    () => supabase.from('smis_hazard_source').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, message: '危险源已删除', breakReturn: true, requireAffected: true }
  )
}

export async function fetchRiskAssessmentList(riskPointId: string) {
  const query = supabase
    .from('smis_risk_assessment')
    .select(assessmentSelect)
    .eq('risk_point_id', riskPointId)
    .order('version_no', { ascending: false })
  return await responseHandle<RiskAssessment[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function createRiskAssessment(
  riskPointId: string,
  assessmentDate: string,
  assessmentSummary?: string | null
) {
  return await responseHandle<RiskAssessment>(
    () =>
      supabase.rpc('smis_create_risk_assessment', {
        p_risk_point_id: riskPointId,
        p_assessment_date: assessmentDate,
        p_assessment_summary: assessmentSummary || null
      }),
    { showMessage: true, message: '评估版本已创建', breakReturn: true }
  )
}

export async function editRiskAssessment(params: RiskAssessment) {
  const { id } = params
  const payload = {
    assessorUserId: params.assessorUserId || null,
    assessmentDate: params.assessmentDate,
    assessmentSummary: params.assessmentSummary || null
  }
  return await responseHandle(
    () => supabase.from('smis_risk_assessment').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, message: '评估信息已更新', breakReturn: true }
  )
}

export async function deleteRiskAssessment(id: string) {
  return await responseHandle(
    () => supabase.from('smis_risk_assessment').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, message: '草稿评估已删除', breakReturn: true, requireAffected: true }
  )
}

export async function transitionRiskAssessment(
  id: string,
  action: Api.Smis.RiskControl.RiskAssessmentTransitionAction,
  comment?: string | null
) {
  return await responseHandle<RiskAssessment>(
    () =>
      supabase.rpc('smis_transition_risk_assessment', {
        p_assessment_id: id,
        p_action: action,
        p_comment: comment || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchRiskAssessmentItemList(assessmentId: string) {
  const query = supabase
    .from('smis_risk_assessment_item')
    .select(assessmentItemSelect)
    .eq('assessment_id', assessmentId)
    .order('risk_score', { ascending: false })
    .order('create_time', { ascending: true })
  return await responseHandle<RiskAssessmentItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addRiskAssessmentItem(params: RiskAssessmentItem) {
  return await responseHandle<RiskAssessmentItem>(
    () =>
      supabase
        .from('smis_risk_assessment_item')
        .insert(keysToSnakeDeep(params))
        .select(assessmentItemSelect)
        .single(),
    { showMessage: true, message: 'LEC 评估项已新增', breakReturn: true }
  )
}

export async function editRiskAssessmentItem(params: RiskAssessmentItem) {
  const { id } = params
  const payload = omit(params, [
    'id',
    'riskScore',
    'riskLevel',
    'hazardNameSnapshot',
    'hazardDescriptionSnapshot',
    'accidentTypeSnapshot',
    'possibleConsequenceSnapshot',
    'existingControlsSnapshot',
    'createTime',
    'updateTime',
    'hazardSource',
    'controlMeasures'
  ])
  return await responseHandle(
    () => supabase.from('smis_risk_assessment_item').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, message: 'LEC 评估项已更新', breakReturn: true }
  )
}

export async function deleteRiskAssessmentItem(id: string) {
  return await responseHandle(
    () => supabase.from('smis_risk_assessment_item').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, message: 'LEC 评估项已删除', breakReturn: true, requireAffected: true }
  )
}

export async function addControlMeasure(params: ControlMeasure) {
  return await responseHandle<ControlMeasure>(
    () =>
      supabase.from('smis_control_measure').insert(keysToSnakeDeep(params)).select('*').single(),
    { showMessage: true, message: '管控措施已新增', breakReturn: true }
  )
}

export async function editControlMeasure(params: ControlMeasure) {
  const { id } = params
  const payload = omit(params, ['id', 'createTime', 'updateTime', 'responsibleUser'])
  return await responseHandle(
    () => supabase.from('smis_control_measure').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, message: '管控措施已更新', breakReturn: true }
  )
}

export async function deleteControlMeasure(id: string) {
  return await responseHandle(
    () => supabase.from('smis_control_measure').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, message: '管控措施已删除', breakReturn: true, requireAffected: true }
  )
}

export async function fetchRiskAssessmentEventList(assessmentId: string) {
  const query = supabase
    .from('smis_risk_assessment_event')
    .select(
      `
        *,
        actor_user:sys_user!smis_risk_assessment_event_actor_tenant_fkey(
          id, user_name, nick_name, user_email
        )
      `
    )
    .eq('assessment_id', assessmentId)
    .order('create_time', { ascending: false })
  return await responseHandle<RiskAssessmentEvent[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}
