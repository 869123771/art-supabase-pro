type WaybillRecord = Api.Tms.Waybill.WaybillRecord

export const DISPATCH_VEHICLE_SELECT = `
  id,
  carrier_id,
  plate_no,
  company_name,
  vin,
  self_no,
  vehicle_type,
  primary_driver_id,
  tonnage_or_seat,
  overall_length,
  primaryDriver:tms_driver!vehicle_archive_primary_driver_id_fkey(
    id,
    carrier_id,
    driver_name
  )
`

const toNullableNumberValue = (value?: number | string | null): number | null => {
  if (value === null || value === undefined || value === '') return null
  const numberValue = Number(value)
  return Number.isFinite(numberValue) ? numberValue : null
}

const createWaybillRoutePoints = (order: WaybillRecord) => {
  const shipperLongitude = toNullableNumberValue(order.shippingLongitude)
  const shipperLatitude = toNullableNumberValue(order.shippingLatitude)
  const receiverLongitude = toNullableNumberValue(order.receivingLongitude)
  const receiverLatitude = toNullableNumberValue(order.receivingLatitude)
  const points: Array<Record<string, unknown>> = []

  if (shipperLongitude !== null && shipperLatitude !== null) {
    points.push({
      type: 'shipper',
      name: order.shippingContactName,
      address: order.shippingAddressDetail,
      longitude: shipperLongitude,
      latitude: shipperLatitude,
      lng: shipperLongitude,
      lat: shipperLatitude
    })
  }

  if (receiverLongitude !== null && receiverLatitude !== null) {
    points.push({
      type: 'receiver',
      name: order.receivingContactName,
      address: order.receivingAddressDetail,
      longitude: receiverLongitude,
      latitude: receiverLatitude,
      lng: receiverLongitude,
      lat: receiverLatitude
    })
  }

  return points
}

export const createDriverWaybillPayload = (order: WaybillRecord) => {
  const firstCargo = order.cargoItems?.find((item) => item.cargoName)
  const cargoWeightKg = toNullableNumberValue(order.cargoWeightTotal)
  const cargoQuantity = toNullableNumberValue(order.cargoQuantityTotal)

  return {
    orderId: order.id || null,
    tenantId: order.tenantId,
    waybillNo: order.orderNo,
    status: 'pending',
    driverId: order.dispatchDriverId || null,
    vehicleId: order.dispatchVehicleId || null,
    shipperAddressId: order.shippingAddressId || null,
    receiverAddressId: order.receivingAddressId || null,
    originCity: order.originStation,
    destinationCity: order.destinationStation,
    shipperName: order.shippingContactName || null,
    shipperPhone: order.shippingContactPhone || null,
    shipperAddress: order.shippingAddressDetail,
    shipperLongitude: toNullableNumberValue(order.shippingLongitude),
    shipperLatitude: toNullableNumberValue(order.shippingLatitude),
    receiverName: order.receivingContactName || null,
    receiverPhone: order.receivingContactPhone || null,
    receiverAddress: order.receivingAddressDetail,
    receiverLongitude: toNullableNumberValue(order.receivingLongitude),
    receiverLatitude: toNullableNumberValue(order.receivingLatitude),
    plannedLoadTime: order.plannedDepartureTime || null,
    plannedUnloadTime: order.plannedArrivalTime || null,
    cargoName: firstCargo?.cargoName || order.cargoNo || order.orderNo,
    cargoWeightTon:
      cargoWeightKg === null ? null : Math.round((cargoWeightKg / 1000) * 1000) / 1000,
    cargoVolumeM3: toNullableNumberValue(order.cargoVolumeTotal),
    cargoQuantity: cargoQuantity === null ? null : String(cargoQuantity),
    freightAmount: toNullableNumberValue(order.totalFee) ?? 0,
    routePoints: createWaybillRoutePoints(order),
    remark: order.dispatchRemark || order.orderRemark || null
  }
}
