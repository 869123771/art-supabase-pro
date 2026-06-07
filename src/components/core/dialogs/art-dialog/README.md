# ArtDialog

`ArtDialog` 是基于 Element Plus `ElDialog` 封装的命令式弹窗组件。父组件不需要维护 `v-model`、`visible` 或多组弹窗 Props，只需要持有组件 Ref，并通过 `handleOpen`、 `handleClose`、`handleConfirm` 等方法控制弹窗。

## 默认行为

- 默认启用 `align-center`
- 默认启用 `destroy-on-close`
- 默认启用 `draggable`
- 默认宽度为 `50%`
- 默认显示“取消”和“确定”按钮
- 确认成功后默认自动关闭
- 关闭完成后默认重置运行时数据和 Loading 状态
- 设置 `contentHeight` 后自动使用 `ElScrollbar`
- 未封装的 `ElDialog` Props、事件和属性可以直接透传

## 配置方式与优先级

所有扩展配置既可以作为组件 Props 长期传入，也可以在每次 `handleOpen` 时覆盖：

```vue
<ArtDialog
  ref="dialogRef"
  width="680px"
  content-height="60vh"
  :show-footer="true"
  :dialog-props="{ appendToBody: true, closeOnClickModal: false }"
  :on-confirm="handleDefaultConfirm"
/>
```

```ts
dialogRef.value?.handleOpen(data, {
  title: '本次打开的标题',
  width: '860px',
  dialogProps: {
    class: 'menu-dialog',
    closeOnClickModal: true
  },
  onConfirm: handleSubmit
})
```

最终优先级：

1. `ArtDialog` 内置默认值
2. 组件上声明的扩展 Props 和原生 `ElDialog` 属性
3. 组件 Props 中的 `dialogProps`
4. `handleOpen` 第二参数
5. `handleOpen.dialogProps` 中的底层属性

`dialogProps`、`contentProps` 会按对象合并，不会因为本次只覆盖一个字段而丢失其他静态配置。

## 基础用法

```vue
<template>
  <ElButton @click="openDialog">打开弹窗</ElButton>

  <ArtDialog ref="dialogRef">
    <template #default="{ data }">
      <ElInput v-model="data.name" placeholder="请输入名称" />
    </template>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'

  interface FormData {
    id?: string
    name: string
  }

  const dialogRef = ref<ArtDialogExpose<FormData>>()

  const openDialog = () => {
    dialogRef.value?.handleOpen(
      { name: '' },
      {
        title: '新增用户',
        width: '600px',
        onConfirm: async (data) => {
          await saveUser(data)
        }
      }
    )
  }
</script>
```

## 推荐的业务组件模式

复杂业务应在业务弹窗组件内部组合 `ArtDialog` 和表单。列表入口只渲染一个业务组件，并通过它暴露的 `handleOpen` 打开。

列表页面：

```vue
<template>
  <UserDialog ref="userDialogRef" @submit="refreshList" />
</template>

<script setup lang="ts">
  import UserDialog from './modules/user-dialog.vue'

  const userDialogRef = ref<{ handleOpen: (data: OpenData) => Promise<void> }>()

  const handleEdit = (row: User) => {
    userDialogRef.value?.handleOpen({ mode: 'edit', editData: row })
  }
</script>
```

业务弹窗组件 `user-dialog.vue`：

```vue
<template>
  <ArtDialog ref="dialogRef">
    <UserForm ref="formRef" />
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'

  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<UserFormExpose>()

  const handleOpen = async (data: OpenData) => {
    await dialogRef.value?.handleOpen(data, {
      title: data.mode === 'edit' ? '编辑用户' : '新增用户',
      width: '760px',
      contentHeight: '65vh',
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

`onConfirm` 返回 `false` 时弹窗不会关闭，适合表单校验失败或接口提交失败的场景。

## 固定内容高度

传入数字时按像素处理，传入字符串时原样使用：

```ts
dialogRef.value?.handleOpen(data, {
  contentHeight: 520
})

dialogRef.value?.handleOpen(data, {
  contentHeight: '70vh',
  scrollbarAlways: true
})
```

没有设置 `contentHeight` 时，不会额外创建 `ElScrollbar`。

## 自定义插槽

```vue
<ArtDialog ref="dialogRef">
  <template #header="{ data, api }">
    <div>{{ data.title }}</div>
  </template>

  <template #default="{ data, api }">
    <BusinessContent :data="data" @close="api.handleClose()" />
  </template>

  <template #footer="{ data, loading, api }">
    <ElButton @click="api.handleClose()">返回</ElButton>
    <ElButton type="primary" :loading="loading" @click="api.handleConfirm()">
      保存
    </ElButton>
  </template>
</ArtDialog>
```

| 插槽      | 参数                     | 说明               |
| --------- | ------------------------ | ------------------ |
| `default` | `data`, `api`            | 默认内容区域       |
| `header`  | `data`, `api`            | 自定义标题区域     |
| `footer`  | `data`, `loading`, `api` | 自定义底部操作区域 |

设置 `showFooter: false` 可以完全隐藏 Footer。

## 动态内容组件

内容也可以在 `handleOpen` 时动态传入：

```ts
import UserDetail from './user-detail.vue'

dialogRef.value?.handleOpen(user, {
  title: '用户详情',
  content: UserDetail,
  contentProps: {
    readonly: true
  },
  showFooter: false
})
```

动态组件会收到：

- `data`：本次 `handleOpen` 传入的数据
- `dialogApi`：当前弹窗的全部操作 API
- `contentProps`：业务传入的其他 Props

## ArtDialogOptions

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `title` | `string` | `''` | 标题 |
| `width` | `string \| number` | `'50%'` | 弹窗宽度 |
| `contentHeight` | `string \| number` | `undefined` | 内容固定高度，设置后启用滚动条 |
| `showFooter` | `boolean` | `true` | 是否显示 Footer |
| `showCancelButton` | `boolean` | `true` | 是否显示取消按钮 |
| `showConfirmButton` | `boolean` | `true` | 是否显示确定按钮 |
| `cancelText` | `string` | `'取消'` | 取消按钮文字 |
| `confirmText` | `string` | `'确定'` | 确定按钮文字 |
| `confirmDisabled` | `boolean` | `false` | 是否禁用确定按钮 |
| `autoClose` | `boolean` | `true` | 确认成功后是否自动关闭 |
| `resetOnClose` | `boolean` | `true` | 关闭完成后是否重置 |
| `closeOnConfirmError` | `boolean` | `false` | 确认回调抛错时是否强制关闭 |
| `scrollbarAlways` | `boolean` | `false` | 是否始终显示滚动条 |
| `nativeScrollbar` | `boolean` | `false` | 是否使用原生滚动条 |
| `content` | `Component` | `undefined` | 动态内容组件 |
| `contentProps` | `Record<string, unknown>` | `undefined` | 动态内容组件 Props |
| `dialogProps` | `ElDialog Props` | `undefined` | 本次打开额外传入的 `ElDialog` 配置 |
| `onOpen` | `(data, api) => void` | `undefined` | 打开后、内容挂载后的回调 |
| `onConfirm` | `(data, api) => boolean \| void` | `undefined` | 确认回调，支持 Promise |
| `onClose` | `(data, api) => boolean \| void` | `undefined` | 调用 `handleClose` 前的拦截回调 |
| `onReset` | `(api) => void` | `undefined` | 重置回调 |

## Ref 方法

| 方法                          | 说明                                    |
| ----------------------------- | --------------------------------------- |
| `handleOpen(data?, options?)` | 打开弹窗并传入本次数据和配置            |
| `handleClose(force?)`         | 关闭弹窗；`force=true` 时跳过 `onClose` |
| `handleConfirm()`             | 主动执行确认流程                        |
| `handleReset()`               | 恢复打开时的数据并清除 Loading          |
| `setLoading(value)`           | 设置内容区域 Loading                    |
| `setConfirmLoading(value)`    | 设置确定按钮 Loading                    |
| `setOptions(options)`         | 在弹窗打开期间增量修改配置              |
| `setData(data)`               | 替换当前数据                            |
| `updateData(data)`            | 浅合并当前对象数据                      |
| `getData()`                   | 获取当前数据                            |
| `getDialogInstance()`         | 获取底层 `ElDialog` 实例                |
| `scrollTo(options)`           | 控制内容滚动位置                        |

## 事件

支持 `open`、`opened`、`close`、`closed`、`open-auto-focus`、 `close-auto-focus` 等 `ElDialog` 生命周期事件，另外提供：

| 事件      | 参数      | 说明                 |
| --------- | --------- | -------------------- |
| `confirm` | 当前数据  | 开始执行确认流程     |
| `reset`   | 无        | 数据重置完成         |
| `error`   | `unknown` | `onConfirm` 抛出异常 |

## ElDialog API 透传

静态属性可以直接写在组件上：

```vue
<ArtDialog
  ref="dialogRef"
  append-to-body
  :close-on-click-modal="false"
  :close-on-press-escape="false"
/>
```

单次打开配置建议放到 `dialogProps`：

```ts
dialogRef.value?.handleOpen(data, {
  dialogProps: {
    appendToBody: true,
    closeOnClickModal: false,
    closeOnPressEscape: false,
    fullscreen: false
  }
})
```

优先级为：组件默认值、静态透传属性、`dialogProps`、`ArtDialogOptions` 中的核心配置。

## 使用建议

- 列表页面只维护业务弹窗 Ref，不直接组合 `ArtDialog` 和业务表单
- 表单校验失败时让 `onConfirm` 返回 `false`
- 接口异常建议在业务层提示，并返回 `false` 保持弹窗
- 大表单统一设置 `contentHeight: '70vh'`
- 多种业务内容共用一个弹窗时使用动态 `content`
- 需要完全自定义操作区时使用 `#footer`
- 通用默认配置放组件 Props，业务场景差异放 `handleOpen` 第二参数
