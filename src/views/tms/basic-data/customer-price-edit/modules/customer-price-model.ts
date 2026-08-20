import { cloneDeep, omit } from 'lodash-es'
import {
  calculateCargoSummary,
  joinRegionPath,
  normalizeMoney,
  normalizeNullableNumber,
  normalizeRequiredText,
  normalizeText,
  roundNumber,
  toNumber
} from '../../modules/price-form-utils'

export type CustomerPrice = Api.Tms.BasicData.CustomerPrice
export type CustomerPriceCargoItem = Api.Tms.BasicData.CustomerPriceCargoItem

export type CustomerPriceForm = CustomerPrice & {
  customerCode?: string
  originRegionPath: string[]
  destinationRegionPath: string[]
}

const feeFields: Array<keyof CustomerPriceForm> = [
  'transportFee',
  'insuranceFee',
  'packageFee',
  'loadingFee',
  'transferFee',
  'fuelFee',
  'serviceFee',
  'otherFee'
]

const paymentFields: Array<keyof CustomerPriceForm> = [
  'cashAmount',
  'prepaidAmount',
  'collectAmount',
  'periodicAmount'
]

export function createInitialCustomerPriceCargoItem(): CustomerPriceCargoItem {
  return {
    cargoName: '',
    quantity: null,
    unit: '',
    volumeM3: null,
    weightKg: null
  }
}

export function createInitialCustomerPriceForm(): CustomerPriceForm {
  return {
    id: undefined,
    customerId: '',
    customerCode: '',
    originRegion: '',
    destinationRegion: '',
    originRegionPath: [],
    destinationRegionPath: [],
    transportType: '',
    cargoType: '',
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
    cargoItems: [createInitialCustomerPriceCargoItem()],
    cargoQuantityTotal: 0,
    cargoVolumeTotal: 0,
    cargoWeightTotal: 0,
    vehicleType: '',
    vehicleLength: '',
    vehicleCount: null,
    billingMethod: '',
    transportFee: 0,
    insuranceFee: 0,
    packageFee: 0,
    loadingFee: 0,
    transferFee: 0,
    fuelFee: 0,
    serviceFee: 0,
    otherFee: 0,
    totalFee: 0,
    cashAmount: 0,
    prepaidAmount: 0,
    collectAmount: 0,
    periodicAmount: 0,
    paymentTotal: 0,
    remark: ''
  }
}

export function normalizeCustomerPriceCargoItems(
  items: CustomerPriceCargoItem[] | undefined
): CustomerPriceCargoItem[] {
  return (items ?? [])
    .map((item) => ({
      cargoName: normalizeText(item.cargoName),
      quantity: normalizeNullableNumber(item.quantity),
      unit: normalizeText(item.unit),
      volumeM3: normalizeNullableNumber(item.volumeM3),
      weightKg: normalizeNullableNumber(item.weightKg)
    }))
    .filter(
      (item) => item.cargoName || item.quantity || item.unit || item.volumeM3 || item.weightKg
    )
}

function sumMoneyFields(form: CustomerPriceForm, fields: Array<keyof CustomerPriceForm>): number {
  return roundNumber(
    fields.reduce((total, field) => total + toNumber(form[field] as number), 0),
    2
  )
}

export function normalizeCustomerPricePayload(form: CustomerPriceForm): CustomerPrice {
  const raw = cloneDeep(form)
  const payload = omit(raw, [
    'tenantId',
    'customer',
    'customerCode',
    'originRegionPath',
    'destinationRegionPath',
    'createBy',
    'createTime',
    'updateBy',
    'updateTime',
    'fieldAccess',
    'isRecordOwner'
  ]) as CustomerPrice
  const cargoItems = normalizeCustomerPriceCargoItems(raw.cargoItems)
  const cargoSummary = calculateCargoSummary(cargoItems)

  Object.assign(payload, {
    originRegion: joinRegionPath(raw.originRegionPath),
    destinationRegion: joinRegionPath(raw.destinationRegionPath),
    cargoItems,
    cargoQuantityTotal: cargoSummary.quantity,
    cargoVolumeTotal: cargoSummary.volume,
    cargoWeightTotal: cargoSummary.weight,
    vehicleType: normalizeText(raw.vehicleType),
    vehicleLength: normalizeText(raw.vehicleLength),
    vehicleCount: normalizeNullableNumber(raw.vehicleCount),
    cargoType: normalizeText(raw.cargoType),
    remark: normalizeText(raw.remark),
    transportFee: normalizeMoney(raw.transportFee),
    insuranceFee: normalizeMoney(raw.insuranceFee),
    packageFee: normalizeMoney(raw.packageFee),
    loadingFee: normalizeMoney(raw.loadingFee),
    transferFee: normalizeMoney(raw.transferFee),
    fuelFee: normalizeMoney(raw.fuelFee),
    serviceFee: normalizeMoney(raw.serviceFee),
    otherFee: normalizeMoney(raw.otherFee),
    totalFee: sumMoneyFields(raw, feeFields),
    cashAmount: normalizeMoney(raw.cashAmount),
    prepaidAmount: normalizeMoney(raw.prepaidAmount),
    collectAmount: normalizeMoney(raw.collectAmount),
    periodicAmount: normalizeMoney(raw.periodicAmount),
    paymentTotal: sumMoneyFields(raw, paymentFields),
    shippingAddressId: normalizeText(raw.shippingAddressId),
    receivingAddressId: normalizeText(raw.receivingAddressId),
    shippingContactName: normalizeRequiredText(raw.shippingContactName),
    shippingContactPhone: normalizeRequiredText(raw.shippingContactPhone),
    shippingAddressDetail: normalizeRequiredText(raw.shippingAddressDetail),
    shippingLongitude: normalizeNullableNumber(raw.shippingLongitude),
    shippingLatitude: normalizeNullableNumber(raw.shippingLatitude),
    receivingContactName: normalizeRequiredText(raw.receivingContactName),
    receivingContactPhone: normalizeRequiredText(raw.receivingContactPhone),
    receivingAddressDetail: normalizeRequiredText(raw.receivingAddressDetail),
    receivingLongitude: normalizeNullableNumber(raw.receivingLongitude),
    receivingLatitude: normalizeNullableNumber(raw.receivingLatitude)
  })

  return payload
}
