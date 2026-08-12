type ContractBusinessType = Api.Tms.BasicData.ContractBusinessType

// 合同分类表示发起端，因此相对方与分类名称相反。
export const usesCarrierParty = (businessType: ContractBusinessType): boolean =>
  businessType === 'customer'
