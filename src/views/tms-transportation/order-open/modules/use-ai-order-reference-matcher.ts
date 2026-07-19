import { trim } from 'lodash-es'
import {
  fetchCargoList,
  fetchCustomerAddressList,
  fetchCustomerSelectorList,
  fetchStationOptions
} from '@/api/tms'
import type {
  AiCargoReferenceMatch,
  AiOrderReferenceMatches,
  AiReferenceMatch
} from './ai-order-types'

type StationOption = Api.Tms.Order.StationOption
type CustomerItem = Api.Tms.Order.CustomerSelectorItem
type CustomerAddress = Api.Tms.BasicData.CustomerAddress
type Cargo = Api.Tms.BasicData.Cargo

export function useAiOrderReferenceMatcher() {
  async function resolveReferences(
    draft: Api.Tms.Order.AiOrderDraft
  ): Promise<AiOrderReferenceMatches> {
    const [
      originStations,
      destinationStations,
      transferStations,
      shippingCustomers,
      receivingCustomers,
      cargoItems
    ] = await Promise.all([
      fetchStationMatches(draft.originStationName, 'shipping'),
      fetchStationMatches(draft.destinationStationName, 'arrival'),
      fetchStationMatches(draft.transferStationName, 'transfer'),
      fetchCustomerMatches(draft.shippingCustomerName),
      fetchCustomerMatches(draft.receivingCustomerName),
      Promise.all(
        (draft.cargoItems ?? []).map((item, index) => fetchCargoMatch(item.cargoName, index))
      )
    ])

    const shippingCustomer = createMatch(
      draft.shippingCustomerName,
      shippingCustomers,
      (item) => item.customerName
    )
    const receivingCustomer = createMatch(
      draft.receivingCustomerName,
      receivingCustomers,
      (item) => item.customerName
    )
    const [shippingAddress, receivingAddress] = await Promise.all([
      fetchAddressMatch(shippingCustomer.id, draft.shippingAddressDetail, 'shipping'),
      fetchAddressMatch(receivingCustomer.id, draft.receivingAddressDetail, 'receiving')
    ])

    return {
      originStation: createMatch(
        draft.originStationName,
        originStations,
        (item) => item.stationName
      ),
      destinationStation: createMatch(
        draft.destinationStationName,
        destinationStations,
        (item) => item.stationName
      ),
      transferStation: createMatch(
        draft.transferStationName,
        transferStations,
        (item) => item.stationName
      ),
      shippingCustomer,
      receivingCustomer,
      shippingAddress,
      receivingAddress,
      cargoItems
    }
  }

  async function fetchStationMatches(
    name: string | null | undefined,
    stationType: string
  ): Promise<StationOption[]> {
    if (!trim(String(name ?? ''))) return []
    const { data } = await fetchStationOptions({ keyword: String(name), stationType })
    return data ?? []
  }

  async function fetchCustomerMatches(name?: string | null): Promise<CustomerItem[]> {
    if (!trim(String(name ?? ''))) return []
    const { data } = await fetchCustomerSelectorList({ keyword: String(name), from: 0, to: 9 })
    return data ?? []
  }

  async function fetchAddressMatch(
    customerId: string | undefined,
    address: string | null | undefined,
    addressType: Api.Tms.BasicData.CustomerAddressType
  ): Promise<AiReferenceMatch> {
    const source = trim(String(address ?? ''))
    if (!source) return { status: 'empty' }
    if (!customerId) return { label: source, status: 'unmatched' }

    const { data } = await fetchCustomerAddressList({
      customerId,
      addressType,
      from: 0,
      to: 99
    })
    return createMatch(source, data ?? [], (item: CustomerAddress) => item.addressDetail)
  }

  async function fetchCargoMatch(
    name: string | null | undefined,
    index: number
  ): Promise<AiCargoReferenceMatch> {
    const source = trim(String(name ?? ''))
    if (!source) return { index, status: 'empty' }

    const { data } = await fetchCargoList({ keyword: source, from: 0, to: 19 })
    return {
      index,
      ...createMatch(source, data ?? [], (item: Cargo) => item.cargoName)
    }
  }

  function createMatch<T extends { id?: string }>(
    source: string | null | undefined,
    candidates: T[],
    labelOf: (item: T) => string
  ): AiReferenceMatch {
    const normalizedSource = normalizeMatchText(source)
    if (!normalizedSource) return { status: 'empty' }

    const exact = candidates.filter(
      (item) => normalizeMatchText(labelOf(item)) === normalizedSource
    )
    const fuzzy = candidates.filter((item) => {
      const label = normalizeMatchText(labelOf(item))
      return label.includes(normalizedSource) || normalizedSource.includes(label)
    })
    const matched = exact.length === 1 ? exact[0] : fuzzy.length === 1 ? fuzzy[0] : undefined
    return matched?.id
      ? { id: matched.id, label: labelOf(matched), status: 'matched' }
      : { label: String(source), status: 'unmatched' }
  }

  function normalizeMatchText(value?: string | null): string {
    return trim(String(value ?? ''))
      .toLowerCase()
      .replace(/[\s,，。.;；:：()（）\-_/]/g, '')
  }

  return { resolveReferences }
}
