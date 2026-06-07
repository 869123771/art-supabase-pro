# ArtDrawer

`ArtDrawer` 是基于 Element Plus `ElDrawer` 封装的命令式抽屉组件。父组件通过 Ref 调用方法，不需要维护 `v-model` 和显示状态，适合详情、编辑、配置、审批等侧边工作流。

## 默认行为

- 默认方向为 `rtl`
- 默认尺寸为 `40%`
- 默认启用 `destroy-on-close`
- 默认显示“取消”和“确定”按钮
- 确认成功后默认自动关闭
- 支持异步确认、关闭拦截和 Loading
- 设置 `contentHeight` 后自动使用 `ElScrollbar`
- 支持自定义 Header、Footer 和动态内容组件
- 未封装的 `ElDrawer` API 可以直接透传

## 配置方式与优先级

扩展配置支持组件 Props 和 `handleOpen` 第二参数两种来源：

```vue
<ArtDrawer
  ref="drawerRef"
  size="45%"
  content-height="70vh"
  :drawer-props="{ appendToBody: true, closeOnClickModal: false }"
  :on-confirm="handleDefaultConfirm"
/>
```

```ts
drawerRef.value?.handleOpen(data, {
  title: '订单详情',
  size: 720,
  drawerProps: {
    class: 'order-drawer',
    resizable: true
  },
  onConfirm: handleSubmit
})
```

优先级为：内置默认值 `<` 组件 Props/原生属性 `<` 组件 `drawerProps` `<` `handleOpen` 第二参数。`handleOpen.drawerProps` 和 `handleOpen.contentProps` 会与静态对象合并，同名字段由本次打开配置覆盖。

## 基础用法

```vue
<template>
  <ArtDrawer ref="drawerRef">
    <template #default="{ data }">
      <ElForm label-width="90px">
        <ElFormItem label="名称">
          <ElInput v-model="data.name" />
        </ElFormItem>
      </ElForm>
    </template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'

  interface DrawerData {
    id?: string
    name: string
  }

  const drawerRef = ref<ArtDrawerExpose<DrawerData>>()

  const handleOpen = () => {
    drawerRef.value?.handleOpen(
      { name: '' },
      {
        title: '编辑资料',
        size: 560,
        onConfirm: async (data) => {
          await saveData(data)
        }
      }
    )
  }
</script>
```

## 复杂业务组件模式

业务抽屉应在自己的组件内部组合 `ArtDrawer` 和表单。列表页面只保留 `<OrderDrawer ref="orderDrawerRef" />`，并通过业务组件暴露的方法打开。

```vue
<template>
  <ArtDrawer ref="drawerRef">
    <OrderForm ref="formRef" />
  </ArtDrawer>
</template>

<script setup lang="ts">
  const drawerRef = ref<ArtDrawerExpose<OrderOpenData>>()
  const formRef = ref<OrderFormExpose>()

  const handleOpen = async (data: OrderOpenData) => {
    await drawerRef.value?.handleOpen(data, {
      title: '处理订单',
      size: '55%',
      onOpen: async (openData) => {
        await nextTick()
        await formRef.value?.handleOpen(openData)
      },
      onConfirm: async () => {
        return (await formRef.value?.handleSubmit()) ?? false
      }
    })
  }

  defineExpose({ handleOpen })
</script>
```

`onConfirm` 返回 `false` 时抽屉保持打开。回调执行期间确定按钮会自动进入 Loading。

## 内容滚动

```ts
drawerRef.value?.handleOpen(data, {
  contentHeight: 'calc(100vh - 180px)',
  scrollbarAlways: true
})
```

也可以主动控制位置：

```ts
drawerRef.value?.scrollTo(0)
drawerRef.value?.scrollTo({ top: 500, behavior: 'smooth' })
```

## 自定义插槽

```vue
<ArtDrawer ref="drawerRef">
  <template #header="{ data }">
    <strong>{{ data.title }}</strong>
  </template>

  <template #default="{ data, api }">
    <DetailPanel :data="data" :drawer-api="api" />
  </template>

  <template #footer="{ loading, api }">
    <ElButton @click="api.handleClose()">取消</ElButton>
    <ElButton type="primary" :loading="loading" @click="api.handleConfirm()">
      提交
    </ElButton>
  </template>
</ArtDrawer>
```

| 插槽      | 参数                     | 说明       |
| --------- | ------------------------ | ---------- |
| `default` | `data`, `api`            | 默认内容   |
| `header`  | `data`, `api`            | 自定义头部 |
| `footer`  | `data`, `loading`, `api` | 自定义底部 |

## 动态组件

```ts
drawerRef.value?.handleOpen(order, {
  title: '订单详情',
  content: OrderDetail,
  contentProps: {
    readonly: true
  },
  showFooter: false
})
```

动态组件自动接收 `data`、`drawerApi` 和 `contentProps`。

## ArtDrawerOptions

| 属性                  | 类型                             | 默认值      | 说明                   |
| --------------------- | -------------------------------- | ----------- | ---------------------- |
| `title`               | `string`                         | `''`        | 标题                   |
| `size`                | `string \| number`               | `'40%'`     | 抽屉尺寸               |
| `direction`           | `ltr \| rtl \| ttb \| btt`       | `'rtl'`     | 展开方向               |
| `contentHeight`       | `string \| number`               | `undefined` | 固定内容高度           |
| `showFooter`          | `boolean`                        | `true`      | 是否显示 Footer        |
| `showCancelButton`    | `boolean`                        | `true`      | 是否显示取消按钮       |
| `showConfirmButton`   | `boolean`                        | `true`      | 是否显示确定按钮       |
| `cancelText`          | `string`                         | `'取消'`    | 取消按钮文字           |
| `confirmText`         | `string`                         | `'确定'`    | 确定按钮文字           |
| `confirmDisabled`     | `boolean`                        | `false`     | 是否禁用确定按钮       |
| `autoClose`           | `boolean`                        | `true`      | 确认成功后自动关闭     |
| `resetOnClose`        | `boolean`                        | `true`      | 关闭后自动重置         |
| `closeOnConfirmError` | `boolean`                        | `false`     | 确认异常后是否强制关闭 |
| `scrollbarAlways`     | `boolean`                        | `false`     | 始终显示滚动条         |
| `nativeScrollbar`     | `boolean`                        | `false`     | 使用原生滚动条         |
| `content`             | `Component`                      | `undefined` | 动态内容组件           |
| `contentProps`        | `Record<string, unknown>`        | `undefined` | 动态组件 Props         |
| `drawerProps`         | `ElDrawer Props`                 | `undefined` | 单次打开的底层配置     |
| `onOpen`              | `(data, api) => void`            | `undefined` | 内容挂载后的打开回调   |
| `onConfirm`           | `(data, api) => boolean \| void` | `undefined` | 异步确认回调           |
| `onClose`             | `(data, api) => boolean \| void` | `undefined` | `handleClose` 关闭拦截 |
| `onReset`             | `(api) => void`                  | `undefined` | 重置回调               |

## Ref 方法

| 方法                          | 说明                            |
| ----------------------------- | ------------------------------- |
| `handleOpen(data?, options?)` | 打开并传入数据和配置            |
| `handleClose(force?)`         | 关闭；`force=true` 跳过关闭拦截 |
| `handleConfirm()`             | 主动执行确认流程                |
| `handleReset()`               | 重置数据与 Loading              |
| `setLoading(value)`           | 设置内容 Loading                |
| `setConfirmLoading(value)`    | 设置确认按钮 Loading            |
| `setOptions(options)`         | 增量更新配置                    |
| `setData(data)`               | 替换当前数据                    |
| `updateData(data)`            | 浅合并当前对象数据              |
| `getData()`                   | 获取当前数据                    |
| `getDrawerInstance()`         | 获取底层 `ElDrawer` 实例        |
| `scrollTo(options)`           | 控制滚动位置                    |

## 事件

支持 `open`、`opened`、`close`、`closed`、`open-auto-focus`、 `close-auto-focus`、`resize-start`、`resize`、`resize-end`，并额外提供：

| 事件      | 参数      | 说明             |
| --------- | --------- | ---------------- |
| `confirm` | 当前数据  | 开始确认         |
| `reset`   | 无        | 重置完成         |
| `error`   | `unknown` | 确认回调发生异常 |

## ElDrawer API 透传

```vue
<ArtDrawer
  ref="drawerRef"
  append-to-body
  :close-on-click-modal="false"
  :close-on-press-escape="false"
/>
```

单次配置：

```ts
drawerRef.value?.handleOpen(data, {
  drawerProps: {
    appendToBody: true,
    closeOnClickModal: false,
    closeOnPressEscape: false,
    modal: true,
    resizable: true
  }
})
```

优先级为：组件默认值、静态透传属性、`drawerProps`、`ArtDrawerOptions` 中的核心配置。

## 使用建议

- 详情类抽屉设置 `showFooter: false`
- 编辑类抽屉让内部表单暴露 `handleOpen` 和 `handleSubmit`
- 校验或接口失败时返回 `false`
- 长内容设置稳定的 `contentHeight`
- 需要阻止关闭时通过 `onClose` 返回 `false`
- 多种详情共用一个抽屉时使用动态 `content`
