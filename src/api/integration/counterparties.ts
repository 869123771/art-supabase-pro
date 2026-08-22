/**
 * 平台级交易对手只读契约。
 *
 * 业务子应用只能依赖本入口，不能直接引用其他业务域的 provider。当前数据由
 * TMS 提供；后续即使 TMS 独立部署，也只需在此切换为 RPC/HTTP 适配器。
 */
export { fetchCarrierOptions } from '@/api/modules/tms/carrier'
export { fetchCustomerOptions, fetchCustomerSelectorList } from '@/api/modules/tms/customer'
