# Art Supabase Pro 3.0：用 Vue 3 + Supabase 打造带 AI、TMS 与审批流的企业级后台

很多后台开源项目擅长展示组件，却很难回答一个更实际的问题：拿到项目之后，能不能直接继续做真实业务？

Art Supabase Pro 最近完成了一轮较大的产品化升级。它不再只是 Vue 3 管理后台模板，而是以 Supabase 为后端底座，逐步形成了 TMS 运输、车辆全生命周期、财务结算、审批工作流与 AI 业务能力协同运行的企业级业务中台。

项目地址：<https://gitee.com/wangyanghub/art-supabase-pro>

在线演示：<https://869123771.github.io/art-supabase-pro/>

## 这次升级解决了什么

项目现在重点解决五类问题：

1. 用 Supabase Auth、PostgreSQL、RLS、Storage、Realtime、RPC 和 Edge Functions 承载真实后台业务，而不是只提供 Mock 页面。
2. 用多租户、RBAC、动态菜单和按钮权限控制企业系统的数据与操作边界。
3. 把运输开单、调度、在途、签收、对账、收付款、发票和利润分析串成 TMS 业务闭环。
4. 提供版本化审批流程，让车辆档案、运单费用、发票和结算等业务可以复用同一套审批基础设施。
5. 让 AI 进入具体业务场景，并具备权限边界、运行审计、质量指标和反馈闭环。

## 运输运营工作台

工作台把今日开单、待配载、运输中、风险待处理、订单趋势、实时运输和车辆风险集中在一个页面。它不是单纯的数据大屏，而是面向调度人员的行动入口。

![运输运营工作台](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/02-dashboard.png)

## AI 智能填单

智能填单支持粘贴客户聊天、运输委托等文字资料，也可以上传订单图片。系统会完成字段识别、低置信信息提醒、客户与货物主数据匹配，并给出建档建议。

这里刻意保留了“人做最终确认”的边界：AI 只生成草稿，不会绕过操作人员直接保存订单。

![AI 智能填单](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/04-ai-order-copilot.png)

## 实时在途监控

在途监控采用驾驶舱式布局，同屏展示车辆位置、线路、运输进度、实时报警、司机、货物和剩余里程。异常车辆可以直接进入 AI 研判、联系司机和提醒处置。

![实时在途监控](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/05-in-transit-monitor.png)

## 一车一档

车辆管理已经从简单车辆列表扩展为全生命周期档案。单车详情聚合车辆档案、司机、零部件、保险、年检、违章、事故、维修保养、例检、里程和设备信息，并提供车辆健康研判。

![一车一档](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/06-vehicle-lifecycle.png)

## 审批工作流与版本治理

审批中心包含待我审批、我已处理、我发起、转交、委托、催办和完整轨迹。流程定义采用版本化治理：发布中的版本保持不可变，历史版本可以查看节点快照与差异，恢复时生成新草稿，不会修改已经发生的审批证据。

![审批工作台](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/07-approval-workbench.png)

![流程版本治理](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/08-workflow-governance.png)

## Supabase AI 项目助手

项目助手可以统一浏览 Database、视图、函数、触发器、RLS 和 Edge Functions，并基于项目实时元数据提供只读分析与治理建议。它不会直接执行 SQL 或修改项目，适合普通用户安全使用。

![Supabase AI 项目助手](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/09-supabase-ai-assistant.png)

## 运输财务与 AI 运行治理

财务工作台覆盖应收、应付、回款、付款、核销、开票、费用审核与运输毛利；AI 运行中心则跟踪调用次数、成功率、响应速度、Token 消耗、能力分布、OCR/填单质量、反馈和失败原因。

这让 AI 从“页面上有一个按钮”变成可以运营、评价和持续改进的生产能力。

![运输财务工作台](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/11-finance-workbench.png)

![AI 运行中心](https://gitee.com/wangyanghub/art-supabase-pro/raw/master/screenshort/12-ai-operations.png)

## 技术栈

- Vue 3、TypeScript、Vite、Pinia、Vue Router
- Element Plus、SCSS、Tailwind CSS、ECharts、Vue Flow
- Supabase Auth、PostgreSQL、RLS、Realtime、Storage、RPC、Edge Functions
- Monaco Editor、XLSX、File Viewer、Playwright

## 快速体验

```bash
git clone https://gitee.com/wangyanghub/art-supabase-pro.git
cd art-supabase-pro
pnpm install
pnpm dev
```

运行环境需要 Node.js 20.19+ 和 pnpm 8.8+。前端只应配置 Supabase anon key，service_role 和 AI Provider 密钥必须保留在服务端安全边界。

如果你正在开发 Supabase 管理后台、TMS、车队管理、车辆管理、审批中心或企业 AI 工具，希望这个项目能提供一些可以直接复用的实现思路。

项目地址：<https://gitee.com/wangyanghub/art-supabase-pro>
