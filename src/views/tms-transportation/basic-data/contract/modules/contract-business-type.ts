type ContractBusinessType = Api.Tms.BasicData.ContractBusinessType

// 业务合同分类直接表示合同相对方：承运商合同选择承运商，货主端合同选择客户/货主。
export const usesCarrierParty = (businessType: ContractBusinessType): boolean =>
  businessType === 'carrier'
