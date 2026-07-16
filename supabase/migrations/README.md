# Database migrations

This directory is intentionally empty until the remote project baseline is exported.

The first migration must be generated from the real remote schema, including tables, RLS policies, RPC functions, triggers, and grants. Never hand-write a partial baseline from frontend API calls: it would make a local reset diverge from production.

Subsequent changes must be additive migration files created with `supabase migration new <name>` and reviewed together with their RLS policies and tests.
