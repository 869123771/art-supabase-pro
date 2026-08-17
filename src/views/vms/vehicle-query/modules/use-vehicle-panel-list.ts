import type { Ref } from 'vue'
import type { VehicleArchive } from './types'

export const useVehiclePanelList = <TRecord>(
  vehicle: Ref<VehicleArchive>,
  fetcher: (vehicle: VehicleArchive) => Promise<TRecord[]>
) => {
  const loading = ref(false)
  const records = ref<TRecord[]>([]) as Ref<TRecord[]>

  const loadRecords = async (): Promise<void> => {
    if (!vehicle.value.plateNo) {
      records.value = []
      return
    }

    loading.value = true
    try {
      records.value = await fetcher(vehicle.value)
    } finally {
      loading.value = false
    }
  }

  watch(
    () => vehicle.value.plateNo,
    () => void loadRecords(),
    { immediate: true }
  )

  return {
    loading,
    records,
    loadRecords
  }
}
