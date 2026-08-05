# 项目 UI 一致性规范

## 业务组件边界

业务页面统一使用项目封装组件：

- 弹窗使用 `ArtDialog`，抽屉使用 `ArtDrawer`。
- 列表使用 `ArtTable`；带查询条件和分页的列表优先使用 `ArtTableQuery`。
- 表单使用 `ArtForm`。复杂品牌配置、可视化编排等特殊布局使用 `custom-layout`，校验和 Ref API 仍由 `ArtForm` 承载。
- 登录、注册、示例和组件演示页允许直接使用 Element Plus 原生容器。

运行 `pnpm ui:audit` 可检查业务页面是否重新引入原生 `ElDialog / ElDrawer / ElTable / ElForm / ElDescriptions`，并阻止弹层重新写死像素尺寸。复杂详情值通过 `ArtDescriptions` 的 `render` 配置或具名插槽呈现，不回退到原生详情容器。

## 页面结构

- 标准页面使用 `ArtPageShell` 统一加载、错误、空数据和完成态。
- 页面标题与返回操作使用 `ArtPageHeader`。
- 信息区块使用 `ArtPageSection` 或 `art-card-xs`，避免页面各自定义卡片外观。
- 长编辑页底部操作使用 `ArtStickyActionBar`，主操作保持唯一、明确。
- 详情字段优先使用 `ArtDescriptions`，统一响应式列数、空值、字典、金额和时间格式。

## 视觉令牌

- 间距使用 `--art-space-*`、`--art-page-padding`、`--art-section-padding`。
- 控件、卡片、强调图形、浮层、弹窗圆角分别使用 `--art-control-radius`、`--art-surface-radius`、`--art-feature-radius`、`--art-floating-radius`、`--art-modal-radius`。
- 弹窗和数据选择弹窗使用 `sm / md / lg / xl / full` 尺寸预设，抽屉使用同名预设，只有业务确有必要时才传自定义宽度。
- 内容滚动优先使用 `ElScrollbar` 或 Art 弹层的 `contentHeight / contentMaxHeight`。

## 交互反馈

- 危险确认、普通确认和文本输入通过 `useArtFeedback` 调用：业务原因使用 `promptReason`，普通文本编辑使用 `promptText`；业务页不得直接调用 `ElMessageBox.prompt`。
- 业务确认使用 `confirmAction`，删除类通用场景优先使用 `confirmDelete`；业务页不得直接调用 `ElMessageBox.confirm`。
- 原因输入默认使用统一 textarea、200 字上限和非空校验；特殊场景通过 Hook 参数调整初始值、最大字数或是否允许留空。
- 异步页面必须覆盖加载、错误、空数据和成功反馈，不用空白区域表达状态。
- 操作按钮按“主操作、次操作、危险操作”排序；同一区域只保留一个主按钮。

## 提交前检查

```bash
pnpm ui:audit
pnpm typecheck
pnpm lint
```

涉及布局或样式的修改还需在真实浏览器中检查桌面宽屏、常规笔记本和窄屏三种尺寸。
