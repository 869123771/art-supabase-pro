
create index if not exists ai_project_snapshot_auth_user_idx
  on public.ai_project_snapshot (auth_user_id);
create index if not exists ai_suggestion_batch_auth_user_idx
  on public.ai_suggestion_batch (auth_user_id);
create index if not exists ai_suggestion_auth_user_idx
  on public.ai_suggestion (auth_user_id);
create index if not exists ai_suggestion_event_auth_user_idx
  on public.ai_suggestion_event (auth_user_id);
;
