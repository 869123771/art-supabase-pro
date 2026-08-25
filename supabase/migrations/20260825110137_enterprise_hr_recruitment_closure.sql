alter table public.hr_candidate
  add column if not exists consent_status text not null default 'pending',
  add column if not exists consent_at timestamptz,
  add column if not exists retention_until date,
  add column if not exists rejection_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_candidate_id_tenant_unique'
      and conrelid = 'public.hr_candidate'::regclass
  ) then
    alter table public.hr_candidate
      add constraint hr_candidate_id_tenant_unique unique (id, tenant_id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_candidate_consent_status_check'
      and conrelid = 'public.hr_candidate'::regclass
  ) then
    alter table public.hr_candidate
      add constraint hr_candidate_consent_status_check
      check (consent_status in ('pending', 'granted', 'withdrawn', 'expired'));
  end if;
end
$$;

alter table public.hr_recruitment_requisition
  drop constraint if exists hr_recruitment_requisition_status_check;
alter table public.hr_recruitment_requisition
  add constraint hr_recruitment_requisition_status_check
  check (status in ('draft', 'pending', 'approved', 'effective', 'completed', 'rejected', 'cancelled'));

create table public.hr_candidate_stage_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  candidate_id uuid not null,
  from_stage text,
  to_stage text not null,
  transition_reason text,
  changed_by text,
  changed_at timestamptz not null default now(),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_candidate_stage_history_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_candidate_stage_history_candidate_fkey foreign key (candidate_id, tenant_id)
    references public.hr_candidate(id, tenant_id) on delete restrict,
  constraint hr_candidate_stage_history_id_tenant_unique unique (id, tenant_id),
  constraint hr_candidate_stage_history_to_stage_not_blank check (btrim(to_stage) <> '')
);

create index hr_candidate_stage_history_candidate_fk_idx
  on public.hr_candidate_stage_history(candidate_id, tenant_id);
create index hr_candidate_stage_history_timeline_idx
  on public.hr_candidate_stage_history(tenant_id, candidate_id, changed_at desc);

create table public.hr_recruitment_interview (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  candidate_id uuid not null,
  round_no integer not null default 1,
  interview_type text not null default 'structured',
  scheduled_start_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  location text,
  interviewer_employee_id uuid not null,
  status text not null default 'scheduled',
  score numeric(5,2),
  recommendation text,
  feedback text,
  completed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_recruitment_interview_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_recruitment_interview_candidate_fkey foreign key (candidate_id, tenant_id)
    references public.hr_candidate(id, tenant_id) on delete restrict,
  constraint hr_recruitment_interview_interviewer_fkey foreign key (interviewer_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_recruitment_interview_id_tenant_unique unique (id, tenant_id),
  constraint hr_recruitment_interview_round_check check (round_no between 1 and 20),
  constraint hr_recruitment_interview_type_check check (
    interview_type in ('phone', 'video', 'onsite', 'structured', 'technical', 'panel', 'executive')
  ),
  constraint hr_recruitment_interview_status_check check (
    status in ('scheduled', 'completed', 'cancelled', 'no_show')
  ),
  constraint hr_recruitment_interview_score_check check (score is null or score between 0 and 100),
  constraint hr_recruitment_interview_recommendation_check check (
    recommendation is null or recommendation in ('strong_hire', 'hire', 'hold', 'no_hire')
  ),
  constraint hr_recruitment_interview_schedule_check check (scheduled_end_at > scheduled_start_at),
  constraint hr_recruitment_interview_completion_check check (
    (status = 'completed' and score is not null and recommendation is not null
      and feedback is not null and btrim(feedback) <> '' and completed_at is not null)
    or (status <> 'completed' and completed_at is null)
  )
);

create index hr_recruitment_interview_candidate_fk_idx
  on public.hr_recruitment_interview(candidate_id, tenant_id);
create index hr_recruitment_interview_interviewer_fk_idx
  on public.hr_recruitment_interview(interviewer_employee_id, tenant_id);
create index hr_recruitment_interview_schedule_idx
  on public.hr_recruitment_interview(tenant_id, status, scheduled_start_at);
create unique index hr_recruitment_interview_panel_unique
  on public.hr_recruitment_interview(tenant_id, candidate_id, round_no, interviewer_employee_id)
  where status <> 'cancelled';

create table public.hr_recruitment_offer (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  candidate_id uuid not null,
  offer_no text not null,
  version_no integer not null default 1,
  employment_type text not null default 'full_time',
  monthly_salary numeric(14,2) not null,
  target_bonus numeric(14,2) not null default 0,
  currency text not null default 'CNY',
  probation_months integer not null default 3,
  proposed_onboard_date date not null,
  expires_on date not null,
  status text not null default 'draft',
  approval_comment text,
  approved_by text,
  approved_at timestamptz,
  sent_at timestamptz,
  responded_at timestamptz,
  response_note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_recruitment_offer_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_recruitment_offer_candidate_fkey foreign key (candidate_id, tenant_id)
    references public.hr_candidate(id, tenant_id) on delete restrict,
  constraint hr_recruitment_offer_id_tenant_unique unique (id, tenant_id),
  constraint hr_recruitment_offer_no_unique unique (tenant_id, offer_no),
  constraint hr_recruitment_offer_version_unique unique (tenant_id, candidate_id, version_no),
  constraint hr_recruitment_offer_version_check check (version_no between 1 and 99),
  constraint hr_recruitment_offer_salary_check check (monthly_salary > 0 and target_bonus >= 0),
  constraint hr_recruitment_offer_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint hr_recruitment_offer_probation_check check (probation_months between 0 and 12),
  constraint hr_recruitment_offer_dates_check check (expires_on >= proposed_onboard_date - 180),
  constraint hr_recruitment_offer_status_check check (
    status in ('draft', 'pending_approval', 'approved', 'rejected', 'sent', 'accepted', 'declined', 'expired', 'withdrawn')
  )
);

create index hr_recruitment_offer_candidate_fk_idx
  on public.hr_recruitment_offer(candidate_id, tenant_id);
create index hr_recruitment_offer_status_idx
  on public.hr_recruitment_offer(tenant_id, status, expires_on);
create unique index hr_recruitment_offer_active_unique
  on public.hr_recruitment_offer(tenant_id, candidate_id)
  where status in ('pending_approval', 'approved', 'sent', 'accepted');

create table public.hr_recruitment_handoff (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  candidate_id uuid not null,
  offer_id uuid not null,
  organization_id uuid not null,
  position_id uuid not null,
  planned_onboard_date date not null,
  owner_employee_id uuid,
  buddy_employee_id uuid,
  onboard_employee_id uuid,
  status text not null default 'pending',
  handoff_note text,
  completed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_recruitment_handoff_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_recruitment_handoff_candidate_fkey foreign key (candidate_id, tenant_id)
    references public.hr_candidate(id, tenant_id) on delete restrict,
  constraint hr_recruitment_handoff_offer_fkey foreign key (offer_id, tenant_id)
    references public.hr_recruitment_offer(id, tenant_id) on delete restrict,
  constraint hr_recruitment_handoff_organization_fkey foreign key (organization_id)
    references public.sys_organization(id) on delete restrict,
  constraint hr_recruitment_handoff_position_fkey foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_recruitment_handoff_owner_fkey foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_recruitment_handoff_buddy_fkey foreign key (buddy_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_recruitment_handoff_onboard_employee_fkey foreign key (onboard_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_recruitment_handoff_id_tenant_unique unique (id, tenant_id),
  constraint hr_recruitment_handoff_candidate_unique unique (tenant_id, candidate_id),
  constraint hr_recruitment_handoff_offer_unique unique (tenant_id, offer_id),
  constraint hr_recruitment_handoff_status_check check (status in ('pending', 'ready', 'completed', 'cancelled')),
  constraint hr_recruitment_handoff_completion_check check (
    (status = 'completed' and onboard_employee_id is not null and completed_at is not null)
    or (status <> 'completed' and completed_at is null)
  )
);

create index hr_recruitment_handoff_candidate_fk_idx
  on public.hr_recruitment_handoff(candidate_id, tenant_id);
create index hr_recruitment_handoff_offer_fk_idx
  on public.hr_recruitment_handoff(offer_id, tenant_id);
create index hr_recruitment_handoff_position_fk_idx
  on public.hr_recruitment_handoff(position_id, tenant_id);
create index hr_recruitment_handoff_owner_fk_idx
  on public.hr_recruitment_handoff(owner_employee_id, tenant_id) where owner_employee_id is not null;
create index hr_recruitment_handoff_buddy_fk_idx
  on public.hr_recruitment_handoff(buddy_employee_id, tenant_id) where buddy_employee_id is not null;
create index hr_recruitment_handoff_onboard_employee_fk_idx
  on public.hr_recruitment_handoff(onboard_employee_id, tenant_id) where onboard_employee_id is not null;
create index hr_recruitment_handoff_due_idx
  on public.hr_recruitment_handoff(tenant_id, status, planned_onboard_date);

create table public.hr_recruitment_onboarding_task (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  handoff_id uuid not null,
  task_category text not null,
  task_title text not null,
  task_description text,
  owner_employee_id uuid,
  due_date date not null,
  status text not null default 'pending',
  completion_note text,
  completed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_recruitment_task_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_recruitment_task_handoff_fkey foreign key (handoff_id, tenant_id)
    references public.hr_recruitment_handoff(id, tenant_id) on delete restrict,
  constraint hr_recruitment_task_owner_fkey foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_recruitment_task_id_tenant_unique unique (id, tenant_id),
  constraint hr_recruitment_task_title_not_blank check (btrim(task_title) <> ''),
  constraint hr_recruitment_task_category_check check (
    task_category in ('documentation', 'account', 'equipment', 'workspace', 'orientation', 'training', 'payroll', 'other')
  ),
  constraint hr_recruitment_task_status_check check (status in ('pending', 'in_progress', 'completed', 'skipped')),
  constraint hr_recruitment_task_completion_check check (
    (status in ('completed', 'skipped') and completed_at is not null)
    or (status in ('pending', 'in_progress') and completed_at is null)
  )
);

create index hr_recruitment_task_handoff_fk_idx
  on public.hr_recruitment_onboarding_task(handoff_id, tenant_id);
create index hr_recruitment_task_owner_fk_idx
  on public.hr_recruitment_onboarding_task(owner_employee_id, tenant_id) where owner_employee_id is not null;
create index hr_recruitment_task_due_idx
  on public.hr_recruitment_onboarding_task(tenant_id, status, due_date);

create trigger hr_candidate_stage_history_create_audit before insert on public.hr_candidate_stage_history
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_recruitment_interview_create_audit before insert on public.hr_recruitment_interview
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_recruitment_interview_update_audit before update on public.hr_recruitment_interview
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_recruitment_offer_create_audit before insert on public.hr_recruitment_offer
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_recruitment_offer_update_audit before update on public.hr_recruitment_offer
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_recruitment_handoff_create_audit before insert on public.hr_recruitment_handoff
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_recruitment_handoff_update_audit before update on public.hr_recruitment_handoff
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_recruitment_task_create_audit before insert on public.hr_recruitment_onboarding_task
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_recruitment_task_update_audit before update on public.hr_recruitment_onboarding_task
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_candidate_stage_history enable row level security;
alter table public.hr_recruitment_interview enable row level security;
alter table public.hr_recruitment_offer enable row level security;
alter table public.hr_recruitment_handoff enable row level security;
alter table public.hr_recruitment_onboarding_task enable row level security;

create policy hr_candidate_stage_history_deny_direct_access on public.hr_candidate_stage_history
  for all to authenticated using (false) with check (false);
create policy hr_recruitment_interview_deny_direct_access on public.hr_recruitment_interview
  for all to authenticated using (false) with check (false);
create policy hr_recruitment_offer_deny_direct_access on public.hr_recruitment_offer
  for all to authenticated using (false) with check (false);
create policy hr_recruitment_handoff_deny_direct_access on public.hr_recruitment_handoff
  for all to authenticated using (false) with check (false);
create policy hr_recruitment_task_deny_direct_access on public.hr_recruitment_onboarding_task
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_candidate_stage_history from public, anon, authenticated;
revoke all on table public.hr_recruitment_interview from public, anon, authenticated;
revoke all on table public.hr_recruitment_offer from public, anon, authenticated;
revoke all on table public.hr_recruitment_handoff from public, anon, authenticated;
revoke all on table public.hr_recruitment_onboarding_task from public, anon, authenticated;
grant all on table public.hr_candidate_stage_history to service_role;
grant all on table public.hr_recruitment_interview to service_role;
grant all on table public.hr_recruitment_offer to service_role;
grant all on table public.hr_recruitment_handoff to service_role;
grant all on table public.hr_recruitment_onboarding_task to service_role;

create or replace function app_private.hr_guard_candidate_stage_write()
returns trigger language plpgsql set search_path = '' as $function$
begin
  if tg_op = 'INSERT' and coalesce(current_setting('app.hr_recruitment_engine', true), '') <> 'on' then
    new.stage := 'new';
  elsif tg_op = 'UPDATE' and old.stage is distinct from new.stage
    and coalesce(current_setting('app.hr_recruitment_engine', true), '') <> 'on' then
    raise exception '候选人阶段必须通过招聘流程动作变更' using errcode = '42501';
  end if;
  return new;
end
$function$;

drop trigger if exists hr_candidate_stage_write_guard on public.hr_candidate;
create trigger hr_candidate_stage_write_guard
before insert or update of stage on public.hr_candidate
for each row execute function app_private.hr_guard_candidate_stage_write();

create or replace function app_private.hr_append_candidate_stage(
  p_candidate_id uuid,
  p_to_stage text,
  p_reason text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_candidate public.hr_candidate;
  v_valid boolean := false;
begin
  select * into v_candidate
  from public.hr_candidate
  where id = p_candidate_id
  for update;
  if not found then raise exception '候选人不存在'; end if;
  if v_candidate.stage = p_to_stage then return; end if;

  v_valid :=
    (v_candidate.stage = 'new' and p_to_stage in ('screening', 'rejected', 'withdrawn')) or
    (v_candidate.stage = 'screening' and p_to_stage in ('interview', 'rejected', 'withdrawn')) or
    (v_candidate.stage = 'interview' and p_to_stage in ('offer', 'rejected', 'withdrawn')) or
    (v_candidate.stage = 'offer' and p_to_stage in ('hired', 'rejected', 'withdrawn'));
  if not v_valid then
    raise exception '候选人阶段不能从 % 变更为 %', v_candidate.stage, p_to_stage;
  end if;
  if p_to_stage in ('rejected', 'withdrawn') and nullif(btrim(p_reason), '') is null then
    raise exception '淘汰或放弃候选人必须填写原因';
  end if;

  perform pg_catalog.set_config('app.hr_recruitment_engine', 'on', true);
  update public.hr_candidate
  set stage = p_to_stage,
      rejection_reason = case when p_to_stage in ('rejected', 'withdrawn') then btrim(p_reason) else null end
  where id = p_candidate_id;
  insert into public.hr_candidate_stage_history(
    tenant_id, candidate_id, from_stage, to_stage, transition_reason, changed_by
  ) values (
    v_candidate.tenant_id, v_candidate.id, v_candidate.stage, p_to_stage,
    nullif(btrim(p_reason), ''), coalesce(app_private.current_user_email(), 'system')
  );
end
$function$;

revoke all on function app_private.hr_guard_candidate_stage_write() from public, anon, authenticated;
revoke all on function app_private.hr_append_candidate_stage(uuid, text, text) from public, anon, authenticated;

insert into public.hr_candidate_stage_history(
  tenant_id, candidate_id, from_stage, to_stage, transition_reason, changed_by
)
select tenant_id, id, null, stage, '历史数据初始化', 'system'
from public.hr_candidate candidate
where not exists (
  select 1 from public.hr_candidate_stage_history history where history.candidate_id = candidate.id
);

create or replace function public.hr_recruitment_overview_secure(p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:View', null, false) then
    raise exception '当前账号没有查看招聘工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  return jsonb_build_object(
    'active_requisition_count', (
      select count(*) from public.hr_recruitment_requisition r
      where (p_tenant_id is null or r.tenant_id = p_tenant_id) and r.status = 'effective'
    ),
    'open_candidate_count', (
      select count(*) from public.hr_candidate c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and c.stage in ('new', 'screening', 'interview', 'offer')
    ),
    'upcoming_interview_count', (
      select count(*) from public.hr_recruitment_interview i
      where (p_tenant_id is null or i.tenant_id = p_tenant_id)
        and i.status = 'scheduled' and i.scheduled_start_at <= now() + interval '7 days'
    ),
    'awaiting_offer_response_count', (
      select count(*) from public.hr_recruitment_offer o
      where (p_tenant_id is null or o.tenant_id = p_tenant_id) and o.status = 'sent'
    ),
    'accepted_offer_count', (
      select count(*) from public.hr_recruitment_offer o
      where (p_tenant_id is null or o.tenant_id = p_tenant_id) and o.status = 'accepted'
    ),
    'pending_handoff_count', (
      select count(*) from public.hr_recruitment_handoff h
      where (p_tenant_id is null or h.tenant_id = p_tenant_id) and h.status in ('pending', 'ready')
    ),
    'overdue_task_count', (
      select count(*) from public.hr_recruitment_onboarding_task t
      where (p_tenant_id is null or t.tenant_id = p_tenant_id)
        and t.status in ('pending', 'in_progress') and t.due_date < current_date
    ),
    'hired_candidate_count', (
      select count(*) from public.hr_candidate c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.stage = 'hired'
    )
  );
end
$function$;

create or replace function public.hr_list_recruitment_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_sensitive boolean;
  v_result jsonb;
begin
  if p_kind not in ('requisition', 'candidate', 'interview', 'offer', 'handoff', 'task') then
    raise exception '不支持的招聘记录类型';
  end if;
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:View', null, false) then
    raise exception '当前账号没有查看招聘工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_sensitive := app_private.can_execute_business_action(
    'HrRecruitment', 'Hr:Recruitment:Sensitive:View', null, false
  );

  if p_kind = 'requisition' then
    with filtered as materialized (
      select r.*, organization.organization_code, organization.organization_name,
        position.position_code, position.position_name,
        (select count(*) from public.hr_candidate c where c.requisition_id = r.id) candidate_count,
        (select count(*) from public.hr_candidate c where c.requisition_id = r.id and c.stage = 'interview') interview_count,
        (select count(*) from public.hr_candidate c where c.requisition_id = r.id and c.stage = 'offer') offer_count
      from public.hr_recruitment_requisition r
      join public.sys_organization organization on organization.id = r.organization_id
      join public.hr_position position on position.id = r.position_id and position.tenant_id = r.tenant_id
      where (p_tenant_id is null or r.tenant_id = p_tenant_id)
        and (p_status is null or r.status = p_status)
        and (v_keyword is null or r.requisition_no ilike '%' || v_keyword || '%'
          or organization.organization_name ilike '%' || v_keyword || '%'
          or position.position_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by create_time desc, requisition_no offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'organization_code' - 'organization_name' - 'position_code' - 'position_name')
        || jsonb_build_object(
          'organization', jsonb_build_object('id', organization_id, 'code', organization_code, 'name', organization_name),
          'position', jsonb_build_object('id', position_id, 'code', position_code, 'name', position_name)
        ) order by create_time desc, requisition_no
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'sensitive_access', v_sensitive
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'sensitive_access', v_sensitive));
  end if;

  if p_kind = 'candidate' then
    with filtered as materialized (
      select c.*, r.requisition_no, position.position_name, organization.organization_name,
        (select count(*) from public.hr_recruitment_interview i where i.candidate_id = c.id and i.status <> 'cancelled') interview_count,
        (select o.status from public.hr_recruitment_offer o where o.candidate_id = c.id order by o.version_no desc limit 1) latest_offer_status,
        (select max(h.changed_at) from public.hr_candidate_stage_history h where h.candidate_id = c.id) stage_changed_at
      from public.hr_candidate c
      join public.hr_recruitment_requisition r on r.id = c.requisition_id and r.tenant_id = c.tenant_id
      join public.hr_position position on position.id = r.position_id and position.tenant_id = r.tenant_id
      join public.sys_organization organization on organization.id = r.organization_id
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and (p_status is null or c.stage = p_status)
        and (v_keyword is null or c.candidate_name ilike '%' || v_keyword || '%'
          or r.requisition_no ilike '%' || v_keyword || '%'
          or position.position_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by create_time desc, candidate_name offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'requisition_no' - 'position_name' - 'organization_name' - 'phone' - 'email' - 'expected_salary')
        || jsonb_build_object(
          'phone', case when v_sensitive then phone else null end,
          'email', case when v_sensitive then email else null end,
          'expected_salary', case when v_sensitive then expected_salary else null end,
          'requisition', jsonb_build_object('id', requisition_id, 'code', requisition_no, 'position_name', position_name, 'organization_name', organization_name)
        ) order by create_time desc, candidate_name
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'sensitive_access', v_sensitive
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'sensitive_access', v_sensitive));
  end if;

  if p_kind = 'interview' then
    with filtered as materialized (
      select i.*, c.candidate_name, r.requisition_no, position.position_name,
        employee.employee_no interviewer_no, employee.employee_name interviewer_name
      from public.hr_recruitment_interview i
      join public.hr_candidate c on c.id = i.candidate_id and c.tenant_id = i.tenant_id
      join public.hr_recruitment_requisition r on r.id = c.requisition_id and r.tenant_id = c.tenant_id
      join public.hr_position position on position.id = r.position_id and position.tenant_id = r.tenant_id
      join public.hr_employee employee on employee.id = i.interviewer_employee_id and employee.tenant_id = i.tenant_id
      where (p_tenant_id is null or i.tenant_id = p_tenant_id)
        and (p_status is null or i.status = p_status)
        and (v_keyword is null or c.candidate_name ilike '%' || v_keyword || '%'
          or r.requisition_no ilike '%' || v_keyword || '%'
          or employee.employee_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by scheduled_start_at desc, round_no offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'candidate_name' - 'requisition_no' - 'position_name' - 'interviewer_no' - 'interviewer_name')
        || jsonb_build_object(
          'candidate', jsonb_build_object('id', candidate_id, 'name', candidate_name, 'requisition_no', requisition_no, 'position_name', position_name),
          'interviewer', jsonb_build_object('id', interviewer_employee_id, 'code', interviewer_no, 'name', interviewer_name)
        ) order by scheduled_start_at desc, round_no
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'sensitive_access', v_sensitive
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'sensitive_access', v_sensitive));
  end if;

  if p_kind = 'offer' then
    with filtered as materialized (
      select o.*, c.candidate_name, r.requisition_no, position.position_name
      from public.hr_recruitment_offer o
      join public.hr_candidate c on c.id = o.candidate_id and c.tenant_id = o.tenant_id
      join public.hr_recruitment_requisition r on r.id = c.requisition_id and r.tenant_id = c.tenant_id
      join public.hr_position position on position.id = r.position_id and position.tenant_id = r.tenant_id
      where (p_tenant_id is null or o.tenant_id = p_tenant_id)
        and (p_status is null or o.status = p_status)
        and (v_keyword is null or o.offer_no ilike '%' || v_keyword || '%'
          or c.candidate_name ilike '%' || v_keyword || '%' or position.position_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by create_time desc, version_no desc offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'candidate_name' - 'requisition_no' - 'position_name' - 'monthly_salary' - 'target_bonus')
        || jsonb_build_object(
          'monthly_salary', case when v_sensitive then monthly_salary else null end,
          'target_bonus', case when v_sensitive then target_bonus else null end,
          'candidate', jsonb_build_object('id', candidate_id, 'name', candidate_name, 'requisition_no', requisition_no, 'position_name', position_name)
        ) order by create_time desc, version_no desc
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'sensitive_access', v_sensitive
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'sensitive_access', v_sensitive));
  end if;

  if p_kind = 'handoff' then
    with filtered as materialized (
      select h.*, c.candidate_name, o.offer_no, r.requisition_no,
        organization.organization_name, position.position_name,
        owner.employee_no owner_no, owner.employee_name owner_name,
        buddy.employee_no buddy_no, buddy.employee_name buddy_name,
        onboard.employee_no onboard_no, onboard.employee_name onboard_name,
        (select count(*) from public.hr_recruitment_onboarding_task t where t.handoff_id = h.id) task_count,
        (select count(*) from public.hr_recruitment_onboarding_task t where t.handoff_id = h.id and t.status in ('completed', 'skipped')) completed_task_count,
        (select count(*) from public.hr_recruitment_onboarding_task t where t.handoff_id = h.id and t.status in ('pending', 'in_progress') and t.due_date < current_date) overdue_task_count
      from public.hr_recruitment_handoff h
      join public.hr_candidate c on c.id = h.candidate_id and c.tenant_id = h.tenant_id
      join public.hr_recruitment_offer o on o.id = h.offer_id and o.tenant_id = h.tenant_id
      join public.hr_recruitment_requisition r on r.id = c.requisition_id and r.tenant_id = c.tenant_id
      join public.sys_organization organization on organization.id = h.organization_id
      join public.hr_position position on position.id = h.position_id and position.tenant_id = h.tenant_id
      left join public.hr_employee owner on owner.id = h.owner_employee_id and owner.tenant_id = h.tenant_id
      left join public.hr_employee buddy on buddy.id = h.buddy_employee_id and buddy.tenant_id = h.tenant_id
      left join public.hr_employee onboard on onboard.id = h.onboard_employee_id and onboard.tenant_id = h.tenant_id
      where (p_tenant_id is null or h.tenant_id = p_tenant_id)
        and (p_status is null or h.status = p_status)
        and (v_keyword is null or c.candidate_name ilike '%' || v_keyword || '%'
          or o.offer_no ilike '%' || v_keyword || '%' or position.position_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by planned_onboard_date, candidate_name offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'candidate_name' - 'offer_no' - 'requisition_no' - 'organization_name' - 'position_name'
          - 'owner_no' - 'owner_name' - 'buddy_no' - 'buddy_name' - 'onboard_no' - 'onboard_name')
        || jsonb_build_object(
          'candidate', jsonb_build_object('id', candidate_id, 'name', candidate_name, 'requisition_no', requisition_no),
          'offer', jsonb_build_object('id', offer_id, 'code', offer_no),
          'organization', jsonb_build_object('id', organization_id, 'name', organization_name),
          'position', jsonb_build_object('id', position_id, 'name', position_name),
          'owner', case when owner_employee_id is null then null else jsonb_build_object('id', owner_employee_id, 'code', owner_no, 'name', owner_name) end,
          'buddy', case when buddy_employee_id is null then null else jsonb_build_object('id', buddy_employee_id, 'code', buddy_no, 'name', buddy_name) end,
          'onboard_employee', case when onboard_employee_id is null then null else jsonb_build_object('id', onboard_employee_id, 'code', onboard_no, 'name', onboard_name) end
        ) order by planned_onboard_date, candidate_name
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'sensitive_access', v_sensitive
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'sensitive_access', v_sensitive));
  end if;

  with filtered as materialized (
    select t.*, h.candidate_id, h.planned_onboard_date, c.candidate_name,
      owner.employee_no owner_no, owner.employee_name owner_name
    from public.hr_recruitment_onboarding_task t
    join public.hr_recruitment_handoff h on h.id = t.handoff_id and h.tenant_id = t.tenant_id
    join public.hr_candidate c on c.id = h.candidate_id and c.tenant_id = h.tenant_id
    left join public.hr_employee owner on owner.id = t.owner_employee_id and owner.tenant_id = t.tenant_id
    where (p_tenant_id is null or t.tenant_id = p_tenant_id)
      and (p_status is null or t.status = p_status)
      and (v_keyword is null or t.task_title ilike '%' || v_keyword || '%'
        or c.candidate_name ilike '%' || v_keyword || '%' or owner.employee_name ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by due_date, task_title offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(
      (to_jsonb(paged) - 'candidate_id' - 'candidate_name' - 'planned_onboard_date' - 'owner_no' - 'owner_name')
      || jsonb_build_object(
        'handoff', jsonb_build_object('id', handoff_id, 'candidate_id', candidate_id, 'candidate_name', candidate_name, 'planned_onboard_date', planned_onboard_date),
        'owner', case when owner_employee_id is null then null else jsonb_build_object('id', owner_employee_id, 'code', owner_no, 'name', owner_name) end
      ) order by due_date, task_title
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'sensitive_access', v_sensitive
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'sensitive_access', v_sensitive));
end
$function$;

create or replace function public.hr_list_recruitment_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:View', null, false) then
    raise exception '当前账号没有查看招聘选项的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  if p_kind = 'requisition' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'tenant_id', r.tenant_id, 'code', r.requisition_no,
      'name', position.position_name, 'organization_name', organization.organization_name
    ) order by r.requisition_no), '[]'::jsonb) into v_result
    from public.hr_recruitment_requisition r
    join public.hr_position position on position.id = r.position_id and position.tenant_id = r.tenant_id
    join public.sys_organization organization on organization.id = r.organization_id
    where (p_tenant_id is null or r.tenant_id = p_tenant_id) and r.status = 'effective';
  elsif p_kind = 'candidate' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'tenant_id', c.tenant_id, 'name', c.candidate_name,
      'code', r.requisition_no, 'position_name', position.position_name, 'stage', c.stage
    ) order by c.candidate_name), '[]'::jsonb) into v_result
    from public.hr_candidate c
    join public.hr_recruitment_requisition r on r.id = c.requisition_id and r.tenant_id = c.tenant_id
    join public.hr_position position on position.id = r.position_id and position.tenant_id = r.tenant_id
    where (p_tenant_id is null or c.tenant_id = p_tenant_id)
      and c.stage in ('new', 'screening', 'interview', 'offer');
  elsif p_kind = 'accepted_offer' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'tenant_id', o.tenant_id, 'code', o.offer_no,
      'name', c.candidate_name, 'candidate_id', c.id, 'proposed_onboard_date', o.proposed_onboard_date
    ) order by o.offer_no), '[]'::jsonb) into v_result
    from public.hr_recruitment_offer o
    join public.hr_candidate c on c.id = o.candidate_id and c.tenant_id = o.tenant_id
    where (p_tenant_id is null or o.tenant_id = p_tenant_id) and o.status = 'accepted';
  elsif p_kind = 'handoff' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', h.id, 'tenant_id', h.tenant_id, 'name', c.candidate_name,
      'code', o.offer_no, 'planned_onboard_date', h.planned_onboard_date
    ) order by h.planned_onboard_date, c.candidate_name), '[]'::jsonb) into v_result
    from public.hr_recruitment_handoff h
    join public.hr_candidate c on c.id = h.candidate_id and c.tenant_id = h.tenant_id
    join public.hr_recruitment_offer o on o.id = h.offer_id and o.tenant_id = h.tenant_id
    where (p_tenant_id is null or h.tenant_id = p_tenant_id) and h.status in ('pending', 'ready');
  else
    raise exception '不支持的招聘选项类型';
  end if;
  return coalesce(v_result, '[]'::jsonb);
end
$function$;

create or replace function public.hr_save_recruitment_record_secure(
  p_kind text,
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := coalesce(nullif(p_payload ->> 'tenant_id', '')::uuid, app_private.current_user_tenant_id());
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_permission text;
  v_candidate public.hr_candidate;
  v_offer public.hr_recruitment_offer;
  v_requisition public.hr_recruitment_requisition;
  v_version integer;
  v_offer_no text;
begin
  if p_kind not in ('requisition', 'candidate', 'interview', 'offer', 'handoff', 'task') then
    raise exception '不支持的招聘记录类型';
  end if;
  v_permission := case p_kind
    when 'requisition' then case when p_id is null then 'Hr:Recruitment:Add' else 'Hr:Recruitment:Edit' end
    when 'candidate' then case when p_id is null then 'Hr:Recruitment:Add' else 'Hr:Recruitment:Edit' end
    when 'interview' then case when p_id is null then 'Hr:Recruitment:Interview:Add' else 'Hr:Recruitment:Interview:Edit' end
    when 'offer' then case when p_id is null then 'Hr:Recruitment:Offer:Add' else 'Hr:Recruitment:Offer:Edit' end
    when 'handoff' then case when p_id is null then 'Hr:Recruitment:Handoff:Add' else 'Hr:Recruitment:Handoff:Edit' end
    else 'Hr:Recruitment:Task:Manage'
  end;
  if not app_private.can_execute_business_action('HrRecruitment', v_permission, null, false) then
    raise exception '当前账号没有执行该招聘操作的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then v_tenant_id := app_private.current_user_tenant_id(); end if;

  if p_kind = 'requisition' then
    if not exists (
      select 1 from public.sys_organization o
      where o.id = (p_payload ->> 'organization_id')::uuid and o.tenant_id = v_tenant_id
    ) then raise exception '招聘组织不存在或不属于当前租户'; end if;
    if not exists (
      select 1 from public.hr_position p
      where p.id = (p_payload ->> 'position_id')::uuid and p.tenant_id = v_tenant_id and p.enabled
    ) then raise exception '招聘岗位不存在、已停用或不属于当前租户'; end if;
    if p_id is not null and not exists (
      select 1 from public.hr_recruitment_requisition r
      where r.id = p_id and r.tenant_id = v_tenant_id and r.status in ('draft', 'rejected')
    ) then raise exception '只有草稿或已驳回的招聘需求可以编辑'; end if;
    insert into public.hr_recruitment_requisition(
      id, tenant_id, requisition_no, organization_id, position_id, opening_count,
      hired_count, expected_onboard_date, employment_type, status, reason, requirements
    ) values (
      v_id, v_tenant_id, upper(btrim(p_payload ->> 'requisition_no')),
      (p_payload ->> 'organization_id')::uuid, (p_payload ->> 'position_id')::uuid,
      greatest(coalesce((p_payload ->> 'opening_count')::integer, 1), 1),
      case when p_id is null then 0 else coalesce((select hired_count from public.hr_recruitment_requisition where id = p_id), 0) end,
      nullif(p_payload ->> 'expected_onboard_date', '')::date,
      coalesce(nullif(p_payload ->> 'employment_type', ''), 'full_time'),
      case when p_id is null then 'draft' else coalesce((select status from public.hr_recruitment_requisition where id = p_id), 'draft') end,
      btrim(p_payload ->> 'reason'), nullif(btrim(p_payload ->> 'requirements'), '')
    ) on conflict (id) do update set
      requisition_no = excluded.requisition_no,
      organization_id = excluded.organization_id,
      position_id = excluded.position_id,
      opening_count = excluded.opening_count,
      expected_onboard_date = excluded.expected_onboard_date,
      employment_type = excluded.employment_type,
      reason = excluded.reason,
      requirements = excluded.requirements
    where hr_recruitment_requisition.tenant_id = v_tenant_id;
    return v_id;
  end if;

  if p_kind = 'candidate' then
    select * into v_requisition from public.hr_recruitment_requisition
    where id = (p_payload ->> 'requisition_id')::uuid and tenant_id = v_tenant_id;
    if not found or v_requisition.status <> 'effective' then
      raise exception '候选人只能关联招聘中的有效需求';
    end if;
    if p_id is not null and not exists (
      select 1 from public.hr_candidate c where c.id = p_id and c.tenant_id = v_tenant_id
        and c.stage not in ('hired', 'rejected', 'withdrawn')
    ) then raise exception '已结束的候选人记录不能再编辑'; end if;
    insert into public.hr_candidate(
      id, tenant_id, requisition_id, candidate_name, phone, email, source, stage,
      expected_salary, resume_url, remark, consent_status, consent_at, retention_until
    ) values (
      v_id, v_tenant_id, v_requisition.id, btrim(p_payload ->> 'candidate_name'),
      nullif(btrim(p_payload ->> 'phone'), ''), nullif(lower(btrim(p_payload ->> 'email')), ''),
      coalesce(nullif(p_payload ->> 'source', ''), 'referral'), 'new',
      nullif(p_payload ->> 'expected_salary', '')::numeric,
      nullif(btrim(p_payload ->> 'resume_url'), ''), nullif(btrim(p_payload ->> 'remark'), ''),
      coalesce(nullif(p_payload ->> 'consent_status', ''), 'pending'),
      nullif(p_payload ->> 'consent_at', '')::timestamptz,
      nullif(p_payload ->> 'retention_until', '')::date
    ) on conflict (id) do update set
      requisition_id = excluded.requisition_id,
      candidate_name = excluded.candidate_name,
      phone = excluded.phone,
      email = excluded.email,
      source = excluded.source,
      expected_salary = excluded.expected_salary,
      resume_url = excluded.resume_url,
      remark = excluded.remark,
      consent_status = excluded.consent_status,
      consent_at = excluded.consent_at,
      retention_until = excluded.retention_until
    where hr_candidate.tenant_id = v_tenant_id;
    if p_id is null then
      insert into public.hr_candidate_stage_history(
        tenant_id, candidate_id, from_stage, to_stage, transition_reason, changed_by
      ) values (v_tenant_id, v_id, null, 'new', '创建候选人', coalesce(app_private.current_user_email(), 'system'));
    end if;
    return v_id;
  end if;

  if p_kind = 'interview' then
    select * into v_candidate from public.hr_candidate
    where id = (p_payload ->> 'candidate_id')::uuid and tenant_id = v_tenant_id;
    if not found or v_candidate.stage not in ('screening', 'interview') then
      raise exception '只有筛选中或面试中的候选人可以安排面试';
    end if;
    if not exists (
      select 1 from public.hr_employee e
      where e.id = (p_payload ->> 'interviewer_employee_id')::uuid and e.tenant_id = v_tenant_id
        and e.employment_status in ('probation', 'active', 'leave')
    ) then raise exception '面试官不存在或不可用'; end if;
    if p_id is not null and not exists (
      select 1 from public.hr_recruitment_interview i
      where i.id = p_id and i.tenant_id = v_tenant_id and i.status = 'scheduled'
    ) then raise exception '只有待进行的面试可以调整'; end if;
    insert into public.hr_recruitment_interview(
      id, tenant_id, candidate_id, round_no, interview_type, scheduled_start_at,
      scheduled_end_at, location, interviewer_employee_id, status
    ) values (
      v_id, v_tenant_id, v_candidate.id, coalesce((p_payload ->> 'round_no')::integer, 1),
      coalesce(nullif(p_payload ->> 'interview_type', ''), 'structured'),
      (p_payload ->> 'scheduled_start_at')::timestamptz,
      (p_payload ->> 'scheduled_end_at')::timestamptz,
      nullif(btrim(p_payload ->> 'location'), ''),
      (p_payload ->> 'interviewer_employee_id')::uuid, 'scheduled'
    ) on conflict (id) do update set
      round_no = excluded.round_no,
      interview_type = excluded.interview_type,
      scheduled_start_at = excluded.scheduled_start_at,
      scheduled_end_at = excluded.scheduled_end_at,
      location = excluded.location,
      interviewer_employee_id = excluded.interviewer_employee_id
    where hr_recruitment_interview.tenant_id = v_tenant_id
      and hr_recruitment_interview.status = 'scheduled';
    if v_candidate.stage = 'screening' then
      perform app_private.hr_append_candidate_stage(v_candidate.id, 'interview', '已安排首轮面试');
    end if;
    return v_id;
  end if;

  if p_kind = 'offer' then
    select * into v_candidate from public.hr_candidate
    where id = (p_payload ->> 'candidate_id')::uuid and tenant_id = v_tenant_id;
    if not found or v_candidate.stage not in ('interview', 'offer') then
      raise exception '只有面试中或 Offer 阶段的候选人可以创建 Offer';
    end if;
    if p_id is not null and not exists (
      select 1 from public.hr_recruitment_offer o
      where o.id = p_id and o.tenant_id = v_tenant_id and o.status in ('draft', 'rejected')
    ) then raise exception '只有草稿或已驳回的 Offer 可以编辑'; end if;
    select coalesce(max(version_no), 0) + 1 into v_version
    from public.hr_recruitment_offer where candidate_id = v_candidate.id and tenant_id = v_tenant_id;
    v_offer_no := coalesce(
      nullif(upper(btrim(p_payload ->> 'offer_no')), ''),
      'OFF-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))
    );
    insert into public.hr_recruitment_offer(
      id, tenant_id, candidate_id, offer_no, version_no, employment_type,
      monthly_salary, target_bonus, currency, probation_months,
      proposed_onboard_date, expires_on, status
    ) values (
      v_id, v_tenant_id, v_candidate.id, v_offer_no,
      case when p_id is null then v_version else coalesce((select version_no from public.hr_recruitment_offer where id = p_id), v_version) end,
      coalesce(nullif(p_payload ->> 'employment_type', ''), 'full_time'),
      (p_payload ->> 'monthly_salary')::numeric,
      coalesce(nullif(p_payload ->> 'target_bonus', '')::numeric, 0),
      upper(coalesce(nullif(p_payload ->> 'currency', ''), 'CNY')),
      coalesce((p_payload ->> 'probation_months')::integer, 3),
      (p_payload ->> 'proposed_onboard_date')::date,
      (p_payload ->> 'expires_on')::date,
      case when p_id is null then 'draft' else coalesce((select status from public.hr_recruitment_offer where id = p_id), 'draft') end
    ) on conflict (id) do update set
      offer_no = excluded.offer_no,
      employment_type = excluded.employment_type,
      monthly_salary = excluded.monthly_salary,
      target_bonus = excluded.target_bonus,
      currency = excluded.currency,
      probation_months = excluded.probation_months,
      proposed_onboard_date = excluded.proposed_onboard_date,
      expires_on = excluded.expires_on
    where hr_recruitment_offer.tenant_id = v_tenant_id
      and hr_recruitment_offer.status in ('draft', 'rejected');
    return v_id;
  end if;

  if p_kind = 'handoff' then
    select * into v_offer from public.hr_recruitment_offer
    where id = (p_payload ->> 'offer_id')::uuid and tenant_id = v_tenant_id;
    if not found or v_offer.status <> 'accepted' then raise exception '仅已接受的 Offer 可以建立入职交接'; end if;
    select r.* into v_requisition
    from public.hr_candidate c
    join public.hr_recruitment_requisition r on r.id = c.requisition_id and r.tenant_id = c.tenant_id
    where c.id = v_offer.candidate_id and c.tenant_id = v_tenant_id;
    if p_id is not null and not exists (
      select 1 from public.hr_recruitment_handoff h
      where h.id = p_id and h.tenant_id = v_tenant_id and h.status in ('pending', 'ready')
    ) then raise exception '已结束的入职交接不能编辑'; end if;
    insert into public.hr_recruitment_handoff(
      id, tenant_id, candidate_id, offer_id, organization_id, position_id,
      planned_onboard_date, owner_employee_id, buddy_employee_id, onboard_employee_id,
      status, handoff_note
    ) values (
      v_id, v_tenant_id, v_offer.candidate_id, v_offer.id,
      v_requisition.organization_id, v_requisition.position_id,
      coalesce(nullif(p_payload ->> 'planned_onboard_date', '')::date, v_offer.proposed_onboard_date),
      nullif(p_payload ->> 'owner_employee_id', '')::uuid,
      nullif(p_payload ->> 'buddy_employee_id', '')::uuid,
      nullif(p_payload ->> 'onboard_employee_id', '')::uuid,
      'pending', nullif(btrim(p_payload ->> 'handoff_note'), '')
    ) on conflict (id) do update set
      planned_onboard_date = excluded.planned_onboard_date,
      owner_employee_id = excluded.owner_employee_id,
      buddy_employee_id = excluded.buddy_employee_id,
      onboard_employee_id = excluded.onboard_employee_id,
      handoff_note = excluded.handoff_note
    where hr_recruitment_handoff.tenant_id = v_tenant_id
      and hr_recruitment_handoff.status in ('pending', 'ready');
    return v_id;
  end if;

  if not exists (
    select 1 from public.hr_recruitment_handoff h
    where h.id = (p_payload ->> 'handoff_id')::uuid and h.tenant_id = v_tenant_id
      and h.status in ('pending', 'ready')
  ) then raise exception '入职交接不存在或已结束'; end if;
  if p_id is not null and not exists (
    select 1 from public.hr_recruitment_onboarding_task t
    where t.id = p_id and t.tenant_id = v_tenant_id and t.status in ('pending', 'in_progress')
  ) then raise exception '已完成或跳过的入职任务不能编辑'; end if;
  insert into public.hr_recruitment_onboarding_task(
    id, tenant_id, handoff_id, task_category, task_title, task_description,
    owner_employee_id, due_date, status
  ) values (
    v_id, v_tenant_id, (p_payload ->> 'handoff_id')::uuid,
    p_payload ->> 'task_category', btrim(p_payload ->> 'task_title'),
    nullif(btrim(p_payload ->> 'task_description'), ''),
    nullif(p_payload ->> 'owner_employee_id', '')::uuid,
    (p_payload ->> 'due_date')::date,
    coalesce(nullif(p_payload ->> 'status', ''), 'pending')
  ) on conflict (id) do update set
    task_category = excluded.task_category,
    task_title = excluded.task_title,
    task_description = excluded.task_description,
    owner_employee_id = excluded.owner_employee_id,
    due_date = excluded.due_date,
    status = excluded.status
  where hr_recruitment_onboarding_task.tenant_id = v_tenant_id
    and hr_recruitment_onboarding_task.status in ('pending', 'in_progress');
  return v_id;
end
$function$;

create or replace function public.hr_transition_candidate_stage_secure(
  p_candidate_id uuid,
  p_to_stage text,
  p_reason text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:Candidate:Move', null, false) then
    raise exception '当前账号没有推进候选人的权限' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.hr_candidate c
    where c.id = p_candidate_id and (app_private.is_platform_super() or c.tenant_id = v_tenant_id)
  ) then raise exception '候选人不存在或无权操作'; end if;
  if p_to_stage not in ('screening', 'rejected', 'withdrawn') then
    raise exception '该阶段必须由面试、Offer 或入职交接动作推进';
  end if;
  perform app_private.hr_append_candidate_stage(p_candidate_id, p_to_stage, p_reason);
end
$function$;

create or replace function public.hr_complete_recruitment_interview_secure(
  p_interview_id uuid,
  p_score numeric,
  p_recommendation text,
  p_feedback text
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:Interview:Complete', null, false) then
    raise exception '当前账号没有提交面试评价的权限' using errcode = '42501';
  end if;
  if p_score not between 0 and 100 or p_recommendation not in ('strong_hire', 'hire', 'hold', 'no_hire')
    or nullif(btrim(p_feedback), '') is null then
    raise exception '请完整填写面试评分、建议和评价依据';
  end if;
  update public.hr_recruitment_interview
  set status = 'completed', score = p_score, recommendation = p_recommendation,
      feedback = btrim(p_feedback), completed_at = now()
  where id = p_interview_id and status = 'scheduled'
    and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  if not found then raise exception '待进行的面试不存在或无权操作'; end if;
end
$function$;

create or replace function public.hr_cancel_recruitment_interview_secure(
  p_interview_id uuid,
  p_no_show boolean default false,
  p_reason text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:Interview:Edit', null, false) then
    raise exception '当前账号没有取消面试的权限' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception '取消面试必须填写原因'; end if;
  update public.hr_recruitment_interview
  set status = case when p_no_show then 'no_show' else 'cancelled' end,
      feedback = btrim(p_reason), completed_at = null
  where id = p_interview_id and status = 'scheduled'
    and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  if not found then raise exception '待进行的面试不存在或无权操作'; end if;
end
$function$;

create or replace function public.hr_transition_recruitment_offer_secure(
  p_offer_id uuid,
  p_action text,
  p_comment text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offer public.hr_recruitment_offer;
  v_candidate public.hr_candidate;
  v_requisition public.hr_recruitment_requisition;
  v_permission text;
  v_next_status text;
  v_handoff_id uuid;
begin
  v_permission := case
    when p_action = 'submit' then 'Hr:Recruitment:Offer:Submit'
    when p_action in ('approve', 'reject') then 'Hr:Recruitment:Offer:Approve'
    when p_action in ('send', 'withdraw', 'expire') then 'Hr:Recruitment:Offer:Send'
    when p_action in ('accept', 'decline') then 'Hr:Recruitment:Offer:Respond'
    else null
  end;
  if v_permission is null then raise exception '不支持的 Offer 动作'; end if;
  if not app_private.can_execute_business_action('HrRecruitment', v_permission, null, false) then
    raise exception '当前账号没有执行该 Offer 动作的权限' using errcode = '42501';
  end if;
  select * into v_offer from public.hr_recruitment_offer
  where id = p_offer_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
  for update;
  if not found then raise exception 'Offer 不存在或无权操作'; end if;
  select * into v_candidate from public.hr_candidate where id = v_offer.candidate_id;
  select r.* into v_requisition
  from public.hr_recruitment_requisition r where r.id = v_candidate.requisition_id;

  v_next_status := case
    when p_action = 'submit' and v_offer.status in ('draft', 'rejected') then 'pending_approval'
    when p_action = 'approve' and v_offer.status = 'pending_approval' then 'approved'
    when p_action = 'reject' and v_offer.status = 'pending_approval' then 'rejected'
    when p_action = 'send' and v_offer.status = 'approved' then 'sent'
    when p_action = 'accept' and v_offer.status = 'sent' then 'accepted'
    when p_action = 'decline' and v_offer.status = 'sent' then 'declined'
    when p_action = 'expire' and v_offer.status = 'sent' then 'expired'
    when p_action = 'withdraw' and v_offer.status in ('approved', 'sent') then 'withdrawn'
    else null
  end;
  if v_next_status is null then
    raise exception 'Offer 当前状态 % 不支持动作 %', v_offer.status, p_action;
  end if;
  if p_action in ('reject', 'decline', 'withdraw') and nullif(btrim(p_comment), '') is null then
    raise exception '该 Offer 动作必须填写原因';
  end if;

  update public.hr_recruitment_offer
  set status = v_next_status,
      approval_comment = case when p_action in ('approve', 'reject') then nullif(btrim(p_comment), '') else approval_comment end,
      approved_by = case when p_action = 'approve' then coalesce(app_private.current_user_email(), 'system') else approved_by end,
      approved_at = case when p_action = 'approve' then now() else approved_at end,
      sent_at = case when p_action = 'send' then now() else sent_at end,
      responded_at = case when p_action in ('accept', 'decline') then now() else responded_at end,
      response_note = case when p_action in ('accept', 'decline') then nullif(btrim(p_comment), '') else response_note end
  where id = v_offer.id;

  if p_action = 'send' and v_candidate.stage = 'interview' then
    perform app_private.hr_append_candidate_stage(v_candidate.id, 'offer', 'Offer 已发送');
  end if;
  if p_action = 'accept' then
    if v_candidate.stage = 'interview' then
      perform app_private.hr_append_candidate_stage(v_candidate.id, 'offer', '候选人已接受 Offer');
    end if;
    insert into public.hr_recruitment_handoff(
      tenant_id, candidate_id, offer_id, organization_id, position_id, planned_onboard_date, status
    ) values (
      v_offer.tenant_id, v_candidate.id, v_offer.id, v_requisition.organization_id,
      v_requisition.position_id, v_offer.proposed_onboard_date, 'pending'
    ) on conflict (tenant_id, candidate_id) do update set
      offer_id = excluded.offer_id,
      organization_id = excluded.organization_id,
      position_id = excluded.position_id,
      planned_onboard_date = excluded.planned_onboard_date,
      status = 'pending',
      completed_at = null
    returning id into v_handoff_id;

    insert into public.hr_recruitment_onboarding_task(
      tenant_id, handoff_id, task_category, task_title, task_description, due_date
    )
    select v_offer.tenant_id, v_handoff_id, seed.category, seed.title, seed.description,
      v_offer.proposed_onboard_date + seed.day_offset
    from (values
      ('documentation', '收集并核验入职资料', '核验身份、学历、离职证明与录用所需资料。', -5),
      ('account', '准备系统账号与权限', '按岗位最小权限原则完成账号、组织和角色开通。', -2),
      ('equipment', '准备工位与工作设备', '确认电脑、工位、门禁及岗位必要设备。', -1),
      ('orientation', '安排首日引导与入职培训', '明确报到联系人、首日议程、制度学习与安全培训。', 0)
    ) seed(category, title, description, day_offset)
    where not exists (
      select 1 from public.hr_recruitment_onboarding_task task
      where task.handoff_id = v_handoff_id and task.task_title = seed.title
    );
  end if;
end
$function$;

create or replace function public.hr_transition_recruitment_handoff_secure(
  p_handoff_id uuid,
  p_action text,
  p_comment text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_handoff public.hr_recruitment_handoff;
  v_candidate public.hr_candidate;
  v_requisition_id uuid;
  v_open_tasks integer;
  v_hired_count integer;
begin
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:Handoff:Complete', null, false) then
    raise exception '当前账号没有推进入职交接的权限' using errcode = '42501';
  end if;
  if p_action not in ('ready', 'complete', 'cancel') then raise exception '不支持的入职交接动作'; end if;
  select * into v_handoff from public.hr_recruitment_handoff
  where id = p_handoff_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
  for update;
  if not found then raise exception '入职交接不存在或无权操作'; end if;
  if p_action = 'ready' and v_handoff.status <> 'pending' then raise exception '只有待准备交接可以标记就绪'; end if;
  if p_action = 'complete' and v_handoff.status not in ('pending', 'ready') then raise exception '当前交接不能完成'; end if;
  if p_action = 'cancel' and v_handoff.status not in ('pending', 'ready') then raise exception '当前交接不能取消'; end if;
  if p_action = 'cancel' and nullif(btrim(p_comment), '') is null then raise exception '取消交接必须填写原因'; end if;

  if p_action = 'complete' then
    if v_handoff.onboard_employee_id is null then raise exception '完成交接前必须关联已创建的员工档案'; end if;
    select count(*) into v_open_tasks from public.hr_recruitment_onboarding_task
    where handoff_id = v_handoff.id and status in ('pending', 'in_progress');
    if v_open_tasks > 0 then raise exception '仍有 % 项入职任务未完成', v_open_tasks; end if;
    update public.hr_recruitment_handoff
    set status = 'completed', completed_at = now(), handoff_note = coalesce(nullif(btrim(p_comment), ''), handoff_note)
    where id = v_handoff.id;
    select * into v_candidate from public.hr_candidate where id = v_handoff.candidate_id for update;
    update public.hr_candidate set onboard_employee_id = v_handoff.onboard_employee_id where id = v_candidate.id;
    if v_candidate.stage <> 'hired' then
      perform app_private.hr_append_candidate_stage(v_candidate.id, 'hired', '入职交接完成并关联员工档案');
    end if;
    v_requisition_id := v_candidate.requisition_id;
    select count(*) into v_hired_count from public.hr_candidate
    where requisition_id = v_requisition_id and stage = 'hired';
    update public.hr_recruitment_requisition
    set hired_count = least(v_hired_count, opening_count),
        status = case when v_hired_count >= opening_count then 'completed' else status end
    where id = v_requisition_id;
  elsif p_action = 'ready' then
    update public.hr_recruitment_handoff set status = 'ready', handoff_note = coalesce(nullif(btrim(p_comment), ''), handoff_note)
    where id = v_handoff.id;
  else
    update public.hr_recruitment_handoff set status = 'cancelled', handoff_note = btrim(p_comment)
    where id = v_handoff.id;
  end if;
end
$function$;

create or replace function public.hr_complete_recruitment_task_secure(
  p_task_id uuid,
  p_skip boolean default false,
  p_note text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:Task:Manage', null, false) then
    raise exception '当前账号没有处理入职任务的权限' using errcode = '42501';
  end if;
  if p_skip and nullif(btrim(p_note), '') is null then raise exception '跳过任务必须填写原因'; end if;
  update public.hr_recruitment_onboarding_task
  set status = case when p_skip then 'skipped' else 'completed' end,
      completion_note = nullif(btrim(p_note), ''), completed_at = now()
  where id = p_task_id and status in ('pending', 'in_progress')
    and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  if not found then raise exception '待处理的入职任务不存在或无权操作'; end if;
end
$function$;

revoke all on table public.hr_candidate from public, anon, authenticated;
grant all on table public.hr_candidate to service_role;

revoke all on function public.hr_recruitment_overview_secure(uuid) from public, anon;
revoke all on function public.hr_list_recruitment_records_secure(text, integer, integer, text, text, uuid) from public, anon;
revoke all on function public.hr_list_recruitment_options_secure(text, uuid) from public, anon;
revoke all on function public.hr_save_recruitment_record_secure(text, uuid, jsonb) from public, anon;
revoke all on function public.hr_transition_candidate_stage_secure(uuid, text, text) from public, anon;
revoke all on function public.hr_complete_recruitment_interview_secure(uuid, numeric, text, text) from public, anon;
revoke all on function public.hr_cancel_recruitment_interview_secure(uuid, boolean, text) from public, anon;
revoke all on function public.hr_transition_recruitment_offer_secure(uuid, text, text) from public, anon;
revoke all on function public.hr_transition_recruitment_handoff_secure(uuid, text, text) from public, anon;
revoke all on function public.hr_complete_recruitment_task_secure(uuid, boolean, text) from public, anon;

grant execute on function public.hr_recruitment_overview_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_recruitment_records_secure(text, integer, integer, text, text, uuid) to authenticated, service_role;
grant execute on function public.hr_list_recruitment_options_secure(text, uuid) to authenticated, service_role;
grant execute on function public.hr_save_recruitment_record_secure(text, uuid, jsonb) to authenticated, service_role;
grant execute on function public.hr_transition_candidate_stage_secure(uuid, text, text) to authenticated, service_role;
grant execute on function public.hr_complete_recruitment_interview_secure(uuid, numeric, text, text) to authenticated, service_role;
grant execute on function public.hr_cancel_recruitment_interview_secure(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.hr_transition_recruitment_offer_secure(uuid, text, text) to authenticated, service_role;
grant execute on function public.hr_transition_recruitment_handoff_secure(uuid, text, text) to authenticated, service_role;
grant execute on function public.hr_complete_recruitment_task_secure(uuid, boolean, text) to authenticated, service_role;

alter table public.hr_recruitment_offer
  drop constraint if exists hr_recruitment_offer_dates_check;
alter table public.hr_recruitment_offer
  add constraint hr_recruitment_offer_dates_check
  check (expires_on between proposed_onboard_date - 180 and proposed_onboard_date);

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('面试类型', 'hrInterviewType', 82),
  ('面试状态', 'hrInterviewStatus', 83),
  ('面试建议', 'hrInterviewRecommendation', 84),
  ('Offer 状态', 'hrOfferStatus', 85),
  ('入职交接状态', 'hrRecruitmentHandoffStatus', 86),
  ('入职任务分类', 'hrOnboardingTaskCategory', 87),
  ('入职任务状态', 'hrOnboardingTaskStatus', 88),
  ('候选人授权状态', 'hrCandidateConsentStatus', 89)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 招聘闭环字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set
  name = excluded.name, status = excluded.status, update_by = excluded.update_by,
  update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrInterviewType', 'phone', '电话沟通', 1, 'info'),
  ('hrInterviewType', 'video', '视频面试', 2, 'primary'),
  ('hrInterviewType', 'onsite', '现场面试', 3, 'success'),
  ('hrInterviewType', 'structured', '结构化面试', 4, 'primary'),
  ('hrInterviewType', 'technical', '专业面试', 5, 'warning'),
  ('hrInterviewType', 'panel', '联合面试', 6, 'danger'),
  ('hrInterviewType', 'executive', '高管终面', 7, 'warning'),
  ('hrInterviewStatus', 'scheduled', '待进行', 1, 'warning'),
  ('hrInterviewStatus', 'completed', '已完成', 2, 'success'),
  ('hrInterviewStatus', 'cancelled', '已取消', 3, 'info'),
  ('hrInterviewStatus', 'no_show', '未到场', 4, 'danger'),
  ('hrInterviewRecommendation', 'strong_hire', '强烈推荐', 1, 'success'),
  ('hrInterviewRecommendation', 'hire', '建议录用', 2, 'primary'),
  ('hrInterviewRecommendation', 'hold', '保留观察', 3, 'warning'),
  ('hrInterviewRecommendation', 'no_hire', '不建议录用', 4, 'danger'),
  ('hrOfferStatus', 'draft', '草稿', 1, 'info'),
  ('hrOfferStatus', 'pending_approval', '待审批', 2, 'warning'),
  ('hrOfferStatus', 'approved', '已批准', 3, 'success'),
  ('hrOfferStatus', 'rejected', '已驳回', 4, 'danger'),
  ('hrOfferStatus', 'sent', '待候选人反馈', 5, 'primary'),
  ('hrOfferStatus', 'accepted', '已接受', 6, 'success'),
  ('hrOfferStatus', 'declined', '已拒绝', 7, 'danger'),
  ('hrOfferStatus', 'expired', '已过期', 8, 'info'),
  ('hrOfferStatus', 'withdrawn', '已撤回', 9, 'info'),
  ('hrRecruitmentHandoffStatus', 'pending', '待准备', 1, 'warning'),
  ('hrRecruitmentHandoffStatus', 'ready', '已就绪', 2, 'primary'),
  ('hrRecruitmentHandoffStatus', 'completed', '已完成', 3, 'success'),
  ('hrRecruitmentHandoffStatus', 'cancelled', '已取消', 4, 'danger'),
  ('hrOnboardingTaskCategory', 'documentation', '入职资料', 1, 'primary'),
  ('hrOnboardingTaskCategory', 'account', '账号权限', 2, 'warning'),
  ('hrOnboardingTaskCategory', 'equipment', '工位设备', 3, 'info'),
  ('hrOnboardingTaskCategory', 'workspace', '办公环境', 4, 'info'),
  ('hrOnboardingTaskCategory', 'orientation', '入职引导', 5, 'success'),
  ('hrOnboardingTaskCategory', 'training', '岗前培训', 6, 'primary'),
  ('hrOnboardingTaskCategory', 'payroll', '薪税福利', 7, 'warning'),
  ('hrOnboardingTaskCategory', 'other', '其他', 8, 'info'),
  ('hrOnboardingTaskStatus', 'pending', '待处理', 1, 'warning'),
  ('hrOnboardingTaskStatus', 'in_progress', '进行中', 2, 'primary'),
  ('hrOnboardingTaskStatus', 'completed', '已完成', 3, 'success'),
  ('hrOnboardingTaskStatus', 'skipped', '已跳过', 4, 'info'),
  ('hrCandidateConsentStatus', 'pending', '待授权', 1, 'warning'),
  ('hrCandidateConsentStatus', 'granted', '已授权', 2, 'success'),
  ('hrCandidateConsentStatus', 'withdrawn', '已撤回授权', 3, 'danger'),
  ('hrCandidateConsentStatus', 'expired', '授权已到期', 4, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 招聘闭环字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

with recruitment_type as (
  select id from public.sys_dict_type where code = 'hrRecruitmentStatus' limit 1
), platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), recruitment_type.id, 'hrRecruitmentStatus_completed', '1',
  '624944977@qq.com', '624944977@qq.com', '招聘人数已满足并完成入职交接',
  'completed', '招聘完成', platform_tenant.id, 'success', 5
from recruitment_type cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = recruitment_type.id and existing.value = 'completed'
);

update public.sys_dictionary
set sort = case value
  when 'completed' then 5 when 'rejected' then 6 when 'cancelled' then 7 else sort end,
  update_by = '624944977@qq.com', update_time = now()
where type_id = (select id from public.sys_dict_type where code = 'hrRecruitmentStatus' limit 1)
  and value in ('completed', 'rejected', 'cancelled');

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000401'::uuid, seed.name, '', '',
  jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()
  ), seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8401-000000000007'::uuid, 'Hr:Recruitment:Candidate:Move', '推进候选人阶段', 7),
  ('c0de0000-0000-4000-8401-000000000008'::uuid, 'Hr:Recruitment:Sensitive:View', '查看招聘敏感信息', 8),
  ('c0de0000-0000-4000-8401-000000000009'::uuid, 'Hr:Recruitment:Interview:Add', '安排面试', 9),
  ('c0de0000-0000-4000-8401-000000000010'::uuid, 'Hr:Recruitment:Interview:Edit', '调整或取消面试', 10),
  ('c0de0000-0000-4000-8401-000000000011'::uuid, 'Hr:Recruitment:Interview:Complete', '提交面试评价', 11),
  ('c0de0000-0000-4000-8401-000000000012'::uuid, 'Hr:Recruitment:Offer:Add', '创建 Offer', 12),
  ('c0de0000-0000-4000-8401-000000000013'::uuid, 'Hr:Recruitment:Offer:Edit', '编辑 Offer', 13),
  ('c0de0000-0000-4000-8401-000000000014'::uuid, 'Hr:Recruitment:Offer:Submit', '提交 Offer 审批', 14),
  ('c0de0000-0000-4000-8401-000000000015'::uuid, 'Hr:Recruitment:Offer:Approve', '审批 Offer', 15),
  ('c0de0000-0000-4000-8401-000000000016'::uuid, 'Hr:Recruitment:Offer:Send', '发送或撤回 Offer', 16),
  ('c0de0000-0000-4000-8401-000000000017'::uuid, 'Hr:Recruitment:Offer:Respond', '登记 Offer 反馈', 17),
  ('c0de0000-0000-4000-8401-000000000018'::uuid, 'Hr:Recruitment:Handoff:Add', '创建入职交接', 18),
  ('c0de0000-0000-4000-8401-000000000019'::uuid, 'Hr:Recruitment:Handoff:Edit', '编辑入职交接', 19),
  ('c0de0000-0000-4000-8401-000000000020'::uuid, 'Hr:Recruitment:Handoff:Complete', '推进入职交接', 20),
  ('c0de0000-0000-4000-8401-000000000021'::uuid, 'Hr:Recruitment:Task:Manage', '管理入职任务', 21)
) seed(id, name, title, sort)
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, meta = excluded.meta,
  sort = excluded.sort, type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_role role on role.id = page_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8401-000000000007'::uuid),
  ('c0de0000-0000-4000-8401-000000000008'::uuid),
  ('c0de0000-0000-4000-8401-000000000009'::uuid),
  ('c0de0000-0000-4000-8401-000000000010'::uuid),
  ('c0de0000-0000-4000-8401-000000000011'::uuid),
  ('c0de0000-0000-4000-8401-000000000012'::uuid),
  ('c0de0000-0000-4000-8401-000000000013'::uuid),
  ('c0de0000-0000-4000-8401-000000000014'::uuid),
  ('c0de0000-0000-4000-8401-000000000015'::uuid),
  ('c0de0000-0000-4000-8401-000000000016'::uuid),
  ('c0de0000-0000-4000-8401-000000000017'::uuid),
  ('c0de0000-0000-4000-8401-000000000018'::uuid),
  ('c0de0000-0000-4000-8401-000000000019'::uuid),
  ('c0de0000-0000-4000-8401-000000000020'::uuid),
  ('c0de0000-0000-4000-8401-000000000021'::uuid)
) button(id)
where page_grant.menu_id = 'c0de0000-0000-4000-8000-000000000401'::uuid
on conflict (role_id, menu_id) do nothing;
