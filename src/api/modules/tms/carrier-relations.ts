import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'

type Carrier = Api.Tms.BasicData.Carrier

interface CarrierRelationRow {
  carrierId?: string | null
}

const { supabase, responseHandle } = useSupabase()

const countCarrierRelations = (rows: CarrierRelationRow[]): Map<string, number> => {
  const counts = new Map<string, number>()
  rows.forEach(({ carrierId }) => {
    if (!carrierId) return
    counts.set(carrierId, (counts.get(carrierId) ?? 0) + 1)
  })
  return counts
}

/** Adds relation counts with two batched queries instead of two queries per carrier. */
export const attachCarrierRelationCounts = async (
  result: QueryResult<Carrier[]>
): Promise<QueryResult<Carrier[]>> => {
  const rows = result.data ?? []
  const carrierIds = rows.map((row) => String(row.id || '')).filter(Boolean)

  if (!carrierIds.length) return result

  const [driverResult, vehicleResult] = await Promise.all([
    responseHandle<CarrierRelationRow[]>(
      () => supabase.from('tms_driver').select('carrier_id').in('carrier_id', carrierIds),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<CarrierRelationRow[]>(
      () => supabase.from('vehicle_archive').select('carrier_id').in('carrier_id', carrierIds),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])

  const driverCountMap = countCarrierRelations(driverResult.data ?? [])
  const vehicleCountMap = countCarrierRelations(vehicleResult.data ?? [])

  return {
    ...result,
    data: rows.map((row) => ({
      ...row,
      driverCount: row.id ? (driverCountMap.get(row.id) ?? 0) : 0,
      vehicleCount: row.id ? (vehicleCountMap.get(row.id) ?? 0) : 0
    }))
  }
}
