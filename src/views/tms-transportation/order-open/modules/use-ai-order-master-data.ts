import { trim } from 'lodash-es'
import { addCargo, addCustomer, addCustomerAddress, addStation } from '@/api/tms'
import type { AiOrderMasterDataTask, AiOrderReferenceMatches } from './ai-order-types'

type Draft = Api.Tms.Order.AiOrderDraft
type AddressType = Api.Tms.BasicData.CustomerAddressType
type StationType = Api.Tms.Station.StationType
type Customer = Api.Tms.BasicData.Customer
type CustomerAddress = Api.Tms.BasicData.CustomerAddress

const PHONE_PATTERN = /^(?:1[3-9]\d{9}|0\d{2,3}-?\d{7,8})$/
const CARGO_UNITS = new Set(['piece', 'box', 'bottle', 'item', 'set'])

interface CustomerSideConfig {
  side: 'shipping' | 'receiving'
  customerKey: 'shippingCustomer' | 'receivingCustomer'
  addressKey: 'shippingAddress' | 'receivingAddress'
  customerTitle: string
  addressTitle: string
  addressType: AddressType
  customerName?: string | null
  contactName?: string | null
  contactPhone?: string | null
  addressDetail?: string | null
}

export function useAiOrderMasterData() {
  function buildTasks(draft: Draft, references: AiOrderReferenceMatches): AiOrderMasterDataTask[] {
    const tasks: AiOrderMasterDataTask[] = []

    pushStationTask(
      tasks,
      'originStation',
      '发货站',
      'shipping',
      draft.originStationName,
      references
    )
    pushStationTask(
      tasks,
      'destinationStation',
      '到货站',
      'arrival',
      draft.destinationStationName,
      references
    )
    pushStationTask(
      tasks,
      'transferStation',
      '中转站',
      'transfer',
      draft.transferStationName,
      references
    )

    pushCustomerTasks(tasks, getCustomerConfig('shipping', draft), references)
    pushCustomerTasks(tasks, getCustomerConfig('receiving', draft), references)

    references.cargoItems.forEach((reference) => {
      if (reference.status !== 'unmatched') return
      const cargo = draft.cargoItems?.[reference.index]
      const cargoName = text(cargo?.cargoName)
      const unit = normalizeCargoUnit(cargo?.unit || cargo?.packageType)
      tasks.push({
        key: `cargo:${reference.index}`,
        kind: 'cargo',
        title: `货物：${cargoName || `第${reference.index + 1}条`}`,
        description: `${cargoName || '-'} · ${unit || '默认计件'}`,
        ready: cargoName.length >= 2,
        reason: cargoName.length >= 2 ? undefined : '缺少有效货物名称'
      })
    })

    return tasks
  }

  async function createTasks(
    draft: Draft,
    references: AiOrderReferenceMatches,
    selectedKeys: string[]
  ): Promise<number> {
    const selected = new Set(selectedKeys)
    let createdCount = 0
    let stationSequence = 0

    for (const config of getStationConfigs(draft)) {
      if (!selected.has(config.key)) continue
      await addStation(
        {
          stationCode: createStationCode(stationSequence++),
          stationName: text(config.name),
          stationType: config.stationType,
          enabled: true,
          sort: 0,
          remark: null
        },
        { showMessage: false }
      )
      createdCount += 1
    }

    for (const side of ['shipping', 'receiving'] as const) {
      const config = getCustomerConfig(side, draft)
      if (selected.has(config.customerKey)) {
        await createCustomerBundle(config)
        createdCount += 1
      } else if (selected.has(config.addressKey)) {
        const customerId = references[config.customerKey].id
        if (!customerId) throw new Error(`${config.customerTitle}尚未匹配，无法创建地址`)
        await createAddress(customerId, config)
        createdCount += 1
      }
    }

    for (const reference of references.cargoItems) {
      if (!selected.has(`cargo:${reference.index}`)) continue
      const cargo = draft.cargoItems?.[reference.index]
      await addCargo(
        {
          cargoName: text(cargo?.cargoName),
          unit: normalizeCargoUnit(cargo?.unit || cargo?.packageType),
          enabled: true,
          remark: null
        },
        { showMessage: false }
      )
      createdCount += 1
    }

    return createdCount
  }

  function pushStationTask(
    tasks: AiOrderMasterDataTask[],
    key: 'originStation' | 'destinationStation' | 'transferStation',
    title: string,
    stationType: StationType,
    source: string | null | undefined,
    references: AiOrderReferenceMatches
  ): void {
    if (references[key].status !== 'unmatched') return
    const stationName = text(source)
    const ready = stationName.length >= 2
    tasks.push({
      key,
      kind: 'station',
      title,
      description: `${stationName || '-'} · ${stationTypeLabel(stationType)}`,
      ready,
      reason: ready ? undefined : '缺少有效站点名称'
    })
  }

  function pushCustomerTasks(
    tasks: AiOrderMasterDataTask[],
    config: CustomerSideConfig,
    references: AiOrderReferenceMatches
  ): void {
    const customerReference = references[config.customerKey]
    const addressReference = references[config.addressKey]
    const customerName = text(config.customerName)
    const addressDetail = text(config.addressDetail)
    const hasAddress = Boolean(addressDetail)
    const addressReady = isAddressReady(config)

    if (customerReference.status === 'unmatched') {
      const ready = customerName.length >= 2 && (!hasAddress || addressReady)
      tasks.push({
        key: config.customerKey,
        kind: 'customer',
        title: hasAddress ? `${config.customerTitle}及默认地址` : config.customerTitle,
        description: compactDescription([
          customerName,
          text(config.contactName),
          text(config.contactPhone),
          addressDetail
        ]),
        ready,
        reason: ready ? undefined : getCustomerNotReadyReason(config)
      })
      return
    }

    if (customerReference.status === 'matched' && addressReference.status === 'unmatched') {
      tasks.push({
        key: config.addressKey,
        kind: 'address',
        title: config.addressTitle,
        description: compactDescription([
          text(config.contactName),
          text(config.contactPhone),
          addressDetail
        ]),
        ready: addressReady,
        reason: addressReady ? undefined : getAddressNotReadyReason(config)
      })
    }
  }

  async function createCustomerBundle(config: CustomerSideConfig): Promise<void> {
    const region = inferRegion(config.addressDetail)
    const customer: Customer = {
      customerName: text(config.customerName),
      tags: [],
      region,
      addressDetail: text(config.addressDetail),
      enabled: true,
      contactName: text(config.contactName),
      contactPhone: text(config.contactPhone),
      coordinateSystem: 'gcj02',
      coordinateStatus: 'pending'
    }
    const { data } = await addCustomer(customer, { showMessage: false })
    if (!data?.id) throw new Error(`${config.customerTitle}创建后未返回编号`)
    if (text(config.addressDetail)) await createAddress(data.id, config)
  }

  async function createAddress(customerId: string, config: CustomerSideConfig): Promise<void> {
    const address: CustomerAddress = {
      customerId,
      addressType: config.addressType,
      contactName: text(config.contactName),
      contactPhone: text(config.contactPhone),
      region: inferRegion(config.addressDetail),
      addressDetail: text(config.addressDetail),
      coordinateSystem: 'gcj02',
      coordinateStatus: 'pending',
      isDefault: true
    }
    await addCustomerAddress(address, { showMessage: false })
  }

  return { buildTasks, createTasks }
}

function getStationConfigs(draft: Draft) {
  return [
    { key: 'originStation', stationType: 'shipping', name: draft.originStationName },
    { key: 'destinationStation', stationType: 'arrival', name: draft.destinationStationName },
    { key: 'transferStation', stationType: 'transfer', name: draft.transferStationName }
  ] as const
}

function getCustomerConfig(side: 'shipping' | 'receiving', draft: Draft): CustomerSideConfig {
  if (side === 'shipping') {
    return {
      side,
      customerKey: 'shippingCustomer',
      addressKey: 'shippingAddress',
      customerTitle: '发货客户',
      addressTitle: '发货地址',
      addressType: 'shipping',
      customerName: draft.shippingCustomerName,
      contactName: draft.shippingContactName,
      contactPhone: draft.shippingContactPhone,
      addressDetail: draft.shippingAddressDetail
    }
  }
  return {
    side,
    customerKey: 'receivingCustomer',
    addressKey: 'receivingAddress',
    customerTitle: '收货客户',
    addressTitle: '收货地址',
    addressType: 'receiving',
    customerName: draft.receivingCustomerName,
    contactName: draft.receivingContactName,
    contactPhone: draft.receivingContactPhone,
    addressDetail: draft.receivingAddressDetail
  }
}

function isAddressReady(config: CustomerSideConfig): boolean {
  return Boolean(
    text(config.contactName) &&
    PHONE_PATTERN.test(text(config.contactPhone)) &&
    inferRegion(config.addressDetail) &&
    text(config.addressDetail)
  )
}

function getCustomerNotReadyReason(config: CustomerSideConfig): string {
  if (text(config.customerName).length < 2) return '缺少有效客户名称'
  return getAddressNotReadyReason(config)
}

function getAddressNotReadyReason(config: CustomerSideConfig): string {
  if (!text(config.contactName)) return '缺少联系人'
  if (!PHONE_PATTERN.test(text(config.contactPhone))) return '联系电话缺失或格式不正确'
  if (!inferRegion(config.addressDetail)) return '无法从详细地址识别省市区'
  if (!text(config.addressDetail)) return '缺少详细地址'
  return '资料不完整'
}

function inferRegion(value: string | null | undefined): string {
  const address = text(value)
  if (!address) return ''

  const municipality = address.match(/^(北京市|上海市|天津市|重庆市)(.+?(?:区|县))/)
  if (municipality) return [municipality[1], municipality[2]].join('/')

  const provinceCityDistrict = address.match(/^(.+?省)(.+?市)(.+?(?:区|县|旗))/)
  if (provinceCityDistrict) {
    return [provinceCityDistrict[1], provinceCityDistrict[2], provinceCityDistrict[3]].join('/')
  }

  const cityDistrict = address.match(/^(.+?市)(.+?(?:区|县|旗))/)
  if (cityDistrict) return [cityDistrict[1], cityDistrict[2]].join('/')
  return ''
}

function createStationCode(sequence: number): string {
  return `ST${Date.now().toString(36).toUpperCase()}${String(sequence).padStart(2, '0')}`
}

function normalizeCargoUnit(value: string | null | undefined): string {
  const unit = text(value)
  return CARGO_UNITS.has(unit) ? unit : 'item'
}

function stationTypeLabel(type: StationType): string {
  if (type === 'shipping') return '发货站'
  if (type === 'arrival') return '到货站'
  return '中转站'
}

function compactDescription(values: string[]): string {
  return values.filter(Boolean).join(' · ') || '-'
}

function text(value: unknown): string {
  return trim(String(value ?? ''))
}
