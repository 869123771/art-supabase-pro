-- 事故调查处理：事故快报一对一生成分析单，参加人员使用独立关联表。

create table public.smis_accident_analysis (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  accident_report_id uuid not null,
  host_employee_id uuid,
  recorder_employee_id uuid,
  rectification_responsible_employee_id uuid,
  accident_level text not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_accident_analysis_id_tenant_key unique (id, tenant_id),
  constraint smis_accident_analysis_report_key unique (tenant_id, accident_report_id),
  constraint smis_accident_analysis_report_fkey foreign key (accident_report_id, tenant_id)
    references public.smis_accident_report(id, tenant_id) on delete cascade,
  constraint smis_accident_analysis_host_fkey foreign key (host_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_accident_analysis_recorder_fkey foreign key (recorder_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_accident_analysis_responsible_fkey foreign key (rectification_responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_accident_analysis_level_check check (
    accident_level in ('near_miss', 'minor_injury', 'general', 'major', 'severe', 'catastrophic')
  )
);

comment on table public.smis_accident_analysis is '由事故快报自动生成的租户级事故分析单';
comment on column public.smis_accident_analysis.accident_report_id is '同一租户内与事故快报一对一关联';

create table public.smis_accident_analysis_participant (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  accident_analysis_id uuid not null,
  employee_id uuid not null,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_accident_analysis_participant_id_tenant_key unique (id, tenant_id),
  constraint smis_accident_analysis_participant_employee_key
    unique (tenant_id, accident_analysis_id, employee_id),
  constraint smis_accident_analysis_participant_analysis_fkey
    foreign key (accident_analysis_id, tenant_id)
    references public.smis_accident_analysis(id, tenant_id) on delete cascade,
  constraint smis_accident_analysis_participant_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_accident_analysis_participant_sort_check check (sort >= 0)
);

comment on table public.smis_accident_analysis_participant is '事故分析会参加人员';

create index smis_accident_analysis_tenant_level_idx
  on public.smis_accident_analysis (tenant_id, accident_level, update_time desc, id);
create index smis_accident_analysis_report_idx
  on public.smis_accident_analysis (accident_report_id, tenant_id);
create index smis_accident_analysis_host_idx
  on public.smis_accident_analysis (host_employee_id, tenant_id) where host_employee_id is not null;
create index smis_accident_analysis_recorder_idx
  on public.smis_accident_analysis (recorder_employee_id, tenant_id) where recorder_employee_id is not null;
create index smis_accident_analysis_responsible_idx
  on public.smis_accident_analysis (rectification_responsible_employee_id, tenant_id)
  where rectification_responsible_employee_id is not null;
create index smis_accident_analysis_participant_analysis_idx
  on public.smis_accident_analysis_participant (accident_analysis_id, tenant_id, sort);
create index smis_accident_analysis_participant_employee_idx
  on public.smis_accident_analysis_participant (employee_id, tenant_id);

create trigger smis_accident_analysis_create_audit before insert on public.smis_accident_analysis
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_accident_analysis_update_audit before update on public.smis_accident_analysis
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_accident_analysis_participant_create_audit
before insert on public.smis_accident_analysis_participant
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_accident_analysis_participant_update_audit
before update on public.smis_accident_analysis_participant
for each row execute function public.trg_set_update_time_and_by();

-- 先补齐历史数据，再启用受控写保护。
insert into public.smis_accident_analysis(tenant_id, accident_report_id, accident_level)
select report.tenant_id, report.id, report.accident_level
from public.smis_accident_report report
on conflict (tenant_id, accident_report_id) do nothing;

create trigger smis_accident_analysis_platform_super_write
before insert or update or delete on public.smis_accident_analysis
for each row execute function app_private.guard_smis_accident_platform_super_write();
create trigger smis_accident_analysis_participant_platform_super_write
before insert or update or delete on public.smis_accident_analysis_participant
for each row execute function app_private.guard_smis_accident_platform_super_write();

create or replace function app_private.create_smis_accident_analysis_from_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.smis_accident_analysis(tenant_id, accident_report_id, accident_level)
  values (new.tenant_id, new.id, new.accident_level)
  on conflict (tenant_id, accident_report_id) do nothing;
  return new;
end;
$$;
revoke all on function app_private.create_smis_accident_analysis_from_report()
  from public, anon, authenticated;

create trigger smis_accident_report_create_analysis
after insert on public.smis_accident_report
for each row execute function app_private.create_smis_accident_analysis_from_report();

alter table public.smis_accident_analysis enable row level security;
alter table public.smis_accident_analysis_participant enable row level security;

create policy smis_accident_analysis_tenant_select on public.smis_accident_analysis
for select to authenticated
using ((app_private.is_platform_super() or tenant_id = (select app_private.current_user_tenant_id()))
  and (select app_private.has_permission('SmisAccidentInvestigation:View')));
create policy smis_accident_analysis_tenant_insert on public.smis_accident_analysis
for insert to authenticated
with check (app_private.is_platform_super()
  and tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisAccidentInvestigation:Add')));
create policy smis_accident_analysis_tenant_update on public.smis_accident_analysis
for update to authenticated
using (app_private.is_platform_super()
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit')))
with check (app_private.is_platform_super()
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit')));
create policy smis_accident_analysis_tenant_delete on public.smis_accident_analysis
for delete to authenticated
using (app_private.is_platform_super()
  and (select app_private.has_permission('SmisAccidentInvestigation:Delete')));

create policy smis_accident_analysis_participant_tenant_select
on public.smis_accident_analysis_participant for select to authenticated
using ((app_private.is_platform_super() or tenant_id = (select app_private.current_user_tenant_id()))
  and (select app_private.has_permission('SmisAccidentInvestigation:View')));
create policy smis_accident_analysis_participant_tenant_insert
on public.smis_accident_analysis_participant for insert to authenticated
with check (app_private.is_platform_super()
  and tenant_id = (select app_private.current_user_tenant_id())
  and ((select app_private.has_permission('SmisAccidentInvestigation:Add'))
    or (select app_private.has_permission('SmisAccidentInvestigation:Edit'))));
create policy smis_accident_analysis_participant_tenant_update
on public.smis_accident_analysis_participant for update to authenticated
using (app_private.is_platform_super()
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit')))
with check (app_private.is_platform_super()
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit')));
create policy smis_accident_analysis_participant_tenant_delete
on public.smis_accident_analysis_participant for delete to authenticated
using (app_private.is_platform_super()
  and (select app_private.has_permission('SmisAccidentInvestigation:Delete')));

grant select on public.smis_accident_analysis to authenticated;
grant select on public.smis_accident_analysis_participant to authenticated;
revoke all on public.smis_accident_analysis from anon;
revoke all on public.smis_accident_analysis_participant from anon;

create or replace function public.smis_list_accident_analyses_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_accident_level text default null,
  p_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1), 5000);
  v_keyword text := nullif(btrim(p_keyword), '');
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
begin
  if not app_private.has_permission('SmisAccidentInvestigation:View') then
    raise exception '当前账号无权查看事故分析单';
  end if;

  with filtered as materialized (
    select analysis.*, report.accident_no, report.accident_name, report.accident_time,
      report.accident_location,
      (select count(*) from public.smis_accident_analysis_participant participant
       where participant.tenant_id = analysis.tenant_id
         and participant.accident_analysis_id = analysis.id)::integer as participant_count
    from public.smis_accident_analysis analysis
    join public.smis_accident_report report
      on report.id = analysis.accident_report_id and report.tenant_id = analysis.tenant_id
    where (app_private.is_platform_super() or analysis.tenant_id = v_tenant)
      and (p_ids is null or analysis.id = any(p_ids))
      and (p_accident_level is null or analysis.accident_level = p_accident_level)
      and (v_keyword is null
        or report.accident_name ilike '%' || v_keyword || '%'
        or report.accident_no ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by update_time desc, id desc offset v_from limit v_limit
  )
  select (select count(*) from filtered), coalesce(jsonb_agg(jsonb_build_object(
    'id', paged.id,
    'accidentReportId', paged.accident_report_id,
    'accident', jsonb_build_object(
      'id', paged.accident_report_id,
      'accidentNo', paged.accident_no,
      'accidentName', paged.accident_name,
      'accidentTime', paged.accident_time,
      'accidentLocation', paged.accident_location,
      'accidentLevel', paged.accident_level
    ),
    'hostEmployeeId', paged.host_employee_id,
    'hostEmployee', app_private.smis_accident_employee_snapshot(paged.tenant_id, paged.host_employee_id),
    'recorderEmployeeId', paged.recorder_employee_id,
    'recorderEmployee', app_private.smis_accident_employee_snapshot(paged.tenant_id, paged.recorder_employee_id),
    'rectificationResponsibleEmployeeId', paged.rectification_responsible_employee_id,
    'rectificationResponsibleEmployee', app_private.smis_accident_employee_snapshot(
      paged.tenant_id, paged.rectification_responsible_employee_id),
    'participants', coalesce((select jsonb_agg(
      app_private.smis_accident_employee_snapshot(participant.tenant_id, participant.employee_id)
      order by participant.sort, participant.id)
      from public.smis_accident_analysis_participant participant
      where participant.tenant_id = paged.tenant_id
        and participant.accident_analysis_id = paged.id), '[]'::jsonb),
    'participantCount', paged.participant_count,
    'accidentLevel', paged.accident_level,
    'isComplete', paged.host_employee_id is not null and paged.recorder_employee_id is not null
      and paged.rectification_responsible_employee_id is not null and paged.participant_count > 0,
    'createBy', paged.create_by,
    'createTime', paged.create_time,
    'updateBy', paged.update_by,
    'updateTime', paged.update_time
  ) order by paged.update_time desc, paged.id desc), '[]'::jsonb)
  into v_total, v_records
  from paged;

  select jsonb_build_object(
    'total', count(*),
    'complete', count(*) filter (where host_employee_id is not null
      and recorder_employee_id is not null
      and rectification_responsible_employee_id is not null
      and exists(select 1 from public.smis_accident_analysis_participant participant
        where participant.tenant_id = analysis.tenant_id
          and participant.accident_analysis_id = analysis.id)),
    'pending', count(*) filter (where host_employee_id is null
      or recorder_employee_id is null
      or rectification_responsible_employee_id is null
      or not exists(select 1 from public.smis_accident_analysis_participant participant
        where participant.tenant_id = analysis.tenant_id
          and participant.accident_analysis_id = analysis.id)),
    'participantCount', coalesce(sum((select count(*)
      from public.smis_accident_analysis_participant participant
      where participant.tenant_id = analysis.tenant_id
        and participant.accident_analysis_id = analysis.id)), 0)
  ) into v_overview
  from public.smis_accident_analysis analysis
  where app_private.is_platform_super() or analysis.tenant_id = v_tenant;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'overview', coalesce(v_overview,
      jsonb_build_object('total', 0, 'complete', 0, 'pending', 0, 'participantCount', 0))
  );
end;
$$;

create or replace function public.smis_save_accident_analysis_secure(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid := p_id;
  v_report_id uuid := nullif(p_payload->>'accident_report_id', '')::uuid;
  v_host_id uuid := nullif(p_payload->>'host_employee_id', '')::uuid;
  v_recorder_id uuid := nullif(p_payload->>'recorder_employee_id', '')::uuid;
  v_responsible_id uuid := nullif(p_payload->>'rectification_responsible_employee_id', '')::uuid;
  v_level text := p_payload->>'accident_level';
  v_participants jsonb := coalesce(p_payload->'participant_employee_ids', '[]'::jsonb);
  v_employee_id uuid;
  v_sort integer := 0;
begin
  if p_id is null and not app_private.has_permission('SmisAccidentInvestigation:Add') then
    raise exception '当前账号无权新增事故分析单';
  end if;
  if p_id is not null and not app_private.has_permission('SmisAccidentInvestigation:Edit') then
    raise exception '当前账号无权编辑事故分析单';
  end if;

  v_tenant := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_accident_analysis target where target.id = p_id
  ));
  if v_report_id is null or not exists(
    select 1 from public.smis_accident_report report
    where report.id = v_report_id and report.tenant_id = v_tenant
  ) then raise exception '请选择当前租户有效的关联事故'; end if;
  if v_level not in ('near_miss', 'minor_injury', 'general', 'major', 'severe', 'catastrophic') then
    raise exception '请选择有效的事故级别';
  end if;
  if exists(
    select 1
    from unnest(array[v_host_id, v_recorder_id, v_responsible_id]) selected(employee_id)
    where selected.employee_id is not null and not exists(
      select 1 from public.hr_employee employee
      where employee.id = selected.employee_id and employee.tenant_id = v_tenant
        and employee.employment_status in ('probation', 'active')
    )
  ) then raise exception '主持人、记录人或整改责任人必须是当前租户在职员工'; end if;
  if exists(
    select 1 from jsonb_array_elements_text(v_participants) item
    where not exists(
      select 1 from public.hr_employee employee
      where employee.id = item::uuid and employee.tenant_id = v_tenant
        and employee.employment_status in ('probation', 'active')
    )
  ) then raise exception '参加人员包含当前租户之外或非在职员工'; end if;
  if (select count(*) from jsonb_array_elements_text(v_participants))
    <> (select count(distinct item) from jsonb_array_elements_text(v_participants) item)
  then raise exception '参加人员不能重复'; end if;

  if v_id is null then
    select analysis.id into v_id
    from public.smis_accident_analysis analysis
    where analysis.tenant_id = v_tenant and analysis.accident_report_id = v_report_id;
  end if;

  if v_id is null then
    insert into public.smis_accident_analysis(
      tenant_id, accident_report_id, host_employee_id, recorder_employee_id,
      rectification_responsible_employee_id, accident_level
    ) values (
      v_tenant, v_report_id, v_host_id, v_recorder_id, v_responsible_id, v_level
    ) returning id into v_id;
  else
    update public.smis_accident_analysis
    set accident_report_id = v_report_id,
        host_employee_id = v_host_id,
        recorder_employee_id = v_recorder_id,
        rectification_responsible_employee_id = v_responsible_id,
        accident_level = v_level
    where id = v_id and tenant_id = v_tenant
    returning id into v_id;
    if not found then raise exception '事故分析单不存在或不属于当前租户'; end if;
  end if;

  delete from public.smis_accident_analysis_participant
  where tenant_id = v_tenant and accident_analysis_id = v_id;
  for v_employee_id in select value::uuid from jsonb_array_elements_text(v_participants)
  loop
    insert into public.smis_accident_analysis_participant(
      tenant_id, accident_analysis_id, employee_id, sort
    ) values (v_tenant, v_id, v_employee_id, v_sort);
    v_sort := v_sort + 1;
  end loop;
  return v_id;
exception
  when unique_violation then
    raise exception '该事故已存在分析单，请直接编辑原分析单';
end;
$$;

create or replace function public.smis_delete_accident_analyses_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_count integer;
begin
  if not app_private.has_permission('SmisAccidentInvestigation:Delete') then
    raise exception '当前账号无权删除事故分析单';
  end if;
  delete from public.smis_accident_analysis
  where id = any(p_ids) and (app_private.is_platform_super() or tenant_id = v_tenant);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 复用事故域人员与事故选择器，并扩展其权限覆盖事故调查页面。
create or replace function public.smis_list_accident_employee_candidates_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1), 200);
  v_keyword text := nullif(btrim(p_keyword), '');
  v_records jsonb;
  v_total bigint;
begin
  if not (
    app_private.has_permission('SmisAccidentFlashReport:Add')
    or app_private.has_permission('SmisAccidentFlashReport:Edit')
    or app_private.has_permission('SmisWorkInjuryDeclaration:Add')
    or app_private.has_permission('SmisWorkInjuryDeclaration:Edit')
    or app_private.has_permission('SmisAccidentInvestigation:Add')
    or app_private.has_permission('SmisAccidentInvestigation:Edit')
  ) then raise exception '当前账号无权选择事故相关人员'; end if;
  with filtered as materialized (
    select employee.id, employee.employee_name, employee.employee_no
    from public.hr_employee employee
    left join public.sys_organization organization
      on organization.id = employee.organization_id and organization.tenant_id = employee.tenant_id
    where employee.tenant_id = v_tenant
      and employee.employment_status in ('probation', 'active')
      and (v_keyword is null
        or employee.employee_name ilike '%' || v_keyword || '%'
        or employee.employee_no ilike '%' || v_keyword || '%'
        or employee.job_title ilike '%' || v_keyword || '%'
        or organization.organization_name ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by employee_name, employee_no, id offset v_from limit v_limit
  )
  select (select count(*) from filtered), coalesce(jsonb_agg(
    app_private.smis_accident_employee_snapshot(v_tenant, paged.id)
    order by paged.employee_name, paged.employee_no, paged.id), '[]'::jsonb)
  into v_total, v_records from paged;
  return jsonb_build_object('records', v_records, 'total', v_total);
end;
$$;

create or replace function public.smis_list_accident_report_options_secure(p_keyword text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_records jsonb;
begin
  if not (
    app_private.has_permission('SmisWorkInjuryDeclaration:Add')
    or app_private.has_permission('SmisWorkInjuryDeclaration:Edit')
    or app_private.has_permission('SmisAccidentInvestigation:Add')
    or app_private.has_permission('SmisAccidentInvestigation:Edit')
  ) then raise exception '当前账号无权选择关联事故'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', report.id,
    'accidentNo', report.accident_no,
    'accidentName', report.accident_name,
    'accidentTime', report.accident_time,
    'accidentLocation', report.accident_location,
    'accidentLevel', report.accident_level
  ) order by report.accident_time desc, report.id desc), '[]'::jsonb)
  into v_records
  from public.smis_accident_report report
  where (app_private.is_platform_super() or report.tenant_id = v_tenant)
    and (nullif(btrim(p_keyword), '') is null
      or report.accident_no ilike '%' || btrim(p_keyword) || '%'
      or report.accident_name ilike '%' || btrim(p_keyword) || '%');
  return v_records;
end;
$$;

revoke all on function public.smis_list_accident_analyses_secure(integer, integer, text, text, uuid[])
  from public, anon;
revoke all on function public.smis_save_accident_analysis_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_accident_analyses_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_accident_analyses_secure(integer, integer, text, text, uuid[])
  to authenticated;
grant execute on function public.smis_save_accident_analysis_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_delete_accident_analyses_secure(uuid[]) to authenticated;

with page_row as (
  select id, app_code from public.sys_menu
  where app_code = 'smis' and name = 'SmisAccidentInvestigation'
), button_rows(button_name, title, sort) as (
  values
    ('SmisAccidentInvestigation:View', '查看', 1),
    ('SmisAccidentInvestigation:Add', '新增', 2),
    ('SmisAccidentInvestigation:Edit', '编辑', 3),
    ('SmisAccidentInvestigation:Delete', '删除', 4),
    ('SmisAccidentInvestigation:Export', '导出', 5)
)
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort, app_code,
  create_by, create_time, update_by, update_time
)
select gen_random_uuid(), page.id, button.button_name, '', '', 'button',
  jsonb_build_object('title', button.title, 'roles', '[]'::jsonb, 'is_hide', true, 'is_enable', true),
  button.sort, page.app_code, '624944977@qq.com', now(), '624944977@qq.com', now()
from button_rows button cross join page_row page
where not exists(select 1 from public.sys_menu existing where existing.name = button.button_name);

insert into public.sys_role_menu(
  id, role_id, menu_id, permission, tenant_id, create_by, create_time, update_by, update_time
)
select gen_random_uuid(), page_grant.role_id, button.id, '{}'::jsonb, page_grant.tenant_id,
  '624944977@qq.com', now(), '624944977@qq.com', now()
from public.sys_menu page
join public.sys_role_menu page_grant on page_grant.menu_id = page.id
join public.sys_role role on role.id = page_grant.role_id and role.tenant_id = page_grant.tenant_id
join public.sys_menu button on button.parent_id = page.id and button.type = 'button'
where page.app_code = 'smis' and page.name = 'SmisAccidentInvestigation'
  and button.name in (
    'SmisAccidentInvestigation:View', 'SmisAccidentInvestigation:Add',
    'SmisAccidentInvestigation:Edit', 'SmisAccidentInvestigation:Delete',
    'SmisAccidentInvestigation:Export'
  )
  and (button.name like '%:View' or button.name like '%:Export' or role.builtin_type = 'platform_super')
  and not exists(
    select 1 from public.sys_role_menu existing
    where existing.role_id = page_grant.role_id and existing.menu_id = button.id
      and existing.tenant_id = page_grant.tenant_id
  );

;
