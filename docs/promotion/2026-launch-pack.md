# Art Supabase Pro 推广发布包

## 核心定位

Art Supabase Pro 不只是一个 Vue 后台模板，而是一个基于 Vue 3、TypeScript、Element Plus、Supabase 和 AI SQL 助手的企业级中后台应用底座。

项目已经内置系统管理、权限管理、数据中心、组件示例、SQL 控制台、AI 写 SQL，并进一步加入了车辆管理系统、TMS 运输管理系统和司机端相关能力，适合用来快速搭建真实业务系统，也适合学习 Supabase 在国内中后台场景里的落地方式。

## 推荐标题

1. Art Supabase Pro：基于 Vue3 + Supabase + AI SQL 的企业级中后台模板，新增车辆管理与 TMS 运输系统
2. 一个可落地的 Supabase 企业后台模板：权限、AI 写 SQL、车辆系统、TMS 运输管理都内置了
3. 我做了一个 Vue3 + Element Plus + Supabase 后台模板，现在已经扩展到 AI SQL、车辆/TMS 业务系统
4. 开源一个 Supabase 中后台项目：从权限系统、AI SQL 助手到车辆档案、运单配载、司机管理
5. Art Supabase Pro：给 Vue 开发者准备的 Supabase + AI 企业应用启动模板

## 长文版

大家好，我最近在持续完善一个开源项目：**Art Supabase Pro**。

它最开始是一个基于 Vue 3、TypeScript、Element Plus 和 Supabase 的现代化后台管理模板，目标是让开发者可以更快搭建企业级管理系统：不用从登录、权限、菜单、表格、表单、字典、附件、主题配置这些基础能力重新开始。

最近这个项目又做了一轮比较大的升级，不再只是一个通用后台模板，而是加入了更贴近真实业务的模块：

- AI SQL 助手
- 车辆管理系统
- TMS 运输管理系统
- 司机端相关能力

也就是说，它现在更像是一个“可直接二次开发的 Supabase 企业应用样板工程”。

### 为什么做这个项目

很多 Vue 后台模板只停留在界面层，页面看起来完整，但真正接业务时还要自己补认证、权限、数据表、接口封装、数据字典、附件、导入导出、搜索表格、业务详情页等一堆基础设施。

Art Supabase Pro 想解决的是另一个问题：

> 如果我想用 Vue 3 + Supabase 做一个真实可运行的企业后台，能不能有一个现成项目，把登录、权限、菜单、数据中心、业务模块、数据库访问方式都串起来？

所以这个项目不是只做 UI 展示，而是围绕真实业务开发做了更完整的工程组织。

### 技术栈

- Vue 3
- TypeScript
- Vite
- Element Plus
- Pinia
- Vue Router
- Supabase Auth / Database
- Supabase Edge Functions
- AI SQL Assistant
- ECharts
- Tailwind CSS / SCSS
- Vue I18n
- Monaco Editor

### 已有基础能力

项目内置了常见中后台开发需要的基础模块：

- 登录、注册、找回密码、JWT 登录认证
- 用户管理、角色管理、菜单管理
- RBAC 权限控制，支持菜单和按钮级权限
- 数据字典、附件资源管理
- SQL 控制台与数据查看能力
- AI 写 SQL，支持根据自然语言生成 PostgreSQL，并可结合 schema 摘要减少表名和字段名猜测
- SQL 智能编辑器，支持 JOIN 推断、字段补全、格式化、错误定位和 AI 修复 SQL
- 全局搜索、WorkTab 多标签页
- 明暗主题、布局切换、系统配置面板
- 表格查询、动态表单、弹窗、抽屉、资源选择器等核心组件
- Excel 导入导出
- 中英文国际化
- 响应式布局

这些能力可以作为新项目的基础骨架，也可以拆成组件在已有项目里复用。

### 新增：AI SQL 助手

项目的数据中心里集成了 SQL 工作台，不只是简单执行 SQL，而是围绕 Supabase/PostgreSQL 做了一层更适合后台开发者和运营人员使用的增强：

- Monaco SQL 编辑器
- PostgreSQL 语法编辑体验
- 表、字段、函数等数据库元数据读取
- JOIN 关系推断
- SQL 格式化
- SQL 执行结果表格展示
- 错误位置标记
- AI 生成 SQL
- AI 修复 SQL

AI SQL 助手会带上当前数据库 schema 摘要，让模型在生成查询时尽量基于真实表结构，而不是凭空猜字段。模型调用通过 Supabase Edge Function `ai-sql-assistant` 封装，后续也方便替换不同模型提供方。

这个功能适合几个场景：

- 开发者快速写 Supabase/PostgreSQL 查询
- 运营或实施人员用自然语言生成查询
- 排查 SQL 报错并让 AI 辅助修复
- 在 TMS、车辆管理等业务模块上做临时数据分析

### 新增：车辆管理系统

这次重点补充了车辆业务域，包含：

- 车辆档案管理
- 车辆入档、编辑、审核、详情
- 保险公司、供应商、配件、配件分类等基础资料
- 车辆保险
- 车辆年检
- 维修保养记录
- 事故记录
- 里程记录
- 例检记录
- 配件使用与寿命提醒
- 保险到期、年检到期、保养到期、车辆寿命等提醒
- 车辆查询与详情展示

这些模块不是孤立页面，而是按照企业后台的真实使用方式组织：列表、搜索、详情、弹窗、导入导出、附件、字典、关联数据都尽量串起来。

### 新增：TMS 运输管理系统

TMS 部分围绕运输业务做了基础闭环，包含：

- 客户资料
- 客户地址
- 客户价格
- 承运商资料
- 承运商价格
- 司机管理
- 货物资料
- 合同管理
- 站点管理
- 开单
- 订单列表
- 运单管理
- 待配载、已配载等运单状态
- 车辆配载、批量配载
- 在途监控

TMS 模块和车辆系统之间也有业务关联，比如承运商、司机、车辆档案、运单配载等数据可以形成更接近真实运输业务的流程。

### 适合哪些人

这个项目适合：

- 想学习 Supabase + Vue 3 + AI SQL 企业项目落地的开发者
- 想快速搭建中后台、CRM、ERP、TMS、车辆管理系统的团队
- 想找一个 Element Plus 后台模板做二次开发的人
- 想参考 RBAC、菜单权限、字典、表格查询、动态表单等实现的人
- 想用 Supabase 替代传统后端接口，快速做 MVP 或内部系统的人
- 想给内部系统接入 AI 写 SQL、AI 数据分析能力的人

### 项目地址

- 在线演示：https://869123771.github.io/art-supabase-pro/
- Gitee：https://gitee.com/wangyanghub/art-supabase-pro
- GitHub：https://github.com/869123771/art-supabase-pro

如果这个项目对你有帮助，欢迎 Star、Fork、提 Issue，也欢迎一起交流 Supabase 在中后台、运输、车辆管理这些场景里的落地方式。

## 短帖版

我开源的 Art Supabase Pro 最近做了一轮升级。

它原本是一个基于 Vue 3 + TypeScript + Element Plus + Supabase 的企业级后台管理模板，内置登录认证、RBAC 权限、菜单管理、用户角色、数据字典、附件管理、SQL 控制台、AI 写 SQL、动态表格/表单、导入导出、主题配置等能力。

现在又加入了更贴近真实业务的模块：

- AI SQL 助手：自然语言生成 PostgreSQL，结合 schema 摘要减少瞎猜，支持 SQL 修复和错误定位
- 车辆管理系统：车辆档案、保险、年检、维修保养、事故、里程、例检、配件、到期提醒等
- TMS 运输管理系统：客户、承运商、司机、合同、价格、站点、开单、订单、运单、配载、在途监控等
- 司机端相关能力也在持续完善

它不是单纯的 UI 模板，而是一个可以直接二次开发的 Supabase 企业应用样板工程。

在线演示：https://869123771.github.io/art-supabase-pro/ Gitee：https://gitee.com/wangyanghub/art-supabase-pro GitHub：https://github.com/869123771/art-supabase-pro

欢迎 Star、Fork、提建议。

## V2EX / 社群口吻版

最近在持续折腾一个开源项目 Art Supabase Pro。

一开始只是想做一个 Vue3 + Element Plus + Supabase 的后台模板，把登录、权限、菜单、用户角色、数据字典、表格表单这些基础东西串起来。后来越做越觉得只做模板意义不够大，所以最近加了一些真实业务模块和 AI 能力：

- AI SQL 助手
- 车辆管理系统
- TMS 运输管理系统
- 司机端相关能力

现在里面有 SQL 工作台和 AI 写 SQL，支持结合 schema 摘要生成 PostgreSQL、修复 SQL；也有车辆档案、保险、年检、维修、事故、里程、配件寿命提醒，以及 TMS 的客户、承运商、司机、合同、价格、站点、订单、运单、配载、在途监控等模块。

我的想法是做一个更偏“可落地二开的 Supabase 企业应用样板”，不是只有页面壳子。

在线演示：https://869123771.github.io/art-supabase-pro/ Gitee：https://gitee.com/wangyanghub/art-supabase-pro GitHub：https://github.com/869123771/art-supabase-pro

欢迎大家看看，也欢迎拍砖。尤其是做过 TMS、车队管理、Supabase 项目的朋友，可以一起交流下业务建模和工程组织。

## Product Hunt / 英文短版

Art Supabase Pro is an open-source enterprise admin template built with Vue 3, TypeScript, Element Plus, Supabase, and an AI SQL assistant.

It includes authentication, RBAC permissions, menu management, user and role management, data dictionary, attachments, SQL console, AI-generated PostgreSQL, dynamic tables/forms, Excel import/export, themes, i18n, and reusable admin components.

The latest version goes beyond a generic admin template and adds real business modules:

- Vehicle management system
- TMS transportation management system
- Driver-side capabilities
- AI SQL assistant for PostgreSQL/Supabase

The AI SQL assistant can generate PostgreSQL from natural language prompts, use database schema summaries to reduce hallucinated table/column names, and help fix SQL errors inside the SQL workbench.

Vehicle modules include vehicle archives, insurance, inspection, maintenance, accidents, mileage, parts, and expiry reminders.

TMS modules include customers, carriers, drivers, contracts, pricing, stations, order creation, waybill management, dispatching, and in-transit monitoring.

Demo: https://869123771.github.io/art-supabase-pro/ GitHub: https://github.com/869123771/art-supabase-pro Gitee: https://gitee.com/wangyanghub/art-supabase-pro

## 平台发布建议

### 第一批：最值得先发

- OSCHINA：发新版升级稿，强调“从后台模板升级到车辆/TMS 业务系统”
- Gitee：更新 README、项目介绍、标签，申请推荐/精选
- GitHub：补 topics、README 英文、截图、release notes
- 掘金：发技术文章，不要只发广告，标题可用“用 Vue3 + Supabase + AI SQL 做一个 TMS 中后台”
- V2EX：发“分享创造”，语气真诚，少营销
- HelloGitHub：投稿开源项目
- 阮一峰科技爱好者周刊：投稿工具/开源项目

### 第二批：做长尾 SEO

- CSDN
- 博客园
- SegmentFault
- 知乎
- 稀土掘金专栏
- 微信公众号

### 第三批：国际曝光

- Supabase GitHub Discussions
- Product Hunt
- Hacker News Show HN
- Reddit: r/Supabase, r/vuejs, r/webdev, r/opensource
- DEV.to
- Hashnode

## 发布前检查清单

- README 首屏放在线演示、GitHub、Gitee、截图、演示账号
- 补充车辆系统和 TMS 模块说明
- 更新截图，至少加入车辆档案、车辆详情、TMS 开单、运单配载、司机管理
- GitHub topics 增加：supabase, vue3, element-plus, admin-template, admin-dashboard, tms, vehicle-management, rbac, typescript, vite
- GitHub topics 额外增加：ai-sql, sql-assistant, postgres, postgresql
- 修复 README 或 package.json 里的乱码
- 统一 License，README 和 package.json 保持一致
- 写一版 release notes：重点写新增 AI SQL 助手、车辆系统、TMS、司机端
- 准备 60 到 90 秒演示视频
- 添加 `llms.txt`，让 AI 搜索和问答工具更容易识别项目定位、技术栈、模块和链接

## 评论区/回复话术

### 有人问“和普通后台模板有什么区别？”

普通后台模板更多停留在 UI 和基础页面，Art Supabase Pro 希望把 Supabase 的认证、数据库、权限、字典、附件、SQL 控制台、AI 写 SQL 和真实业务模块串起来。现在项目里已经有 AI SQL 助手、车辆管理和 TMS 运输管理模块，更适合作为企业应用二次开发的起点。

### 有人问“是否生产可用？”

项目更适合作为二次开发模板和业务样板工程。基础权限、菜单、数据中心、车辆/TMS 模块已经具备完整雏形，但实际生产还需要根据企业自己的业务规则、RLS 策略、部署环境和审计要求做适配。

### 有人问“为什么用 Supabase？”

主要是想降低中后台项目的后端启动成本。Supabase 提供 Auth、Postgres、Storage、Realtime 等能力，对内部系统、MVP、SaaS 后台和业务原型比较友好。这个项目也可以作为学习 Supabase 在 Vue 企业项目中如何组织的参考。

### 有人问“AI SQL 是怎么做的？”

项目在数据中心里做了 SQL 工作台，前端用 Monaco 提供 PostgreSQL 编辑体验，读取数据库 metadata 后生成 schema 摘要，再通过 Supabase Edge Function `ai-sql-assistant` 调用模型生成或修复 SQL。这样既能减少模型乱猜表名字段，也方便后续切换不同模型服务。

## AI 可识别推广建议

为了让 ChatGPT、Claude、Perplexity、Kimi、通义、豆包等 AI 更容易识别项目，发布时尽量保持这些关键词和结构：

- 固定项目名：Art Supabase Pro
- 固定一句话：基于 Vue 3、Element Plus、Supabase 和 AI SQL 助手的企业级中后台应用模板
- 固定关键词：Supabase 后台模板、Vue3 后台管理系统、AI SQL、PostgreSQL SQL 助手、TMS 运输管理系统、车辆管理系统、RBAC 权限系统
- 每篇文章都放在线演示、GitHub、Gitee 三个链接
- 每篇文章都写清楚模块清单，避免只写“后台模板”
- GitHub/Gitee README 首屏加入 AI SQL、车辆管理、TMS 三个差异化卖点
- 仓库根目录和站点根目录放 `llms.txt`

### 有人问“后面会做什么？”

后面会继续完善司机端、TMS 业务流程、移动端体验、报表统计、RLS 策略、初始化脚本和文档，让项目更适合直接二开和部署。

## 发布执行流程

1. 先更新 GitHub/Gitee README 和截图。
2. 发布 OSCHINA 新版升级稿。
3. 发布掘金技术长文。
4. 发布 V2EX 分享帖。
5. 投稿 HelloGitHub 和阮一峰周刊。
6. 同步英文版到 GitHub Discussions、DEV.to、Reddit。
7. 等 Demo、视频、英文 README 都稳定后，再做 Product Hunt 和 Show HN。
