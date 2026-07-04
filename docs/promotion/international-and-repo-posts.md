# Art Supabase Pro: Repo and International Posting Pack

## Gitee Dynamic

### Title

Art Supabase Pro 升级：新增 AI SQL、车辆管理系统、TMS 运输管理系统

### Content

Art Supabase Pro 最近做了一轮比较大的升级。

这是一个基于 Vue 3、TypeScript、Element Plus、Supabase 的开源企业中后台模板，目标是作为可直接二次开发的企业应用样板工程，而不是只停留在 UI 页面展示。

这次重点新增和完善了：

- AI SQL 助手：自然语言生成 PostgreSQL，结合 schema 摘要减少表名、字段名猜测，支持 SQL 修复和错误定位
- 车辆管理系统：车辆档案、保险、年检、维修保养、事故、里程、例检、配件、到期提醒等
- TMS 运输管理系统：客户、承运商、司机、合同、价格、站点、订单、运单、配载、在途监控等
- 司机端相关能力也在持续完善

项目地址：

- 在线演示：https://869123771.github.io/art-supabase-pro/
- Gitee：https://gitee.com/wangyanghub/art-supabase-pro
- GitHub：https://github.com/869123771/art-supabase-pro

欢迎 Star、Fork、Issue，也欢迎一起交流 Supabase 在中后台、AI SQL、TMS、车辆管理这些场景里的落地方式。

### Tags

Vue3, Supabase, AI SQL, 开源, 中后台, TMS, 车辆管理

## GitHub Release

### Release Title

Art Supabase Pro: AI SQL Assistant, Vehicle Management and TMS Modules

### Tag Suggestion

v1.1.0

### Description

Art Supabase Pro has evolved from a general Vue 3 admin template into a more practical enterprise application starter built with Vue 3, TypeScript, Element Plus, Supabase, and an AI SQL assistant.

This release focuses on making the project more useful for real business scenarios and secondary development.

## Highlights

- Added AI SQL assistant for Supabase/PostgreSQL.
- Added SQL workbench features based on Monaco Editor.
- Added vehicle management modules.
- Added TMS transportation management modules.
- Added driver-side related capabilities.
- Improved project positioning for enterprise admin, TMS, vehicle management, and internal tool scenarios.
- Added `llms.txt` to help AI tools better identify the project purpose, stack, modules, and links.

## AI SQL Assistant

The SQL workbench can generate PostgreSQL from natural language prompts, use database schema summaries to reduce hallucinated table and column names, and help fix SQL errors.

The model call is wrapped through the Supabase Edge Function `ai-sql-assistant`, making it easier to switch model providers later.

## Vehicle Management

Vehicle-related modules include:

- Vehicle archives
- Vehicle entry, edit, audit, and detail view
- Insurance companies, suppliers, parts, and part categories
- Vehicle insurance
- Vehicle inspection
- Maintenance records
- Accident records
- Mileage records
- Routine inspection records
- Part usage and expiry reminders
- Insurance, inspection, maintenance, and vehicle lifetime reminders

## TMS Transportation Management

TMS modules include:

- Customers and customer addresses
- Customer pricing
- Carriers and carrier pricing
- Driver management
- Cargo records
- Contract management
- Station management
- Order creation
- Order list
- Waybill management
- Dispatching and batch dispatching
- Delivery management
- In-transit monitoring

## Links

- Demo: https://869123771.github.io/art-supabase-pro/
- GitHub: https://github.com/869123771/art-supabase-pro
- Gitee: https://gitee.com/wangyanghub/art-supabase-pro

## GitHub Discussion

### Title

Open-sourcing Art Supabase Pro: a Vue 3 + Supabase enterprise admin starter with AI SQL, vehicle management, and TMS modules

### Content

Hi everyone,

I am building and open-sourcing **Art Supabase Pro**, an enterprise admin application starter built with Vue 3, TypeScript, Element Plus, Supabase, and an AI SQL assistant.

The project started as a practical Vue + Supabase admin template, but it is now becoming a more complete enterprise application starter for real business systems.

It includes:

- Supabase Auth, Database, Storage, RPC, and Edge Functions integration
- RBAC permissions with menu-level and button-level access control
- User, role, menu, dictionary, attachment, and system management modules
- SQL workbench based on Monaco Editor
- AI SQL assistant for PostgreSQL/Supabase
- Vehicle management modules
- TMS transportation management modules
- Driver-side related capabilities
- Dynamic tables, forms, dialogs, drawers, selectors, import/export, themes, and i18n

The AI SQL assistant can generate PostgreSQL from natural language prompts, use database schema summaries to reduce hallucinated table/column names, and help fix SQL errors inside the SQL workbench.

The latest modules focus on real business workflows:

- Vehicle management: vehicle archives, insurance, inspections, maintenance, accidents, mileage, parts, and expiry reminders
- TMS: customers, carriers, drivers, contracts, pricing, stations, orders, waybills, dispatching, delivery, and in-transit monitoring

Links:

- Demo: https://869123771.github.io/art-supabase-pro/
- GitHub: https://github.com/869123771/art-supabase-pro
- Gitee: https://gitee.com/wangyanghub/art-supabase-pro

I would love to hear feedback from people building internal tools, TMS systems, vehicle/fleet management systems, or Supabase-based business applications.

## DEV.to / Hashnode

### Title

Building an Open-Source Vue 3 + Supabase Enterprise Admin Starter with AI SQL, Vehicle Management, and TMS

### Tags

vue, supabase, opensource, postgresql

### Content

I have been building an open-source project called **Art Supabase Pro**.

It started as a Vue 3 + TypeScript + Element Plus + Supabase admin template, but it is now evolving into a more practical enterprise application starter for real business systems.

The goal is simple: instead of starting every internal tool from scratch, developers can begin with authentication, RBAC permissions, menu management, data dictionaries, attachments, SQL tools, reusable admin components, and real business modules already connected together.

## Tech Stack

- Vue 3
- TypeScript
- Vite
- Element Plus
- Pinia
- Vue Router
- Supabase Auth / Database / Edge Functions
- PostgreSQL
- Monaco Editor
- ECharts
- Tailwind CSS / SCSS
- Vue I18n

## Core Features

Art Supabase Pro includes:

- Login, registration, password recovery, and JWT authentication
- User, role, and menu management
- RBAC permissions with menu-level and button-level access control
- Data dictionary and attachment management
- SQL workbench
- AI-generated PostgreSQL
- Dynamic tables and forms
- Dialogs, drawers, selectors, and resource pickers
- Excel import/export
- Themes, layout switching, global search, and WorkTab navigation
- Chinese and English i18n

## AI SQL Assistant

One of the most interesting parts is the SQL workbench.

It is not only a SQL input box. It is designed around Supabase/PostgreSQL and includes:

- Monaco SQL editor
- PostgreSQL editing experience
- Database metadata reading
- Table, column, and function awareness
- JOIN inference
- SQL formatting
- SQL execution result table
- Error location
- AI SQL generation
- AI SQL repair

The AI SQL assistant sends a schema summary with the prompt, so the model can generate SQL based on the real database structure instead of guessing table or column names. The model call is wrapped in a Supabase Edge Function named `ai-sql-assistant`.

## Vehicle Management

The project now includes vehicle management modules such as:

- Vehicle archives
- Vehicle entry, edit, audit, and detail view
- Insurance companies, suppliers, parts, and part categories
- Vehicle insurance and inspections
- Maintenance, accident, mileage, and routine inspection records
- Part usage and expiry reminders
- Insurance, inspection, maintenance, and vehicle lifetime reminders

## TMS Transportation Management

The TMS modules include:

- Customers and customer addresses
- Customer pricing
- Carriers and carrier pricing
- Driver management
- Cargo records
- Contract management
- Station management
- Order creation and order list
- Waybill management
- Dispatching and batch dispatching
- Delivery management
- In-transit monitoring

## Links

- Demo: https://869123771.github.io/art-supabase-pro/
- GitHub: https://github.com/869123771/art-supabase-pro
- Gitee: https://gitee.com/wangyanghub/art-supabase-pro

If you are building internal tools, admin dashboards, TMS systems, vehicle management systems, or Supabase-based business applications, feedback and suggestions are welcome.

## Hacker News

### Title

Show HN: Art Supabase Pro – Vue 3 + Supabase admin starter with AI SQL and TMS modules

### URL

https://github.com/869123771/art-supabase-pro

### Text Alternative

I built an open-source enterprise admin starter with Vue 3, TypeScript, Element Plus, Supabase, and an AI SQL assistant.

It includes auth, RBAC permissions, menu/user/role management, data dictionaries, attachments, SQL workbench, AI-generated PostgreSQL, vehicle management modules, TMS transportation management modules, and driver-side related capabilities.

The AI SQL assistant uses database schema summaries to reduce hallucinated table/column names and calls the model through a Supabase Edge Function.

Demo: https://869123771.github.io/art-supabase-pro/
GitHub: https://github.com/869123771/art-supabase-pro

## Reddit

### Suggested Subreddits

- r/Supabase
- r/vuejs
- r/webdev
- r/opensource

### Title

I built an open-source Vue 3 + Supabase enterprise admin starter with AI SQL, vehicle management, and TMS modules

### Content

Hi everyone,

I am working on an open-source project called **Art Supabase Pro**.

It is an enterprise admin application starter built with Vue 3, TypeScript, Element Plus, Supabase, PostgreSQL, and an AI SQL assistant.

The project includes:

- Supabase Auth / Database / Edge Functions integration
- RBAC permissions
- User, role, menu, dictionary, and attachment management
- SQL workbench based on Monaco Editor
- AI SQL assistant for PostgreSQL/Supabase
- Vehicle management modules
- TMS transportation management modules
- Driver-side related capabilities

The AI SQL assistant can generate PostgreSQL from natural language prompts, use database schema summaries to reduce hallucinated table and column names, and help fix SQL errors.

Vehicle modules include vehicle archives, insurance, inspections, maintenance, accidents, mileage, parts, and expiry reminders.

TMS modules include customers, carriers, drivers, contracts, pricing, stations, orders, waybills, dispatching, delivery, and in-transit monitoring.

Links:

- Demo: https://869123771.github.io/art-supabase-pro/
- GitHub: https://github.com/869123771/art-supabase-pro
- Gitee: https://gitee.com/wangyanghub/art-supabase-pro

I would appreciate feedback from developers building internal tools, fleet/vehicle management systems, TMS systems, or Supabase-based business apps.

## Supabase GitHub Discussion

### Title

Art Supabase Pro: open-source Vue 3 enterprise admin starter using Supabase, AI SQL, vehicle management, and TMS

### Content

Hi Supabase community,

I am building an open-source project called **Art Supabase Pro**.

It is a Vue 3 + TypeScript + Element Plus enterprise admin starter that uses Supabase as the backend foundation.

Supabase is used for:

- Authentication
- PostgreSQL database access
- RPC
- Edge Functions
- Storage-related business integration

The project includes common enterprise admin features such as RBAC permissions, menu management, users, roles, dictionaries, attachments, dynamic tables/forms, and a SQL workbench.

The part I am currently focusing on is an **AI SQL assistant for Supabase/PostgreSQL**. It reads database metadata, builds a schema summary, and sends that context to an Edge Function called `ai-sql-assistant` to generate or repair SQL.

The latest version also adds business modules:

- Vehicle management system
- TMS transportation management system
- Driver-side related capabilities

Links:

- Demo: https://869123771.github.io/art-supabase-pro/
- GitHub: https://github.com/869123771/art-supabase-pro
- Gitee: https://gitee.com/wangyanghub/art-supabase-pro

I would love to hear feedback on Supabase architecture, RLS design, Edge Function usage, and practical patterns for building enterprise admin systems with Supabase.

## Product Hunt Short Copy

### Name

Art Supabase Pro

### Tagline

Open-source Vue 3 + Supabase enterprise admin starter with AI SQL, vehicle management, and TMS modules.

### Description

Art Supabase Pro is an open-source enterprise admin starter built with Vue 3, TypeScript, Element Plus, Supabase, PostgreSQL, and an AI SQL assistant.

It includes authentication, RBAC permissions, user/role/menu management, data dictionaries, attachments, dynamic tables/forms, SQL workbench, AI-generated PostgreSQL, vehicle management modules, TMS transportation management modules, and driver-side related capabilities.

The AI SQL assistant uses database schema summaries to reduce hallucinated table and column names and helps generate or repair SQL through a Supabase Edge Function.

### Links

- Demo: https://869123771.github.io/art-supabase-pro/
- GitHub: https://github.com/869123771/art-supabase-pro
- Gitee: https://gitee.com/wangyanghub/art-supabase-pro
