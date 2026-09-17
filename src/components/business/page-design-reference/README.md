# PageDesignReference

用于标准业务页头中的平台超级管理员个人设计参考标记。组件读取当前稳定路由名，将用户选择的设计特征、备注和不含业务数据的结构化页面特征保存到 `ai_ui_design_reference`。

## 使用边界

- 列表、工作台和模块首页由 `BusinessWorkspaceHeader` 自动接入。
- 创建、编辑、详情和配置页由 `ArtPageHeader` 自动接入。
- 仅平台超级管理员渲染入口并发起请求；数据库 RLS 同样只允许平台超级管理员读写本人记录。
- 登录、异常、iframe、全屏大屏或不应参与设计学习的页面通过页头的 `design-reference="false"` 关闭。
- 组件只保存设计特征，不保存截图、DOM 文本、表格内容或业务记录。

## 独立使用

```vue
<PageDesignReference
  title="工序任务"
  surface-kind="workspace"
  :style-snapshot="{ component: 'BusinessWorkspaceHeader', density: 'compact' }"
/>
```
