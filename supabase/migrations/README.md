# Database migrations

This directory is synchronized from the linked remote project.

- `20260716093927_baseline.sql` is the real remote baseline, including schemas, tables, RLS policies, RPC functions, triggers, and grants.
- The following timestamped files are the remote migration history fetched with `supabase migration fetch --linked`.
- New changes must be additive migration files created with `supabase migration new <name>` and reviewed together with their RLS policies and tests.

Do not replace the baseline with a partial schema inferred from frontend API calls. Before pushing, use `supabase migration list --linked` to confirm that only reviewed local migrations are pending.
