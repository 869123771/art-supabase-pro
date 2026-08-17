import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'

const { supabase } = useSupabase()

export async function analyzeVehicleHealthByAi(
  vehicleId: string
): Promise<QueryResult<Api.Vms.VehicleManage.VehicleHealthAdvisorResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Vms.VehicleManage.VehicleHealthAdvisorResponse>(
      'ai-vehicle-health-advisor',
      { body: { vehicleId } }
    )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}
