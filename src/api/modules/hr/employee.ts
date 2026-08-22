import { useSupabase } from '@/hooks'
import TreeUtils from '@/utils/tree'

type Employee = Api.Hr.Employee
type EmployeeSearchParams = Api.Hr.EmployeeSearchParams
type EmployeeSelectorItem = Api.Hr.EmployeeSelectorItem
type EmployeeProfile = Api.Hr.EmployeeProfile
type EmployeeProfilePayload = Api.Hr.EmployeeProfilePayload
type OrganizationScopeFilterItem = Api.SystemManage.OrganizationScopeFilterItem

interface EmployeeListPayload {
  records?: Employee[]
  total?: number
  fieldAccess?: Api.Hr.EmployeeFieldAccessMap
}

interface EmployeeSelectorListPayload {
  records?: EmployeeSelectorItem[]
  total?: number
  fieldAccess?: Api.Hr.EmployeeFieldAccessMap
}

const organizationTreeUtils = new TreeUtils({
  idKey: 'id',
  parentKey: 'parentId',
  childrenKey: 'children'
})

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const normalizeEmployeeProfile = (profile: EmployeeProfile): EmployeeProfile => ({
  ...profile,
  contracts: Array.isArray(profile.contracts) ? profile.contracts : [],
  educations: Array.isArray(profile.educations) ? profile.educations : [],
  workExperiences: Array.isArray(profile.workExperiences) ? profile.workExperiences : [],
  trainings: Array.isArray(profile.trainings) ? profile.trainings : [],
  rewards: Array.isArray(profile.rewards) ? profile.rewards : []
})

export async function fetchEmployeeList(params: EmployeeSearchParams) {
  const { from = 0, to = 9 } = params
  const result = await responseHandle<EmployeeListPayload>(
    () =>
      supabase.rpc('hr_list_employees_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_tenant_id: params.tenantId || null,
        p_organization_ids: params.organizationIds?.length ? params.organizationIds : null,
        p_organization_unassigned: Boolean(params.organizationUnassigned),
        p_employment_status: params.employmentStatus || null,
        p_employment_type: params.employmentType || null,
        p_keyword: params.keyword?.trim() || null,
        p_hire_start: params.hireDateRange?.[0] || null,
        p_hire_end: params.hireDateRange?.[1] || null,
        p_record_id: params.recordId || null
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

export async function fetchEmployeeSelectorList(
  params: Pick<EmployeeSearchParams, 'tenantId' | 'keyword' | 'from' | 'to'>
) {
  const { tenantId, keyword, from = 0, to = 9 } = params
  const result = await responseHandle<EmployeeSelectorListPayload>(
    () =>
      supabase.rpc('hr_list_employee_selector_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_tenant_id: tenantId || null,
        p_keyword: keyword?.trim() || null
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

export async function deleteEmployee(id: string) {
  return await responseHandle<void>(
    () => supabase.rpc('hr_delete_employee_secure', { p_employee_id: id }),
    {
      showMessage: true,
      message: '员工档案已删除',
      breakReturn: true
    }
  )
}

export async function fetchEmployeeOrganizationTree(params: { tenantId?: string } = {}) {
  if (!params.tenantId) return { data: [], error: null }

  const response = await responseHandle<OrganizationScopeFilterItem[]>(
    () =>
      supabase.rpc('hr_list_employee_organization_scope_secure', {
        p_tenant_id: params.tenantId
      }),
    { showErrorMessage: true }
  )

  return {
    ...response,
    data: organizationTreeUtils.listToTree(response.data ?? [], (a, b) => {
      const sortDiff = (a.sort ?? 0) - (b.sort ?? 0)
      return sortDiff || a.organizationName.localeCompare(b.organizationName, 'zh-CN')
    })
  }
}

export async function fetchEmployeeProfile(employeeId: string): Promise<EmployeeProfile | null> {
  const response = await responseHandle<EmployeeProfile>(
    () => supabase.rpc('hr_get_employee_profile_secure', { p_employee_id: employeeId }),
    { breakReturn: true, showErrorMessage: true }
  )
  return response.data ? normalizeEmployeeProfile(response.data) : null
}

export async function saveEmployeeProfile(payload: EmployeeProfilePayload): Promise<string> {
  const response = await responseHandle<string>(
    () =>
      supabase.rpc('hr_save_employee_profile_secure', {
        p_payload: keysToSnakeDeep(payload)
      }),
    {
      breakReturn: true,
      showMessage: false
    }
  )
  if (!response.data) throw new Error('保存员工档案后未返回员工 ID')
  return response.data
}
