type ContractBusinessType = Api.Tms.BasicData.ContractBusinessType

// 业务合同分类表示合同发起端，选择的合同相对方应取另一侧。
export const usesCarrierParty = (businessType: ContractBusinessType): boolean =>
  businessType === 'customer'
