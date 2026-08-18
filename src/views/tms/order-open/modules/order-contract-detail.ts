import { differenceWith, round, uniqBy } from 'lodash-es'
import { createInitialCargoItem, numericValue, textValue, type CargoItem } from './order-open-model'

type ContractDetail = Api.Tms.BasicData.ContractDetailSelectorItem

export interface MergeOrderContractDetailsResult {
  items: CargoItem[]
  addedCount: number
}

export interface ContractCargoFreightResult {
  hasContractCargo: boolean
  transportFee: number
}

export const createCargoItemFromContractDetail = (detail: ContractDetail): CargoItem => ({
  ...createInitialCargoItem(),
  cargoId: detail.cargoId ?? null,
  cargoName: detail.cargoDescription,
  cargoCode: detail.cargoCode,
  packageType: detail.unit,
  quantity: 1,
  unit: detail.unit,
  unitPrice: detail.transportUnitPrice,
  freight: round(numericValue(detail.transportUnitPrice), 2),
  sourceContractId: detail.contractId,
  sourceContractNo: detail.contractNo,
  sourceContractName: detail.contractName,
  sourceContractDetailKey: detail.key
})

export const mergeOrderContractDetails = (
  currentItems: readonly CargoItem[],
  selectedDetails: readonly ContractDetail[]
): MergeOrderContractDetailsResult => {
  const detailKey = (item: ContractDetail): string => textValue(item.key)
  const itemKey = (item: CargoItem): string => textValue(item.sourceContractDetailKey)
  const uniqueSelections = uniqBy(selectedDetails.filter(detailKey), detailKey)
  const additions = differenceWith(
    uniqueSelections,
    currentItems,
    (detail, item) => detailKey(detail) === itemKey(item)
  ).map(createCargoItemFromContractDetail)

  if (!additions.length) return { items: [...currentItems], addedCount: 0 }
  const shouldReplacePlaceholder =
    currentItems.length === 1 && !textValue(currentItems[0].cargoName)
  return {
    items: shouldReplacePlaceholder ? additions : [...currentItems, ...additions],
    addedCount: additions.length
  }
}

export const calculateContractCargoFreight = (item: CargoItem): number =>
  round(numericValue(item.quantity) * numericValue(item.unitPrice), 2)

export const calculateContractTransportFee = (items: readonly CargoItem[]): number =>
  round(
    items.reduce(
      (sum, item) => sum + (item.sourceContractId ? calculateContractCargoFreight(item) : 0),
      0
    ),
    2
  )

export const synchronizeContractCargoFreight = (
  items: readonly CargoItem[]
): ContractCargoFreightResult => {
  const contractItems = items.filter((item) => item.sourceContractId)
  contractItems.forEach((item) => {
    item.freight = calculateContractCargoFreight(item)
  })

  return {
    hasContractCargo: contractItems.length > 0,
    transportFee: calculateContractTransportFee(contractItems)
  }
}
