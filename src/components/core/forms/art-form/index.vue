<!-- 表单组件 -->
<!-- 支持常用表单组件、自定义组件、插槽、校验、隐藏表单项 -->
<!-- 写法同 ElementPlus 官方文档组件，把属性写在 props 里面就可以了 -->
<template>
  <section :class="['art-form px-4 pb-0 pt-4 md:px-4 md:pt-4', rootClass]">
    <ElForm
      ref="formRef"
      :model="modelValue"
      :rules="props.rules"
      :label-position="labelPosition"
      v-bind="{ ...$attrs }"
      @validate="handleValidate"
    >
      <ElRow class="flex flex-wrap" :gutter="gutter">
        <ElCol
          v-for="item in visibleFormItems"
          :key="item.key"
          :xs="getColSpan(item.span, 'xs')"
          :sm="getColSpan(item.span, 'sm')"
          :md="getColSpan(item.span, 'md')"
          :lg="getColSpan(item.span, 'lg')"
          :xl="getColSpan(item.span, 'xl')"
        >
          <div v-if="isDividerItem(item)" class="art-form-divider">
            <slot
              :name="item.key"
              :item="item"
              :modelValue="modelValue"
              :value="getFieldValue(item.key)"
              :setValue="createSlotSetValue(item)"
              :clearValue="createSlotClearValue(item)"
            >
              <component v-if="typeof item.label !== 'string'" :is="item.label" />
              <span v-else>{{ item.label }}</span>
            </slot>
          </div>
          <ElFormItem v-else :prop="item.key" :label-width="getFormItemLabelWidth(item)">
            <template #label v-if="item.label">
              <span class="art-form-item__label">
                <component v-if="typeof item.label !== 'string'" :is="item.label" />
                <span v-else>{{ item.label }}</span>
                <ElTooltip v-if="item.help" placement="top" effect="dark">
                  <template #content>
                    <component v-if="typeof item.help !== 'string'" :is="item.help" />
                    <span v-else class="whitespace-pre-line">{{ item.help }}</span>
                  </template>
                  <ElIcon class="art-form-item__help-icon" aria-label="查看帮助信息" tabindex="0">
                    <QuestionFilled />
                  </ElIcon>
                </ElTooltip>
              </span>
            </template>
            <div class="art-form-item__content">
              <slot
                :name="item.key"
                :item="item"
                :modelValue="modelValue"
                :value="getFieldValue(item.key)"
                :setValue="createSlotSetValue(item)"
                :clearValue="createSlotClearValue(item)"
              >
                <component
                  :is="getComponent(item)"
                  :model-value="getFieldValue(item.key)"
                  @update:model-value="setFieldValue(item.key, $event, item)"
                  v-bind="getComponentProps(item)"
                >
                  <!-- 下拉选择 -->
                  <template v-if="item.type === 'select' && getOptions(item).length">
                    <ElOption
                      v-for="option in getOptions(item)"
                      v-bind="option"
                      :key="option.value"
                      :label="option.label"
                      :value="option.value"
                    />
                  </template>

                  <!-- 复选框组 -->
                  <template v-if="item.type === 'checkboxGroup' && getOptions(item).length">
                    <ElCheckbox
                      v-for="option in getOptions(item)"
                      v-bind="option"
                      :key="option.value"
                    />
                  </template>

                  <!-- 单选框组 -->
                  <template v-if="item.type === 'radioGroup' && getOptions(item).length">
                    <component
                      :is="getProps(item).optionType === 'button' ? ElRadioButton : ElRadio"
                      v-for="option in getOptions(item)"
                      v-bind="option"
                      :key="option.value"
                    />
                  </template>

                  <!-- 动态插槽支持 -->
                  <template
                    v-for="(slotFn, slotName) in getSlots(item)"
                    :key="slotName"
                    #[slotName]
                  >
                    <component :is="slotFn" />
                  </template>
                </component>
              </slot>

              <div v-if="item.description" class="art-form-item__description">
                <component v-if="typeof item.description !== 'string'" :is="item.description" />
                <span v-else class="whitespace-pre-line">{{ item.description }}</span>
              </div>
            </div>
          </ElFormItem>
        </ElCol>
        <ElCol
          :xs="getActionColSpan('xs')"
          :sm="getActionColSpan('sm')"
          :md="getActionColSpan('md')"
          :lg="getActionColSpan('lg')"
          :xl="getActionColSpan('xl')"
          class="max-w-full"
        >
          <div
            class="mb-3 flex-c flex-wrap justify-end md:flex-row md:items-stretch md:gap-2"
            :style="actionButtonsStyle"
          >
            <div class="flex gap-2 md:justify-center">
              <ElButton v-if="showReset" class="reset-button" @click="handleReset" v-ripple>
                <ElIcon>
                  <RefreshLeft />
                </ElIcon>
                {{ resetText || t('table.form.reset') }}
              </ElButton>
              <ElButton
                v-if="showSubmit"
                type="primary"
                class="submit-button"
                @click="handleSubmit"
                v-ripple
                :disabled="disabledSubmit"
              >
                <ElIcon>
                  <Search />
                </ElIcon>
                {{ submitText || t('table.form.submit') }}
              </ElButton>
            </div>
            <div
              v-if="shouldShowExpandToggle"
              class="art-form__filter-toggle"
              @click="toggleExpand"
            >
              <span>{{ expandToggleText }}</span>
              <div class="art-form__filter-toggle-icon">
                <ElIcon>
                  <ArrowUpBold v-if="isExpanded" />
                  <ArrowDownBold v-else />
                </ElIcon>
              </div>
            </div>
          </div>
        </ElCol>
      </ElRow>
    </ElForm>
  </section>
</template>

<script setup lang="ts">
  import { useWindowSize } from '@vueuse/core'
  import { useI18n } from 'vue-i18n'
  import { onMounted, toRaw, unref, watch, type Component, type Ref, type VNodeChild } from 'vue'
  import {
    ElCascader,
    ElCheckbox,
    ElCheckboxGroup,
    ElDatePicker,
    ElIcon,
    ElInput,
    ElInputTag,
    ElInputNumber,
    ElRadio,
    ElRadioGroup,
    ElRadioButton,
    ElRate,
    ElSelect,
    ElSlider,
    ElSwitch,
    ElTimePicker,
    ElTimeSelect,
    ElTooltip,
    ElTreeSelect,
    type FormInstance,
    type FormItemProp,
    type FormPropsPublic
  } from 'element-plus'
  import type { SelectPropsPublic } from 'element-plus/es/components/select/src/select'
  import {
    ArrowDownBold,
    ArrowUpBold,
    QuestionFilled,
    RefreshLeft,
    Search
  } from '@element-plus/icons-vue'
  import ArtIconPicker from '@/components/core/forms/art-icon-picker/index.vue'
  import ArtDataSelect from '@/components/core/forms/art-data-select/index.vue'
  import { calculateResponsiveSpan, type ResponsiveBreakpoint } from '@/utils/form/responsive'

  defineOptions({ name: 'ArtForm' })

  const componentMap = {
    input: ElInput, // 输入框
    inputTag: ElInputTag, // 标签输入框
    number: ElInputNumber, // 数字输入框
    select: ElSelect, // 选择器
    switch: ElSwitch, // 开关
    checkbox: ElCheckbox, // 复选框
    checkboxGroup: ElCheckboxGroup, // 复选框组
    radioGroup: ElRadioGroup, // 单选框组
    date: ElDatePicker, // 日期选择器
    rate: ElRate, // 评分
    slider: ElSlider, // 滑块
    cascader: ElCascader, // 级联选择器
    timePicker: ElTimePicker, // 时间选择器
    timeSelect: ElTimeSelect, // 时间选择
    treeSelect: ElTreeSelect, // 树选择器
    iconPicker: ArtIconPicker, // 图标选择器
    dataSelect: ArtDataSelect // 数据选择器
  }

  const dividerType = 'divider'

  const { width } = useWindowSize()
  const { t } = useI18n()
  const isMobile = computed(() => width.value < 500)

  const formInstance = useTemplateRef<FormInstance>('formRef')

  type ComponentMap = typeof componentMap
  type FormItemTypedComponentPropsMap = {
    select: SelectPropsPublic
  }

  export type FormItemContent = string | (() => VNodeChild) | Component
  export type FormItemPresetType = keyof ComponentMap
  export type FormItemType = FormItemPresetType | (string & {})
  export type FormItemComponentProps<TType extends FormItemType> =
    TType extends keyof FormItemTypedComponentPropsMap
      ? Partial<FormItemTypedComponentPropsMap[TType]>
      : Record<string, any>
  export type MaybePromise<T> = T | Promise<T>
  export type FormItemApiParams = Record<string, any> | undefined
  export type FormItemOption = Record<string, any>
  export type FormItemApiFn<TParams = FormItemApiParams, TResult = unknown> = (
    params: TParams
  ) => MaybePromise<TResult>
  export type FormItemBeforeFetch<TParams = FormItemApiParams> = (
    params: TParams
  ) => MaybePromise<TParams>
  export type FormItemShouldFetch<TParams = FormItemApiParams> = (
    params: TParams
  ) => MaybePromise<boolean>
  export type FormItemAfterFetch<TResult = unknown> = (
    result: TResult
  ) => MaybePromise<TResult | FormItemOption[]>
  export type ApiComponentLabelFn<TOption extends FormItemOption = FormItemOption> = (
    option: TOption
  ) => string
  export type ApiComponentAutoSelect<TOption extends FormItemOption = FormItemOption> =
    | 'first'
    | 'last'
    | 'one'
    | false
    | ((options: TOption[]) => TOption | undefined)
  export type FormItemHidden =
    | boolean
    | Ref<boolean>
    | ((model: Record<string, any>, item: FormItem) => boolean)

  // 表单项配置
  export interface FormItemBase<
    TApiResult = unknown,
    TParams = FormItemApiParams,
    TType extends FormItemType = FormItemType
  > {
    /** 表单项的唯一标识 */
    key: string
    /** 表单项的标签文本或自定义渲染函数 */
    label: string | (() => VNode) | Component
    /** 显示在组件下方的常驻描述 */
    description?: FormItemContent
    /** 显示在标签帮助图标中的提示内容 */
    help?: FormItemContent
    /** 表单项标签的宽度，会覆盖 Form 的 labelWidth */
    labelWidth?: string | number
    /** 表单项类型，支持预定义的组件类型 */
    type?: TType
    /** 自定义渲染函数或组件，用于渲染自定义组件（优先级高于 type） */
    render?: (() => VNode) | Component
    /** 是否隐藏该表单项 */
    hidden?: FormItemHidden
    /** 表单项占据的列宽，基于24格栅格系统 */
    span?: number
    /** 选项数据，用于 select、checkbox-group、radio-group 等 */
    options?: Record<string, any>
    /** 传递给表单项组件的属性 */
    props?: FormItemComponentProps<TType> & Record<string, any>
    /** 表单项的插槽配置 */
    slots?: Record<string, (() => any) | undefined>
    /** 表单项的占位符文本 */
    placeholder?: string
    /** 异步获取选项数据的接口，适用于 select、checkboxGroup、radioGroup、cascader、treeSelect */
    api?: FormItemApiFn<TParams, TApiResult>
    /** 是否在组件挂载后立即请求 api，默认 true */
    immediate?: boolean
    /** 传递给 api 的参数 */
    params?: TParams
    /** 请求前转换参数 */
    beforeFetch?: FormItemBeforeFetch<TParams>
    /** 请求前判断是否允许请求，返回 false 时跳过请求 */
    shouldFetch?: FormItemShouldFetch<TParams>
    /** 请求后转换响应数据，可直接返回 options 数组或返回新的响应对象 */
    afterFetch?: FormItemAfterFetch<TApiResult>
    /** 从响应对象中提取 options 数组的字段路径，支持 a.b.c */
    resultField?: string
    /** 选项 label 字段名，默认 label */
    labelField?: string
    /** 选项 value 字段名，默认 value */
    valueField?: string
    /** 自定义选项 label */
    labelFn?: ApiComponentLabelFn
    /** 子级字段名，默认 children，适用于 cascader/treeSelect */
    childrenField?: string
    /** 自动选择策略：first 首项，last 末项，one 仅一项时选中，函数自定义，false 不自动选择 */
    autoSelect?: ApiComponentAutoSelect
    /** 更多属性配置请参考 ElementPlus 官方文档 */
  }

  export type FormItem<TApiResult = unknown, TParams = FormItemApiParams> =
    | {
        [TType in FormItemPresetType]: FormItemBase<TApiResult, TParams, TType>
      }[FormItemPresetType]
    | FormItemBase<TApiResult, TParams, string & {}>

  // 表单配置
  export interface ArtFormProps extends Partial<
    Omit<FormPropsPublic, 'model' | 'labelPosition' | 'labelWidth'>
  > {
    /** 表单数据 */
    items: FormItem[]
    /** 每列的宽度（基于 24 格布局） */
    span?: number
    /** 表单控件间隙 */
    gutter?: number
    /** 表单域标签的位置 */
    labelPosition?: 'left' | 'right' | 'top'
    /** 文字宽度 */
    labelWidth?: string | number
    /** 按钮靠左对齐限制（表单项小于等于该值时） */
    buttonLeftLimit?: number
    /** 是否显示重置按钮 */
    showReset?: boolean
    /** 是否显示提交按钮 */
    showSubmit?: boolean
    /** 是否禁用提交按钮 */
    disabledSubmit?: boolean
    /** 根节点附加 class */
    rootClass?: string
    /** 重置按钮文本 */
    resetText?: string
    /** 提交按钮文本 */
    submitText?: string
    /** 是否启用折叠展开能力 */
    enableExpand?: boolean
    /** 是否强制展开全部表单项 */
    isExpand?: boolean
    /** 默认是否展开 */
    defaultExpanded?: boolean
    /** 是否显示展开/收起按钮 */
    showExpand?: boolean
    /** 提交时是否清洗空值 */
    sanitizeOutput?: Partial<SanitizeOutputOptions>
  }

  interface SanitizeOutputOptions {
    /** 移除空字符串 */
    removeEmptyString: boolean
    /** 移除空数组 */
    removeEmptyArray: boolean
    /** 移除清洗后为空的对象 */
    removeEmptyObject: boolean
    /** 移除空富文本占位内容，如 <p><br></p> */
    removeEmptyRichText: boolean
    /** 保留数字 0 这类有效值 */
    keepZero: boolean
    /** 保留 false 这类有效值 */
    keepFalse: boolean
  }

  const props = withDefaults(defineProps<ArtFormProps>(), {
    items: () => [],
    span: 6,
    gutter: 12,
    labelPosition: 'right',
    labelWidth: '70px',
    buttonLeftLimit: 2,
    showReset: true,
    showSubmit: true,
    disabledSubmit: false,
    rootClass: '',
    resetText: '',
    submitText: '',
    enableExpand: false,
    isExpand: false,
    defaultExpanded: false,
    showExpand: true,
    sanitizeOutput: () => ({})
  })

  export interface ArtFormEmits {
    reset: []
    submit: [Record<string, any>]
    validate: [prop: FormItemProp, isValid: boolean, message: string]
  }

  const emit = defineEmits<ArtFormEmits>()

  const modelValue = defineModel<Record<string, any>>({ default: {} })
  const initialModelValue = ref<Record<string, any>>({})
  const isExpanded = ref(props.defaultExpanded)
  const asyncOptionsMap = ref<Record<string, Record<string, any>[]>>({})
  const asyncLoadingMap = ref<Record<string, boolean>>({})

  // 保存组件初始化时的表单快照，用于 reset 时恢复默认值。
  const cloneModelValue = (value: Record<string, any> | undefined) => {
    if (!value) return {}

    const deepClone = (source: unknown): unknown => {
      if (Array.isArray(source)) {
        return source.map((item) => deepClone(item))
      }

      if (source && typeof source === 'object') {
        const rawSource = toRaw(source)
        return Object.keys(rawSource).reduce<Record<string, unknown>>((accumulator, key) => {
          accumulator[key] = deepClone((rawSource as Record<string, unknown>)[key])
          return accumulator
        }, {})
      }

      return source
    }

    return deepClone(toRaw(value)) as Record<string, any>
  }

  initialModelValue.value = cloneModelValue(modelValue.value)

  const rootProps = [
    'label',
    'description',
    'help',
    'labelWidth',
    'key',
    'type',
    'render',
    'hidden',
    'span',
    'slots',
    'api',
    'immediate',
    'params',
    'beforeFetch',
    'shouldFetch',
    'afterFetch',
    'resultField',
    'labelField',
    'valueField',
    'labelFn',
    'childrenField',
    'autoSelect'
  ]
  // 业务表单默认保留空字符串，避免编辑时清空字段后输出丢字段；搜索表单可在 ArtSearchBar 中覆盖。
  const sanitizeOutputOptions = computed<SanitizeOutputOptions>(() => ({
    removeEmptyString: false,
    removeEmptyArray: false,
    removeEmptyObject: false,
    removeEmptyRichText: false,
    keepZero: true,
    keepFalse: true,
    ...props.sanitizeOutput
  }))

  const PATH_NUMBER_RE = /^\d+$/

  // 兼容 a.b、a.0.b 这类路径写法，数字段会被当作数组索引处理。
  const parsePath = (path: string) => {
    return path
      .split('.')
      .filter(Boolean)
      .map((segment) => (PATH_NUMBER_RE.test(segment) ? Number(segment) : segment))
  }

  const getFieldValue = (path: string) => {
    return getRecordFieldValue(modelValue.value, path)
  }

  const getRecordFieldValue = (record: Record<string, any> | undefined, path: string) => {
    return parsePath(path).reduce<any>((currentValue, segment) => {
      if (currentValue == null) return undefined
      return currentValue[segment]
    }, record)
  }

  const createModelSnapshot = () => cloneModelValue(modelValue.value)

  const commitModelValue = (nextValue: Record<string, any>) => {
    const currentValue = modelValue.value

    if (currentValue && typeof currentValue === 'object' && !Array.isArray(currentValue)) {
      Object.keys(currentValue).forEach((key) => {
        delete currentValue[key]
      })
      Object.assign(currentValue, nextValue)
      return
    }

    modelValue.value = nextValue
  }

  const deleteFieldValue = (path: string, target: Record<string, any>) => {
    const segments = parsePath(path)
    if (!segments.length) return target

    const lastSegment = segments.pop()
    const parent = segments.reduce<any>((currentValue, segment) => {
      if (currentValue == null) return undefined
      return currentValue[segment]
    }, target)

    if (parent != null && lastSegment !== undefined) {
      delete parent[lastSegment]
    }

    return target
  }

  const normalizeClearedValue = (value: unknown, item: FormItem): unknown => {
    if (value !== undefined && value !== null) return value

    if (shouldNormalizeClearToEmptyString(item)) {
      return ''
    }

    return value
  }

  const setFieldValue = (path: string, value: unknown, item: FormItem) => {
    const normalizedValue = normalizeClearedValue(value, item)
    const segments = parsePath(path)

    if (!segments.length) return

    const nextModelValue = createModelSnapshot()

    if (normalizedValue === undefined) {
      commitModelValue(deleteFieldValue(path, nextModelValue))
      return
    }

    let currentValue: any = nextModelValue

    segments.forEach((segment, index) => {
      const isLast = index === segments.length - 1

      if (isLast) {
        currentValue[segment] = normalizedValue
        return
      }

      const nextSegment = segments[index + 1]
      const nextContainer = typeof nextSegment === 'number' ? [] : {}

      if (
        currentValue[segment] === null ||
        currentValue[segment] === undefined ||
        typeof currentValue[segment] !== 'object'
      ) {
        currentValue[segment] = nextContainer
      }

      currentValue = currentValue[segment]
    })

    commitModelValue(nextModelValue)
  }

  const emptyStringClearTypes = ['input', 'inputTag', 'select', 'treeSelect', 'cascader']
  const stringValueFieldKeys = ref(new Set<string>())

  const shouldNormalizeClearToEmptyString = (item: FormItem): boolean => {
    if (emptyStringClearTypes.includes(String(item.type))) return true

    if (!item.slots && !item.render) return false

    const initialValue = getRecordFieldValue(initialModelValue.value, item.key)
    return stringValueFieldKeys.value.has(item.key) || typeof initialValue === 'string'
  }

  const normalizeClearedFormValues = () => {
    props.items.forEach((item) => {
      const value = getFieldValue(item.key)

      if (typeof value === 'string') {
        stringValueFieldKeys.value.add(item.key)
        return
      }

      if ((value === null || value === undefined) && shouldNormalizeClearToEmptyString(item)) {
        setFieldValue(item.key, '', item)
      }
    })
  }

  const createSlotSetValue = (item: FormItem) => {
    return (value: unknown) => setFieldValue(item.key, value, item)
  }

  const createSlotClearValue = (item: FormItem) => {
    return () => setFieldValue(item.key, undefined, item)
  }

  const isRichTextEmpty = (value: string) => {
    if (/<(img|video|audio|iframe|embed|object)\b/i.test(value)) {
      return false
    }

    // 去掉编辑器常见占位标签后再判断是否还有实际内容。
    return (
      value
        .replace(/&nbsp;/gi, '')
        .replace(/<br\s*\/?>/gi, '')
        .replace(/<[^>]*>/g, '')
        .trim() === ''
    )
  }

  // 提交时按配置清洗空值，但保留 0 和 false 这类有效值。
  const sanitizeOutputValue = (value: unknown): unknown => {
    const options = sanitizeOutputOptions.value

    if (Array.isArray(value)) {
      const sanitizedArray = value
        .map((item) => sanitizeOutputValue(item))
        .filter((item) => item !== undefined)
      return sanitizedArray.length === 0 && options.removeEmptyArray ? undefined : sanitizedArray
    }

    if (value && typeof value === 'object') {
      const rawValue = toRaw(value)
      const sanitizedObject = Object.entries(rawValue).reduce<Record<string, unknown>>(
        (accumulator, [key, item]) => {
          const sanitizedItem = sanitizeOutputValue(item)
          if (sanitizedItem !== undefined) {
            accumulator[key] = sanitizedItem
          }
          return accumulator
        },
        {}
      )
      return Object.keys(sanitizedObject).length === 0 && options.removeEmptyObject
        ? undefined
        : sanitizedObject
    }

    if (typeof value === 'string') {
      if (options.removeEmptyString && value.trim() === '') {
        return undefined
      }
      if (options.removeEmptyRichText && isRichTextEmpty(value)) {
        return undefined
      }
      return value
    }

    if (value === 0) {
      return options.keepZero ? value : undefined
    }

    if (value === false) {
      return options.keepFalse ? value : undefined
    }

    return value ?? undefined
  }

  const getSanitizedOutput = () => {
    const outputValue = cloneModelValue(modelValue.value)

    props.items.forEach((item) => {
      if (isFormItemHidden(item)) {
        deleteFieldValue(item.key, outputValue)
      }
    })

    return (sanitizeOutputValue(outputValue) || {}) as Record<string, any>
  }

  const optionComponentTypes = ['select', 'checkboxGroup', 'radioGroup', 'cascader', 'treeSelect']

  const isOptionComponent = (item: FormItem) => optionComponentTypes.includes(String(item.type))

  const getValueByPath = (source: unknown, path?: string): unknown => {
    if (!path) return source
    return path.split('.').reduce<unknown>((currentValue, segment) => {
      if (currentValue == null || typeof currentValue !== 'object') return undefined
      return (currentValue as Record<string, unknown>)[segment]
    }, source)
  }

  const extractOptionsResult = (result: unknown, resultField?: string): Record<string, any>[] => {
    const target = getValueByPath(result, resultField)
    return Array.isArray(target) ? target : []
  }

  const normalizeOptionItem = (
    option: Record<string, any>,
    item: FormItem
  ): Record<string, any> => {
    const labelField = item.labelField || 'label'
    const valueField = item.valueField || 'value'
    const childrenField = item.childrenField || 'children'
    const children = option[childrenField]
    const normalizedOption: Record<string, any> = {
      ...option,
      label: item.labelFn ? item.labelFn(option) : (option[labelField] ?? option.label),
      value: option[valueField] ?? option.value
    }

    if (Array.isArray(children)) {
      normalizedOption.children = children.map((child) => normalizeOptionItem(child, item))
    }

    return normalizedOption
  }

  const normalizeOptions = (options: Record<string, any>[], item: FormItem) => {
    return options.map((option) => normalizeOptionItem(option, item))
  }

  const isEmptyFieldValue = (value: unknown) => {
    return (
      value === undefined ||
      value === null ||
      value === '' ||
      (Array.isArray(value) && !value.length)
    )
  }

  const applyAutoSelect = (item: FormItem, options: Record<string, any>[]) => {
    if (!item.autoSelect || !options.length || !isEmptyFieldValue(getFieldValue(item.key))) return

    let selectedOption: Record<string, any> | undefined
    if (item.autoSelect === 'first') {
      selectedOption = options[0]
    } else if (item.autoSelect === 'last') {
      selectedOption = options[options.length - 1]
    } else if (item.autoSelect === 'one' && options.length === 1) {
      selectedOption = options[0]
    } else if (typeof item.autoSelect === 'function') {
      selectedOption = item.autoSelect(options)
    }

    if (selectedOption) {
      setFieldValue(item.key, selectedOption.value, item)
    }
  }

  const fetchOptions = async (item: FormItem): Promise<Record<string, any>[]> => {
    if (!item.api || !isOptionComponent(item)) return getOptions(item)

    let apiParams = cloneModelValue(item.params) as Record<string, any> | undefined
    if (item.beforeFetch) {
      apiParams = await item.beforeFetch(apiParams)
    }

    if (item.shouldFetch) {
      const canFetch = await item.shouldFetch(apiParams)
      if (!canFetch) return getOptions(item)
    }

    asyncLoadingMap.value[item.key] = true
    try {
      const rawResult = await item.api(apiParams)
      const result = item.afterFetch ? await item.afterFetch(rawResult) : rawResult
      const options = normalizeOptions(extractOptionsResult(result, item.resultField), item)
      asyncOptionsMap.value[item.key] = options
      applyAutoSelect(item, options)
      return options
    } finally {
      asyncLoadingMap.value[item.key] = false
    }
  }

  const loadImmediateOptions = () => {
    props.items.forEach((item) => {
      if (item.api && item.immediate !== false) {
        void fetchOptions(item)
      }
    })
  }

  const reloadOptions = async (key?: string) => {
    const targetItems = key ? props.items.filter((item) => item.key === key) : props.items
    const results = await Promise.all(targetItems.filter((item) => item.api).map(fetchOptions))
    return key ? results[0] : results
  }

  const getProps = (item: FormItem): Record<string, any> => {
    if (item.props) return item.props
    const props: Record<string, any> = { ...item }
    rootProps.forEach((key) => delete props[key])
    return props
  }

  const getOptions = (item: FormItem): Record<string, any>[] => {
    if (asyncOptionsMap.value[item.key]) return asyncOptionsMap.value[item.key]
    const options = item.options ?? getProps(item).options
    return Array.isArray(options) ? options : []
  }

  const getPlainTextLabel = (item: FormItem): string => {
    return typeof item.label === 'string' ? item.label : ''
  }

  const getDefaultPlaceholder = (item: FormItem): string | undefined => {
    const label = getPlainTextLabel(item)
    if (!label) return undefined

    if (
      [
        'select',
        'cascader',
        'treeSelect',
        'date',
        'timePicker',
        'timeSelect',
        'dataSelect'
      ].includes(String(item.type))
    ) {
      return `请选择${label}`
    }

    if (['input', 'inputTag', 'number'].includes(String(item.type))) {
      return `请输入${label}`
    }

    return undefined
  }

  const getDefaultComponentProps = (item: FormItem): Record<string, any> => {
    const itemType = String(item.type)
    const defaults: Record<string, any> = {}
    const placeholder = getDefaultPlaceholder(item)

    if (placeholder) {
      defaults.placeholder = placeholder
    }

    if (
      [
        'input',
        'inputTag',
        'select',
        'cascader',
        'treeSelect',
        'date',
        'timePicker',
        'timeSelect',
        'dataSelect'
      ].includes(itemType)
    ) {
      defaults.clearable = true
    }

    if (['select', 'cascader', 'treeSelect'].includes(itemType)) {
      defaults.filterable = true
    }

    return defaults
  }

  const isDividerItem = (item: FormItem): boolean => String(item.type) === dividerType

  const getFormItemLabelWidth = (item: FormItem): string | number | undefined => {
    return item.label ? item.labelWidth || labelWidth.value : undefined
  }

  const getComponentProps = (item: FormItem) => {
    const props = { ...getDefaultComponentProps(item), ...getProps(item) }
    const options = getOptions(item)

    if (['select', 'checkboxGroup', 'radioGroup'].includes(String(item.type))) {
      delete props.options
    }
    if (String(item.type) === 'cascader') {
      props.options = options
    }
    if (String(item.type) === 'treeSelect') {
      props.data = props.data ?? options
    }
    if (String(item.type) === 'dataSelect') {
      if (item.api && !props.apiFn) {
        props.apiFn = (params: Record<string, any>) => {
          const baseParams =
            item.params && typeof item.params === 'object'
              ? (item.params as Record<string, any>)
              : {}
          return item.api?.({ ...baseParams, ...params } as never)
        }
      }
      props.rowKey = props.rowKey ?? item.valueField
      props.labelKey = props.labelKey ?? item.labelField
      props.childrenKey = props.childrenKey ?? item.childrenField
      props.resultField = props.resultField ?? item.resultField
    }
    if (item.api) {
      props.loading = asyncLoadingMap.value[item.key] || props.loading
    }
    delete props.optionType
    return props
  }

  // 获取插槽
  const getSlots = (item: FormItem) => {
    if (!item.slots) return {}
    const validSlots: Record<string, () => any> = {}
    Object.entries(item.slots).forEach(([key, slotFn]) => {
      if (slotFn) {
        validSlots[key] = slotFn
      }
    })
    return validSlots
  }

  // 组件
  const getComponent = (item: FormItem) => {
    // 优先使用 render 函数或组件渲染自定义组件
    if (item.render) {
      return item.render
    }
    // 使用 type 获取预定义组件
    const { type } = item
    return componentMap[type as keyof typeof componentMap] || componentMap['input']
  }

  /**
   * 获取列宽 span 值
   * 根据屏幕尺寸智能降级，避免小屏幕上表单项被压缩过小
   */
  const getColSpan = (itemSpan: number | undefined, breakpoint: ResponsiveBreakpoint): number => {
    return calculateResponsiveSpan(itemSpan, span.value, breakpoint)
  }

  const getActionColSpan = (breakpoint: ResponsiveBreakpoint): number => {
    const occupiedSpan = visibleFormItems.value.reduce((total, item) => {
      return (total + getColSpan(item.span, breakpoint)) % 24
    }, 0)

    return occupiedSpan === 0 ? 24 : 24 - occupiedSpan
  }

  const isFormItemHidden = (item: FormItem): boolean => {
    if (typeof item.hidden === 'function') {
      return item.hidden(modelValue.value, item)
    }

    return !!unref(item.hidden)
  }

  const filteredFormItems = computed(() => {
    return props.items.filter((item) => !isFormItemHidden(item))
  })

  /**
   * 可见的表单项
   */
  const visibleFormItems = computed(() => {
    const shouldShowLess = props.enableExpand && !props.isExpand && !isExpanded.value

    if (shouldShowLess) {
      const maxItemsPerRow = Math.floor(24 / props.span) - 1
      return filteredFormItems.value.slice(0, maxItemsPerRow)
    }

    return filteredFormItems.value
  })

  const shouldShowExpandToggle = computed(() => {
    return (
      props.enableExpand &&
      !props.isExpand &&
      props.showExpand &&
      filteredFormItems.value.length > Math.floor(24 / props.span) - 1
    )
  })

  const expandToggleText = computed(() => {
    return isExpanded.value ? t('table.searchBar.collapse') : t('table.searchBar.expand')
  })

  const toggleExpand = () => {
    isExpanded.value = !isExpanded.value
  }

  /**
   * 操作按钮样式
   */
  const actionButtonsStyle = computed(() => ({
    'justify-content': isMobile.value
      ? 'flex-end'
      : filteredFormItems.value.length <= props.buttonLeftLimit
        ? 'flex-start'
        : 'flex-end'
  }))

  /**
   * 处理重置事件
   */
  const handleReset = () => {
    // 重置表单字段（UI 层）
    formInstance.value?.resetFields()

    // 恢复初始表单值，保留默认值而不是简单清空。
    commitModelValue(cloneModelValue(initialModelValue.value))

    // 触发 reset 事件
    emit('reset')
  }

  /**
   * 处理提交事件
   */
  const handleSubmit = () => {
    // 对外只抛出清洗后的结果，避免业务层重复过滤空值。
    emit('submit', getSanitizedOutput())
  }

  const handleValidate = (prop: FormItemProp, isValid: boolean, message: string) => {
    emit('validate', prop, isValid, message)
  }

  onMounted(loadImmediateOptions)

  watch(
    () =>
      props.items.map((item) => ({
        key: item.key,
        hasApi: !!item.api,
        immediate: item.immediate,
        params: item.params
      })),
    loadImmediateOptions,
    { deep: true }
  )

  watch(
    () =>
      props.items.map((item) => ({
        key: item.key,
        type: item.type,
        slots: item.slots,
        render: item.render,
        value: getFieldValue(item.key)
      })),
    normalizeClearedFormValues,
    { deep: true, immediate: true }
  )

  defineExpose({
    ref: formInstance,
    validate: (...args: any[]) => formInstance.value?.validate(...args),
    clearValidate: (...args: any[]) => formInstance.value?.clearValidate(...args),
    reset: handleReset,
    fetchOptions,
    reloadOptions,
    // 允许外部在不触发提交事件时主动获取清洗后的输出。
    getOutput: getSanitizedOutput
  })

  // 解构 props 以便在模板中直接使用
  const { span, gutter, labelPosition, labelWidth } = toRefs(props)
</script>

<style scoped lang="scss">
  .art-form {
    &.art-search-bar {
      padding: 15px 20px 0;
    }

    &-item {
      &__label {
        display: inline-flex;
        align-items: center;
        min-width: 0;
      }

      &__help-icon {
        flex: none;
        margin-left: 4px;
        color: var(--el-text-color-secondary);
        cursor: help;
      }

      &__content {
        width: 100%;
        min-width: 0;
      }

      &__description {
        margin-top: 6px;
        font-size: 12px;
        line-height: 20px;
        color: var(--el-text-color-secondary);
      }
    }

    &-divider {
      display: flex;
      align-items: center;
      width: 100%;
      margin: 4px 0 14px;
      color: var(--el-text-color-primary);
      font-weight: 600;
      line-height: 24px;

      &::before {
        width: 3px;
        height: 14px;
        margin-right: 8px;
        content: '';
        border-radius: 999px;
        background: var(--el-color-primary);
      }

      &::after {
        flex: 1;
        height: 1px;
        margin-left: 12px;
        content: '';
        background: var(--el-border-color-lighter);
      }
    }

    &__filter-toggle {
      display: flex;
      align-items: center;
      margin-left: 10px;
      line-height: 32px;
      color: var(--theme-color);
      cursor: pointer;
      transition: color 0.2s ease;

      &:hover {
        color: var(--ElColor-primary);
      }

      span {
        font-size: 14px;
        user-select: none;
      }
    }

    &__filter-toggle-icon {
      display: flex;
      align-items: center;
      margin-left: 4px;
      font-size: 14px;
      transition: transform 0.2s ease;
    }

    @media (width <= 768px) {
      &.art-search-bar {
        padding: 16px 16px 0;
      }
    }
  }
</style>
