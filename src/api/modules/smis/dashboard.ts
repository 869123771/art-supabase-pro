import dayjs from 'dayjs'
import { useSupabase } from '@/hooks'
import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import type { QueryResult } from '@/types/api/response'

const { supabase, responseHandle, keysToCamelDeep } = useSupabase()

const riskPointSelect = `
  id, risk_point_no, risk_point_name, current_risk_level, map_geometry,
  site:smis_site!smis_risk_point_site_tenant_fkey(id, site_name),
  area:smis_area!smis_risk_point_area_tenant_fkey(id, area_name)
`
const dangerSelect = `
  *,
  risk_point:smis_risk_point!smis_hidden_danger_risk_point_tenant_fkey(
    id, risk_point_no, risk_point_name, current_risk_level
  )
`
interface OpenAccidentPayload {
  records?: Api.Smis.AccidentEmergency.AccidentCaseRecord[]
  total?: number
  fieldAccess?: Api.Smis.AccidentEmergency.AccidentCaseFieldAccessMap
}

function coordinateFromGeometry(
  geometry?: Record<string, unknown> | null
): [number, number] | null {
  if (!geometry) return null
  const direct = [geometry.longitude ?? geometry.lng, geometry.latitude ?? geometry.lat]
  const coordinates = Array.isArray(geometry.coordinates) ? geometry.coordinates : direct
  const longitude = Number(coordinates[0])
  const latitude = Number(coordinates[1])
  if (
    !Number.isFinite(longitude) ||
    !Number.isFinite(latitude) ||
    longitude < -180 ||
    longitude > 180 ||
    latitude < -90 ||
    latitude > 90
  ) {
    return null
  }
  return [longitude, latitude]
}

export async function fetchSmisSafetyDashboard() {
  const now = dayjs()
  const upcomingEnd = now.add(30, 'day').toISOString()
  const [riskPoints, dangers, tasks, accidents, plans, drills] = await Promise.all([
    supabase.from('smis_risk_point').select(riskPointSelect).eq('status', 'active').limit(2000),
    supabase
      .from('smis_hidden_danger')
      .select(dangerSelect)
      .not('status', 'in', '(closed,cancelled)')
      .order('reported_at', { ascending: false })
      .limit(2000),
    supabase
      .from('smis_inspection_task')
      .select('id,status,scheduled_end_at')
      .in('status', ['pending', 'in_progress'])
      .limit(2000),
    supabase.rpc('smis_list_open_accident_cases_secure', { p_limit: 1000 }),
    supabase.from('smis_emergency_plan').select('id,status').eq('status', 'active').limit(1000),
    supabase
      .from('smis_emergency_drill')
      .select('id,status,scheduled_at')
      .eq('status', 'planned')
      .gte('scheduled_at', now.toISOString())
      .lte('scheduled_at', upcomingEnd)
      .limit(1000)
  ])
  const error = [riskPoints, dangers, tasks, accidents, plans, drills].find(
    (result) => result.error
  )?.error
  if (error) {
    return await responseHandle<Api.Smis.Dashboard.SafetyDashboardData>(
      () => Promise.resolve({ data: null, error }),
      { showErrorMessage: true, breakReturn: true }
    )
  }

  const riskRows = keysToCamelDeep<
    Array<{
      id: string
      riskPointNo: string
      riskPointName: string
      currentRiskLevel?: Api.Smis.RiskControl.RiskLevel | null
      mapGeometry?: Record<string, unknown> | null
      site?: { siteName?: string | null } | null
      area?: { areaName?: string | null } | null
    }>
  >(riskPoints.data ?? [])
  const dangerRows = keysToCamelDeep<Api.Smis.InspectionControl.HiddenDangerRecord[]>(
    dangers.data ?? []
  )
  const accidentPayload = keysToCamelDeep<OpenAccidentPayload>(accidents.data ?? {})
  const accidentRows = accidentPayload.records ?? []
  const dangerByRiskPoint = new Map<string, { open: number; overdue: number }>()
  dangerRows.forEach((row) => {
    const value = dangerByRiskPoint.get(row.riskPointId) ?? { open: 0, overdue: 0 }
    value.open += 1
    if (row.rectificationDeadline && dayjs(row.rectificationDeadline).isBefore(now))
      value.overdue += 1
    dangerByRiskPoint.set(row.riskPointId, value)
  })
  const hotspots = riskRows
    .map((row) => {
      const danger = dangerByRiskPoint.get(row.id) ?? { open: 0, overdue: 0 }
      return {
        id: row.id,
        riskPointNo: row.riskPointNo,
        riskPointName: row.riskPointName,
        riskLevel: row.currentRiskLevel,
        siteName: row.site?.siteName,
        areaName: row.area?.areaName,
        openDangerCount: danger.open,
        overdueDangerCount: danger.overdue,
        mapGeometry: row.mapGeometry
      }
    })
    .sort(
      (left, right) =>
        right.overdueDangerCount * 10 +
        right.openDangerCount -
        (left.overdueDangerCount * 10 + left.openDangerCount)
    )
    .slice(0, 12)
  const levels: Api.Smis.RiskControl.RiskLevel[] = ['low', 'general', 'major', 'critical']
  const mapPoints: Api.Smis.Dashboard.SafetyMapPoint[] = []
  riskRows.forEach((row) => {
    const coordinate = coordinateFromGeometry(row.mapGeometry)
    if (!coordinate) return
    mapPoints.push({
      id: row.id,
      kind: 'risk_point',
      title: row.riskPointName,
      subtitle: [row.site?.siteName, row.area?.areaName].filter(Boolean).join(' · '),
      level: row.currentRiskLevel || 'general',
      longitude: coordinate[0],
      latitude: coordinate[1]
    })
  })
  accidentRows.forEach((row) => {
    if (row.longitude == null || row.latitude == null) return
    const longitude = Number(row.longitude)
    const latitude = Number(row.latitude)
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return
    mapPoints.push({
      id: row.id!,
      kind: 'accident',
      title: row.caseTitle,
      subtitle: row.location,
      level: row.severity === 'slight' ? 'low' : row.severity,
      longitude,
      latitude
    })
  })
  const data: Api.Smis.Dashboard.SafetyDashboardData = {
    riskPointTotal: riskRows.length,
    majorRiskPointCount: riskRows.filter((row) =>
      ['major', 'critical'].includes(row.currentRiskLevel || '')
    ).length,
    openDangerCount: dangerRows.length,
    overdueDangerCount: dangerRows.filter(
      (row) => row.rectificationDeadline && dayjs(row.rectificationDeadline).isBefore(now)
    ).length,
    pendingInspectionCount: tasks.data?.length ?? 0,
    openAccidentCount: accidentPayload.total ?? accidentRows.length,
    activeEmergencyPlanCount: plans.data?.length ?? 0,
    upcomingDrillCount: drills.data?.length ?? 0,
    riskDistribution: levels.map((level) => ({
      level,
      count: riskRows.filter((row) => row.currentRiskLevel === level).length
    })),
    hotspots,
    mapPoints,
    recentDangers: dangerRows.slice(0, 6),
    recentAccidents: accidentRows.slice(0, 6)
  }
  return { data, error: null, total: 1 }
}

export async function analyzeSmisSafetyByAi(): Promise<
  QueryResult<Api.Smis.Dashboard.SafetyAdvisorResponse>
> {
  const { data, error } = await supabase.functions.invoke<Api.Smis.Dashboard.SafetyAdvisorResponse>(
    'ai-smis-safety-advisor',
    { body: {} }
  )
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
}
