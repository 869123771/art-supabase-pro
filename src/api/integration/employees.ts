import { useSupabase } from '@/hooks'

/** 跨应用可依赖的员工只读数据契约。 */
export interface EmployeeIntegrationItem {
  id: string
  tenantId: string
  organizationId?: string | null
  employeeNo: string
  employeeName: string
  avatarUrl?: string | null
  jobTitle?: string | null
  employmentStatus: string
  gender?: string | null
  phone?: string | null
  email?: string | null
  organization?: {
    id: string
    organizationCode: string
    organizationName: string
  } | null
}

export interface EmployeeSelectorContractParams {
  tenantId?: string
  keyword?: string
  from?: number
  to?: number
}

interface EmployeeSelectorContractPayload {
  records?: EmployeeIntegrationItem[]
  total?: number
  fieldAccess?: Record<string, boolean>
}

const { supabase, responseHandle } = useSupabase()

/**
 * 平台级员工只读契约。
 *
 * 调用方只依赖稳定 RPC/HTTP 形状，不引用 HR 的页面、provider 或业务类型。
 * 将来 HR 独立成服务时，只需替换本适配器。
 */
export async function fetchEmployeeSelectorList(params: EmployeeSelectorContractParams = {}) {
  const { tenantId, keyword, from = 0, to = 9 } = params
  const result = await responseHandle<EmployeeSelectorContractPayload>(
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
