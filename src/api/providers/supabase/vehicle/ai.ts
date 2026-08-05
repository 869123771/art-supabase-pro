import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'

const { supabase } = useSupabase()

export async function analyzeVehicleHealthByAi(
  vehicleId: string
): Promise<QueryResult<Api.VehicleMgtSys.VehicleManage.VehicleHealthAdvisorResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.VehicleMgtSys.VehicleManage.VehicleHealthAdvisorResponse>(
      'ai-vehicle-health-advisor',
      { body: { vehicleId } }
    )

  return {
    data: data ?? null,
    error: await normalizeFunctionInvokeError(error)
  }
}

async function normalizeFunctionInvokeError(error: unknown): Promise<unknown | null> {
  if (!error || typeof error !== 'object' || !('context' in error)) return error

  const context = (error as { context?: unknown }).context
  if (!(context instanceof Response)) return error

  try {
    const payload = (await context.clone().json()) as { code?: unknown; message?: unknown }
    if (typeof payload.message !== 'string' || !payload.message) return error
    return {
      code: typeof payload.code === 'string' ? payload.code : undefined,
      message: payload.message
    }
  } catch {
    return error
  }
}
