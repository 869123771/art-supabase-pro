# Supabase source of truth

This directory contains the deployable Supabase project assets for `ckbftoopuyophiebamwy`.

- `functions/` contains the source downloaded from the deployed project. Deploy a reviewed change with `supabase functions deploy <name> --project-ref ckbftoopuyophiebamwy --use-api`.
- `migrations/` is reserved for the baseline schema and every future database change. Do not edit production schema manually after the baseline is committed.

## Baseline migration

The initial migration must be generated from the currently linked remote project with `supabase db pull <baseline-name> --linked`. The Supabase CLI requires the remote database password for that operation, so this repository intentionally does not contain a guessed schema snapshot.

After the baseline exists, validate every database change with a local reset and add the matching RLS coverage before deployment.

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
