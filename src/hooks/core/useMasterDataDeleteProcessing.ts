export interface MasterDataDeleteProcessingContext {
  active: boolean
  addressId: string
  carrierId: string
  cargoId: string
  customerId: string
  customerName: string
  driverId: string
  recordId: string
  recordNo: string
  vehicleId: string
}

const toQueryText = (value: unknown): string => (typeof value === 'string' ? value : '')

export function useMasterDataDeleteProcessingContext() {
  const route = useRoute()

  return computed<MasterDataDeleteProcessingContext>(() => ({
    active: route.query.fromCustomerDelete === '1' || route.query.fromMasterDelete === '1',
    addressId: toQueryText(route.query.addressId),
    carrierId: toQueryText(route.query.carrierId),
    cargoId: toQueryText(route.query.cargoId),
    customerId: toQueryText(route.query.customerId),
    customerName: toQueryText(route.query.customerName),
    driverId: toQueryText(route.query.driverId),
    recordId: toQueryText(route.query.recordId),
    recordNo: toQueryText(route.query.recordNo),
    vehicleId: toQueryText(route.query.vehicleId)
  }))
}
