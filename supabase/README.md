# Supabase source of truth

中文的远端备份、只读分发、本地恢复与跨项目恢复操作说明见 [README.zh-CN.md](README.zh-CN.md)。

This is the only Supabase directory for project `ckbftoopuyophiebamwy`. Business subrepositories do not keep separate Supabase assets.

- `functions/` contains the reviewed, deployable Edge Function source. Deploy a reviewed change with `supabase functions deploy <name> --project-ref ckbftoopuyophiebamwy --use-api`.
- `migrations/` has no local migration SQL. Reviewed production SQL is applied directly through the project-scoped Supabase MCP after backup and validation.
- `tests/` contains read-only database regression SQL shared by the whole workspace. Run `pnpm test:db` with an authenticated Supabase CLI after RLS changes, or execute the test SQL through the project-scoped MCP when only MCP authentication is available.
- `pnpm database:security:audit` checks source boundaries and the presence of live regression assertions locally. It does not replace `pnpm test:db` against the linked database.
- `backup-supabase.ps1` exports the remote project into one timestamped, Git-ignored backup directory. `package-supabase-backup.ps1` packages it for verified download, and `restore-local-supabase.ps1` restores it into an isolated local stack. `restore-supabase.ps1` imports it into a new remote project.

Database structure, data, and migration history are kept together inside the backup directory. Export does not create one SQL file per migration in the repository.

## Tenant read-scope boundary

The authenticated platform super's home tenant is the platform tenant. The header scope is a separate read context: an empty selection means all tenants; a concrete selection limits tenant-owned reads to that tenant. Ordinary users always read and write within their authenticated tenant, even if they forge the header. A permissive `canonical_platform_super_write` policy also grants SELECT, so every tenant-owned table with that policy needs a restrictive `canonical_tenant_read_scope` SELECT policy. Keep existing permissive grants for feature permissions and ownership; they combine with the restrictive scope.

The 2026-10-01 live audit found 42 tables whose platform-super `FOR ALL` policy bypassed a concrete selected tenant. After a verified backup and transactional rollback test, all 42 gained the restrictive guard; 28 existing permissive read grants were preserved. The read-only regression query in `tests/database_security_policy_test.sql` now checks this invariant for the full policy catalog. A four-context check on `mdm_project` returned 4 rows for platform-all, 2 for platform-selected, 2 for an authorized ordinary user, and the same 2 after that user supplied a forged cross-tenant header. No selected-scope cross-tenant rows remained.

AI order master-data creation remains available to ordinary users with `TmsOrderOpen:AiFill` and the matching `Add` permission. The `create_ai_order_master_data` RPC resolves their authenticated tenant at the database boundary. The target contract is that platform-all defaults a new root record to the authenticated administrator's platform tenant, while an explicit selected tenant overrides it. The live RPC still rejects platform-all until a fresh recoverable backup permits its update. Rollback-only live checks confirmed ordinary station, cargo, customer with default address, and separate customer-address creation without leaving test records.

VMS vehicle-document OCR analysis is available to users with `VehicleArchive:Ocr`. The form permits an ordinary user with `VehicleArchive:Add` to apply the result when creating a vehicle in their authenticated tenant; applying it to an existing archive remains platform-super-only. The OCR request uses the form's concrete tenant so platform-all does not broaden the image scope. As read on 2026-10-01, `vms_create_vehicle_archive_secure` still rejects `ai_artifact_id` for every non-super user, so ordinary AI-assisted vehicle creation is not yet usable end to end. After a verified recoverable backup, update that create RPC to enforce `VehicleArchive:Ocr` and `VehicleArchive:Add`, bind ordinary users and their OCR artifacts to their authenticated tenant, retain artifact ownership and feature checks, and default a platform-all root create to the authenticated platform tenant unless another tenant is explicitly chosen. Keep the platform-super check in `vms_update_vehicle_archive_secure`. The form payload regression test retains `aiArtifactId` so the database receives the marker for both create and edit.

TMS cargo's direct table writes also require their exact business buttons: `Add` or `Import` for INSERT, `Edit` for UPDATE, and `Delete` for DELETE. The platform-super write policy remains available for authorized cross-tenant maintenance. The regression query checks these permissions so a later permissive policy cannot silently reopen the direct endpoint.

TMS station writes resolve a concrete tenant for creation: the platform tenant by default in platform-all mode, or an explicitly selected tenant. The station save/import RPCs check their button permissions; direct station writes use button-aware RLS, and a toggle-only user may change only `enabled`. Station roles are maintained by the checked save RPC and a restricted trigger, while authenticated clients have no direct role-table DML grant. Ordinary users with `TmsOrderOpen:AiFill` and `TmsStation:Add` can create a station through the AI RPC; its primary role is synchronized automatically. Transactional live tests covered ordinary create/edit/import/toggle/delete, AI create, platform-all explicit creation, selected-tenant creation, and forged/cross-tenant rejection; test records were rolled back.

As read on 2026-10-02, `tms_create_contract_secure` and `tms_import_contracts_secure` always write to `current_user_tenant_id()` and do not accept an explicit target. The client defaults contract creation in platform-all to that home tenant and blocks a selected foreign tenant before calling either RPC, avoiding a silent write to the wrong tenant. `tms_list_carrier_options_secure` also bypasses the selected read scope for platform super. After a fresh recoverable backup, update these contract RPCs to resolve and authorize a concrete target tenant and scope carrier options to the selected or form tenant; then remove the temporary client block and verify home, selected, and forged cross-tenant contexts in rollback-only tests.

The FMS invoice and cash-voucher OCR source now binds each analysis to one authenticated tenant: platform-all defaults to the administrator's home tenant, a concrete target is sent with the Function request, and the Function validates every image against that tenant's project attachment path. Artifact review follows the saved artifact's tenant, and cash-voucher statement recommendations use that same tenant. These Function changes are source-only until a fresh recoverable backup and deployment verification are available. The live `save_tms_invoice_secure` RPC still validates linked statements against `current_user_tenant_id()` even when its underlying save derives a different tenant from the selected counterparty; this must be aligned before selected-tenant invoice creation with links is considered complete. The current carrier-option RPC omits the carrier tenant ID, so FMS invoice and cash-payment dialogs cannot safely infer a foreign parent tenant for attachments while the header remains on all tenants. Add the tenant ID to the authorized option response, then bind these child uploads to the selected parent and clear mismatched pending attachments when the parent changes. Verify platform-all/home, platform-selected, ordinary-own, forged-header, mixed-tenant image, and cross-tenant artifact review paths after deployment.

Station deletion is guarded separately because order station foreign keys use `ON DELETE SET NULL`: without a guard, deleting a station erases order routing references. The `get_tms_station_delete_dependency_details` RPC lists linked orders for `MasterDataDeleteGuard`, with order identifiers and navigation only when the actor has order-view permission. A `BEFORE DELETE` trigger rejects deletion while any order still references the station, including concurrent references added after the UI check. The 2026-10-01 audit found 6 referenced stations and 38 station-order pairs. Rollback-only checks confirmed ordinary own-tenant inspection and unreferenced deletion, rejection of referenced deletion and forged cross-tenant inspection, plus platform-all and platform-selected behavior; the checks left no deleted station or order records.

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

For recipient-only download access, the owner can package the verified backup and use `publish-supabase-backup.ps1` to upload it to a **private bucket in a separate distribution project**. The package removes source Auth password hashes, sessions, refresh tokens, MFA data, OAuth flow data, migration history rows, and the owner-only managed-schema snapshot; the original owner backup remains intact. Share only the short-lived signed URL and SHA-256. Recipients use `download-supabase-backup.ps1`, `restore-local-supabase.ps1`, and `set-local-login.ps1`; they need no source project token or database password. Review business data and Storage files for other secrets before distribution. See [README.zh-CN.md](README.zh-CN.md) for the full owner and recipient commands, including an offline test with `-ArchivePath`.

Supabase cannot export Edge Function secret **values** or dashboard-only Auth/OAuth, SMTP, domain, and similar settings; configure those on the new project. Changes made to managed `auth` and `storage` schemas require manual review of `database/managed-schema-snapshot.sql` before the target is equivalent. If the source uses Vault or encrypted columns, transfer its encryption root key through Supabase's supported procedure before restoring. Custom `LOGIN` role passwords, Function import maps, and `deno.json` must be supplied separately. See the [Supabase backup and restore guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) for those limits.
