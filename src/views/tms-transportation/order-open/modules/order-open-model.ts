import { cloneDeep, isNil, omit, round, toNumber, trim } from 'lodash-es'

export type OrderRecord = Api.Tms.Order.OrderRecord
export type CargoItem = Api.Tms.Order.CargoItem

export type OrderForm = OrderRecord & {
  imageUrls: string[]
  shippingCustomerName: string
  receivingCustomerName: string
}

export interface OrderCargoSummary {
  quantity: number
  weight: number
  volume: number
}

interface NormalizeOrderPayloadOptions {
  form: OrderForm
  stationNames: {
    origin?: string
    destination?: string
    transfer?: string
  }
}

const feeFields: Array<keyof OrderForm> = [
  'transportFee',
  'deliveryFee',
  'unloadingFee',
  'collectPaymentFee',
  'transferFee',
  'insuranceFee',
  'packageFee',
  'otherFee'
]

const paymentFields: Array<keyof OrderForm> = [
  'cashAmount',
  'collectAmount',
  'monthlyAmount',
  'codAmount',
  'handlingFee'
]

export function createInitialCargoItem(): CargoItem {
  return {
    cargoName: '',
    packageType: '',
    quantity: null,
    unit: '',
    weightKg: null,
    volumeM3: null
  }
}

export function createInitialForm(): OrderForm {
  return {
    orderNo: '',
    cargoNo: '',
    orderStatus: 'pending_load',
    originStationId: null,
    destinationStationId: null,
    transferStationId: null,
    originStation: '',
    destinationStation: '',
    transferStation: '',
    deliveryMethod: 'door',
    shippingCustomerId: null,
    receivingCustomerId: null,
    shippingCustomerName: '',
    receivingCustomerName: '',
    shippingAddressId: null,
    receivingAddressId: null,
    shippingContactName: '',
    shippingContactPhone: '',
    shippingAddressDetail: '',
    shippingLongitude: null,
    shippingLatitude: null,
    receivingContactName: '',
    receivingContactPhone: '',
    receivingAddressDetail: '',
    receivingLongitude: null,
    receivingLatitude: null,
    cargoItems: [createInitialCargoItem()],
    cargoQuantityTotal: 0,
    cargoWeightTotal: 0,
    cargoVolumeTotal: 0,
    transportFee: 0,
    deliveryFee: 0,
    unloadingFee: 0,
    collectPaymentFee: 0,
    transferFee: 0,
    declaredValue: 0,
    insuranceFee: 0,
    packageFee: 0,
    otherFee: 0,
    totalFee: 0,
    paymentMethod: 'collect',
    cashAmount: 0,
    collectAmount: 0,
    monthlyAmount: 0,
    codAmount: 0,
    handlingFee: 0,
    paymentTotal: 0,
    transportMode: 'road',
    orderRemark: '',
    imageUrls: []
  }
}

export function numericValue(value?: number | string | null): number {
  const parsed = toNumber(value ?? 0)
  return Number.isFinite(parsed) ? parsed : 0
}

export function formatNumber(value?: number | string | null, precision = 2): string {
  return numericValue(value)
    .toFixed(precision)
    .replace(/\.0+$/, '')
    .replace(/(\.\d*?)0+$/, '$1')
}

export function textValue(value?: string | null): string {
  return trim(String(value ?? ''))
}

export function nullableText(value?: string | null): string | null {
  const text = textValue(value)
  return text || null
}

export function nullableNumber(value?: number | string | null): number | null {
  if (isNil(value) || value === '') return null
  const parsed = toNumber(value)
  return Number.isFinite(parsed) ? parsed : null
}

export function moneyValue(value?: number | string | null): number {
  return round(nullableNumber(value) ?? 0, 2)
}

export function normalizeCargoItems(items?: CargoItem[]): CargoItem[] {
  return (items ?? [])
    .map((item) => ({
      cargoName: textValue(item.cargoName),
      packageType: textValue(item.packageType),
      quantity: nullableNumber(item.quantity),
      unit: textValue(item.unit),
      weightKg: nullableNumber(item.weightKg),
      volumeM3: nullableNumber(item.volumeM3)
    }))
    .filter(
      (item) =>
        item.cargoName || item.packageType || item.quantity || item.weightKg || item.volumeM3
    )
}

export function calculateOrderCargoSummary(items?: CargoItem[]): OrderCargoSummary {
  return {
    quantity: round(
      (items ?? []).reduce((sum, item) => sum + numericValue(item.quantity), 0),
      0
    ),
    weight: round(
      (items ?? []).reduce((sum, item) => sum + numericValue(item.weightKg), 0),
      2
    ),
    volume: round(
      (items ?? []).reduce((sum, item) => sum + numericValue(item.volumeM3), 0),
      3
    )
  }
}

function sumOrderFields(form: OrderForm, fields: Array<keyof OrderForm>): number {
  return round(
    fields.reduce((sum, field) => sum + numericValue(form[field] as number), 0),
    2
  )
}

export function normalizeOrderPayload({
  form,
  stationNames
}: NormalizeOrderPayloadOptions): OrderRecord {
  const raw = cloneDeep(form)
  const payload = omit(raw, [
    'tenantId',
    'shippingCustomer',
    'receivingCustomer',
    'shippingCustomerName',
    'receivingCustomerName',
    'originStationRef',
    'destinationStationRef',
    'transferStationRef',
    'createBy',
    'createTime',
    'updateBy',
    'updateTime'
  ]) as OrderRecord
  const cargoItems = normalizeCargoItems(raw.cargoItems)
  const cargoSummary = calculateOrderCargoSummary(cargoItems)

  Object.assign(payload, {
    cargoItems,
    cargoQuantityTotal: cargoSummary.quantity,
    cargoWeightTotal: cargoSummary.weight,
    cargoVolumeTotal: cargoSummary.volume,
    transportFee: moneyValue(raw.transportFee),
    deliveryFee: moneyValue(raw.deliveryFee),
    unloadingFee: moneyValue(raw.unloadingFee),
    collectPaymentFee: moneyValue(raw.collectPaymentFee),
    transferFee: moneyValue(raw.transferFee),
    declaredValue: moneyValue(raw.declaredValue),
    insuranceFee: moneyValue(raw.insuranceFee),
    packageFee: moneyValue(raw.packageFee),
    otherFee: moneyValue(raw.otherFee),
    totalFee: sumOrderFields(raw, feeFields),
    cashAmount: moneyValue(raw.cashAmount),
    collectAmount: moneyValue(raw.collectAmount),
    monthlyAmount: moneyValue(raw.monthlyAmount),
    codAmount: moneyValue(raw.codAmount),
    handlingFee: moneyValue(raw.handlingFee),
    paymentTotal: sumOrderFields(raw, paymentFields),
    originStationId: nullableText(raw.originStationId),
    destinationStationId: nullableText(raw.destinationStationId),
    transferStationId: nullableText(raw.transferStationId),
    shippingAddressId: nullableText(raw.shippingAddressId),
    receivingAddressId: nullableText(raw.receivingAddressId),
    shippingLongitude: nullableNumber(raw.shippingLongitude),
    shippingLatitude: nullableNumber(raw.shippingLatitude),
    receivingLongitude: nullableNumber(raw.receivingLongitude),
    receivingLatitude: nullableNumber(raw.receivingLatitude),
    originStation: stationNames.origin || textValue(raw.originStation),
    destinationStation: stationNames.destination || textValue(raw.destinationStation),
    transferStation: stationNames.transfer || nullableText(raw.transferStation),
    transportMode: textValue(raw.transportMode),
    orderRemark: textValue(raw.orderRemark),
    orderNo: textValue(raw.orderNo),
    cargoNo: textValue(raw.cargoNo),
    imageUrls: raw.imageUrls ?? []
  })

  return payload
}

export function getDictLabel(
  options: Api.DataCenter.DictListItem[],
  value?: string | null
): string {
  if (!value) return ''
  return options.find((item) => item.value === value)?.label || value
}
