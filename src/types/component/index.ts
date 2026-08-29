/**
 * 组件类型定义模块
 *
 * 提供项目组件的类型定义
 *
 * ## 主要功能
 *
 * - 搜索组件类型定义
 * - 表格列配置类型
 * - 分页配置类型
 * - 表单规则类型
 * - 对话框配置类型
 *
 * ## 使用场景
 *
 * - 组件 Props 类型约束
 * - 组件配置类型定义
 * - 组件事件参数类型
 *
 * @module types/component/index
 * @author Art Design Pro Team
 */

// 搜索组件类型
export type SearchComponentType =
  | 'input'
  | 'select'
  | 'radio'
  | 'checkbox'
  | 'date'
  | 'month'
  | 'monthrange'
  | 'year'
  | 'yearrange'
  | 'week'
  | 'time'
  | 'timerange'

// 搜索框值变化参数
export interface SearchChangeParams {
  prop: string
  val: unknown
}

export type DictDisplayMode = 'auto' | 'tag' | 'badge' | 'text'

// 通用组件配置默认服务于元数据驱动场景，未知行结构由调用处通过泛型收窄。
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type ComponentRecord = any
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type ComponentValue = any

export interface DictColumnOption<T = ComponentRecord> {
  /** 字典类型编码 */
  code: string
  /** auto: 标签样式优先，其次文字颜色 Badge，最后普通文字 */
  display?: DictDisplayMode
  /** 动态指定用于匹配字典项的值，默认读取当前列 prop */
  value?: (row: T) => string | number | null | undefined
}

// 表格列配置接口
export interface ColumnOption<T = ComponentRecord> {
  // 列类型
  type?: 'selection' | 'expand' | 'index' | 'globalIndex'
  // 列属性名
  prop?: string
  // 列标题
  label?: string
  // 编辑型表格中的必填列；表头会以与表单一致的红色星号提示
  required?: boolean
  // 分组表头子列
  children?: ColumnOption<T>[]
  // 列宽度
  width?: string | number
  // 最小列宽度
  minWidth?: string | number
  // 固定列
  fixed?: boolean | 'left' | 'right'
  // 是否可排序
  sortable?: boolean | 'custom'
  // 是否展示行拖拽手柄，默认 false；支持按行动态控制
  draggable?: boolean | ((row: T) => boolean)
  // 是否禁用当前行拖拽，默认 false；支持按行动态控制
  dragDisabled?: boolean | ((row: T) => boolean)
  // 行拖拽手柄图标
  dragIcon?: string
  // 过滤器选项
  filters?: ComponentValue[]
  // 过滤方法
  filterMethod?: (value: ComponentValue, row: T) => boolean
  // 过滤器位置
  filterPlacement?: string
  // 是否禁用
  disabled?: boolean
  // 是否显示列
  visible?: boolean
  // 是否选中显示
  checked?: boolean
  // 自定义渲染函数
  formatter?: (row: T) => ComponentValue
  // 字典展示配置
  dict?: DictColumnOption<T>
  // 插槽相关配置
  // 是否使用插槽渲染内容
  useSlot?: boolean
  // 插槽名称（默认为 prop 值）
  slotName?: string
  // 是否使用表头插槽
  useHeaderSlot?: boolean
  // 表头插槽名称（默认为 `${prop}-header`）
  headerSlotName?: string
  // 其他属性
  [key: string]: ComponentValue
}

// 分页配置
export interface PaginationConfig {
  // 当前页
  currentPage: number
  // 每页条数
  pageSize: number
  // 总条数
  total: number
  // 每页显示个数选择器的选项
  pageSizes?: number[]
  // 组件布局
  layout?: string
  // 是否为小型分页
  small?: boolean
}

// 表单规则
export interface FormRule {
  // 是否必填
  required?: boolean
  // 错误提示信息
  message?: string
  // 触发方式
  trigger?: string | string[]
  // 最小长度
  min?: number
  // 最大长度
  max?: number
  // 正则表达式
  pattern?: RegExp
  // 自定义验证函数
  validator?: (
    rule: ComponentValue,
    value: ComponentValue,
    callback: (error?: Error) => void
  ) => void
}

// 对话框配置
export interface DialogConfig {
  // 标题
  title: string
  // 是否显示
  visible: boolean
  // 宽度
  width?: string | number
  // 是否可以通过点击 modal 关闭
  closeOnClickModal?: boolean
  // 是否可以通过按下 ESC 关闭
  closeOnPressEscape?: boolean
  // 是否显示关闭按钮
  showClose?: boolean
  // 是否在 Dialog 出现时将 body 滚动锁定
  lockScroll?: boolean
  // 是否显示遮罩层
  modal?: boolean
  // 自定义类名
  customClass?: string
}
