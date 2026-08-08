<div align="center">
  <img src="./src/assets/images/common/logo.webp" width="96" alt="Art Supabase Pro Logo" />
  <h1>Art Supabase Pro</h1>
  <p><strong>An enterprise business platform powered by Vue 3 and Supabase</strong></p>
  <p>Connect permissions, data, workflows, transportation, fleet operations, finance, and AI in one production-oriented application.</p>

  <p>
    <a href="https://gitee.com/wangyanghub/art-supabase-pro">Gitee</a>
    ·
    <a href="https://github.com/869123771/art-supabase-pro">GitHub</a>
    ·
    <a href="https://869123771.github.io/art-supabase-pro/">Live Demo</a>
    ·
    <a href="./README.md">简体中文</a>
  </p>
</div>

![Transportation operations dashboard](screenshort/02-dashboard.png)

## Overview

Art Supabase Pro goes beyond a UI-only admin template. It uses Supabase Auth, PostgreSQL, RLS, Storage, Realtime, RPC, and Edge Functions as its backend foundation and provides reusable, real-world enterprise workflows in a Vue 3 application.

The project currently includes:

- Enterprise platform capabilities: authentication, multi-tenancy, RBAC, dynamic menus, button permissions, dictionaries, attachments, system parameters, and audit records.
- End-to-end TMS operations: customers, carriers, drivers, cargo, contracts, stations, order entry, waybills, dispatching, delivery, in-transit monitoring, and financial settlement.
- Vehicle lifecycle management: archives, approval, insurance, inspection, maintenance, accidents, mileage, routine checks, parts, suppliers, and expiry reminders.
- Approval workflows: versioned definitions, conditional nodes, tasks, transfer, delegation, reminders, monitoring, callback compensation, and full audit trails.
- Governed AI capabilities: intelligent order entry, SQL assistant, project assistant, dispatch recommendations, transport anomaly analysis, cost review, profit diagnostics, receivables risk, vehicle health, OCR, and AI operations.

## Product Highlights

### AI-assisted order entry

Convert customer chats, transport instructions, and uploaded order images into a reviewable order draft. AI can extract fields and suggest master-data matches, while the operator remains responsible for the final save.

![AI-assisted order entry](screenshort/04-ai-order-copilot.png)

### Real-time transportation monitoring

Monitor vehicles, routes, progress, alerts, drivers, cargo, and remaining mileage in one operations cockpit, with quick access to AI anomaly analysis and response actions.

![Real-time transportation monitoring](screenshort/05-in-transit-monitor.png)

### Vehicle lifecycle record

Aggregate archives, drivers, parts, insurance, inspections, violations, accidents, maintenance, routine checks, mileage, and devices around a single vehicle.

![Vehicle lifecycle record](screenshort/06-vehicle-lifecycle.png)

### Workflow governance

Published workflow versions remain immutable. Operators can inspect historical node snapshots, version differences, approval tasks, delegations, transfers, SLAs, and callback recovery.

![Approval workspace](screenshort/07-approval-workbench.png)

![Workflow version governance](screenshort/08-workflow-governance.png)

### Supabase project copilot

Browse database objects, views, functions, triggers, RLS policies, and Edge Functions, then ask a read-only project assistant for evidence-based analysis and governance recommendations.

![Supabase project copilot](screenshort/09-supabase-ai-assistant.png)

### Finance and AI operations

Track receivables, payables, collections, payments, invoices, cost review, and transport profit. The AI operations center provides observability for success rates, latency, token usage, capability adoption, quality signals, feedback, and failures.

![Transportation finance workspace](screenshort/11-finance-workbench.png)

![AI operations center](screenshort/12-ai-operations.png)

## Technology Stack

| Category             | Technologies                                                       |
| -------------------- | ------------------------------------------------------------------ |
| Frontend             | Vue 3, TypeScript, Vite, Vue Router, Pinia                         |
| UI and visualization | Element Plus, SCSS, Tailwind CSS, ECharts, Vue Flow                |
| Backend and data     | Supabase, PostgreSQL, RLS, Realtime, Storage, Edge Functions       |
| Editors and files    | Monaco Editor, WangEditor, XLSX, File Viewer, XGPlayer             |
| Quality              | ESLint, Prettier, Stylelint, vue-tsc, Playwright, Node Test Runner |

## Quick Start

Requirements:

- Node.js `>= 20.19.0`
- pnpm `>= 8.8.0`
- A Supabase project

```bash
git clone https://gitee.com/wangyanghub/art-supabase-pro.git
cd art-supabase-pro
pnpm install
```

Configure `.env` or `.env.development`:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_KEY=your-supabase-anon-key

# Optional: required by the in-transit map
VITE_AMAP_KEY=your-amap-key
VITE_AMAP_SECURITY_JS_CODE=your-amap-security-code
```

Run the application:

```bash
pnpm dev
```

Run quality checks and create a production build:

```bash
pnpm check
pnpm build
```

> Only expose the Supabase `anon` key to the frontend. Keep `service_role`, AI provider keys, and other server credentials behind database functions or Edge Functions, and enforce access with RLS.

## License and Credits

Art Supabase Pro is released under the [MIT License](LICENSE).

The project continues to evolve from the excellent [Art Design Pro](https://gitee.com/lingchen163/art-design-pro) project. Thanks to its maintainers and community.
