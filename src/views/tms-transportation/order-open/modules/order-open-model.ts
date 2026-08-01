import dayjs from 'dayjs'
import { isNil, round, toNumber, trim } from 'lodash-es'

export type OrderRecord = Api.Tms.Order.OrderRecord
export type CargoItem = Api.Tms.Order.CargoItem

export type OrderForm = OrderRecord & {
  imageUrls: string[]
  shippingCustomerName: string
  receivingCustomerName: string
}

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

export function createOrderNo(): string {
  return `NGSJ${dayjs().format('MMDD')}-${Math.floor(100 + Math.random() * 900)}`
}

export function createCargoNo(): string {
  return `A${dayjs().format('M-D')}-${Math.floor(10 + Math.random() * 90)}`
}

export function createInitialForm(): OrderForm {
  return {
    orderNo: createOrderNo(),
    cargoNo: createCargoNo(),
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

export function getDictLabel(
  options: Api.DataCenter.DictListItem[],
  value?: string | null
): string {
  if (!value) return ''
  return options.find((item) => item.value === value)?.label || value
}
