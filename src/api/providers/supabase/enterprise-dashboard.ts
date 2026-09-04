import dayjs from 'dayjs'
import { useSupabase } from '@/hooks'
import { fetchDashboardData, type DashboardData } from './dashboard'
import type { SupabaseQueryLike } from './query'

const { supabase, responseHandle } = useSupabase()

export interface EnterpriseFleetSummary {
  total: number
  operating: number
  pendingAudit: number
  dueDocuments: number
}

export interface EnterpriseFinanceSummary {
  voucherCount: number
  postedAmount: number
  cashInflow: number
  cashOutflow: number
  receivable: number
  payable: number
  approvedWaybillCost: number
}

export interface EnterpriseWorkforceSummary {
  total: number
  active: number
  probation: number
  expiringContracts: number
}

export interface EnterpriseSafetySummary {
  openHazards: number
  overdueHazards: number
  overdueInspections: number
  recentAccidents: number
  equipmentTotal: number
  equipmentNormal: number
  criticalEquipment: number
}

export interface EnterpriseDashboardSummary {
  generatedAt: string
  fleet: EnterpriseFleetSummary
  finance: EnterpriseFinanceSummary
  workforce: EnterpriseWorkforceSummary
  safety: EnterpriseSafetySummary
}

export interface EnterpriseDashboardData extends EnterpriseDashboardSummary {
  transport: DashboardData
}

function asDashboardQuery(query: unknown): SupabaseQueryLike {
  return query as SupabaseQueryLike
}

export async function fetchEnterpriseDashboardData(): Promise<EnterpriseDashboardData> {
  const [transport, enterpriseResult] = await Promise.all([
    fetchDashboardData('month'),
    responseHandle<EnterpriseDashboardSummary>(
      () =>
        asDashboardQuery(
          supabase.rpc('get_enterprise_dashboard', {
            p_reference_date: dayjs().format('YYYY-MM-DD')
          })
        ),
      {
        breakReturn: true,
        errorMessage: '企业经营大屏加载失败，请稍后重试'
      }
    )
  ])

  if (!enterpriseResult.data) throw new Error('企业经营大屏未返回可用数据')

  return {
    ...enterpriseResult.data,
    transport
  }
}
