export type AiReferenceStatus = 'empty' | 'matched' | 'unmatched'

export interface AiReferenceMatch {
  id?: string
  label?: string
  status: AiReferenceStatus
}

export interface AiCargoReferenceMatch extends AiReferenceMatch {
  index: number
}

export interface AiOrderReferenceMatches {
  originStation: AiReferenceMatch
  destinationStation: AiReferenceMatch
  transferStation: AiReferenceMatch
  shippingCustomer: AiReferenceMatch
  receivingCustomer: AiReferenceMatch
  shippingAddress: AiReferenceMatch
  receivingAddress: AiReferenceMatch
  cargoItems: AiCargoReferenceMatch[]
}

export type AiOrderMasterDataKind = 'station' | 'customer' | 'address' | 'cargo'

export interface AiOrderMasterDataTask {
  key: string
  kind: AiOrderMasterDataKind
  title: string
  description: string
  ready: boolean
  reason?: string
}

export interface AiOrderApplyPayload {
  analysis: Api.Tms.Order.AiOrderAnalyzeResponse
  references: AiOrderReferenceMatches
}

export interface AiOrderDrawerOpenData {
  options: NonNullable<Api.Tms.Order.AiOrderAnalyzeRequest['options']>
}

export interface AiOrderInputModel {
  prompt: string
  imageUrls: string[]
}

export interface AiOrderDrawerExpose {
  handleOpen: (data: AiOrderDrawerOpenData) => Promise<void>
}
