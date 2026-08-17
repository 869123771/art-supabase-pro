import type { OrderForm } from './order-open-model'
import { normalizeCargoItems, nullableNumber, nullableText } from './order-open-model'

export function buildAiOrderFinalPayload(order: OrderForm): Api.Tms.Order.AiOrderDraft {
  return {
    originStationName: nullableText(order.originStation),
    destinationStationName: nullableText(order.destinationStation),
    transferStationName: nullableText(order.transferStation),
    deliveryMethod: nullableText(order.deliveryMethod),
    shippingCustomerName: nullableText(order.shippingCustomerName),
    shippingContactName: nullableText(order.shippingContactName),
    shippingContactPhone: nullableText(order.shippingContactPhone),
    shippingAddressDetail: nullableText(order.shippingAddressDetail),
    receivingCustomerName: nullableText(order.receivingCustomerName),
    receivingContactName: nullableText(order.receivingContactName),
    receivingContactPhone: nullableText(order.receivingContactPhone),
    receivingAddressDetail: nullableText(order.receivingAddressDetail),
    cargoItems: normalizeCargoItems(order.cargoItems),
    transportFee: nullableNumber(order.transportFee),
    deliveryFee: nullableNumber(order.deliveryFee),
    unloadingFee: nullableNumber(order.unloadingFee),
    collectPaymentFee: nullableNumber(order.collectPaymentFee),
    transferFee: nullableNumber(order.transferFee),
    declaredValue: nullableNumber(order.declaredValue),
    insuranceFee: nullableNumber(order.insuranceFee),
    packageFee: nullableNumber(order.packageFee),
    otherFee: nullableNumber(order.otherFee),
    paymentMethod: nullableText(order.paymentMethod),
    cashAmount: nullableNumber(order.cashAmount),
    collectAmount: nullableNumber(order.collectAmount),
    monthlyAmount: nullableNumber(order.monthlyAmount),
    codAmount: nullableNumber(order.codAmount),
    handlingFee: nullableNumber(order.handlingFee),
    transportMode: nullableText(order.transportMode),
    orderRemark: nullableText(order.orderRemark)
  }
}
