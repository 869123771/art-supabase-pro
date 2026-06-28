# Project Instructions

- Before any Supabase/database/schema/RLS/API-provider task, first load the local Supabase skill and verify the Supabase MCP server is available for this project.
- This repo is scoped to Supabase project `ckbftoopuyophiebamwy` through `.mcp.json`.
- Expected MCP URL: `https://mcp.supabase.com/mcp?project_ref=ckbftoopuyophiebamwy&features=database,debugging,development,docs`.
- If Supabase MCP tools such as `execute_sql`, `search_docs`, or `get_advisors` are not visible, check remote reachability with `curl.exe -so NUL -w "%{http_code}" https://mcp.supabase.com/mcp`; `401` means the hosted server is reachable and the Codex session likely needs OAuth authentication or a reload.
- Prefer MCP `search_docs`, `execute_sql`, and `get_advisors` for Supabase work when available; otherwise use the Supabase CLI or documented fallbacks from the local skill.
