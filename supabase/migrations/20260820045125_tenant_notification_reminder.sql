-- Tenant lifecycle and reusable notification reminder center.
-- Business dates stay on their source records; rules, subjects, events and deliveries
-- are normalized so tenant expiry and business documents share one audited pipeline.

create extension if not exists pg_net;

alter table public.sys_tenant
  add column if not exists service_start_date date,
  add column if not exists service_end_date date;

alter table public.sys_tenant
  drop constraint if exists sys_tenant_service_period_check;
alter table public.sys_tenant
  add constraint sys_tenant_service_period_check
  check (
    service_start_date is null
    or service_end_date is null
    or service_end_date >= service_start_date
  );

comment on column public.sys_tenant.service_start_date is 'Tenant service enable date; null means no lower bound.';
comment on column public.sys_tenant.service_end_date is 'Tenant service expiry date; null means no upper bound.';

-- Make the tenant validity boundary effective for every tenant-scoped RLS policy.
create or replace function app_private.current_user_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select user_row.tenant_id
  from public.sys_user user_row
  join public.sys_tenant tenant_row on tenant_row.id = user_row.tenant_id
  where user_row.auth_user_id = (select auth.uid())
    and user_row.status = '1'
    and user_row.deleted_at is null
    and tenant_row.status = '1'
    and (tenant_row.service_start_date is null or tenant_row.service_start_date <= current_date)
    and (tenant_row.service_end_date is null or tenant_row.service_end_date >= current_date)
  limit 1;
$$;

create table public.sys_notification_scenario (
  id uuid primary key default gen_random_uuid(),
  scenario_code text not null unique,
  scenario_name text not null,
  module_code text not null,
  description text,
  route_path text not null,
  sort integer not null default 0,
  enabled boolean not null default true,
  builtin boolean not null default true,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_notification_scenario_code_check
    check (scenario_code ~ '^[a-z][a-z0-9_]*$'),
  constraint sys_notification_scenario_module_check
    check (module_code in ('system', 'tms', 'vms', 'fms', 'hr')),
  constraint sys_notification_scenario_sort_check check (sort >= 0)
);

create table public.sys_notification_channel_config (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  channel_code text not null,
  provider_code text not null default 'builtin',
  enabled boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  vault_secret_id uuid,
  last_test_at timestamptz,
  last_test_status text,
  last_error text,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_notification_channel_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete cascade,
  constraint sys_notification_channel_code_check
    check (channel_code in ('in_app', 'email', 'sms', 'dingtalk', 'wecom')),
  constraint sys_notification_channel_provider_check check (btrim(provider_code) <> ''),
  constraint sys_notification_channel_config_check check (jsonb_typeof(config) = 'object'),
  constraint sys_notification_channel_test_status_check
    check (last_test_status is null or last_test_status in ('pending', 'delivered', 'failed')),
  constraint sys_notification_channel_tenant_key unique (tenant_id, channel_code),
  constraint sys_notification_channel_id_tenant_key unique (id, tenant_id)
);

create table public.sys_notification_rule (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  scenario_id uuid not null,
  rule_name text not null,
  lead_days integer not null default 0,
  repeat_every_days integer,
  send_hour smallint not null default 9,
  recipient_strategy text not null default 'owner_then_roles',
  recipient_role_codes text[] not null default array['R_ADMIN', 'YQ_ADMIN', 'R_SUPER']::text[],
  channels text[] not null default array['in_app']::text[],
  enabled boolean not null default true,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_notification_rule_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete cascade,
  constraint sys_notification_rule_scenario_fkey
    foreign key (scenario_id) references public.sys_notification_scenario(id) on delete cascade,
  constraint sys_notification_rule_lead_check check (lead_days between 0 and 3650),
  constraint sys_notification_rule_repeat_check
    check (repeat_every_days is null or repeat_every_days between 1 and 365),
  constraint sys_notification_rule_hour_check check (send_hour between 0 and 23),
  constraint sys_notification_rule_recipient_check
    check (recipient_strategy in ('tenant_admins', 'owner_then_roles')),
  constraint sys_notification_rule_channels_check
    check (
      cardinality(channels) > 0
      and channels <@ array['in_app', 'email', 'sms', 'dingtalk', 'wecom']::text[]
    ),
  constraint sys_notification_rule_tenant_name_key unique (tenant_id, scenario_id, rule_name),
  constraint sys_notification_rule_id_tenant_key unique (id, tenant_id)
);

create table public.sys_notification_subject (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  scenario_id uuid not null,
  business_type text not null,
  business_id uuid not null,
  subject_key text not null default 'default',
  subject_title text not null,
  due_at timestamptz not null,
  owner_user_id uuid,
  route_path text not null,
  route_query jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_notification_subject_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete cascade,
  constraint sys_notification_subject_scenario_fkey
    foreign key (scenario_id) references public.sys_notification_scenario(id) on delete cascade,
  constraint sys_notification_subject_owner_tenant_fkey
    foreign key (owner_user_id, tenant_id) references public.sys_user(id, tenant_id)
    on delete set null (owner_user_id),
  constraint sys_notification_subject_status_check
    check (status in ('active', 'resolved', 'cancelled')),
  constraint sys_notification_subject_route_query_check check (jsonb_typeof(route_query) = 'object'),
  constraint sys_notification_subject_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint sys_notification_subject_business_key
    unique (tenant_id, scenario_id, business_type, business_id, subject_key),
  constraint sys_notification_subject_id_tenant_key unique (id, tenant_id)
);

create table public.sys_notification_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_id uuid,
  rule_id uuid,
  occurrence_date date not null,
  scheduled_at timestamptz not null,
  title text not null,
  content text not null,
  severity text not null default 'warning',
  status text not null default 'pending',
  error_message text,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_notification_event_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete cascade,
  constraint sys_notification_event_subject_tenant_fkey
    foreign key (subject_id, tenant_id)
    references public.sys_notification_subject(id, tenant_id) on delete cascade,
  constraint sys_notification_event_rule_tenant_fkey
    foreign key (rule_id, tenant_id)
    references public.sys_notification_rule(id, tenant_id) on delete set null (rule_id),
  constraint sys_notification_event_severity_check
    check (severity in ('info', 'success', 'warning', 'danger')),
  constraint sys_notification_event_status_check
    check (status in ('pending', 'queued', 'delivered', 'failed')),
  constraint sys_notification_event_occurrence_key unique (subject_id, rule_id, occurrence_date),
  constraint sys_notification_event_id_tenant_key unique (id, tenant_id)
);

create table public.sys_notification_delivery (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  event_id uuid,
  recipient_user_id uuid not null,
  channel_code text not null,
  title text not null,
  content text not null,
  route_path text not null default '/',
  route_query jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  next_retry_at timestamptz,
  delivered_at timestamptz,
  external_message_id text,
  error_message text,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_notification_delivery_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete cascade,
  constraint sys_notification_delivery_event_tenant_fkey
    foreign key (event_id, tenant_id)
    references public.sys_notification_event(id, tenant_id) on delete cascade,
  constraint sys_notification_delivery_user_tenant_fkey
    foreign key (recipient_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete cascade,
  constraint sys_notification_delivery_channel_check
    check (channel_code in ('in_app', 'email', 'sms', 'dingtalk', 'wecom')),
  constraint sys_notification_delivery_status_check
    check (status in ('pending', 'processing', 'delivered', 'failed', 'skipped')),
  constraint sys_notification_delivery_attempt_check check (attempt_count between 0 and 10),
  constraint sys_notification_delivery_route_query_check check (jsonb_typeof(route_query) = 'object'),
  constraint sys_notification_delivery_event_recipient_key
    unique (event_id, recipient_user_id, channel_code)
);

create index sys_notification_subject_due_idx
  on public.sys_notification_subject (tenant_id, due_at, scenario_id)
  where status = 'active';
create index sys_notification_event_status_idx
  on public.sys_notification_event (status, scheduled_at, tenant_id);
create index sys_notification_delivery_pending_idx
  on public.sys_notification_delivery (status, next_retry_at, create_time)
  where status in ('pending', 'failed');

alter table public.sys_notification_scenario enable row level security;
alter table public.sys_notification_channel_config enable row level security;
alter table public.sys_notification_rule enable row level security;
alter table public.sys_notification_subject enable row level security;
alter table public.sys_notification_event enable row level security;
alter table public.sys_notification_delivery enable row level security;

create policy sys_notification_scenario_select
on public.sys_notification_scenario for select to authenticated using (enabled is true);

do $policies$
declare
  v_table text;
begin
  foreach v_table in array array[
    'sys_notification_channel_config',
    'sys_notification_rule',
    'sys_notification_subject',
    'sys_notification_event',
    'sys_notification_delivery'
  ]
  loop
    execute format(
      'create policy tenant_select on public.%I for select to authenticated using (' ||
      'app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())',
      v_table
    );
  end loop;
end
$policies$;

revoke all on table public.sys_notification_scenario from public, anon, authenticated;
revoke all on table public.sys_notification_channel_config from public, anon, authenticated;
revoke all on table public.sys_notification_rule from public, anon, authenticated;
revoke all on table public.sys_notification_subject from public, anon, authenticated;
revoke all on table public.sys_notification_event from public, anon, authenticated;
revoke all on table public.sys_notification_delivery from public, anon, authenticated;

create trigger sys_notification_scenario_create_audit before insert on public.sys_notification_scenario
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_notification_scenario_update_audit before update on public.sys_notification_scenario
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_notification_channel_create_audit before insert on public.sys_notification_channel_config
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_notification_channel_update_audit before update on public.sys_notification_channel_config
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_notification_rule_create_audit before insert on public.sys_notification_rule
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_notification_rule_update_audit before update on public.sys_notification_rule
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_notification_subject_create_audit before insert on public.sys_notification_subject
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_notification_subject_update_audit before update on public.sys_notification_subject
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_notification_event_create_audit before insert on public.sys_notification_event
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_notification_event_update_audit before update on public.sys_notification_event
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_notification_delivery_create_audit before insert on public.sys_notification_delivery
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_notification_delivery_update_audit before update on public.sys_notification_delivery
for each row execute function public.trg_set_update_time_and_by();

insert into public.sys_notification_scenario (
  scenario_code, scenario_name, module_code, description, route_path, sort,
  create_by, update_by
)
values
  ('tenant_expiry', '租户服务到期', 'system', '租户服务有效期即将结束或已经到期。', '/system/tenant', 10, 'system-reminder', 'system-reminder'),
  ('tms_contract_expiry', '运输合同到期', 'tms', '运输合同有效期即将结束。', '/tms/basic-data/contract', 20, 'system-reminder', 'system-reminder'),
  ('fms_commercial_bill_due', '商业票据到期', 'fms', '应收或应付商业票据即将到期。', '/fms/commercial-bill', 30, 'system-reminder', 'system-reminder'),
  ('vms_commercial_insurance_expiry', '车辆商业险到期', 'vms', '车辆商业保险即将到期。', '/vms/reminder-manage/insurance-expiry', 40, 'system-reminder', 'system-reminder'),
  ('vms_compulsory_insurance_expiry', '车辆交强险到期', 'vms', '车辆交强保险即将到期。', '/vms/reminder-manage/insurance-expiry', 50, 'system-reminder', 'system-reminder'),
  ('vms_vehicle_inspection_expiry', '车辆年检到期', 'vms', '车辆年检有效期即将结束。', '/vms/reminder-manage/inspection-expiry', 60, 'system-reminder', 'system-reminder'),
  ('vms_vehicle_service_expiry', '车辆服务期到期', 'vms', '车辆服务期即将结束。', '/vms/reminder-manage/vehicle-service-life', 70, 'system-reminder', 'system-reminder')
on conflict (scenario_code) do update
set scenario_name = excluded.scenario_name,
    module_code = excluded.module_code,
    description = excluded.description,
    route_path = excluded.route_path,
    sort = excluded.sort,
    enabled = true,
    update_by = excluded.update_by,
    update_time = now();

create or replace function app_private.notification_target_tenant(p_tenant_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
begin
  if app_private.is_platform_super() then
    if p_tenant_id is null or not exists (select 1 from public.sys_tenant where id = p_tenant_id) then
      raise exception '请选择有效租户';
    end if;
    return p_tenant_id;
  end if;
  if v_current_tenant is null or (p_tenant_id is not null and p_tenant_id <> v_current_tenant) then
    raise exception '无权访问其他租户的提醒配置' using errcode = '42501';
  end if;
  return v_current_tenant;
end;
$$;

create or replace function app_private.seed_notification_defaults(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_tenant_id is null or not exists (select 1 from public.sys_tenant where id = p_tenant_id) then
    raise exception 'Tenant not found';
  end if;

  insert into public.sys_notification_channel_config (
    tenant_id, channel_code, provider_code, enabled, config, create_by, update_by
  )
  values
    (p_tenant_id, 'in_app', 'builtin', true, '{}'::jsonb, 'system-reminder', 'system-reminder'),
    (p_tenant_id, 'email', 'resend', false, jsonb_build_object('fromEmail', '', 'senderName', ''), 'system-reminder', 'system-reminder'),
    (p_tenant_id, 'sms', 'generic_webhook', false, '{}'::jsonb, 'system-reminder', 'system-reminder'),
    (p_tenant_id, 'dingtalk', 'robot_webhook', false, '{}'::jsonb, 'system-reminder', 'system-reminder'),
    (p_tenant_id, 'wecom', 'robot_webhook', false, '{}'::jsonb, 'system-reminder', 'system-reminder')
  on conflict (tenant_id, channel_code) do nothing;

  insert into public.sys_notification_rule (
    tenant_id, scenario_id, rule_name, lead_days, repeat_every_days,
    send_hour, recipient_strategy, channels, enabled, create_by, update_by
  )
  select p_tenant_id, scenario.id, default_rule.rule_name, default_rule.lead_days,
         default_rule.repeat_every_days, 9,
         case when scenario.scenario_code = 'tenant_expiry' then 'tenant_admins' else 'owner_then_roles' end,
         array['in_app']::text[], true, 'system-reminder', 'system-reminder'
  from public.sys_notification_scenario scenario
  cross join lateral (
    values
      ('提前 30 天提醒一次'::text, 30, null::integer),
      ('提前 7 天每天提醒'::text, 7, 1::integer)
  ) default_rule(rule_name, lead_days, repeat_every_days)
  where scenario.enabled is true
  on conflict (tenant_id, scenario_id, rule_name) do nothing;
end;
$$;

create or replace function app_private.seed_notification_defaults_for_new_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.seed_notification_defaults(new.id);
  return new;
end;
$$;

create trigger sys_tenant_seed_notification_defaults
after insert on public.sys_tenant
for each row execute function app_private.seed_notification_defaults_for_new_tenant();

do $seed$
declare
  v_tenant record;
begin
  for v_tenant in select id from public.sys_tenant loop
    perform app_private.seed_notification_defaults(v_tenant.id);
  end loop;
end
$seed$;

create or replace function app_private.upsert_notification_subject(
  p_tenant_id uuid,
  p_scenario_code text,
  p_business_type text,
  p_business_id uuid,
  p_subject_key text,
  p_subject_title text,
  p_due_at timestamptz,
  p_owner_user_id uuid,
  p_route_path text,
  p_route_query jsonb,
  p_metadata jsonb,
  p_status text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scenario public.sys_notification_scenario%rowtype;
  v_subject_id uuid;
begin
  select * into v_scenario
  from public.sys_notification_scenario
  where scenario_code = p_scenario_code and enabled is true;
  if not found then raise exception 'Notification scenario not found: %', p_scenario_code; end if;

  if p_due_at is null or p_status <> 'active' then
    update public.sys_notification_subject
    set status = case when p_status in ('resolved', 'cancelled') then p_status else 'cancelled' end,
        update_by = 'system-reminder'
    where tenant_id = p_tenant_id
      and scenario_id = v_scenario.id
      and business_type = p_business_type
      and business_id = p_business_id
      and subject_key = coalesce(nullif(p_subject_key, ''), 'default')
    returning id into v_subject_id;
    return v_subject_id;
  end if;

  insert into public.sys_notification_subject (
    tenant_id, scenario_id, business_type, business_id, subject_key,
    subject_title, due_at, owner_user_id, route_path, route_query, metadata,
    status, create_by, update_by
  )
  values (
    p_tenant_id, v_scenario.id, p_business_type, p_business_id,
    coalesce(nullif(p_subject_key, ''), 'default'), btrim(p_subject_title), p_due_at,
    p_owner_user_id, coalesce(nullif(p_route_path, ''), v_scenario.route_path),
    coalesce(p_route_query, '{}'::jsonb), coalesce(p_metadata, '{}'::jsonb),
    'active', 'system-reminder', 'system-reminder'
  )
  on conflict (tenant_id, scenario_id, business_type, business_id, subject_key)
  do update set
    subject_title = excluded.subject_title,
    due_at = excluded.due_at,
    owner_user_id = excluded.owner_user_id,
    route_path = excluded.route_path,
    route_query = excluded.route_query,
    metadata = excluded.metadata,
    status = 'active',
    update_by = excluded.update_by
  returning id into v_subject_id;
  return v_subject_id;
end;
$$;

create or replace function app_private.sync_notification_subject_from_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_status text := case when tg_op = 'DELETE' then 'cancelled' else 'active' end;
  v_tenant_id uuid := (v_row ->> 'tenant_id')::uuid;
  v_business_id uuid := (v_row ->> 'id')::uuid;
begin
  if tg_table_name = 'sys_tenant' then
    v_tenant_id := v_business_id;
    if coalesce(v_row ->> 'status', '0') <> '1' then v_status := 'cancelled'; end if;
    perform app_private.upsert_notification_subject(
      v_tenant_id, 'tenant_expiry', 'sys_tenant', v_business_id, 'service_end',
      coalesce(v_row ->> 'tenant_name', '租户') || ' 服务到期',
      case when v_row ->> 'service_end_date' is null then null
        else ((v_row ->> 'service_end_date')::date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/system/tenant', jsonb_build_object('tenantId', v_business_id), '{}'::jsonb, v_status
    );
  elsif tg_table_name = 'tms_contract' then
    if coalesce((v_row ->> 'is_completed')::boolean, false) then v_status := 'resolved'; end if;
    perform app_private.upsert_notification_subject(
      v_tenant_id, 'tms_contract_expiry', 'tms_contract', v_business_id, 'expiry_date',
      '运输合同「' || coalesce(v_row ->> 'contract_name', v_row ->> 'contract_no', '未命名') || '」到期',
      case when v_row ->> 'expiry_date' is null then null
        else ((v_row ->> 'expiry_date')::date + time '09:00') at time zone 'Asia/Shanghai' end,
      nullif(v_row ->> 'created_by_user_id', '')::uuid,
      '/tms/basic-data/contract', jsonb_build_object('contractId', v_business_id),
      jsonb_build_object('businessNo', v_row ->> 'contract_no'), v_status
    );
  elsif tg_table_name = 'fms_commercial_bill' then
    if coalesce(v_row ->> 'status', '') in ('settled', 'cancelled', 'voided') then v_status := 'resolved'; end if;
    perform app_private.upsert_notification_subject(
      v_tenant_id, 'fms_commercial_bill_due', 'fms_commercial_bill', v_business_id, 'due_date',
      '商业票据「' || coalesce(v_row ->> 'bill_no', '未编号') || '」到期',
      case when v_row ->> 'due_date' is null then null
        else ((v_row ->> 'due_date')::date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/fms/commercial-bill', jsonb_build_object('billId', v_business_id),
      jsonb_build_object('businessNo', v_row ->> 'bill_no'), v_status
    );
  elsif tg_table_name = 'vehicle_insurance' then
    perform app_private.upsert_notification_subject(
      v_tenant_id, 'vms_commercial_insurance_expiry', 'vehicle_insurance', v_business_id, 'commercial',
      coalesce(v_row ->> 'plate_no', '车辆') || ' 商业险到期',
      case when v_row ->> 'commercial_expire_date' is null then null
        else ((v_row ->> 'commercial_expire_date')::date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/insurance-expiry', jsonb_build_object('vehicleId', v_row ->> 'vehicle_id'),
      jsonb_build_object('plateNo', v_row ->> 'plate_no'), v_status
    );
    perform app_private.upsert_notification_subject(
      v_tenant_id, 'vms_compulsory_insurance_expiry', 'vehicle_insurance', v_business_id, 'compulsory',
      coalesce(v_row ->> 'plate_no', '车辆') || ' 交强险到期',
      case when v_row ->> 'compulsory_expire_date' is null then null
        else ((v_row ->> 'compulsory_expire_date')::date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/insurance-expiry', jsonb_build_object('vehicleId', v_row ->> 'vehicle_id'),
      jsonb_build_object('plateNo', v_row ->> 'plate_no'), v_status
    );
  elsif tg_table_name = 'vehicle_inspection' then
    perform app_private.upsert_notification_subject(
      v_tenant_id, 'vms_vehicle_inspection_expiry', 'vehicle_inspection', v_business_id, 'expire_date',
      coalesce(v_row ->> 'plate_no', '车辆') || ' 年检到期',
      case when v_row ->> 'expire_date' is null then null
        else ((v_row ->> 'expire_date')::date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/inspection-expiry', jsonb_build_object('vehicleId', v_row ->> 'vehicle_id'),
      jsonb_build_object('plateNo', v_row ->> 'plate_no'), v_status
    );
  elsif tg_table_name = 'vehicle_archive' then
    if coalesce(v_row ->> 'operation_status', '') in ('scrapped', 'retired', 'inactive') then v_status := 'resolved'; end if;
    perform app_private.upsert_notification_subject(
      v_tenant_id, 'vms_vehicle_service_expiry', 'vehicle_archive', v_business_id, 'service_end',
      coalesce(v_row ->> 'plate_no', '车辆') || ' 服务期到期',
      case when v_row ->> 'service_end_time' is null then null
        else ((v_row ->> 'service_end_time')::date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/vehicle-service-life', jsonb_build_object('vehicleId', v_business_id),
      jsonb_build_object('plateNo', v_row ->> 'plate_no'), v_status
    );
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger sys_tenant_sync_notification_subject
after insert or update of tenant_name, status, service_end_date or delete on public.sys_tenant
for each row execute function app_private.sync_notification_subject_from_source();
create trigger tms_contract_sync_notification_subject
after insert or update of contract_name, contract_no, expiry_date, is_completed, created_by_user_id or delete on public.tms_contract
for each row execute function app_private.sync_notification_subject_from_source();
create trigger fms_commercial_bill_sync_notification_subject
after insert or update of bill_no, due_date, status or delete on public.fms_commercial_bill
for each row execute function app_private.sync_notification_subject_from_source();
create trigger vehicle_insurance_sync_notification_subject
after insert or update of plate_no, commercial_expire_date, compulsory_expire_date or delete on public.vehicle_insurance
for each row execute function app_private.sync_notification_subject_from_source();
create trigger vehicle_inspection_sync_notification_subject
after insert or update of plate_no, expire_date or delete on public.vehicle_inspection
for each row execute function app_private.sync_notification_subject_from_source();
create trigger vehicle_archive_sync_notification_subject
after insert or update of plate_no, service_end_time, operation_status or delete on public.vehicle_archive
for each row execute function app_private.sync_notification_subject_from_source();

-- Seed subjects already present before this migration.
do $subjects$
declare
  v_row record;
begin
  for v_row in select * from public.sys_tenant loop
    perform app_private.upsert_notification_subject(
      v_row.id, 'tenant_expiry', 'sys_tenant', v_row.id, 'service_end',
      v_row.tenant_name || ' 服务到期',
      case when v_row.service_end_date is null then null
        else (v_row.service_end_date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/system/tenant', jsonb_build_object('tenantId', v_row.id), '{}'::jsonb,
      case when v_row.status = '1' then 'active' else 'cancelled' end
    );
  end loop;
  for v_row in select * from public.tms_contract loop
    perform app_private.upsert_notification_subject(
      v_row.tenant_id, 'tms_contract_expiry', 'tms_contract', v_row.id, 'expiry_date',
      '运输合同「' || coalesce(v_row.contract_name, v_row.contract_no, '未命名') || '」到期',
      case when v_row.expiry_date is null then null else (v_row.expiry_date + time '09:00') at time zone 'Asia/Shanghai' end,
      v_row.created_by_user_id, '/tms/basic-data/contract', jsonb_build_object('contractId', v_row.id),
      jsonb_build_object('businessNo', v_row.contract_no), case when coalesce(v_row.is_completed, false) then 'resolved' else 'active' end
    );
  end loop;
  for v_row in select * from public.fms_commercial_bill loop
    perform app_private.upsert_notification_subject(
      v_row.tenant_id, 'fms_commercial_bill_due', 'fms_commercial_bill', v_row.id, 'due_date',
      '商业票据「' || coalesce(v_row.bill_no, '未编号') || '」到期',
      case when v_row.due_date is null then null else (v_row.due_date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/fms/commercial-bill', jsonb_build_object('billId', v_row.id), jsonb_build_object('businessNo', v_row.bill_no),
      case when v_row.status in ('settled', 'cancelled', 'voided') then 'resolved' else 'active' end
    );
  end loop;
end
$subjects$;

create or replace function app_private.can_view_notification_reminders()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and app_private.has_permission('System:NotificationReminder:View');
$$;

create or replace function public.get_notification_reminder_workspace(p_tenant_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
begin
  if not app_private.can_view_notification_reminders() then
    raise exception '缺少查看消息提醒配置权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.notification_target_tenant(p_tenant_id);

  return jsonb_build_object(
    'tenant', (
      select jsonb_build_object(
        'id', tenant_row.id,
        'tenantCode', tenant_row.tenant_code,
        'tenantName', tenant_row.tenant_name,
        'serviceStartDate', tenant_row.service_start_date,
        'serviceEndDate', tenant_row.service_end_date,
        'status', tenant_row.status
      )
      from public.sys_tenant tenant_row where tenant_row.id = v_tenant_id
    ),
    'scenarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', scenario.id,
        'scenarioCode', scenario.scenario_code,
        'scenarioName', scenario.scenario_name,
        'moduleCode', scenario.module_code,
        'description', scenario.description,
        'routePath', scenario.route_path
      ) order by scenario.sort, scenario.id)
      from public.sys_notification_scenario scenario where scenario.enabled is true
    ), '[]'::jsonb),
    'rules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rule_row.id,
        'tenantId', rule_row.tenant_id,
        'scenarioId', rule_row.scenario_id,
        'scenarioCode', scenario.scenario_code,
        'scenarioName', scenario.scenario_name,
        'moduleCode', scenario.module_code,
        'ruleName', rule_row.rule_name,
        'leadDays', rule_row.lead_days,
        'repeatEveryDays', rule_row.repeat_every_days,
        'sendHour', rule_row.send_hour,
        'recipientStrategy', rule_row.recipient_strategy,
        'recipientRoleCodes', rule_row.recipient_role_codes,
        'channels', rule_row.channels,
        'enabled', rule_row.enabled,
        'updateTime', rule_row.update_time,
        'updateBy', rule_row.update_by
      ) order by scenario.sort, rule_row.lead_days desc, rule_row.rule_name)
      from public.sys_notification_rule rule_row
      join public.sys_notification_scenario scenario on scenario.id = rule_row.scenario_id
      where rule_row.tenant_id = v_tenant_id
    ), '[]'::jsonb),
    'channels', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', channel.id,
        'tenantId', channel.tenant_id,
        'channelCode', channel.channel_code,
        'providerCode', channel.provider_code,
        'enabled', channel.enabled,
        'config', channel.config,
        'secretConfigured', channel.channel_code = 'in_app' or channel.vault_secret_id is not null,
        'lastTestAt', channel.last_test_at,
        'lastTestStatus', channel.last_test_status,
        'lastError', channel.last_error,
        'updateTime', channel.update_time
      ) order by array_position(array['in_app','email','sms','dingtalk','wecom']::text[], channel.channel_code))
      from public.sys_notification_channel_config channel
      where channel.tenant_id = v_tenant_id
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'activeSubjectCount', (
        select count(*) from public.sys_notification_subject subject
        where subject.tenant_id = v_tenant_id and subject.status = 'active'
      ),
      'dueWithin30Days', (
        select count(*) from public.sys_notification_subject subject
        where subject.tenant_id = v_tenant_id and subject.status = 'active'
          and subject.due_at >= now() and subject.due_at < now() + interval '30 days'
      ),
      'enabledRuleCount', (
        select count(*) from public.sys_notification_rule rule_row
        where rule_row.tenant_id = v_tenant_id and rule_row.enabled is true
      ),
      'enabledChannelCount', (
        select count(*) from public.sys_notification_channel_config channel
        where channel.tenant_id = v_tenant_id and channel.enabled is true
      ),
      'pendingDeliveryCount', (
        select count(*) from public.sys_notification_delivery delivery
        where delivery.tenant_id = v_tenant_id and delivery.status in ('pending', 'processing', 'failed')
      ),
      'failedDeliveryCount', (
        select count(*) from public.sys_notification_delivery delivery
        where delivery.tenant_id = v_tenant_id and delivery.status = 'failed'
      )
    )
  );
end;
$$;

create or replace function public.save_notification_rule(p_rule jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule_id uuid := nullif(p_rule ->> 'id', '')::uuid;
  v_tenant_id uuid := app_private.notification_target_tenant(nullif(p_rule ->> 'tenantId', '')::uuid);
  v_scenario_id uuid := nullif(p_rule ->> 'scenarioId', '')::uuid;
  v_channels text[];
  v_roles text[];
  v_result public.sys_notification_rule%rowtype;
begin
  if v_rule_id is null then
    if not app_private.has_permission('System:NotificationReminder:AddRule') then
      raise exception '缺少新增提醒规则权限' using errcode = '42501';
    end if;
  elsif not app_private.has_permission('System:NotificationReminder:EditRule') then
    raise exception '缺少编辑提醒规则权限' using errcode = '42501';
  end if;

  if not exists (select 1 from public.sys_notification_scenario where id = v_scenario_id and enabled is true) then
    raise exception '提醒场景不存在或已停用';
  end if;
  select array_agg(distinct value order by value) into v_channels
  from jsonb_array_elements_text(coalesce(p_rule -> 'channels', '[]'::jsonb)) value;
  select coalesce(array_agg(distinct value order by value), array[]::text[]) into v_roles
  from jsonb_array_elements_text(coalesce(p_rule -> 'recipientRoleCodes', '[]'::jsonb)) value;
  if coalesce(cardinality(v_channels), 0) = 0 then raise exception '请至少选择一个通知渠道'; end if;

  if v_rule_id is null then
    insert into public.sys_notification_rule (
      tenant_id, scenario_id, rule_name, lead_days, repeat_every_days, send_hour,
      recipient_strategy, recipient_role_codes, channels, enabled, create_by, update_by
    ) values (
      v_tenant_id, v_scenario_id, btrim(p_rule ->> 'ruleName'),
      coalesce((p_rule ->> 'leadDays')::integer, 0), nullif(p_rule ->> 'repeatEveryDays', '')::integer,
      coalesce((p_rule ->> 'sendHour')::smallint, 9),
      coalesce(nullif(p_rule ->> 'recipientStrategy', ''), 'owner_then_roles'),
      v_roles, v_channels, coalesce((p_rule ->> 'enabled')::boolean, true),
      coalesce(app_private.current_user_email(), 'system-reminder'),
      coalesce(app_private.current_user_email(), 'system-reminder')
    ) returning * into v_result;
  else
    update public.sys_notification_rule
    set scenario_id = v_scenario_id,
        rule_name = btrim(p_rule ->> 'ruleName'),
        lead_days = coalesce((p_rule ->> 'leadDays')::integer, 0),
        repeat_every_days = nullif(p_rule ->> 'repeatEveryDays', '')::integer,
        send_hour = coalesce((p_rule ->> 'sendHour')::smallint, 9),
        recipient_strategy = coalesce(nullif(p_rule ->> 'recipientStrategy', ''), 'owner_then_roles'),
        recipient_role_codes = v_roles,
        channels = v_channels,
        enabled = coalesce((p_rule ->> 'enabled')::boolean, true),
        update_by = coalesce(app_private.current_user_email(), 'system-reminder')
    where id = v_rule_id and tenant_id = v_tenant_id
    returning * into v_result;
    if not found then raise exception '提醒规则不存在或无权编辑'; end if;
  end if;
  return to_jsonb(v_result);
end;
$$;

create or replace function public.delete_notification_rule(p_rule_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.sys_notification_rule%rowtype;
begin
  if not app_private.has_permission('System:NotificationReminder:DeleteRule') then
    raise exception '缺少删除提醒规则权限' using errcode = '42501';
  end if;
  select * into v_rule from public.sys_notification_rule where id = p_rule_id;
  if not found then return false; end if;
  perform app_private.notification_target_tenant(v_rule.tenant_id);
  delete from public.sys_notification_rule where id = p_rule_id;
  return found;
end;
$$;

create or replace function public.save_notification_channel_config(
  p_tenant_id uuid,
  p_channel_code text,
  p_provider_code text,
  p_enabled boolean,
  p_config jsonb,
  p_secret jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.notification_target_tenant(p_tenant_id);
  v_secret_id uuid;
  v_result public.sys_notification_channel_config%rowtype;
  v_secret_name text;
begin
  if not app_private.has_permission('System:NotificationReminder:EditChannel') then
    raise exception '缺少编辑通知渠道权限' using errcode = '42501';
  end if;
  if p_channel_code not in ('in_app', 'email', 'sms', 'dingtalk', 'wecom') then
    raise exception '不支持的通知渠道';
  end if;
  if coalesce(jsonb_typeof(p_config), 'null') <> 'object'
     or (p_secret is not null and jsonb_typeof(p_secret) <> 'object') then
    raise exception '渠道配置格式无效';
  end if;

  select vault_secret_id into v_secret_id
  from public.sys_notification_channel_config
  where tenant_id = v_tenant_id and channel_code = p_channel_code;

  if p_channel_code <> 'in_app' and p_secret is not null and p_secret <> '{}'::jsonb then
    v_secret_name := 'notification_channel_' || replace(v_tenant_id::text, '-', '') || '_' || p_channel_code;
    if v_secret_id is null then
      select vault.create_secret(p_secret::text, v_secret_name, 'Notification channel credential')
        into v_secret_id;
    else
      perform vault.update_secret(v_secret_id, p_secret::text);
    end if;
  end if;

  insert into public.sys_notification_channel_config (
    tenant_id, channel_code, provider_code, enabled, config, vault_secret_id,
    create_by, update_by
  ) values (
    v_tenant_id, p_channel_code, coalesce(nullif(btrim(p_provider_code), ''), 'builtin'),
    case when p_channel_code = 'in_app' then true else coalesce(p_enabled, false) end,
    coalesce(p_config, '{}'::jsonb), v_secret_id,
    coalesce(app_private.current_user_email(), 'system-reminder'),
    coalesce(app_private.current_user_email(), 'system-reminder')
  )
  on conflict (tenant_id, channel_code) do update
  set provider_code = excluded.provider_code,
      enabled = excluded.enabled,
      config = excluded.config,
      vault_secret_id = coalesce(excluded.vault_secret_id, public.sys_notification_channel_config.vault_secret_id),
      last_error = null,
      update_by = excluded.update_by
  returning * into v_result;

  return jsonb_build_object(
    'id', v_result.id,
    'tenantId', v_result.tenant_id,
    'channelCode', v_result.channel_code,
    'providerCode', v_result.provider_code,
    'enabled', v_result.enabled,
    'config', v_result.config,
    'secretConfigured', v_result.channel_code = 'in_app' or v_result.vault_secret_id is not null
  );
end;
$$;

create or replace function public.test_notification_channel(p_tenant_id uuid, p_channel_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.notification_target_tenant(p_tenant_id);
  v_user_id uuid := app_private.current_app_user_id();
  v_delivery_id uuid;
begin
  if not app_private.has_permission('System:NotificationReminder:TestChannel') then
    raise exception '缺少测试通知渠道权限' using errcode = '42501';
  end if;
  if v_user_id is null then raise exception '当前账号未绑定业务用户'; end if;
  if not exists (
    select 1 from public.sys_notification_channel_config
    where tenant_id = v_tenant_id and channel_code = p_channel_code
      and (channel_code = 'in_app' or vault_secret_id is not null)
  ) then raise exception '请先完成该渠道的凭据配置'; end if;

  insert into public.sys_notification_delivery (
    tenant_id, recipient_user_id, channel_code, title, content, route_path,
    status, create_by, update_by
  ) values (
    v_tenant_id, v_user_id, p_channel_code, '通知渠道测试',
    '这是一条渠道连通性测试消息，发送时间：' || to_char(now() at time zone 'Asia/Shanghai', 'YYYY-MM-DD HH24:MI:SS'),
    '/system/notification-reminder', 'pending',
    coalesce(app_private.current_user_email(), 'system-reminder'),
    coalesce(app_private.current_user_email(), 'system-reminder')
  ) returning id into v_delivery_id;

  update public.sys_notification_channel_config
  set last_test_at = now(), last_test_status = 'pending', last_error = null,
      update_by = coalesce(app_private.current_user_email(), 'system-reminder')
  where tenant_id = v_tenant_id and channel_code = p_channel_code;

  if p_channel_code = 'in_app' then
    perform app_private.enqueue_user_notification(
      v_user_id, v_tenant_id, 'message', '通知渠道测试', '站内通知渠道已连通。',
      'success', 'notification_channel_test', v_delivery_id,
      'notification_channel', v_delivery_id, null, '/system/notification-reminder', '{}'::jsonb
    );
    update public.sys_notification_delivery
    set status = 'delivered', delivered_at = now(), attempt_count = 1, update_by = 'system-reminder'
    where id = v_delivery_id;
    update public.sys_notification_channel_config
    set last_test_status = 'delivered', update_by = 'system-reminder'
    where tenant_id = v_tenant_id and channel_code = p_channel_code;
  end if;
  return v_delivery_id;
end;
$$;

create or replace function app_private.process_notification_reminders(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 2000);
  v_created_events integer := 0;
  v_created_deliveries integer := 0;
  v_delivered_in_app integer := 0;
  v_delivery record;
  v_rows integer;
begin
  insert into public.sys_notification_event (
    tenant_id, subject_id, rule_id, occurrence_date, scheduled_at,
    title, content, severity, status, create_by, update_by
  )
  select
    subject.tenant_id,
    subject.id,
    rule_row.id,
    case when rule_row.repeat_every_days is null
      then (subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days
      else v_today
    end,
    (
      case when rule_row.repeat_every_days is null
        then (subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days
        else v_today
      end + make_time(rule_row.send_hour, 0, 0)
    ) at time zone 'Asia/Shanghai',
    subject.subject_title,
    case
      when (subject.due_at at time zone 'Asia/Shanghai')::date < v_today
        then subject.subject_title || '，已到期 ' || (v_today - (subject.due_at at time zone 'Asia/Shanghai')::date) || ' 天，请尽快处理。'
      when (subject.due_at at time zone 'Asia/Shanghai')::date = v_today
        then subject.subject_title || '，今天到期，请及时处理。'
      else subject.subject_title || '，还有 ' || ((subject.due_at at time zone 'Asia/Shanghai')::date - v_today) || ' 天到期，请提前处理。'
    end,
    case when (subject.due_at at time zone 'Asia/Shanghai')::date <= v_today then 'danger' else 'warning' end,
    'pending', 'system-reminder', 'system-reminder'
  from public.sys_notification_subject subject
  join public.sys_notification_rule rule_row
    on rule_row.tenant_id = subject.tenant_id
   and rule_row.scenario_id = subject.scenario_id
   and rule_row.enabled is true
  join public.sys_tenant tenant_row on tenant_row.id = subject.tenant_id and tenant_row.status = '1'
  where subject.status = 'active'
    and v_today >= (subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days
    and v_today <= (subject.due_at at time zone 'Asia/Shanghai')::date
    and (
      rule_row.repeat_every_days is null
      or mod(
        v_today - ((subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days),
        rule_row.repeat_every_days
      ) = 0
    )
  on conflict (subject_id, rule_id, occurrence_date) do nothing;
  get diagnostics v_created_events = row_count;

  insert into public.sys_notification_delivery (
    tenant_id, event_id, recipient_user_id, channel_code, title, content,
    route_path, route_query, status, create_by, update_by
  )
  select distinct
    event_row.tenant_id, event_row.id, recipient.id, channel.channel_code,
    event_row.title, event_row.content, subject.route_path, subject.route_query,
    'pending', 'system-reminder', 'system-reminder'
  from public.sys_notification_event event_row
  join public.sys_notification_subject subject
    on subject.id = event_row.subject_id and subject.tenant_id = event_row.tenant_id
  join public.sys_notification_rule rule_row
    on rule_row.id = event_row.rule_id and rule_row.tenant_id = event_row.tenant_id
  join public.sys_notification_channel_config channel
    on channel.tenant_id = event_row.tenant_id
   and channel.channel_code = any(rule_row.channels)
   and channel.enabled is true
  join lateral (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = event_row.tenant_id
      and user_row.status = '1'
      and user_row.deleted_at is null
      and (
        (rule_row.recipient_strategy = 'owner_then_roles' and user_row.id = subject.owner_user_id)
        or exists (
          select 1 from public.sys_role role_row
          where role_row.tenant_id = user_row.tenant_id
            and role_row.enabled is true
            and role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
            and role_row.role_code = any(rule_row.recipient_role_codes)
        )
      )
  ) recipient on true
  where event_row.status in ('pending', 'failed')
    and event_row.scheduled_at <= now()
  on conflict (event_id, recipient_user_id, channel_code) do nothing;
  get diagnostics v_created_deliveries = row_count;

  for v_delivery in
    select delivery.*, subject.business_type, subject.business_id
    from public.sys_notification_delivery delivery
    left join public.sys_notification_event event_row on event_row.id = delivery.event_id
    left join public.sys_notification_subject subject on subject.id = event_row.subject_id
    where delivery.channel_code = 'in_app' and delivery.status in ('pending', 'failed')
      and (delivery.next_retry_at is null or delivery.next_retry_at <= now())
    order by delivery.create_time
    for update of delivery skip locked
    limit v_limit
  loop
    begin
      update public.sys_notification_delivery
      set status = 'processing', attempt_count = attempt_count + 1, update_by = 'system-reminder'
      where id = v_delivery.id;
      perform app_private.enqueue_user_notification(
        v_delivery.recipient_user_id, v_delivery.tenant_id, 'message',
        v_delivery.title, v_delivery.content, 'warning', 'notification_reminder_delivery',
        v_delivery.id, v_delivery.business_type, v_delivery.business_id, null,
        v_delivery.route_path, v_delivery.route_query
      );
      update public.sys_notification_delivery
      set status = 'delivered', delivered_at = now(), next_retry_at = null,
          error_message = null, update_by = 'system-reminder'
      where id = v_delivery.id;
      v_delivered_in_app := v_delivered_in_app + 1;
    exception when others then
      update public.sys_notification_delivery
      set status = 'failed', next_retry_at = now() + interval '15 minutes',
          error_message = left(sqlerrm, 1000), update_by = 'system-reminder'
      where id = v_delivery.id;
    end;
  end loop;

  update public.sys_notification_event event_row
  set status = case
        when exists (select 1 from public.sys_notification_delivery d where d.event_id = event_row.id and d.status in ('pending','processing','failed')) then 'queued'
        when exists (select 1 from public.sys_notification_delivery d where d.event_id = event_row.id and d.status = 'delivered') then 'delivered'
        else 'failed'
      end,
      update_by = 'system-reminder'
  where event_row.status in ('pending', 'queued', 'failed')
    and exists (select 1 from public.sys_notification_delivery d where d.event_id = event_row.id);
  get diagnostics v_rows = row_count;

  return jsonb_build_object(
    'createdEventCount', v_created_events,
    'createdDeliveryCount', v_created_deliveries,
    'deliveredInAppCount', v_delivered_in_app,
    'updatedEventCount', v_rows
  );
end;
$$;

create or replace function public.run_notification_reminders_now(p_tenant_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission('System:NotificationReminder:Dispatch') then
    raise exception '缺少立即执行提醒任务权限' using errcode = '42501';
  end if;
  perform app_private.notification_target_tenant(coalesce(p_tenant_id, app_private.current_user_tenant_id()));
  return app_private.process_notification_reminders(500);
end;
$$;

create or replace function public.get_notification_dispatch_scope()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission('System:NotificationReminder:Dispatch')
     and not app_private.has_permission('System:NotificationReminder:TestChannel') then
    raise exception '缺少通知投递权限' using errcode = '42501';
  end if;
  return app_private.current_user_tenant_id();
end;
$$;

create or replace function public.claim_notification_deliveries(
  p_limit integer default 50,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  with candidates as (
    select delivery.id
    from public.sys_notification_delivery delivery
    join public.sys_notification_channel_config channel
      on channel.tenant_id = delivery.tenant_id
     and channel.channel_code = delivery.channel_code
     and channel.enabled is true
    where delivery.channel_code <> 'in_app'
      and delivery.status in ('pending', 'failed')
      and delivery.attempt_count < 5
      and (delivery.next_retry_at is null or delivery.next_retry_at <= now())
      and (p_tenant_id is null or delivery.tenant_id = p_tenant_id)
    order by delivery.create_time
    for update of delivery skip locked
    limit least(greatest(coalesce(p_limit, 50), 1), 200)
  ), claimed as (
    update public.sys_notification_delivery delivery
    set status = 'processing', attempt_count = attempt_count + 1,
        error_message = null, update_by = 'notification-dispatcher'
    from candidates
    where delivery.id = candidates.id
    returning delivery.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', claimed.id,
    'tenantId', claimed.tenant_id,
    'recipientUserId', claimed.recipient_user_id,
    'recipientEmail', user_row.user_email,
    'recipientPhone', user_row.user_phone,
    'channelCode', claimed.channel_code,
    'title', claimed.title,
    'content', claimed.content,
    'routePath', claimed.route_path,
    'routeQuery', claimed.route_query,
    'attemptCount', claimed.attempt_count,
    'providerCode', channel.provider_code,
    'config', channel.config,
    'secret', coalesce(secret.decrypted_secret::jsonb, '{}'::jsonb)
  ) order by claimed.create_time), '[]'::jsonb)
  into v_result
  from claimed
  join public.sys_user user_row on user_row.id = claimed.recipient_user_id
  join public.sys_notification_channel_config channel
    on channel.tenant_id = claimed.tenant_id and channel.channel_code = claimed.channel_code
  left join vault.decrypted_secrets secret on secret.id = channel.vault_secret_id;
  return v_result;
end;
$$;

create or replace function public.finish_notification_delivery(
  p_delivery_id uuid,
  p_succeeded boolean,
  p_external_message_id text default null,
  p_error_message text default null,
  p_skipped boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery public.sys_notification_delivery%rowtype;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  update public.sys_notification_delivery
  set status = case when p_succeeded then 'delivered' when p_skipped then 'skipped' else 'failed' end,
      delivered_at = case when p_succeeded then now() else null end,
      external_message_id = nullif(p_external_message_id, ''),
      error_message = case when p_succeeded then null else left(coalesce(p_error_message, '投递失败'), 1000) end,
      next_retry_at = case
        when p_succeeded or p_skipped or attempt_count >= 5 then null
        else now() + make_interval(mins => least(15 * attempt_count, 120))
      end,
      update_by = 'notification-dispatcher'
  where id = p_delivery_id and status = 'processing'
  returning * into v_delivery;
  if not found then return false; end if;

  update public.sys_notification_channel_config
  set last_test_status = case
        when last_test_at is not null and last_test_at >= v_delivery.create_time
          then case when p_succeeded then 'delivered' else 'failed' end
        else last_test_status
      end,
      last_error = case when p_succeeded then null else left(coalesce(p_error_message, '投递失败'), 1000) end,
      update_by = 'notification-dispatcher'
  where tenant_id = v_delivery.tenant_id and channel_code = v_delivery.channel_code;

  if v_delivery.event_id is not null and not exists (
    select 1 from public.sys_notification_delivery
    where event_id = v_delivery.event_id and status in ('pending', 'processing', 'failed')
  ) then
    update public.sys_notification_event
    set status = case when exists (
          select 1 from public.sys_notification_delivery
          where event_id = v_delivery.event_id and status = 'delivered'
        ) then 'delivered' else 'failed' end,
        update_by = 'notification-dispatcher'
    where id = v_delivery.event_id;
  end if;
  return true;
end;
$$;

revoke all on function public.claim_notification_deliveries(integer, uuid) from public, anon, authenticated;
revoke all on function public.finish_notification_delivery(uuid, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.claim_notification_deliveries(integer, uuid) to service_role;
grant execute on function public.finish_notification_delivery(uuid, boolean, text, text, boolean) to service_role;
grant execute on function public.get_notification_reminder_workspace(uuid) to authenticated;
grant execute on function public.save_notification_rule(jsonb) to authenticated;
grant execute on function public.delete_notification_rule(uuid) to authenticated;
grant execute on function public.save_notification_channel_config(uuid, text, text, boolean, jsonb, jsonb) to authenticated;
grant execute on function public.test_notification_channel(uuid, text) to authenticated;
grant execute on function public.run_notification_reminders_now(uuid) to authenticated;
grant execute on function public.get_notification_dispatch_scope() to authenticated;

do $dispatch_secret$
begin
  if not exists (
    select 1 from vault.decrypted_secrets where name = 'notification_dispatch_cron_token'
  ) then
    perform vault.create_secret(
      encode(gen_random_bytes(32), 'hex'),
      'notification_dispatch_cron_token',
      'Authenticates pg_cron calls to the notification dispatcher'
    );
  end if;
end
$dispatch_secret$;

create or replace function public.verify_notification_dispatch_token(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'role'), '') = 'service_role'
    and exists (
      select 1 from vault.decrypted_secrets
      where name = 'notification_dispatch_cron_token'
        and decrypted_secret = p_token
    );
$$;

revoke all on function public.verify_notification_dispatch_token(text) from public, anon, authenticated;
grant execute on function public.verify_notification_dispatch_token(text) to service_role;

create or replace function app_private.invoke_notification_dispatcher()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_request_id bigint;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'notification_dispatch_cron_token'
  limit 1;
  if v_token is null then raise exception 'Notification dispatch token is missing'; end if;

  select net.http_post(
    url := 'https://ckbftoopuyophiebamwy.supabase.co/functions/v1/notification-dispatcher',
    body := jsonb_build_object('limit', 100),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notification-dispatch-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;
  return v_request_id;
end;
$$;

-- Register the page and every page action as assignable RBAC records.
do $menu$
declare
  v_system_menu_id uuid;
  v_page_menu_id uuid;
  v_button_id uuid;
  v_permission record;
begin
  select id into v_system_menu_id from public.sys_menu
  where name = 'System' and type is distinct from 'button' order by create_time limit 1;
  if v_system_menu_id is null then raise exception 'System menu not found'; end if;

  select id into v_page_menu_id from public.sys_menu
  where name = 'NotificationReminder' and type = 'menu' order by create_time limit 1;
  if v_page_menu_id is null then
    insert into public.sys_menu (
      parent_id, name, path, component, meta, sort, type, create_by, update_by
    ) values (
      v_system_menu_id, 'NotificationReminder', 'notification-reminder',
      '/system/notification-reminder',
      jsonb_build_object(
        'icon', 'ri:notification-badge-line', 'link', '', 'roles', '[]'::jsonb,
        'title', '消息提醒', 'is_hide', false, 'fixed_tab', false, 'is_enable', true,
        'is_iframe', false, 'keep_alive', true, 'show_badge', false, 'active_path', '',
        'is_hide_tab', false, 'is_full_page', false, 'is_auth_button', false,
        'show_text_badge', ''
      ), 15, 'menu', 'system-reminder', 'system-reminder'
    ) returning id into v_page_menu_id;
  end if;

  for v_permission in
    select * from (values
      ('System:NotificationReminder:View', '查看提醒配置', 1),
      ('System:NotificationReminder:AddRule', '新增提醒规则', 2),
      ('System:NotificationReminder:EditRule', '编辑提醒规则', 3),
      ('System:NotificationReminder:DeleteRule', '删除提醒规则', 4),
      ('System:NotificationReminder:EditChannel', '配置通知渠道', 5),
      ('System:NotificationReminder:TestChannel', '测试通知渠道', 6),
      ('System:NotificationReminder:Dispatch', '立即执行提醒', 7)
    ) item(permission_code, permission_title, permission_sort)
  loop
    select id into v_button_id from public.sys_menu
    where parent_id = v_page_menu_id and type = 'button' and name = v_permission.permission_code;
    if v_button_id is null then
      insert into public.sys_menu (
        parent_id, name, path, component, meta, sort, type, create_by, update_by
      ) values (
        v_page_menu_id, v_permission.permission_code, '', '',
        jsonb_build_object(
          'icon', '', 'link', '', 'roles', '[]'::jsonb,
          'title', v_permission.permission_title, 'is_hide', false, 'fixed_tab', false,
          'is_enable', true, 'is_iframe', false, 'keep_alive', false,
          'show_badge', false, 'active_path', '', 'is_hide_tab', false,
          'is_full_page', false, 'is_auth_button', true, 'show_text_badge', ''
        ), v_permission.permission_sort, 'button', 'system-reminder', 'system-reminder'
      ) returning id into v_button_id;
    end if;

    insert into public.sys_role_menu (tenant_id, role_id, menu_id, create_by, update_by)
    select distinct role_menu.tenant_id, role_menu.role_id, v_button_id,
           'system-reminder', 'system-reminder'
    from public.sys_role_menu role_menu
    join public.sys_menu permission_menu on permission_menu.id = role_menu.menu_id
    where permission_menu.name = 'System:Role:AssignPermission'
    on conflict (role_id, menu_id) do nothing;
  end loop;

  insert into public.sys_role_menu (tenant_id, role_id, menu_id, create_by, update_by)
  select distinct role_menu.tenant_id, role_menu.role_id, v_page_menu_id,
         'system-reminder', 'system-reminder'
  from public.sys_role_menu role_menu
  join public.sys_menu permission_menu on permission_menu.id = role_menu.menu_id
  where permission_menu.name = 'System:Role:AssignPermission'
  on conflict (role_id, menu_id) do nothing;
end
$menu$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'notification-reminder-engine';
  perform cron.unschedule(jobid) from cron.job where jobname = 'notification-external-dispatcher';
  perform cron.schedule(
    'notification-reminder-engine',
    '0 * * * *',
    'select app_private.process_notification_reminders(1000);'
  );
  perform cron.schedule(
    'notification-external-dispatcher',
    '*/5 * * * *',
    'select app_private.invoke_notification_dispatcher();'
  );
end
$cron$;

select app_private.process_notification_reminders(1000);

;
