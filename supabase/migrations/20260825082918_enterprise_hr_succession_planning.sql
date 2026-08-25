create table public.hr_succession_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_code text not null,
  position_id uuid not null,
  plan_name text not null,
  criticality text not null default 'high',
  vacancy_risk text not null default 'medium',
  business_impact text not null default 'high',
  target_successors integer not null default 2,
  review_cycle_months integer not null default 6,
  next_review_date date not null default (current_date + 180),
  owner_employee_id uuid,
  status text not null default 'draft',
  notes text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_succession_plan_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_succession_plan_position_fkey foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_succession_plan_owner_fkey foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_succession_plan_id_tenant_unique unique (id, tenant_id),
  constraint hr_succession_plan_code_unique unique (tenant_id, plan_code),
  constraint hr_succession_plan_name_not_blank check (btrim(plan_name) <> ''),
  constraint hr_succession_plan_criticality_check check (criticality in ('medium', 'high', 'critical')),
  constraint hr_succession_plan_vacancy_risk_check check (vacancy_risk in ('low', 'medium', 'high')),
  constraint hr_succession_plan_business_impact_check check (business_impact in ('medium', 'high', 'critical')),
  constraint hr_succession_plan_target_check check (target_successors between 1 and 20),
  constraint hr_succession_plan_cycle_check check (review_cycle_months between 1 and 36),
  constraint hr_succession_plan_status_check check (status in ('draft', 'active', 'closed'))
);

create index hr_succession_plan_position_fk_idx
  on public.hr_succession_plan(position_id, tenant_id);
create index hr_succession_plan_owner_fk_idx
  on public.hr_succession_plan(owner_employee_id, tenant_id) where owner_employee_id is not null;
create index hr_succession_plan_review_idx
  on public.hr_succession_plan(tenant_id, status, next_review_date);
create unique index hr_succession_plan_active_position_unique
  on public.hr_succession_plan(tenant_id, position_id) where status = 'active';

create table public.hr_succession_candidate (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_id uuid not null,
  employee_id uuid not null,
  readiness text not null default 'development_needed',
  potential_level text not null default 'emerging',
  retention_risk text not null default 'medium',
  priority integer not null default 1,
  nomination_source text not null default 'talent_review',
  aspiration_confirmed boolean not null default false,
  mobility_scope text,
  strengths text,
  development_gaps text,
  review_comment text,
  status text not null default 'nominated',
  nominated_on date not null default current_date,
  last_reviewed_on date,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_succession_candidate_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_succession_candidate_plan_fkey foreign key (plan_id, tenant_id)
    references public.hr_succession_plan(id, tenant_id) on delete cascade,
  constraint hr_succession_candidate_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_succession_candidate_id_tenant_unique unique (id, tenant_id),
  constraint hr_succession_candidate_readiness_check check (
    readiness in ('ready_now', 'one_to_two_years', 'three_to_five_years', 'development_needed')
  ),
  constraint hr_succession_candidate_potential_check check (potential_level in ('emerging', 'medium', 'high')),
  constraint hr_succession_candidate_retention_check check (retention_risk in ('low', 'medium', 'high')),
  constraint hr_succession_candidate_priority_check check (priority between 1 and 20),
  constraint hr_succession_candidate_source_check check (
    nomination_source in ('talent_review', 'manager', 'hr', 'self', 'external_assessment')
  ),
  constraint hr_succession_candidate_status_check check (status in ('nominated', 'active', 'withdrawn', 'placed'))
);

create index hr_succession_candidate_plan_fk_idx
  on public.hr_succession_candidate(plan_id, tenant_id);
create index hr_succession_candidate_employee_fk_idx
  on public.hr_succession_candidate(employee_id, tenant_id);
create index hr_succession_candidate_readiness_idx
  on public.hr_succession_candidate(tenant_id, status, readiness);
create unique index hr_succession_candidate_active_unique
  on public.hr_succession_candidate(tenant_id, plan_id, employee_id)
  where status in ('nominated', 'active');

create table public.hr_succession_development_action (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  candidate_id uuid not null,
  action_type text not null,
  action_title text not null,
  action_description text,
  owner_employee_id uuid,
  start_date date not null default current_date,
  due_date date not null,
  status text not null default 'planned',
  completion_date date,
  outcome text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_succession_action_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_succession_action_candidate_fkey foreign key (candidate_id, tenant_id)
    references public.hr_succession_candidate(id, tenant_id) on delete cascade,
  constraint hr_succession_action_owner_fkey foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_succession_action_id_tenant_unique unique (id, tenant_id),
  constraint hr_succession_action_title_not_blank check (btrim(action_title) <> ''),
  constraint hr_succession_action_type_check check (
    action_type in ('mentoring', 'training', 'stretch_assignment', 'job_rotation', 'coaching', 'assessment', 'other')
  ),
  constraint hr_succession_action_status_check check (status in ('planned', 'in_progress', 'completed', 'cancelled')),
  constraint hr_succession_action_dates_check check (due_date >= start_date),
  constraint hr_succession_action_completion_check check (
    (status = 'completed' and completion_date is not null and completion_date >= start_date)
    or (status <> 'completed' and completion_date is null)
  )
);

create index hr_succession_action_candidate_fk_idx
  on public.hr_succession_development_action(candidate_id, tenant_id);
create index hr_succession_action_owner_fk_idx
  on public.hr_succession_development_action(owner_employee_id, tenant_id) where owner_employee_id is not null;
create index hr_succession_action_due_idx
  on public.hr_succession_development_action(tenant_id, status, due_date);

create trigger hr_succession_plan_create_audit before insert on public.hr_succession_plan
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_succession_plan_update_audit before update on public.hr_succession_plan
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_succession_candidate_create_audit before insert on public.hr_succession_candidate
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_succession_candidate_update_audit before update on public.hr_succession_candidate
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_succession_action_create_audit before insert on public.hr_succession_development_action
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_succession_action_update_audit before update on public.hr_succession_development_action
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_succession_plan enable row level security;
alter table public.hr_succession_candidate enable row level security;
alter table public.hr_succession_development_action enable row level security;
create policy hr_succession_plan_deny_direct_access on public.hr_succession_plan
  for all to authenticated using (false) with check (false);
create policy hr_succession_candidate_deny_direct_access on public.hr_succession_candidate
  for all to authenticated using (false) with check (false);
create policy hr_succession_action_deny_direct_access on public.hr_succession_development_action
  for all to authenticated using (false) with check (false);
revoke all on table public.hr_succession_plan from public, anon, authenticated;
revoke all on table public.hr_succession_candidate from public, anon, authenticated;
revoke all on table public.hr_succession_development_action from public, anon, authenticated;
grant all on table public.hr_succession_plan to service_role;
grant all on table public.hr_succession_candidate to service_role;
grant all on table public.hr_succession_development_action to service_role;

create or replace function public.hr_succession_overview_secure(p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrSuccession', 'Hr:Succession:View', null, false) then
    raise exception 'Missing succession view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  return jsonb_build_object(
    'active_plan_count', (select count(*) from public.hr_succession_plan p where (p_tenant_id is null or p.tenant_id=p_tenant_id) and p.status='active'),
    'critical_position_count', (select count(*) from public.hr_succession_plan p where (p_tenant_id is null or p.tenant_id=p_tenant_id) and p.status='active' and p.criticality='critical'),
    'ready_now_count', (select count(*) from public.hr_succession_candidate c join public.hr_succession_plan p on p.id=c.plan_id where (p_tenant_id is null or c.tenant_id=p_tenant_id) and p.status='active' and c.status='active' and c.readiness='ready_now'),
    'uncovered_plan_count', (select count(*) from public.hr_succession_plan p where (p_tenant_id is null or p.tenant_id=p_tenant_id) and p.status='active' and not exists (select 1 from public.hr_succession_candidate c where c.plan_id=p.id and c.status='active')),
    'overdue_action_count', (select count(*) from public.hr_succession_development_action a where (p_tenant_id is null or a.tenant_id=p_tenant_id) and a.status in ('planned','in_progress') and a.due_date < current_date),
    'due_review_count', (select count(*) from public.hr_succession_plan p where (p_tenant_id is null or p.tenant_id=p_tenant_id) and p.status='active' and p.next_review_date <= current_date + 30)
  );
end;
$function$;

create or replace function public.hr_list_succession_records_secure(
  p_kind text, p_from integer default 0, p_to integer default 19,
  p_keyword text default null, p_status text default null, p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from,0),0);
  v_limit integer := least(500,greatest(coalesce(p_to,19)-greatest(coalesce(p_from,0),0)+1,1));
  v_keyword text := nullif(btrim(p_keyword),'');
  v_result jsonb;
begin
  if p_kind not in ('plan','candidate','action') then raise exception '不支持的继任记录类型'; end if;
  if not app_private.can_execute_business_action('HrSuccession', 'Hr:Succession:View', null, false) then
    raise exception 'Missing succession view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind='plan' then
    with filtered as materialized (
      select p.*, t.tenant_code, t.tenant_name, pos.position_code, pos.position_name,
        o.organization_name, owner.employee_no owner_no, owner.employee_name owner_name,
        (select count(*) from public.hr_succession_candidate c where c.plan_id=p.id and c.status='active') active_candidate_count,
        (select count(*) from public.hr_succession_candidate c where c.plan_id=p.id and c.status='active' and c.readiness='ready_now') ready_now_count
      from public.hr_succession_plan p join public.sys_tenant t on t.id=p.tenant_id
      join public.hr_position pos on pos.id=p.position_id
      left join public.sys_organization o on o.id=pos.organization_id
      left join public.hr_employee owner on owner.id=p.owner_employee_id
      where (p_tenant_id is null or p.tenant_id=p_tenant_id)
        and (p_status is null or p.status=p_status)
        and (v_keyword is null or p.plan_code ilike '%'||v_keyword||'%' or p.plan_name ilike '%'||v_keyword||'%'
          or pos.position_name ilike '%'||v_keyword||'%' or o.organization_name ilike '%'||v_keyword||'%')
    ), paged as (select * from filtered order by criticality desc, next_review_date, plan_name offset v_offset limit v_limit)
    select jsonb_build_object('records',coalesce(jsonb_agg((to_jsonb(paged)-'tenant_code'-'tenant_name'-'position_code'-'position_name'-'organization_name'-'owner_no'-'owner_name')||jsonb_build_object(
      'tenant',jsonb_build_object('id',tenant_id,'code',tenant_code,'name',tenant_name),
      'position',jsonb_build_object('id',position_id,'code',position_code,'name',position_name,'organization_name',organization_name),
      'owner',case when owner_employee_id is null then null else jsonb_build_object('id',owner_employee_id,'code',owner_no,'name',owner_name) end
    ) order by criticality desc,next_review_date,plan_name),'[]'::jsonb),'total',(select count(*) from filtered)) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind='candidate' then
    with filtered as materialized (
      select c.*, p.plan_code, p.plan_name, pos.position_name,
        e.employee_no, e.employee_name, e.job_title, o.organization_name,
        (select count(*) from public.hr_succession_development_action a where a.candidate_id=c.id and a.status in ('planned','in_progress')) open_action_count
      from public.hr_succession_candidate c join public.hr_succession_plan p on p.id=c.plan_id
      join public.hr_position pos on pos.id=p.position_id join public.hr_employee e on e.id=c.employee_id
      left join public.sys_organization o on o.id=e.organization_id
      where (p_tenant_id is null or c.tenant_id=p_tenant_id) and (p_status is null or c.status=p_status)
        and (v_keyword is null or p.plan_name ilike '%'||v_keyword||'%' or pos.position_name ilike '%'||v_keyword||'%'
          or e.employee_no ilike '%'||v_keyword||'%' or e.employee_name ilike '%'||v_keyword||'%')
    ), paged as (select * from filtered order by status, readiness, priority, employee_name offset v_offset limit v_limit)
    select jsonb_build_object('records',coalesce(jsonb_agg((to_jsonb(paged)-'plan_code'-'plan_name'-'position_name'-'employee_no'-'employee_name'-'job_title'-'organization_name')||jsonb_build_object(
      'plan',jsonb_build_object('id',plan_id,'code',plan_code,'name',plan_name,'position_name',position_name),
      'employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name,'job_title',job_title,'organization_name',organization_name)
    ) order by status,readiness,priority,employee_name),'[]'::jsonb),'total',(select count(*) from filtered)) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  with filtered as materialized (
    select a.*, c.employee_id, e.employee_no, e.employee_name, p.plan_name, pos.position_name,
      owner.employee_no owner_no, owner.employee_name owner_name
    from public.hr_succession_development_action a join public.hr_succession_candidate c on c.id=a.candidate_id
    join public.hr_employee e on e.id=c.employee_id join public.hr_succession_plan p on p.id=c.plan_id
    join public.hr_position pos on pos.id=p.position_id left join public.hr_employee owner on owner.id=a.owner_employee_id
    where (p_tenant_id is null or a.tenant_id=p_tenant_id) and (p_status is null or a.status=p_status)
      and (v_keyword is null or a.action_title ilike '%'||v_keyword||'%' or e.employee_no ilike '%'||v_keyword||'%'
        or e.employee_name ilike '%'||v_keyword||'%' or p.plan_name ilike '%'||v_keyword||'%')
  ), paged as (select * from filtered order by status,due_date,action_title offset v_offset limit v_limit)
  select jsonb_build_object('records',coalesce(jsonb_agg((to_jsonb(paged)-'employee_id'-'employee_no'-'employee_name'-'plan_name'-'position_name'-'owner_no'-'owner_name')||jsonb_build_object(
    'candidate',jsonb_build_object('id',candidate_id,'employee_id',employee_id,'employee_no',employee_no,'employee_name',employee_name,'plan_name',plan_name,'position_name',position_name),
    'owner',case when owner_employee_id is null then null else jsonb_build_object('id',owner_employee_id,'code',owner_no,'name',owner_name) end
  ) order by status,due_date,action_title),'[]'::jsonb),'total',(select count(*) from filtered)) into v_result from paged;
  return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
end;
$function$;

create or replace function public.hr_list_succession_options_secure(p_kind text,p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_tenant_id uuid:=app_private.current_user_tenant_id(); v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrSuccession','Hr:Succession:View',null,false) then raise exception 'Missing succession view permission' using errcode='42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id:=v_tenant_id; end if;
  if p_kind='position' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'tenant_id',p.tenant_id,'code',p.position_code,'name',p.position_name,'organization_name',o.organization_name) order by p.position_name),'[]'::jsonb) into v_result
    from public.hr_position p left join public.sys_organization o on o.id=p.organization_id where (p_tenant_id is null or p.tenant_id=p_tenant_id) and p.enabled;
  elsif p_kind='employee' then
    select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'tenant_id',e.tenant_id,'code',e.employee_no,'name',e.employee_name,'job_title',e.job_title,'organization_name',o.organization_name) order by e.employee_name),'[]'::jsonb) into v_result
    from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id where (p_tenant_id is null or e.tenant_id=p_tenant_id) and e.employment_status in ('probation','active','leave');
  elsif p_kind='plan' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'tenant_id',p.tenant_id,'code',p.plan_code,'name',p.plan_name,'position_name',pos.position_name) order by p.plan_name),'[]'::jsonb) into v_result
    from public.hr_succession_plan p join public.hr_position pos on pos.id=p.position_id where (p_tenant_id is null or p.tenant_id=p_tenant_id) and p.status in ('draft','active');
  elsif p_kind='candidate' then
    select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'tenant_id',c.tenant_id,'code',e.employee_no,'name',e.employee_name,'plan_name',p.plan_name,'position_name',pos.position_name) order by e.employee_name),'[]'::jsonb) into v_result
    from public.hr_succession_candidate c join public.hr_employee e on e.id=c.employee_id join public.hr_succession_plan p on p.id=c.plan_id join public.hr_position pos on pos.id=p.position_id
    where (p_tenant_id is null or c.tenant_id=p_tenant_id) and c.status in ('nominated','active');
  else raise exception '不支持的继任选项类型'; end if;
  return coalesce(v_result,'[]'::jsonb);
end;
$function$;

create or replace function public.hr_save_succession_plan_secure(p_id uuid default null,p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare v_tenant_id uuid:=coalesce(nullif(p_payload->>'tenant_id','')::uuid,app_private.current_user_tenant_id()); v_id uuid:=coalesce(p_id,gen_random_uuid()); v_permission text:=case when p_id is null then 'Hr:Succession:Plan:Add' else 'Hr:Succession:Plan:Edit' end;
begin
  if not app_private.can_execute_business_action('HrSuccession',v_permission,null,false) then raise exception 'Missing succession plan permission' using errcode='42501'; end if;
  if not app_private.is_platform_super() then v_tenant_id:=app_private.current_user_tenant_id(); end if;
  if not exists(select 1 from public.hr_position where id=(p_payload->>'position_id')::uuid and tenant_id=v_tenant_id) then raise exception '岗位不存在或不属于当前租户'; end if;
  insert into public.hr_succession_plan(id,tenant_id,plan_code,position_id,plan_name,criticality,vacancy_risk,business_impact,target_successors,review_cycle_months,next_review_date,owner_employee_id,status,notes)
  values(v_id,v_tenant_id,upper(btrim(p_payload->>'plan_code')),(p_payload->>'position_id')::uuid,btrim(p_payload->>'plan_name'),p_payload->>'criticality',p_payload->>'vacancy_risk',p_payload->>'business_impact',coalesce((p_payload->>'target_successors')::integer,2),coalesce((p_payload->>'review_cycle_months')::integer,6),(p_payload->>'next_review_date')::date,nullif(p_payload->>'owner_employee_id','')::uuid,coalesce(p_payload->>'status','draft'),nullif(btrim(p_payload->>'notes'),''))
  on conflict(id) do update set plan_code=excluded.plan_code,position_id=excluded.position_id,plan_name=excluded.plan_name,criticality=excluded.criticality,vacancy_risk=excluded.vacancy_risk,business_impact=excluded.business_impact,target_successors=excluded.target_successors,review_cycle_months=excluded.review_cycle_months,next_review_date=excluded.next_review_date,owner_employee_id=excluded.owner_employee_id,status=excluded.status,notes=excluded.notes
  where hr_succession_plan.tenant_id=v_tenant_id;
  return v_id;
end;
$function$;

create or replace function public.hr_save_succession_candidate_secure(p_id uuid default null,p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare v_tenant_id uuid:=coalesce(nullif(p_payload->>'tenant_id','')::uuid,app_private.current_user_tenant_id()); v_id uuid:=coalesce(p_id,gen_random_uuid()); v_permission text:=case when p_id is null then 'Hr:Succession:Candidate:Add' else 'Hr:Succession:Candidate:Edit' end; v_plan_position uuid;
begin
  if not app_private.can_execute_business_action('HrSuccession',v_permission,null,false) then raise exception 'Missing succession candidate permission' using errcode='42501'; end if;
  if not app_private.is_platform_super() then v_tenant_id:=app_private.current_user_tenant_id(); end if;
  select position_id into v_plan_position from public.hr_succession_plan where id=(p_payload->>'plan_id')::uuid and tenant_id=v_tenant_id;
  if v_plan_position is null then raise exception '继任计划不存在或不属于当前租户'; end if;
  if not exists(select 1 from public.hr_employee where id=(p_payload->>'employee_id')::uuid and tenant_id=v_tenant_id) then raise exception '员工不存在或不属于当前租户'; end if;
  if exists(select 1 from public.hr_employee where id=(p_payload->>'employee_id')::uuid and position_id=v_plan_position) then raise exception '当前岗位任职者不能作为同一岗位的继任候选人'; end if;
  insert into public.hr_succession_candidate(id,tenant_id,plan_id,employee_id,readiness,potential_level,retention_risk,priority,nomination_source,aspiration_confirmed,mobility_scope,strengths,development_gaps,review_comment,status,nominated_on,last_reviewed_on)
  values(v_id,v_tenant_id,(p_payload->>'plan_id')::uuid,(p_payload->>'employee_id')::uuid,p_payload->>'readiness',p_payload->>'potential_level',p_payload->>'retention_risk',coalesce((p_payload->>'priority')::integer,1),coalesce(p_payload->>'nomination_source','talent_review'),coalesce((p_payload->>'aspiration_confirmed')::boolean,false),nullif(btrim(p_payload->>'mobility_scope'),''),nullif(btrim(p_payload->>'strengths'),''),nullif(btrim(p_payload->>'development_gaps'),''),nullif(btrim(p_payload->>'review_comment'),''),coalesce(p_payload->>'status','nominated'),coalesce(nullif(p_payload->>'nominated_on','')::date,current_date),nullif(p_payload->>'last_reviewed_on','')::date)
  on conflict(id) do update set plan_id=excluded.plan_id,employee_id=excluded.employee_id,readiness=excluded.readiness,potential_level=excluded.potential_level,retention_risk=excluded.retention_risk,priority=excluded.priority,nomination_source=excluded.nomination_source,aspiration_confirmed=excluded.aspiration_confirmed,mobility_scope=excluded.mobility_scope,strengths=excluded.strengths,development_gaps=excluded.development_gaps,review_comment=excluded.review_comment,status=excluded.status,nominated_on=excluded.nominated_on,last_reviewed_on=excluded.last_reviewed_on
  where hr_succession_candidate.tenant_id=v_tenant_id;
  return v_id;
end;
$function$;

create or replace function public.hr_save_succession_action_secure(p_id uuid default null,p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare v_tenant_id uuid:=coalesce(nullif(p_payload->>'tenant_id','')::uuid,app_private.current_user_tenant_id()); v_id uuid:=coalesce(p_id,gen_random_uuid()); v_permission text:=case when p_id is null then 'Hr:Succession:Action:Add' else 'Hr:Succession:Action:Edit' end; v_status text:=coalesce(p_payload->>'status','planned');
begin
  if not app_private.can_execute_business_action('HrSuccession',v_permission,null,false) then raise exception 'Missing succession action permission' using errcode='42501'; end if;
  if not app_private.is_platform_super() then v_tenant_id:=app_private.current_user_tenant_id(); end if;
  if not exists(select 1 from public.hr_succession_candidate where id=(p_payload->>'candidate_id')::uuid and tenant_id=v_tenant_id) then raise exception '继任候选人不存在或不属于当前租户'; end if;
  insert into public.hr_succession_development_action(id,tenant_id,candidate_id,action_type,action_title,action_description,owner_employee_id,start_date,due_date,status,completion_date,outcome)
  values(v_id,v_tenant_id,(p_payload->>'candidate_id')::uuid,p_payload->>'action_type',btrim(p_payload->>'action_title'),nullif(btrim(p_payload->>'action_description'),''),nullif(p_payload->>'owner_employee_id','')::uuid,coalesce(nullif(p_payload->>'start_date','')::date,current_date),(p_payload->>'due_date')::date,v_status,case when v_status='completed' then coalesce(nullif(p_payload->>'completion_date','')::date,current_date) else null end,case when v_status='completed' then nullif(btrim(p_payload->>'outcome'),'') else null end)
  on conflict(id) do update set candidate_id=excluded.candidate_id,action_type=excluded.action_type,action_title=excluded.action_title,action_description=excluded.action_description,owner_employee_id=excluded.owner_employee_id,start_date=excluded.start_date,due_date=excluded.due_date,status=excluded.status,completion_date=excluded.completion_date,outcome=excluded.outcome
  where hr_succession_development_action.tenant_id=v_tenant_id;
  return v_id;
end;
$function$;

create or replace function public.hr_review_succession_candidate_secure(p_id uuid,p_action text,p_comment text default null)
returns void language plpgsql security definer set search_path = '' as $function$
declare v_tenant_id uuid:=app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrSuccession','Hr:Succession:Candidate:Review',null,false) then raise exception 'Missing succession review permission' using errcode='42501'; end if;
  if p_action not in ('activate','withdraw','place') then raise exception '不支持的候选人评审动作'; end if;
  update public.hr_succession_candidate set status=case p_action when 'activate' then 'active' when 'withdraw' then 'withdrawn' else 'placed' end,last_reviewed_on=current_date,review_comment=coalesce(nullif(btrim(p_comment),''),review_comment)
  where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id);
  if not found then raise exception '继任候选人不存在或无权操作'; end if;
end;
$function$;

create or replace function public.hr_delete_succession_record_secure(p_kind text,p_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
declare v_tenant_id uuid:=app_private.current_user_tenant_id(); v_permission text;
begin
  v_permission:=case p_kind when 'plan' then 'Hr:Succession:Plan:Delete' when 'candidate' then 'Hr:Succession:Candidate:Delete' when 'action' then 'Hr:Succession:Action:Delete' else null end;
  if v_permission is null then raise exception '不支持的继任记录类型'; end if;
  if not app_private.can_execute_business_action('HrSuccession',v_permission,null,false) then raise exception 'Missing succession delete permission' using errcode='42501'; end if;
  if p_kind='plan' then delete from public.hr_succession_plan where id=p_id and status='draft' and (app_private.is_platform_super() or tenant_id=v_tenant_id);
  elsif p_kind='candidate' then delete from public.hr_succession_candidate where id=p_id and status='nominated' and (app_private.is_platform_super() or tenant_id=v_tenant_id);
  else delete from public.hr_succession_development_action where id=p_id and status='planned' and (app_private.is_platform_super() or tenant_id=v_tenant_id); end if;
  if not found then raise exception '仅草稿计划、待评审候选人或计划中行动可删除'; end if;
end;
$function$;

revoke all on function public.hr_succession_overview_secure(uuid) from public,anon;
revoke all on function public.hr_list_succession_records_secure(text,integer,integer,text,text,uuid) from public,anon;
revoke all on function public.hr_list_succession_options_secure(text,uuid) from public,anon;
revoke all on function public.hr_save_succession_plan_secure(uuid,jsonb) from public,anon;
revoke all on function public.hr_save_succession_candidate_secure(uuid,jsonb) from public,anon;
revoke all on function public.hr_save_succession_action_secure(uuid,jsonb) from public,anon;
revoke all on function public.hr_review_succession_candidate_secure(uuid,text,text) from public,anon;
revoke all on function public.hr_delete_succession_record_secure(text,uuid) from public,anon;
grant execute on function public.hr_succession_overview_secure(uuid) to authenticated,service_role;
grant execute on function public.hr_list_succession_records_secure(text,integer,integer,text,text,uuid) to authenticated,service_role;
grant execute on function public.hr_list_succession_options_secure(text,uuid) to authenticated,service_role;
grant execute on function public.hr_save_succession_plan_secure(uuid,jsonb) to authenticated,service_role;
grant execute on function public.hr_save_succession_candidate_secure(uuid,jsonb) to authenticated,service_role;
grant execute on function public.hr_save_succession_action_secure(uuid,jsonb) to authenticated,service_role;
grant execute on function public.hr_review_succession_candidate_secure(uuid,text,text) to authenticated,service_role;
grant execute on function public.hr_delete_succession_record_secure(text,uuid) to authenticated,service_role;

with platform_tenant as (select id from public.sys_tenant where tenant_code='platform' limit 1),types(name,code,sort) as (values
  ('继任计划状态','hrSuccessionPlanStatus',73),('岗位关键度','hrSuccessionCriticality',74),('岗位空缺风险','hrSuccessionVacancyRisk',75),
  ('继任准备度','hrSuccessionReadiness',76),('人才潜力','hrSuccessionPotential',77),('人才留任风险','hrSuccessionRetentionRisk',78),
  ('候选人状态','hrSuccessionCandidateStatus',79),('发展行动类型','hrSuccessionActionType',80),('发展行动状态','hrSuccessionActionStatus',81)
)
insert into public.sys_dict_type(id,name,code,status,create_by,update_by,remark,tenant_id,parent_id,node_type,sort)
select gen_random_uuid(),types.name,types.code,'1','624944977@qq.com','624944977@qq.com','企业 HR 继任规划字典',platform_tenant.id,(select id from public.sys_dict_type where code='hrManage' limit 1),'dictionary',types.sort from types cross join platform_tenant
on conflict(code) do update set name=excluded.name,status=excluded.status,update_by=excluded.update_by,update_time=now(),remark=excluded.remark,sort=excluded.sort;

with platform_tenant as (select id from public.sys_tenant where tenant_code='platform' limit 1),items(type_code,value,label,sort,tag_type) as (values
  ('hrSuccessionPlanStatus','draft','草稿',1,'info'),('hrSuccessionPlanStatus','active','执行中',2,'success'),('hrSuccessionPlanStatus','closed','已关闭',3,'danger'),
  ('hrSuccessionCriticality','medium','重要',1,'info'),('hrSuccessionCriticality','high','关键',2,'warning'),('hrSuccessionCriticality','critical','核心关键',3,'danger'),
  ('hrSuccessionVacancyRisk','low','低',1,'success'),('hrSuccessionVacancyRisk','medium','中',2,'warning'),('hrSuccessionVacancyRisk','high','高',3,'danger'),
  ('hrSuccessionReadiness','ready_now','可立即继任',1,'success'),('hrSuccessionReadiness','one_to_two_years','1–2 年',2,'primary'),('hrSuccessionReadiness','three_to_five_years','3–5 年',3,'warning'),('hrSuccessionReadiness','development_needed','需重点发展',4,'danger'),
  ('hrSuccessionPotential','emerging','潜力初显',1,'info'),('hrSuccessionPotential','medium','中潜力',2,'primary'),('hrSuccessionPotential','high','高潜力',3,'success'),
  ('hrSuccessionRetentionRisk','low','低',1,'success'),('hrSuccessionRetentionRisk','medium','中',2,'warning'),('hrSuccessionRetentionRisk','high','高',3,'danger'),
  ('hrSuccessionCandidateStatus','nominated','待评审',1,'warning'),('hrSuccessionCandidateStatus','active','在继任池',2,'success'),('hrSuccessionCandidateStatus','withdrawn','已退出',3,'info'),('hrSuccessionCandidateStatus','placed','已继任',4,'primary'),
  ('hrSuccessionActionType','mentoring','导师辅导',1,'primary'),('hrSuccessionActionType','training','专项学习',2,'success'),('hrSuccessionActionType','stretch_assignment','挑战性任务',3,'warning'),('hrSuccessionActionType','job_rotation','岗位轮换',4,'danger'),('hrSuccessionActionType','coaching','职业教练',5,'info'),('hrSuccessionActionType','assessment','人才测评',6,'primary'),('hrSuccessionActionType','other','其他',7,'info'),
  ('hrSuccessionActionStatus','planned','计划中',1,'info'),('hrSuccessionActionStatus','in_progress','进行中',2,'primary'),('hrSuccessionActionStatus','completed','已完成',3,'success'),('hrSuccessionActionStatus','cancelled','已取消',4,'danger')
)
insert into public.sys_dictionary(id,type_id,code,status,create_by,update_by,remark,value,label,tenant_id,tag_type,sort)
select gen_random_uuid(),t.id,items.type_code||'_'||items.value,'1','624944977@qq.com','624944977@qq.com','企业 HR 继任规划字典项',items.value,items.label,platform_tenant.id,items.tag_type,items.sort
from items join public.sys_dict_type t on t.code=items.type_code cross join platform_tenant
where not exists(select 1 from public.sys_dictionary d where d.type_id=t.id and d.value=items.value);

insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,app_code,create_by,update_by)
values('c0de0000-0000-4000-8000-000000000304','c0de0000-0000-4000-8000-000000000300','HrSuccession','succession','/hr/talent/succession',jsonb_build_object('title','继任与发展','icon','ri:git-merge-line','is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,'show_badge',false,'show_text_badge','','is_hide_tab',false,'is_full_page',false,'active_path','','link','','roles',jsonb_build_array('R_SUPER','R_ADMIN')),5,'menu','hr','624944977@qq.com','624944977@qq.com')
on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,component=excluded.component,meta=excluded.meta,sort=excluded.sort,type=excluded.type,app_code=excluded.app_code,update_by=excluded.update_by,update_time=now();

insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,app_code,create_by,update_by)
select seed.id,'c0de0000-0000-4000-8000-000000000304',seed.name,'','',jsonb_build_object('title',seed.title,'icon','','is_hide',true,'is_enable',true,'roles',jsonb_build_array()),seed.sort,'button','hr','624944977@qq.com','624944977@qq.com'
from (values
 ('c0de0000-0000-4000-8304-000000000001'::uuid,'Hr:Succession:View','查看继任规划',1),
 ('c0de0000-0000-4000-8304-000000000002'::uuid,'Hr:Succession:Plan:Add','新增继任计划',2),('c0de0000-0000-4000-8304-000000000003'::uuid,'Hr:Succession:Plan:Edit','编辑继任计划',3),('c0de0000-0000-4000-8304-000000000004'::uuid,'Hr:Succession:Plan:Delete','删除继任计划',4),
 ('c0de0000-0000-4000-8304-000000000005'::uuid,'Hr:Succession:Candidate:Add','提名继任候选人',5),('c0de0000-0000-4000-8304-000000000006'::uuid,'Hr:Succession:Candidate:Edit','编辑继任候选人',6),('c0de0000-0000-4000-8304-000000000007'::uuid,'Hr:Succession:Candidate:Delete','删除继任候选人',7),('c0de0000-0000-4000-8304-000000000008'::uuid,'Hr:Succession:Candidate:Review','评审继任候选人',8),
 ('c0de0000-0000-4000-8304-000000000009'::uuid,'Hr:Succession:Action:Add','新增发展行动',9),('c0de0000-0000-4000-8304-000000000010'::uuid,'Hr:Succession:Action:Edit','编辑发展行动',10),('c0de0000-0000-4000-8304-000000000011'::uuid,'Hr:Succession:Action:Delete','删除发展行动',11)
) seed(id,name,title,sort)
on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,meta=excluded.meta,sort=excluded.sort,type=excluded.type,app_code=excluded.app_code,update_by=excluded.update_by,update_time=now();

insert into public.sys_role_menu(role_id,menu_id,tenant_id,permission,create_by,update_by)
select r.id,m.id,r.tenant_id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com'
from public.sys_role r cross join (values
 ('c0de0000-0000-4000-8000-000000000304'::uuid),('c0de0000-0000-4000-8304-000000000001'::uuid),('c0de0000-0000-4000-8304-000000000002'::uuid),('c0de0000-0000-4000-8304-000000000003'::uuid),('c0de0000-0000-4000-8304-000000000004'::uuid),('c0de0000-0000-4000-8304-000000000005'::uuid),('c0de0000-0000-4000-8304-000000000006'::uuid),('c0de0000-0000-4000-8304-000000000007'::uuid),('c0de0000-0000-4000-8304-000000000008'::uuid),('c0de0000-0000-4000-8304-000000000009'::uuid),('c0de0000-0000-4000-8304-000000000010'::uuid),('c0de0000-0000-4000-8304-000000000011'::uuid)
) m(id) where r.enabled and (r.builtin_type='platform_super' or r.role_code in ('R_SUPER','R_ADMIN'))
on conflict(role_id,menu_id) do nothing;
