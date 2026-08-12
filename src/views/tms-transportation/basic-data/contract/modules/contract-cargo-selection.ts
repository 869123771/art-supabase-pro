import { differenceWith, uniqBy } from 'lodash-es'

type Cargo = Api.Tms.BasicData.Cargo
type ContractTransportDetail = Api.Tms.BasicData.ContractTransportDetail

export interface ContractCargoMergeResult {
  items: ContractTransportDetail[]
  addedCount: number
}

export const createContractDetailFromCargo = (cargo: Cargo): ContractTransportDetail => ({
  cargoId: cargo.id ?? null,
  cargoDescription: cargo.cargoName,
  cargoCode: cargo.cargoCode ?? '',
  contractQuantity: 1,
  unit: cargo.unit || '',
  transportUnitPrice: 0,
  freight: 0
})

export const mergeContractCargoSelections = (
  currentItems: readonly ContractTransportDetail[],
  selectedCargoes: readonly Cargo[]
): ContractCargoMergeResult => {
  const cargoKey = (item: Cargo): string => String(item.id ?? '').trim()
  const detailKey = (item: ContractTransportDetail): string => String(item.cargoId ?? '').trim()
  const uniqueSelections = uniqBy(selectedCargoes.filter(cargoKey), cargoKey)
  const additions = differenceWith(
    uniqueSelections,
    currentItems,
    (cargo, detail) => cargoKey(cargo) === detailKey(detail)
  ).map(createContractDetailFromCargo)

  if (!additions.length) return { items: [...currentItems], addedCount: 0 }

  const shouldReplacePlaceholder = currentItems.length === 1 && isPlaceholderDetail(currentItems[0])
  return {
    items: shouldReplacePlaceholder ? additions : [...currentItems, ...additions],
    addedCount: additions.length
  }
}

const isPlaceholderDetail = (detail: ContractTransportDetail): boolean =>
  !detail.cargoId && !detail.cargoDescription.trim() && !detail.cargoCode.trim()
