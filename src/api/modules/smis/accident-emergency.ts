import { omit } from 'lodash-es'
import { useSupabase } from '@/hooks'

type AccidentCase = Api.Smis.AccidentEmergency.AccidentCaseRecord
type AccidentSearch = Api.Smis.AccidentEmergency.AccidentCaseSearchParams
type EmergencyPlan = Api.Smis.AccidentEmergency.EmergencyPlanRecord
type EmergencyDrill = Api.Smis.AccidentEmergency.EmergencyDrillRecord

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

interface AccidentCaseListPayload {
  records?: AccidentCase[]
  total?: number
  fieldAccess?: Api.Smis.AccidentEmergency.AccidentCaseFieldAccessMap
}

const userSelect = 'id, user_name, nick_name, user_email'
const planSelect = `
  *, owner_user:sys_user!smis_emergency_plan_owner_tenant_fkey(${userSelect})
`
const drillSelect = `
  *,
  plan:smis_emergency_plan!smis_emergency_drill_plan_tenant_fkey(id, plan_no, plan_name),
  organizer_user:sys_user!smis_emergency_drill_organizer_tenant_fkey(${userSelect})
`

export async function fetchAccidentCaseList(params: AccidentSearch) {
  const { from = 0, to = 9 } = params
  const result = await responseHandle<AccidentCaseListPayload>(
    () =>
      supabase.rpc('smis_list_accident_cases_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_status: params.status || null,
        p_severity: params.severity || null,
        p_keyword: params.keyword?.trim() || null,
        p_occurred_from: params.occurredTimeRange?.[0]
          ? `${params.occurredTimeRange[0]}T00:00:00`
          : null,
        p_occurred_to: params.occurredTimeRange?.[1]
          ? `${params.occurredTimeRange[1]}T23:59:59.999`
          : null
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

export async function addAccidentCase(params: AccidentCase) {
  const payload = omit(params, [
    'id',
    'status',
    'closedAt',
    'createTime',
    'updateTime',
    'riskPoint',
    'reporterUser',
    'investigatorUser',
    'createdByUserId',
    'fieldAccess',
    'isRecordOwner'
  ])
  return await responseHandle<AccidentCase>(
    () => supabase.rpc('smis_save_accident_case_secure', { p_payload: keysToSnakeDeep(payload) }),
    { showMessage: true, message: '事故事件已上报', breakReturn: true }
  )
}

export async function editAccidentCase(params: AccidentCase) {
  const payload = omit(params, [
    'id',
    'status',
    'closedAt',
    'createTime',
    'updateTime',
    'riskPoint',
    'reporterUser',
    'investigatorUser',
    'createdByUserId',
    'fieldAccess',
    'isRecordOwner'
  ])
  return await responseHandle<AccidentCase>(
    () => supabase.rpc('smis_save_accident_case_secure', { p_payload: keysToSnakeDeep(payload) }),
    { showMessage: true, message: '事故事件已更新', breakReturn: true }
  )
}

export async function fetchAccidentCaseDetail(id: string) {
  return await responseHandle<AccidentCase>(
    () => supabase.rpc('smis_get_accident_case_secure', { p_case_id: id }),
    { showErrorMessage: true, breakReturn: true }
  )
}

export async function transitionAccidentCase(params: {
  id: string
  action: Api.Smis.AccidentEmergency.AccidentCaseAction
  investigatorUserId?: string | null
  comment?: string | null
  attachmentRefs?: Api.Smis.AccidentEmergency.AttachmentRef[]
}) {
  return await responseHandle<AccidentCase>(
    () =>
      supabase.rpc('smis_transition_accident_case_secure', {
        p_accident_case_id: params.id,
        p_action: params.action,
        p_investigator_user_id: params.investigatorUserId || null,
        p_comment: params.comment || null,
        p_attachment_refs: params.attachmentRefs ?? []
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchAccidentCaseEventList(accidentCaseId: string) {
  return await responseHandle<Api.Smis.AccidentEmergency.AccidentCaseEventRecord[]>(
    () => supabase.rpc('smis_list_accident_case_events_secure', { p_case_id: accidentCaseId }),
    { showErrorMessage: true }
  )
}

export async function fetchVmsAccidentOptions(keyword = '') {
  return await responseHandle<Api.Smis.AccidentEmergency.VmsAccidentOption[]>(
    () =>
      supabase.rpc('vms_list_vehicle_accident_options_secure', {
        p_keyword: keyword.trim() || null,
        p_limit: 100
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchEmergencyPlanList() {
  const query = supabase.from('smis_emergency_plan').select(planSelect).order('plan_no')
  return await responseHandle<EmergencyPlan[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function saveEmergencyPlan(params: EmergencyPlan) {
  const payload = omit(params, ['id', 'createTime', 'updateTime', 'ownerUser'])
  const request = params.id
    ? supabase
        .from('smis_emergency_plan')
        .update(keysToSnakeDeep(payload))
        .eq('id', params.id)
        .select(planSelect)
        .single()
    : supabase
        .from('smis_emergency_plan')
        .insert(keysToSnakeDeep(payload))
        .select(planSelect)
        .single()
  return await responseHandle<EmergencyPlan>(() => request, {
    showMessage: true,
    message: params.id ? '应急预案已更新' : '应急预案已新增',
    breakReturn: true
  })
}

export async function deleteEmergencyPlan(id: string) {
  return await responseHandle(
    () => supabase.from('smis_emergency_plan').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, message: '应急预案已删除', breakReturn: true, requireAffected: true }
  )
}

export async function fetchEmergencyDrillList() {
  const query = supabase
    .from('smis_emergency_drill')
    .select(drillSelect)
    .order('scheduled_at', { ascending: false })
  return await responseHandle<EmergencyDrill[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function saveEmergencyDrill(params: EmergencyDrill) {
  const payload = omit(params, ['id', 'createTime', 'updateTime', 'plan', 'organizerUser'])
  const request = params.id
    ? supabase
        .from('smis_emergency_drill')
        .update(keysToSnakeDeep(payload))
        .eq('id', params.id)
        .select(drillSelect)
        .single()
    : supabase
        .from('smis_emergency_drill')
        .insert(keysToSnakeDeep(payload))
        .select(drillSelect)
        .single()
  return await responseHandle<EmergencyDrill>(() => request, {
    showMessage: true,
    message: params.id ? '应急演练已更新' : '应急演练已新增',
    breakReturn: true
  })
}

export async function deleteEmergencyDrill(id: string) {
  return await responseHandle(
    () => supabase.from('smis_emergency_drill').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, message: '应急演练已删除', breakReturn: true, requireAffected: true }
  )
}
