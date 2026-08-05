# Supabase source of truth

This directory contains the deployable Supabase project assets for `ckbftoopuyophiebamwy`.

- `functions/` contains the source downloaded from the deployed project. Deploy a reviewed change with `supabase functions deploy <name> --project-ref ckbftoopuyophiebamwy --use-api`.
- `migrations/` is reserved for the baseline schema and every future database change. Do not edit production schema manually after the baseline is committed.

## Baseline migration

The initial migration must be generated from the currently linked remote project with `supabase db pull <baseline-name> --linked`. The Supabase CLI requires the remote database password for that operation, so this repository intentionally does not contain a guessed schema snapshot.

After the baseline exists, validate every database change with a local reset and add the matching RLS coverage before deployment.

## AI project planner

The `ai-project-planner` Edge Function powers **System management → AI project planner**.
Application users still authenticate with Supabase JWT; model access is server-to-server through an
OpenAI-compatible provider. Configure `AI_API_KEY`, `AI_BASE_URL`, and `AI_MODEL` in Edge Function
Secrets. The key is never stored in a browser or database. `OPENAI_*` aliases remain supported for a
reversible provider switch.

Refresh the repository facts after meaningful code changes, then deploy the reviewed function:

```powershell
pnpm snapshot:ai
supabase functions deploy ai-project-planner --project-ref ckbftoopuyophiebamwy --use-api
```

For NVIDIA NIM, set `AI_BASE_URL=https://integrate.api.nvidia.com/v1` and choose an available model
ID from AI Configuration Center. A Codex or ChatGPT login session is not used as an application API
credential.

## AI dispatch advisor

The `ai-dispatch-advisor` Edge Function powers the advisory panel in the TMS waybill dispatch
dialog. It ranks eligible vehicles and primary drivers with deterministic, auditable rules covering
current assignment conflicts, approved load capacity, route experience, punctuality, and license
validity. The function reads business data through the caller's JWT and RLS policies; it never writes
dispatch state. A dispatcher must explicitly adopt a recommendation and submit the existing dispatch
form.

Apply the matching dictionary migration and deploy the function before enabling the UI in a shared
environment:

```powershell
supabase db push
supabase functions deploy ai-dispatch-advisor --project-ref ckbftoopuyophiebamwy --use-api
```

## AI transport anomaly advisor

The `ai-transport-anomaly-advisor` Edge Function powers the advisory drawer in the TMS in-transit
monitor. It evaluates arrival and departure deadlines, stale business records, missing transport
resources or schedule data, and order/waybill status mismatches. Reads use the caller's JWT and RLS
policies, while the result is recorded in `ai_run` for auditability.

The advisor is read-only: it does not update orders, waybills, schedules, or reminder state. Because
the current project has no continuous GPS telemetry source, it explicitly does not claim real route
deviation or physical vehicle stoppage.

Apply the dictionary migration and deploy the reviewed function before enabling the UI in a shared
environment:

```powershell
supabase db push
supabase functions deploy ai-transport-anomaly-advisor --project-ref ckbftoopuyophiebamwy --use-api
```

## Complete backup and restore

From the repository root, run:

```powershell
.\supabase\backup-supabase.ps1
```

It prompts for the database password and writes a timestamped backup beneath `supabase/backups/`. The backup folder is ignored by Git because it contains database data and uploaded files. Docker Desktop must be installed and running: the Supabase CLI runs `pg_dump` in a Docker container.

To restore into a **new, empty** Supabase project:

```powershell
.\supabase\restore-supabase.ps1 -BackupPath '.\supabase\backups\YYYYMMDD-HHMMSS' -TargetProjectRef '<new-project-ref>'
```

The restore script asks for the target database password, requires an explicit confirmation, and refuses a non-empty public schema by default. Database roles, schema (including views, functions, triggers, RLS, policies, and grants), data, Storage files, and Edge Function source/JWT settings are restored. Secret values and dashboard-only settings cannot be exported by Supabase and must be entered again after restore.
