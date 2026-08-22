import { omit } from 'lodash-es'
import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type WorkspaceEntity = Api.Hr.WorkspaceEntity
type WorkspaceRecord = Api.Hr.WorkspaceRecord
type WorkspaceSearchParams = Api.Hr.WorkspaceSearchParams

interface WorkspaceTransportConfig {
  table: string
  select: string
  searchColumns: string[]
  statusColumn?: string
  employeeColumn?: string
  orderColumn: string
}

const workspaceTransportConfigs: Record<WorkspaceEntity, WorkspaceTransportConfig> = {
  contract: {
    table: 'hr_employee_contract',
    select: '*',
    searchColumns: ['contract_no'],
    statusColumn: 'contract_status',
    employeeColumn: 'employee_id',
    orderColumn: 'end_date'
  },
  personnelChange: {
    table: 'hr_personnel_change',
    select: '*',
    searchColumns: ['change_no', 'reason'],
    statusColumn: 'status',
    employeeColumn: 'employee_id',
    orderColumn: 'create_time'
  },
  lifecycleCase: {
    table: 'hr_lifecycle_case',
    select: '*',
    searchColumns: ['case_no', 'remark'],
    statusColumn: 'status',
    employeeColumn: 'employee_id',
    orderColumn: 'create_time'
  },
  lifecycleTask: {
    table: 'hr_lifecycle_task',
    select:
      '*, lifecycle_case:hr_lifecycle_case!hr_lifecycle_task_case_fkey(id,case_no,case_type,employee_id)',
    searchColumns: ['task_name', 'completion_note'],
    statusColumn: 'status',
    orderColumn: 'sort'
  },
  qualification: {
    table: 'hr_employee_qualification',
    select: '*',
    searchColumns: ['qualification_name', 'certificate_no', 'issuer'],
    statusColumn: 'status',
    employeeColumn: 'employee_id',
    orderColumn: 'expiry_date'
  },
  headcount: {
    table: 'hr_position_headcount',
    select: '*',
    searchColumns: ['remark'],
    orderColumn: 'effective_from'
  },
  shift: {
    table: 'hr_shift',
    select: '*',
    searchColumns: ['shift_code', 'shift_name'],
    orderColumn: 'shift_code'
  },
  shiftAssignment: {
    table: 'hr_shift_assignment',
    select: '*, shift:hr_shift!hr_shift_assignment_shift_fkey(id,shift_code,shift_name)',
    searchColumns: ['remark'],
    statusColumn: 'assignment_status',
    employeeColumn: 'employee_id',
    orderColumn: 'work_date'
  },
  attendance: {
    table: 'hr_attendance_record',
    select: '*, shift:hr_shift!hr_attendance_record_shift_fkey(id,shift_code,shift_name)',
    searchColumns: ['remark'],
    statusColumn: 'attendance_status',
    employeeColumn: 'employee_id',
    orderColumn: 'work_date'
  },
  selfServiceRequest: {
    table: 'hr_self_service_request',
    select: '*',
    searchColumns: ['request_no', 'title', 'reason'],
    statusColumn: 'status',
    employeeColumn: 'employee_id',
    orderColumn: 'create_time'
  },
  performanceCycle: {
    table: 'hr_performance_cycle',
    select: '*',
    searchColumns: ['cycle_code', 'cycle_name'],
    statusColumn: 'status',
    orderColumn: 'start_date'
  },
  performanceReview: {
    table: 'hr_performance_review',
    select:
      '*, cycle:hr_performance_cycle!hr_performance_review_cycle_id_tenant_id_fkey(id,cycle_code,cycle_name)',
    searchColumns: ['employee_summary', 'reviewer_comment'],
    statusColumn: 'status',
    employeeColumn: 'employee_id',
    orderColumn: 'create_time'
  },
  performanceGoal: {
    table: 'hr_performance_goal',
    select:
      '*, review:hr_performance_review!hr_performance_goal_review_id_tenant_id_fkey(id,employee_id,cycle_id)',
    searchColumns: ['goal_name', 'target_description', 'actual_result'],
    orderColumn: 'create_time'
  },
  trainingPlan: {
    table: 'hr_training_plan',
    select: '*',
    searchColumns: ['plan_code', 'plan_name', 'provider_name'],
    statusColumn: 'status',
    orderColumn: 'start_date'
  },
  trainingEnrollment: {
    table: 'hr_training_enrollment',
    select:
      '*, plan:hr_training_plan!hr_training_enrollment_plan_id_tenant_id_fkey(id,plan_code,plan_name)',
    searchColumns: ['certificate_no', 'remark'],
    statusColumn: 'status',
    employeeColumn: 'employee_id',
    orderColumn: 'create_time'
  },
  competency: {
    table: 'hr_competency',
    select: '*',
    searchColumns: ['competency_code', 'competency_name', 'description'],
    orderColumn: 'competency_code'
  },
  positionCompetency: {
    table: 'hr_position_competency',
    select:
      '*, competency:hr_competency!hr_position_competency_competency_id_tenant_id_fkey(id,competency_code,competency_name)',
    searchColumns: [],
    orderColumn: 'create_time'
  },
  employeeCompetency: {
    table: 'hr_employee_competency',
    select:
      '*, competency:hr_competency!hr_employee_competency_competency_id_tenant_id_fkey(id,competency_code,competency_name)',
    searchColumns: ['evidence'],
    employeeColumn: 'employee_id',
    orderColumn: 'assessed_date'
  },
  recruitmentRequisition: {
    table: 'hr_recruitment_requisition',
    select: '*',
    searchColumns: ['requisition_no', 'reason', 'requirements'],
    statusColumn: 'status',
    orderColumn: 'create_time'
  },
  candidate: {
    table: 'hr_candidate',
    select:
      '*, requisition:hr_recruitment_requisition!hr_candidate_requisition_id_tenant_id_fkey(id,requisition_no,position_id)',
    searchColumns: ['candidate_name', 'phone', 'email'],
    statusColumn: 'stage',
    orderColumn: 'create_time'
  }
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

interface HeadcountReference {
  organizationId: string
  positionId: string
  occupiedCount: number
}

interface WorkspaceReferenceBundle {
  employees: Api.Hr.WorkspaceReference[]
  positions: Api.Hr.WorkspaceReference[]
  organizations: Api.Hr.WorkspaceReference[]
  headcounts: HeadcountReference[]
}

const addReferenceId = (ids: Set<string>, value?: string | null): void => {
  if (value) ids.add(value)
}

const enrichWorkspaceReferences = async (
  records: WorkspaceRecord[]
): Promise<WorkspaceRecord[]> => {
  if (!records.length) return records

  const employeeIds = new Set<string>()
  const positionIds = new Set<string>()
  const organizationIds = new Set<string>()
  const headcountScopes = new Map<string, { organization_id: string; position_id: string }>()

  records.forEach((record) => {
    addReferenceId(employeeIds, record.employeeId)
    addReferenceId(employeeIds, record.onboardEmployeeId)
    addReferenceId(positionIds, record.positionId)
    addReferenceId(positionIds, record.fromPositionId)
    addReferenceId(positionIds, record.toPositionId)
    addReferenceId(organizationIds, record.organizationId)
    addReferenceId(organizationIds, record.fromOrganizationId)
    addReferenceId(organizationIds, record.toOrganizationId)

    if (record.organizationId && record.positionId) {
      headcountScopes.set(`${record.organizationId}:${record.positionId}`, {
        organization_id: record.organizationId,
        position_id: record.positionId
      })
    }
  })

  if (!employeeIds.size && !positionIds.size && !organizationIds.size && !headcountScopes.size) {
    return records
  }

  const result = await responseHandle<WorkspaceReferenceBundle>(
    () =>
      supabase.rpc('hr_resolve_workspace_references_secure', {
        p_employee_ids: [...employeeIds],
        p_position_ids: [...positionIds],
        p_organization_ids: [...organizationIds],
        p_headcount_scopes: [...headcountScopes.values()]
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
  if (!result.data) return records

  const employees = new Map(result.data.employees.map((item) => [item.id, item]))
  const positions = new Map(result.data.positions.map((item) => [item.id, item]))
  const organizations = new Map(result.data.organizations.map((item) => [item.id, item]))
  const headcounts = new Map(
    result.data.headcounts.map((item) => [
      `${item.organizationId}:${item.positionId}`,
      item.occupiedCount
    ])
  )

  return records.map((record) => {
    const employeeId = record.employeeId ?? record.onboardEmployeeId
    const occupiedCount =
      record.organizationId && record.positionId
        ? headcounts.get(`${record.organizationId}:${record.positionId}`)
        : undefined

    return {
      ...record,
      employee: employeeId ? (employees.get(employeeId) ?? null) : record.employee,
      organization: record.organizationId
        ? (organizations.get(record.organizationId) ?? null)
        : record.organization,
      fromOrganization: record.fromOrganizationId
        ? (organizations.get(record.fromOrganizationId) ?? null)
        : record.fromOrganization,
      toOrganization: record.toOrganizationId
        ? (organizations.get(record.toOrganizationId) ?? null)
        : record.toOrganization,
      position: record.positionId ? (positions.get(record.positionId) ?? null) : record.position,
      fromPosition: record.fromPositionId
        ? (positions.get(record.fromPositionId) ?? null)
        : record.fromPosition,
      toPosition: record.toPositionId
        ? (positions.get(record.toPositionId) ?? null)
        : record.toPosition,
      occupiedCount: occupiedCount ?? record.occupiedCount,
      vacancyCount:
        occupiedCount === undefined || record.approvedCount === undefined
          ? record.vacancyCount
          : Math.max(record.approvedCount - occupiedCount, 0)
    }
  })
}

export async function fetchHrWorkspaceRecords(
  entity: WorkspaceEntity,
  params: WorkspaceSearchParams,
  options?: ApiRequestOptions
) {
  const config = workspaceTransportConfigs[entity]
  const from = Math.max(params.from ?? 0, 0)
  const to = Math.max(params.to ?? from + 19, from)
  let query = supabase
    .from(config.table)
    .select(config.select, { count: 'exact' })
    .range(from, to)
    .order(config.orderColumn, { ascending: false, nullsFirst: false })

  const keyword = params.keyword?.trim()
  if (keyword && config.searchColumns.length) {
    query = query.or(config.searchColumns.map((column) => `${column}.ilike.%${keyword}%`).join(','))
  }
  if (params.status && config.statusColumn) query = query.eq(config.statusColumn, params.status)
  if (params.employeeId && config.employeeColumn)
    query = query.eq(config.employeeColumn, params.employeeId)
  if (params.tenantId) query = query.eq('tenant_id', params.tenantId)

  const result = await responseHandle<WorkspaceRecord[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
  const data = result.error ? [] : await enrichWorkspaceReferences(result.data ?? [])
  return { data, total: result.total ?? 0, error: result.error }
}

export async function saveHrWorkspaceRecord(entity: WorkspaceEntity, record: WorkspaceRecord) {
  const config = workspaceTransportConfigs[entity]
  const id = record.id
  const payload = keysToSnakeDeep(omit(record, ['id']))
  return await responseHandle<WorkspaceRecord>(
    () => {
      const query = id
        ? supabase.from(config.table).update(payload).eq('id', id)
        : supabase.from(config.table).insert(payload)
      return query.select(config.select).single()
    },
    { showMessage: true, breakReturn: true, message: id ? '记录已更新' : '记录已创建' }
  )
}

export async function deleteHrWorkspaceRecord(entity: WorkspaceEntity, id: string) {
  const config = workspaceTransportConfigs[entity]
  return await responseHandle<void>(() => supabase.from(config.table).delete().eq('id', id), {
    showMessage: true,
    breakReturn: true,
    message: '记录已删除'
  })
}

export async function submitHrApproval(businessType: string, businessId: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('hr_submit_approval', {
        p_business_type: businessType,
        p_business_id: businessId
      }),
    { showMessage: true, breakReturn: true, message: '已提交审批' }
  )
}

export async function effectPersonnelChange(changeId: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('hr_effect_personnel_change', { p_change_id: changeId }),
    { showMessage: true, breakReturn: true, message: '人事异动已生效' }
  )
}

export async function effectRecruitmentRequisition(requisitionId: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('hr_effect_recruitment_requisition', { p_requisition_id: requisitionId }),
    { showMessage: true, breakReturn: true, message: '招聘需求已启动' }
  )
}

export async function completeLifecycleTask(
  taskId: string,
  params: { completionNote?: string; skip?: boolean } = {}
) {
  return await responseHandle<boolean>(
    () =>
      supabase.rpc('hr_complete_lifecycle_task', {
        p_task_id: taskId,
        p_completion_note: params.completionNote?.trim() || null,
        p_skip: params.skip ?? false
      }),
    { showMessage: true, breakReturn: true, message: params.skip ? '任务已跳过' : '任务已完成' }
  )
}
