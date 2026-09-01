-- Secure the privileged SQL console RPCs behind the authenticated Edge Function.
revoke all on function public.execute_sql_query(text) from public, anon, authenticated;
grant execute on function public.execute_sql_query(text) to service_role;

revoke all on function public.get_database_metadata_all() from public, anon, authenticated;
grant execute on function public.get_database_metadata_all() to service_role;

create table public.ai_conversation (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New conversation',
  context jsonb not null default '{}'::jsonb,
  status text not null default 'active' check (status in ('active', 'archived')),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
);

create table public.ai_message (
  id bigint generated always as identity primary key,
  conversation_id uuid not null references public.ai_conversation(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'tool')),
  content text not null default '',
  tool_name text,
  citations jsonb not null default '[]'::jsonb,
  usage jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
);

create table public.ai_run (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.ai_conversation(id) on delete set null,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null,
  model text not null,
  prompt_version text not null default 'v1',
  status text not null default 'running' check (status in ('running', 'succeeded', 'failed', 'limited')),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  tool_calls jsonb not null default '[]'::jsonb,
  error_code text,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
);

create table public.ai_tool_call (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.ai_run(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  tool_name text not null,
  arguments jsonb not null default '{}'::jsonb,
  status text not null default 'running' check (status in ('running', 'succeeded', 'failed')),
  result_summary jsonb not null default '{}'::jsonb,
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  error_message text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
);

create table public.ai_feedback (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.ai_run(id) on delete cascade,
  auth_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  rating smallint not null check (rating in (-1, 1)),
  comment text,
  correction jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  unique (run_id, auth_user_id)
);

create index ai_conversation_tenant_user_updated_idx
  on public.ai_conversation (tenant_id, auth_user_id, update_time desc);
create index ai_message_conversation_created_idx
  on public.ai_message (conversation_id, create_time);
create index ai_message_tenant_user_created_idx
  on public.ai_message (tenant_id, auth_user_id, create_time desc);
create index ai_run_tenant_user_created_idx
  on public.ai_run (tenant_id, auth_user_id, create_time desc);
create index ai_run_running_idx
  on public.ai_run (auth_user_id, started_at)
  where status = 'running';
create index ai_tool_call_run_created_idx
  on public.ai_tool_call (run_id, create_time);
create index ai_feedback_tenant_user_created_idx
  on public.ai_feedback (tenant_id, auth_user_id, create_time desc);

alter table public.ai_conversation enable row level security;
alter table public.ai_message enable row level security;
alter table public.ai_run enable row level security;
alter table public.ai_tool_call enable row level security;
alter table public.ai_feedback enable row level security;

create policy tenant_select on public.ai_conversation
  for select to authenticated
  using (
    (select app_private.is_platform_super())
    or (
      tenant_id = (select app_private.current_user_tenant_id())
      and auth_user_id = (select auth.uid())
    )
  );
create policy tenant_delete on public.ai_conversation
  for delete to authenticated
  using (
    (select app_private.is_platform_super())
    or (
      tenant_id = (select app_private.current_user_tenant_id())
      and auth_user_id = (select auth.uid())
    )
  );

create policy tenant_select on public.ai_message
  for select to authenticated
  using (
    (select app_private.is_platform_super())
    or (
      tenant_id = (select app_private.current_user_tenant_id())
      and auth_user_id = (select auth.uid())
    )
  );

create policy tenant_select on public.ai_run
  for select to authenticated
  using (
    (select app_private.is_platform_super())
    or (
      tenant_id = (select app_private.current_user_tenant_id())
      and auth_user_id = (select auth.uid())
    )
  );

create policy tenant_select on public.ai_tool_call
  for select to authenticated
  using (
    (select app_private.is_platform_super())
    or (
      tenant_id = (select app_private.current_user_tenant_id())
      and auth_user_id = (select auth.uid())
    )
  );

create policy tenant_select on public.ai_feedback
  for select to authenticated
  using (
    (select app_private.is_platform_super())
    or (
      tenant_id = (select app_private.current_user_tenant_id())
      and auth_user_id = (select auth.uid())
    )
  );
create policy tenant_insert on public.ai_feedback
  for insert to authenticated
  with check (
    tenant_id = (select app_private.current_user_tenant_id())
    and auth_user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_run run
      where run.id = run_id
        and run.tenant_id = (select app_private.current_user_tenant_id())
        and run.auth_user_id = (select auth.uid())
    )
  );
create policy tenant_update on public.ai_feedback
  for update to authenticated
  using (
    tenant_id = (select app_private.current_user_tenant_id())
    and auth_user_id = (select auth.uid())
  )
  with check (
    tenant_id = (select app_private.current_user_tenant_id())
    and auth_user_id = (select auth.uid())
  );
create policy tenant_delete on public.ai_feedback
  for delete to authenticated
  using (
    tenant_id = (select app_private.current_user_tenant_id())
    and auth_user_id = (select auth.uid())
  );

create trigger ai_conversation_create_audit
before insert on public.ai_conversation
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger ai_conversation_update_audit
before update on public.ai_conversation
for each row execute function public.trg_set_update_time_and_by();

create trigger ai_message_create_audit
before insert on public.ai_message
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger ai_message_update_audit
before update on public.ai_message
for each row execute function public.trg_set_update_time_and_by();

create trigger ai_run_create_audit
before insert on public.ai_run
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger ai_run_update_audit
before update on public.ai_run
for each row execute function public.trg_set_update_time_and_by();

create trigger ai_tool_call_create_audit
before insert on public.ai_tool_call
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger ai_tool_call_update_audit
before update on public.ai_tool_call
for each row execute function public.trg_set_update_time_and_by();

create trigger ai_feedback_create_audit
before insert on public.ai_feedback
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger ai_feedback_update_audit
before update on public.ai_feedback
for each row execute function public.trg_set_update_time_and_by();

revoke all on public.ai_conversation, public.ai_message, public.ai_run,
  public.ai_tool_call, public.ai_feedback from anon;
grant select, delete on public.ai_conversation to authenticated;
grant select on public.ai_message, public.ai_run, public.ai_tool_call to authenticated;
grant select, insert, update, delete on public.ai_feedback to authenticated;
grant all on public.ai_conversation, public.ai_message, public.ai_run,
  public.ai_tool_call, public.ai_feedback to service_role;
grant usage, select on sequence public.ai_message_id_seq,
  public.ai_tool_call_id_seq, public.ai_feedback_id_seq to service_role;
grant usage, select on sequence public.ai_feedback_id_seq to authenticated;

comment on table public.ai_conversation is 'Tenant-isolated AI assistant conversations.';
comment on table public.ai_message is 'Messages persisted by the AI assistant gateway.';
comment on table public.ai_run is 'AI model invocation audit, usage, latency, and status.';
comment on table public.ai_tool_call is 'Allowlisted business tool execution audit.';
comment on table public.ai_feedback is 'User feedback and corrections for AI runs.';

;
