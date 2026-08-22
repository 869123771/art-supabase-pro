/**
 * 平台级员工只读契约。
 *
 * 系统管理只能通过本入口获取 HR 员工选项，不能直接依赖 HR 的内部 provider。
 * 后续 HR 改为独立服务时，只需替换这里的 RPC/HTTP 适配器。
 */
export { fetchEmployeeSelectorList } from '@hr/api'
