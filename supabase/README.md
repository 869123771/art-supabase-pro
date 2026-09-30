# Supabase source of truth

中文的远端备份与跨项目恢复操作说明见 [README.zh-CN.md](README.zh-CN.md)。

This is the only Supabase directory for project `ckbftoopuyophiebamwy`. Business subrepositories do not keep separate Supabase assets.

- `functions/` contains the reviewed, deployable Edge Function source. Deploy a reviewed change with `supabase functions deploy <name> --project-ref ckbftoopuyophiebamwy --use-api`.
- `migrations/` has no local migration SQL. Reviewed production SQL is applied directly through the project-scoped Supabase MCP after backup and validation.
- `tests/` contains database regression SQL shared by the whole workspace.
- `backup-supabase.ps1` exports the remote project into one timestamped, Git-ignored backup directory. `restore-supabase.ps1` imports that backup into a new project.

Database structure, data, and migration history are kept together inside the backup directory. Export does not create one SQL file per migration in the repository.

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

Apply reviewed database SQL through the project-scoped Supabase MCP, then deploy the function before enabling the UI in a shared environment:

```powershell
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

Apply reviewed database SQL through the project-scoped Supabase MCP, then deploy the reviewed function before enabling the UI in a shared environment:

```powershell
supabase functions deploy ai-transport-anomaly-advisor --project-ref ckbftoopuyophiebamwy --use-api
```

## Export and import a Supabase project

Install and sign in to the Supabase CLI, then start Docker Desktop. From the repository root, export the linked source project:

```powershell
.\supabase\backup-supabase.ps1
```

The script prompts for the source database password. Its result is `supabase/backups/<timestamp>/manifest.json` plus database dumps, Storage files, deployed Edge Functions, and project metadata. Keep this ignored directory in encrypted storage because it contains live data. It does not overwrite the repository's reviewed Function source.

To restore into a **new, empty** Supabase project:

```powershell
.\supabase\restore-supabase.ps1 -BackupPath '.\supabase\backups\YYYYMMDD-HHMMSS' -TargetProjectRef '<new-project-ref>'
```

The restore script verifies the manifest and file hashes, asks for the target database password and project ref confirmation, and refuses a project that already has application tables. It restores the database (including Auth users and migration history), Storage objects, Realtime publication membership, and deployed Edge Functions. The source repository's project link is not changed.

To check a backup without connecting to either project, add `-VerifyBackupOnly` to the restore command.

Supabase cannot export Edge Function secret **values** or dashboard-only Auth/OAuth, SMTP, domain, and similar settings; configure those on the new project. Changes made to managed `auth` and `storage` schemas require manual review of `database/managed-schema-snapshot.sql` before the target is equivalent. If the source uses Vault or encrypted columns, transfer its encryption root key through Supabase's supported procedure before restoring. Custom `LOGIN` role passwords, Function import maps, and `deno.json` must be supplied separately. See the [Supabase backup and restore guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) for those limits.
