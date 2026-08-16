import { omit } from 'lodash-es'
import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import TreeUtils from '@/utils/tree'

type Employee = Api.Hr.Employee
type EmployeeSearchParams = Api.Hr.EmployeeSearchParams
type EmployeeSelectorItem = Api.Hr.EmployeeSelectorItem
type EmployeeProfile = Api.Hr.EmployeeProfile
type EmployeeProfilePayload = Api.Hr.EmployeeProfilePayload
type OrganizationScopeFilterItem = Api.SystemManage.OrganizationScopeFilterItem

const organizationTreeUtils = new TreeUtils({
  idKey: 'id',
  parentKey: 'parentId',
  childrenKey: 'children'
})

interface EmployeeRecord extends Omit<Employee, 'account'> {
  account?: Api.Hr.EmployeeAccount | Api.Hr.EmployeeAccount[] | null
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const EMPLOYEE_SELECT = `
  *,
  tenant:sys_tenant!hr_employee_tenant_fkey(id, tenant_code, tenant_name),
  organization:sys_organization!hr_employee_organization_fkey(
    id,
    organization_code,
    organization_name
  ),
  account:sys_user!sys_user_hr_employee_tenant_fkey(id, user_email, status)
`

const normalizeEmployeeRecord = (record: EmployeeRecord): Employee => ({
  ...record,
  account: Array.isArray(record.account) ? (record.account[0] ?? null) : (record.account ?? null)
})

const normalizeEmployeeRecords = (records: EmployeeRecord[] | null): Employee[] | null =>
  records?.map(normalizeEmployeeRecord) ?? null

const applyEmployeeFilters = <
  TQuery extends {
    eq: (column: string, value: unknown) => TQuery
    gte: (column: string, value: unknown) => TQuery
    lte: (column: string, value: unknown) => TQuery
    in: (column: string, values: readonly unknown[]) => TQuery
    is: (column: string, value: null | boolean) => TQuery
    or: (filters: string) => TQuery
  }
>(
  query: TQuery,
  params: EmployeeSearchParams
): TQuery => {
  const {
    tenantId,
    organizationId,
    organizationIds,
    organizationUnassigned,
    employmentStatus,
    employmentType,
    keyword,
    hireDateRange,
    recordId
  } = params

  if (recordId) query = query.eq('id', recordId)
  if (tenantId) query = query.eq('tenant_id', tenantId)
  if (organizationUnassigned) query = query.is('organization_id', null)
  else if (organizationIds?.length) query = query.in('organization_id', organizationIds)
  else if (organizationId) query = query.eq('organization_id', organizationId)
  if (employmentStatus) query = query.eq('employment_status', employmentStatus)
  if (employmentType) query = query.eq('employment_type', employmentType)
  if (hireDateRange?.[0]) query = query.gte('hire_date', hireDateRange[0])
  if (hireDateRange?.[1]) query = query.lte('hire_date', hireDateRange[1])

  const trimmedKeyword = keyword?.trim()
  if (trimmedKeyword) {
    query = query.or(
      `employee_no.ilike.%${trimmedKeyword}%,employee_name.ilike.%${trimmedKeyword}%,phone.ilike.%${trimmedKeyword}%,email.ilike.%${trimmedKeyword}%,id_card_no.ilike.%${trimmedKeyword}%,job_title.ilike.%${trimmedKeyword}%`
    )
  }

  return query
}

export async function fetchEmployeeList(params: EmployeeSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('hr_employee')
    .select(EMPLOYEE_SELECT, { count: 'exact' })
    .order('employment_status', { ascending: true })
    .order('hire_date', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyEmployeeFilters(query, params)
  const result = await responseHandle<EmployeeRecord[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })

  return { ...result, data: normalizeEmployeeRecords(result.data) }
}

export async function fetchEmployeeSelectorList(
  params: Pick<EmployeeSearchParams, 'tenantId' | 'keyword' | 'from' | 'to'>,
  options?: ApiRequestOptions
) {
  const { tenantId, keyword, from = 0, to = 9 } = params
  let query = supabase
    .from('hr_employee')
    .select(
      `
        id,
        tenant_id,
        organization_id,
        employee_no,
        employee_name,
        avatar_url,
        job_title,
        employment_status,
        gender,
        phone,
        email,
        organization:sys_organization!hr_employee_organization_fkey(
          id,
          organization_code,
          organization_name
        ),
        account:sys_user!sys_user_hr_employee_tenant_fkey()
      `,
      { count: 'exact' }
    )
    .in('employment_status', ['probation', 'active'])
    .is('account', null)
    .order('employee_name', { ascending: true })
    .range(from, to)

  if (tenantId) query = query.eq('tenant_id', tenantId)
  const trimmedKeyword = keyword?.trim()
  if (trimmedKeyword) {
    query = query.or(
      `employee_no.ilike.%${trimmedKeyword}%,employee_name.ilike.%${trimmedKeyword}%,phone.ilike.%${trimmedKeyword}%,email.ilike.%${trimmedKeyword}%,job_title.ilike.%${trimmedKeyword}%`
    )
  }

  return await responseHandle<EmployeeSelectorItem[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addEmployee(params: Employee) {
  const payload = omit(params, [
    'id',
    'tenant',
    'organization',
    'account',
    'createBy',
    'createTime',
    'updateBy',
    'updateTime'
  ])
  return await responseHandle<Pick<Employee, 'id'>>(
    () => supabase.from('hr_employee').insert(keysToSnakeDeep(payload)).select('id').single(),
    {
      showMessage: true,
      message: '员工档案已创建',
      breakReturn: true
    }
  )
}

export async function editEmployee(params: Employee) {
  const { id } = params
  if (!id) throw new Error('未找到需要编辑的员工档案')

  const payload = omit(params, [
    'id',
    'tenantId',
    'tenant',
    'organization',
    'account',
    'createBy',
    'createTime',
    'updateBy',
    'updateTime'
  ])
  return await responseHandle(
    () =>
      supabase
        .from('hr_employee')
        .update(keysToSnakeDeep(payload), { count: 'exact' })
        .eq('id', id),
    {
      showMessage: true,
      message: '员工档案已更新',
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: '员工档案不存在，或当前账号没有编辑权限'
    }
  )
}

export async function deleteEmployee(id: string) {
  return await responseHandle(
    () => supabase.from('hr_employee').delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      message: '员工档案已删除',
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: '员工档案不存在，或当前账号没有删除权限'
    }
  )
}

export async function fetchEmployeeOrganizationTree(params: { tenantId?: string } = {}) {
  if (!params.tenantId) return { data: [], error: null }

  const query = supabase
    .from('sys_organization')
    .select(
      `
        id, tenant_id, parent_id, organization_code, organization_name,
        organization_type, status, sort, is_system,
        employees:hr_employee!hr_employee_organization_fkey(id)
      `
    )
    .eq('tenant_id', params.tenantId)
    .eq('status', '1')
    .order('sort', { ascending: true })
    .order('organization_name', { ascending: true })

  const response = await responseHandle<
    Array<OrganizationScopeFilterItem & { employees?: Array<{ id: string }> }>
  >(() => query, { ignoreCheck: true, showErrorMessage: true })

  return {
    ...response,
    data: organizationTreeUtils.listToTree(
      (response.data ?? []).map(({ employees, ...organization }) => ({
        ...organization,
        scopeCount: employees?.length ?? 0
      })),
      (a, b) => {
        const sortDiff = (a.sort ?? 0) - (b.sort ?? 0)
        return sortDiff || a.organizationName.localeCompare(b.organizationName, 'zh-CN')
      }
    )
  }
}

const fetchEmployeeChildren = async <T>(
  table: string,
  employeeId: string,
  orderColumn: string
): Promise<T[]> => {
  const response = await responseHandle<T[]>(
    () =>
      supabase
        .from(table)
        .select('*')
        .eq('employee_id', employeeId)
        .order(orderColumn, { ascending: false, nullsFirst: false })
        .order('create_time', { ascending: false }),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return response.data ?? []
}

export async function fetchEmployeeProfile(employeeId: string): Promise<EmployeeProfile | null> {
  const employeeResponse = await fetchEmployeeList({ recordId: employeeId, from: 0, to: 0 })
  const employee = employeeResponse.data?.[0]
  if (!employee) return null

  const [contracts, educations, workExperiences, trainings, rewards] = await Promise.all([
    fetchEmployeeChildren<Api.Hr.EmployeeContract>(
      'hr_employee_contract',
      employeeId,
      'start_date'
    ),
    fetchEmployeeChildren<Api.Hr.EmployeeEducation>(
      'hr_employee_education',
      employeeId,
      'start_date'
    ),
    fetchEmployeeChildren<Api.Hr.EmployeeWorkExperience>(
      'hr_employee_work_experience',
      employeeId,
      'start_date'
    ),
    fetchEmployeeChildren<Api.Hr.EmployeeTraining>(
      'hr_employee_training',
      employeeId,
      'start_date'
    ),
    fetchEmployeeChildren<Api.Hr.EmployeeReward>('hr_employee_reward', employeeId, 'record_date')
  ])

  return { ...employee, contracts, educations, workExperiences, trainings, rewards }
}

const replaceEmployeeChildren = async <T extends object>(
  table: string,
  employeeId: string,
  tenantId: string | undefined,
  records: T[]
): Promise<void> => {
  await responseHandle(() => supabase.from(table).delete().eq('employee_id', employeeId), {
    breakReturn: true
  })
  if (!records.length) return

  const payload = records.map((record) => {
    const cleanRecord = omit(record, [
      'id',
      'tenantId',
      'employeeId',
      'employee',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ])
    return keysToSnakeDeep({
      ...cleanRecord,
      employeeId,
      ...(tenantId ? { tenantId } : {})
    })
  })
  await responseHandle(() => supabase.from(table).insert(payload), { breakReturn: true })
}

export async function saveEmployeeProfile(payload: EmployeeProfilePayload): Promise<string> {
  let employeeId = payload.employee.id
  if (employeeId) {
    await editEmployee(payload.employee)
  } else {
    const response = await addEmployee(payload.employee)
    employeeId = response.data?.id
  }
  if (!employeeId) throw new Error('保存员工基础档案后未返回员工 ID')

  await replaceEmployeeChildren(
    'hr_employee_contract',
    employeeId,
    payload.employee.tenantId,
    payload.contracts
  )
  await replaceEmployeeChildren(
    'hr_employee_education',
    employeeId,
    payload.employee.tenantId,
    payload.educations
  )
  await replaceEmployeeChildren(
    'hr_employee_work_experience',
    employeeId,
    payload.employee.tenantId,
    payload.workExperiences
  )
  await replaceEmployeeChildren(
    'hr_employee_training',
    employeeId,
    payload.employee.tenantId,
    payload.trainings
  )
  await replaceEmployeeChildren(
    'hr_employee_reward',
    employeeId,
    payload.employee.tenantId,
    payload.rewards
  )

  return employeeId
}
