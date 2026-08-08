# GitHub Discussions publishing card

**Recommended category:** Show and tell  
**Title:** Art Supabase Pro: a production-oriented Vue 3 + Supabase platform for TMS, workflows, fleet operations, finance, and governed AI

---

Art Supabase Pro started as an admin application, but it has grown into a production-oriented enterprise platform built with Vue 3 and Supabase.

Instead of stopping at tables, forms, and dashboard widgets, the project connects authentication, tenant isolation, permissions, operational workflows, transportation, fleet management, finance, and AI-assisted business tools into one working system.

- **GitHub:** <https://github.com/869123771/art-supabase-pro>
- **Live demo:** <https://869123771.github.io/art-supabase-pro/>
- **Gitee mirror:** <https://gitee.com/wangyanghub/art-supabase-pro>

## What is included

- **Supabase-native backend:** Auth, PostgreSQL, RLS, Storage, Realtime, RPC, and Edge Functions.
- **Enterprise access control:** multi-tenancy, RBAC, dynamic menus, button-level permissions, and audit boundaries.
- **TMS operations:** order entry, dispatching, loading, in-transit monitoring, delivery, reconciliation, invoicing, payments, and profitability analysis.
- **Fleet lifecycle:** vehicle profiles, drivers, insurance, inspections, violations, accidents, maintenance, mileage, parts, devices, and expiry alerts.
- **Versioned approval workflows:** conditional routing, countersign/any-sign tasks, delegation, transfer, reminders, immutable published versions, callbacks, retries, and audit trails.
- **Governed AI capabilities:** intelligent order extraction, SQL assistance, Supabase project analysis, dispatch recommendations, transport-risk analysis, OCR, financial review, vehicle health, quality metrics, and feedback loops.

## A quick visual tour

### Transportation operations dashboard

The dashboard combines daily orders, loading queues, active shipments, risk items, trends, live transportation status, and vehicle alerts into an action-oriented workspace.

![Transportation operations dashboard](https://raw.githubusercontent.com/869123771/art-supabase-pro/master/screenshort/02-dashboard.png)

### AI-assisted order entry

Operators can paste customer conversations or transportation requests, or upload order images. AI extracts fields, highlights low-confidence values, matches master data, and prepares a draft for human confirmation instead of writing business data directly.

![AI-assisted order entry](https://raw.githubusercontent.com/869123771/art-supabase-pro/master/screenshort/04-ai-order-copilot.png)

### Real-time in-transit monitoring

The monitoring cockpit brings together vehicle positions, routes, progress, alerts, drivers, cargo, and remaining mileage, with quick access to AI-assisted incident analysis and follow-up actions.

![Real-time in-transit monitoring](https://raw.githubusercontent.com/869123771/art-supabase-pro/master/screenshort/05-in-transit-monitor.png)

### Vehicle lifecycle workspace

Each vehicle has a unified profile covering documents, drivers, components, insurance, inspections, violations, accidents, maintenance, mileage, devices, and health analysis.

![Vehicle lifecycle workspace](https://raw.githubusercontent.com/869123771/art-supabase-pro/master/screenshort/06-vehicle-lifecycle.png)

### Approval workflow governance

Published workflow versions remain immutable. Teams can inspect node snapshots and version differences, while restoration creates a new draft instead of rewriting historical approval evidence.

![Approval workflow governance](https://raw.githubusercontent.com/869123771/art-supabase-pro/master/screenshort/08-workflow-governance.png)

### AI operations and quality

The AI operations center tracks usage, success rate, latency, token consumption, capability distribution, OCR and extraction quality, feedback, and failure reasons so AI features can be operated and improved like production services.

![AI operations and quality](https://raw.githubusercontent.com/869123771/art-supabase-pro/master/screenshort/12-ai-operations.png)

## Technology stack

- Vue 3, TypeScript, Vite, Vue Router, Pinia
- Element Plus, SCSS, Tailwind CSS, ECharts, Vue Flow
- Supabase Auth, PostgreSQL, RLS, Realtime, Storage, RPC, Edge Functions
- Monaco Editor, XLSX, File Viewer, Playwright

## Quick start

```bash
git clone https://github.com/869123771/art-supabase-pro.git
cd art-supabase-pro
pnpm install
pnpm dev
```

The project requires Node.js 20.19+ and pnpm 8.8+. Only the Supabase anon key belongs in the frontend; service-role credentials and AI provider secrets must stay behind the server boundary.

## Feedback welcome

I would especially appreciate feedback from maintainers building with Vue or Supabase:

1. Which module would be most useful as a standalone reference: TMS, fleet lifecycle, workflow governance, or AI operations?
2. Which Supabase RLS and multi-tenant patterns would you like to see documented in more detail?
3. What production safeguards do you expect from AI-assisted enterprise workflows?

If the project is useful to you, a star, issue, discussion, or pull request would be greatly appreciated.

中文项目介绍请查看仓库中的 [README.md](../../README.md)。
