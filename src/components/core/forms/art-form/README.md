# ArtForm

`ArtForm` 是基于 Element Plus `ElForm` 的元数据表单组件。它负责栅格布局、字段渲染、动态显隐、异步选项、重置/提交按钮、展开收起和提交输出清洗；底层未接管的 `ElForm` Props、属性和事件会透传到内部 `ElForm`。

## 基础用法

```vue
<template>
  <ArtForm
    ref="formRef"
    v-model="form"
    :items="formItems"
    :rules="rules"
    :span="12"
    label-width="100px"
    validate-on-rule-change
    @submit="handleSubmit"
    @reset="handleReset"
    @validate="handleValidate"
  />
</template>

<script setup lang="ts">
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import type { FormRules } from 'element-plus'

  const form = ref({
    name: '',
    status: '1'
  })

  const formItems = computed<FormItem[]>(() => [
    {
      label: '基础信息',
      key: 'basicSection',
      type: 'divider',
      span: 24
    },
    {
      label: '名称',
      key: 'name',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '请输入名称'
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'radioGroup',
      props: {
        options: [
          { label: '启用', value: '1' },
          { label: '禁用', value: '2' }
        ]
      }
    }
  ])

  const rules: FormRules = {
    name: [{ required: true, message: '请输入名称', trigger: 'blur' }]
  }
</script>
```

## Props

`ArtForm` 自有 Props：

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `v-model` | `Record<string, any>` | `{}` | 表单数据；字段变化会整体回写新对象，父级建议使用 `ref` |
| `items` | `FormItem[]` | `[]` | 表单项元数据 |
| `span` | `number` | `6` | 默认列宽，基于 24 栅格 |
| `gutter` | `number` | `12` | 栅格间距 |
| `labelPosition` | `'left' \| 'right' \| 'top'` | `'right'` | 标签位置，会传给 `ElForm` |
| `labelWidth` | `string \| number` | `'70px'` | 默认标签宽度，字段可用 `item.labelWidth` 覆盖 |
| `buttonLeftLimit` | `number` | `2` | 可见字段数量小于等于该值时，按钮组左对齐；设为 `0` 可始终右对齐 |
| `showReset` | `boolean` | `true` | 是否显示重置按钮 |
| `showSubmit` | `boolean` | `true` | 是否显示提交按钮 |
| `disabledSubmit` | `boolean` | `false` | 是否禁用提交按钮 |
| `rootClass` | `string` | `''` | 根节点附加 class |
| `resetText` | `string` | i18n 默认值 | 重置按钮文字 |
| `submitText` | `string` | i18n 默认值 | 提交按钮文字 |
| `enableExpand` | `boolean` | `false` | 是否启用展开/收起能力 |
| `isExpand` | `boolean` | `false` | 是否强制展开全部表单项 |
| `defaultExpanded` | `boolean` | `false` | 非强制展开时，初始是否展开 |
| `showExpand` | `boolean` | `true` | 是否显示展开/收起按钮 |
| `sanitizeOutput` | `Partial<SanitizeOutputOptions>` | `{}` | 提交输出清洗策略 |

## ElForm Props 透传

除 `model` 由 `v-model` 接管外，`ElForm` 的 Props 可直接写在 `ArtForm` 上，并会透传到内部 `ElForm`：

| ElForm 属性                 | 类型/说明                                |
| --------------------------- | ---------------------------------------- |
| `rules`                     | 表单校验规则                             |
| `label-position`            | 标签位置；也可用 `ArtForm.labelPosition` |
| `require-asterisk-position` | 必填星号位置                             |
| `label-width`               | 标签宽度；也可用 `ArtForm.labelWidth`    |
| `label-suffix`              | 标签后缀                                 |
| `inline`                    | 行内表单                                 |
| `inline-message`            | 行内显示校验信息                         |
| `status-icon`               | 显示校验状态图标                         |
| `show-message`              | 是否显示校验信息                         |
| `validate-on-rule-change`   | rules 变化后是否触发校验                 |
| `hide-required-asterisk`    | 隐藏必填星号                             |
| `scroll-to-error`           | 校验失败时滚动到错误项                   |
| `scroll-into-view-options`  | 滚动配置                                 |
| `size`                      | 表单尺寸                                 |
| `disabled`                  | 禁用整个表单                             |

示例：

```vue
<ArtForm
  v-model="form"
  :items="items"
  :rules="rules"
  label-width="100px"
  status-icon
  scroll-to-error
  :validate-on-rule-change="false"
/>
```

## Events

| 事件       | 参数                          | 说明                                   |
| ---------- | ----------------------------- | -------------------------------------- |
| `submit`   | `output: Record<string, any>` | 点击提交按钮触发，参数为清洗后的输出   |
| `reset`    | 无                            | 点击重置按钮触发；组件会先恢复初始快照 |
| `validate` | `prop, isValid, message`      | 透传 `ElForm` 的字段校验事件           |

## Slots

`ArtForm` 为每个 `FormItem.key` 自动开放同名插槽。

| 插槽         | 参数                   | 说明                   |
| ------------ | ---------------------- | ---------------------- |
| `[item.key]` | `{ item, modelValue }` | 完全自定义当前字段内容 |

```vue
<ArtForm v-model="form" :items="items">
  <template #avatar>
    <ArtUploadImage v-model="form.avatar" />
  </template>
</ArtForm>
```

## Ref API

| 方法/属性 | 类型 | 说明 |
| --- | --- | --- |
| `ref` | `Ref<FormInstance \| undefined>` | 底层 `ElForm` 实例 |
| `validate(...args)` | `FormInstance['validate']` | 执行校验 |
| `clearValidate(...args)` | `FormInstance['clearValidate']` | 清除校验状态 |
| `reset()` | `() => void` | 执行组件重置逻辑并触发 `reset` |
| `fetchOptions(item)` | `(item: FormItem) => Promise<Record<string, any>[]>` | 加载单个字段的异步选项 |
| `reloadOptions(key?)` | `(key?: string) => Promise<unknown>` | 重新加载指定字段或全部异步选项 |
| `getOutput()` | `() => Record<string, any>` | 获取按 `sanitizeOutput` 清洗后的表单输出 |

底层 `ElForm` 的其他方法可通过 `formRef.value?.ref.value` 访问，例如 `validateField`、`resetFields`、`scrollToField`、`fields`。

## FormItem

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `key` | `string` | 必填 | 字段路径，支持 `a.b`、`a.0.b` |
| `label` | `string \| () => VNodeChild \| Component` | 必填 | 字段标签 |
| `description` | `string \| () => VNodeChild \| Component` | `undefined` | 字段下方说明 |
| `help` | `string \| () => VNodeChild \| Component` | `undefined` | 标签旁帮助提示 |
| `labelWidth` | `string \| number` | `undefined` | 当前字段标签宽度 |
| `type` | `FormItemType` | `'input'` | 内置组件类型 |
| `render` | `() => VNode \| Component` | `undefined` | 自定义渲染组件，优先级高于 `type` |
| `hidden` | `boolean \| Ref<boolean> \| (model, item) => boolean` | `false` | 是否隐藏字段 |
| `span` | `number` | 继承 `ArtForm.span` | 当前字段列宽 |
| `options` | `Record<string, any>[]` | `[]` | 静态选项 |
| `props` | `Record<string, any>` | `{}` | 透传给字段组件的 Props/事件 |
| `slots` | `Record<string, () => any>` | `{}` | 透传给字段组件的内部插槽 |
| `placeholder` | `string` | `undefined` | 兼容字段；推荐写在 `props.placeholder` |
| `api` | `(params) => MaybePromise<TResult>` | `undefined` | 异步获取选项 |
| `immediate` | `boolean` | `true` | 是否挂载后立即请求 `api` |
| `params` | `TParams` | `undefined` | 传给 `api` 的参数 |
| `beforeFetch` | `(params) => MaybePromise<TParams>` | `undefined` | 请求前转换参数 |
| `shouldFetch` | `(params) => MaybePromise<boolean>` | `undefined` | 请求前判断是否允许请求 |
| `afterFetch` | `(result) => MaybePromise<TResult \| FormItemOption[]>` | `undefined` | 请求后转换响应 |
| `resultField` | `string` | `undefined` | 从响应中提取选项数组的路径 |
| `labelField` | `string` | `'label'` | 选项标签字段 |
| `valueField` | `string` | `'value'` | 选项值字段 |
| `labelFn` | `(option) => string` | `undefined` | 自定义选项标签 |
| `childrenField` | `string` | `'children'` | 子级字段名 |
| `autoSelect` | `'first' \| 'last' \| 'one' \| false \| fn` | `false` | 异步选项加载后自动选择 |

## 内置字段类型

| type | 底层组件 | 选项写法 |
| --- | --- | --- |
| `input` | `ElInput` | 无 |
| `inputTag` | `ElInputTag` | 无 |
| `number` | `ElInputNumber` | 无 |
| `select` | `ElSelect` + `ElOption` | `props.options` / `options` / `api` |
| `segment` | `ElSegmented` | `props.options` / `options` / `api` |
| `switch` | `ElSwitch` | 无 |
| `checkbox` | `ElCheckbox` | 无 |
| `checkboxGroup` | `ElCheckboxGroup` + `ElCheckbox` / `ElCheckboxButton` | `props.options` / `options` / `api`；`props.optionType='button'` 使用按钮样式 |
| `radioGroup` | `ElRadioGroup` + `ElRadio` / `ElRadioButton` | `props.options` / `options` / `api`；`props.optionType='button'` 使用按钮样式 |
| `date` | `ElDatePicker` | 无 |
| `rate` | `ElRate` | 无 |
| `slider` | `ElSlider` | 无 |
| `cascader` | `ElCascader` | `props.options` / `options` / `api` |
| `timePicker` | `ElTimePicker` | 无 |
| `timeSelect` | `ElTimeSelect` | 无 |
| `treeSelect` | `ElTreeSelect` | `props.data` / `options` / `api` |
| `iconPicker` | `ArtIconPicker` | 无 |
| `divider` | 内置分区标题 | 使用 `label` 作为标题，建议 `span: 24` |

字段组件的 Element Plus Props 和事件写在 `item.props` 中：

```ts
{
  label: '状态',
  key: 'status',
  type: 'select',
  props: {
    clearable: true,
    placeholder: '请选择状态',
    options: statusOptions,
    onChange: (value: string) => {
      console.log(value)
    }
  }
}
```

## 分区标题

普通表单分区标题直接使用 `type: 'divider'`，不要在业务组件里为标题单独写插槽和样式。

```ts
const formItems = computed<FormItem[]>(() => [
  {
    label: '基础信息',
    key: 'basicSection',
    type: 'divider',
    span: 24
  },
  {
    label: '名称',
    key: 'name',
    type: 'input'
  }
])
```

## 异步选项

```ts
const formItems = computed<FormItem[]>(() => [
  {
    label: '地区',
    key: 'region',
    type: 'cascader',
    api: fetchRegionOptions,
    resultField: 'data.records',
    labelField: 'name',
    valueField: 'code',
    childrenField: 'children',
    afterFetch: (response) => response.data,
    autoSelect: 'one',
    props: {
      clearable: true,
      filterable: true
    }
  }
])
```

## 提交输出清洗

默认清洗策略偏接口友好：

| 策略                  | 默认值 | 说明                 |
| --------------------- | ------ | -------------------- |
| `removeEmptyString`   | `true` | 移除空字符串         |
| `removeEmptyArray`    | `true` | 移除空数组           |
| `removeEmptyObject`   | `true` | 移除清洗后为空的对象 |
| `removeEmptyRichText` | `true` | 移除空富文本占位内容 |
| `keepZero`            | `true` | 保留数字 `0`         |
| `keepFalse`           | `true` | 保留布尔 `false`     |

```vue
<ArtForm
  v-model="form"
  :items="items"
  :sanitize-output="{ removeEmptyString: false }"
  @submit="submitApi"
/>
```

## 使用建议

- 父组件使用 `ref` 承接 `v-model`，不要把 `reactive` 常量对象直接传给 `ArtForm`，因为组件会整体回写新对象。
- 普通字段优先用 `items` 描述；复杂字段用同名插槽。
- 业务弹窗中配合 `ArtDialog` 使用时，通常设置 `show-reset=false`、`show-submit=false`，把提交交给弹窗 Footer。
- Element Plus 字段组件的所有 Props 和事件都写到 `item.props`，例如 `maxlength`、`showWordLimit`、`onChange`。
