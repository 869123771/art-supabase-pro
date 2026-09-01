-- HR P0: personnel lifecycle, onboarding/offboarding, contract workbench and qualifications.

alter table public.hr_employee_contract
  add column if not exists attachment_url text,
  add column if not exists renewal_reminder_days integer not null default 30;

alter table public.hr_employee_contract
  drop constraint if exists hr_employee_contract_reminder_days_check;
alter table public.hr_employee_contract
  add constraint hr_employee_contract_reminder_days_check
  check (renewal_reminder_days between 0 and 365);

create table if not exists public.hr_personnel_change (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  change_no text not null,
  employee_id uuid not null,
  change_type text not null,
  effective_date date not null,
  status text not null default 'draft',
  from_organization_id uuid,
  to_organization_id uuid,
  from_position_id uuid,
  to_position_id uuid,
  from_employment_status text,
  to_employment_status text,
  from_job_title text,
  to_job_title text,
  reason text not null,
  workflow_instance_id uuid,
  approved_at timestamptz,
  approved_by text,
  effected_at timestamptz,
  effected_by text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_personnel_change_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_personnel_change_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_personnel_change_from_position_fkey foreign key (from_position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_personnel_change_to_position_fkey foreign key (to_position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_personnel_change_status_check check (
    status in ('draft', 'pending', 'approved', 'effective', 'rejected', 'cancelled')
  ),
  constraint hr_personnel_change_no_unique unique (tenant_id, change_no)
);

create table if not exists public.hr_lifecycle_case (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  case_no text not null,
  employee_id uuid not null,
  case_type text not null,
  planned_effective_date date not null,
  status text not null default 'draft',
  owner_user_id uuid,
  workflow_instance_id uuid,
  approved_at timestamptz,
  approved_by text,
  completed_at timestamptz,
  completed_by text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_lifecycle_case_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_lifecycle_case_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_lifecycle_case_owner_fkey foreign key (tenant_id, owner_user_id)
    references public.sys_user(tenant_id, id) on delete restrict,
  constraint hr_lifecycle_case_status_check check (
    status in ('draft', 'pending', 'approved', 'effective', 'rejected', 'cancelled')
  ),
  constraint hr_lifecycle_case_no_unique unique (tenant_id, case_no),
  constraint hr_lifecycle_case_id_tenant_unique unique (id, tenant_id)
);

create table if not exists public.hr_lifecycle_task (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  lifecycle_case_id uuid not null,
  task_type text not null,
  task_name text not null,
  responsible_user_id uuid,
  due_date date,
  status text not null default 'pending',
  completed_at timestamptz,
  completed_by text,
  completion_note text,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_lifecycle_task_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_lifecycle_task_case_fkey foreign key (lifecycle_case_id, tenant_id)
    references public.hr_lifecycle_case(id, tenant_id) on delete cascade,
  constraint hr_lifecycle_task_responsible_fkey foreign key (tenant_id, responsible_user_id)
    references public.sys_user(tenant_id, id) on delete restrict,
  constraint hr_lifecycle_task_status_check check (
    status in ('pending', 'processing', 'completed', 'skipped', 'cancelled')
  )
);

create table if not exists public.hr_employee_qualification (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  qualification_type text not null,
  qualification_name text not null,
  certificate_no text,
  issuer text,
  issue_date date,
  expiry_date date,
  status text not null default 'valid',
  attachment_url text,
  reminder_days integer not null default 30,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_qualification_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_qualification_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete cascade,
  constraint hr_employee_qualification_dates_check check (
    expiry_date is null or issue_date is null or expiry_date >= issue_date
  ),
  constraint hr_employee_qualification_reminder_days_check check (reminder_days between 0 and 365),
  constraint hr_employee_qualification_status_check check (
    status in ('valid', 'expiring', 'expired', 'revoked')
  )
);

create index if not exists idx_hr_personnel_change_employee
  on public.hr_personnel_change(tenant_id, employee_id, effective_date desc);
create index if not exists idx_hr_personnel_change_status
  on public.hr_personnel_change(tenant_id, status, effective_date);
create index if not exists idx_hr_lifecycle_case_employee
  on public.hr_lifecycle_case(tenant_id, employee_id, planned_effective_date desc);
create index if not exists idx_hr_lifecycle_case_status
  on public.hr_lifecycle_case(tenant_id, status, planned_effective_date);
create index if not exists idx_hr_lifecycle_task_case
  on public.hr_lifecycle_task(tenant_id, lifecycle_case_id, status, sort);
create index if not exists idx_hr_employee_qualification_employee
  on public.hr_employee_qualification(tenant_id, employee_id, expiry_date);
create index if not exists idx_hr_employee_qualification_expiry
  on public.hr_employee_qualification(tenant_id, status, expiry_date);

create or replace function app_private.hr_guard_approval_record()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('app.workflow_engine', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.status not in ('draft', 'rejected') then
      raise exception '当前状态的人事单据不可编辑';
    end if;
    if new.status is distinct from old.status then
      raise exception '人事单据状态只能通过审批流程变更';
    end if;
  elsif tg_op = 'DELETE' and old.status not in ('draft', 'rejected', 'cancelled') then
    raise exception '仅草稿、已驳回或已取消单据允许删除';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger hr_personnel_change_guard
before update or delete on public.hr_personnel_change
for each row execute function app_private.hr_guard_approval_record();

create trigger hr_lifecycle_case_guard
before update or delete on public.hr_lifecycle_case
for each row execute function app_private.hr_guard_approval_record();

create trigger hr_personnel_change_create_audit before insert on public.hr_personnel_change
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_personnel_change_update_audit before update on public.hr_personnel_change
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_lifecycle_case_create_audit before insert on public.hr_lifecycle_case
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_lifecycle_case_update_audit before update on public.hr_lifecycle_case
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_lifecycle_task_create_audit before insert on public.hr_lifecycle_task
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_lifecycle_task_update_audit before update on public.hr_lifecycle_task
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_employee_qualification_create_audit before insert on public.hr_employee_qualification
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_employee_qualification_update_audit before update on public.hr_employee_qualification
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_personnel_change enable row level security;
alter table public.hr_lifecycle_case enable row level security;
alter table public.hr_lifecycle_task enable row level security;
alter table public.hr_employee_qualification enable row level security;

grant select, insert, update, delete on public.hr_personnel_change to authenticated;
grant select, insert, update, delete on public.hr_lifecycle_case to authenticated;
grant select, insert, update, delete on public.hr_lifecycle_task to authenticated;
grant select, insert, update, delete on public.hr_employee_qualification to authenticated;

create policy hr_personnel_change_tenant_select on public.hr_personnel_change for select to authenticated
using ((select app_private.is_platform_super()) or (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:PersonnelChange:View'))
));
create policy hr_personnel_change_tenant_insert on public.hr_personnel_change for insert to authenticated
with check (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:PersonnelChange:Add')));
create policy hr_personnel_change_tenant_update on public.hr_personnel_change for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:PersonnelChange:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy hr_personnel_change_tenant_delete on public.hr_personnel_change for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:PersonnelChange:Delete'))));

create policy hr_lifecycle_case_tenant_select on public.hr_lifecycle_case for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:View'))));
create policy hr_lifecycle_case_tenant_insert on public.hr_lifecycle_case for insert to authenticated
with check (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:Add')));
create policy hr_lifecycle_case_tenant_update on public.hr_lifecycle_case for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy hr_lifecycle_case_tenant_delete on public.hr_lifecycle_case for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:Delete'))));

create policy hr_lifecycle_task_tenant_select on public.hr_lifecycle_task for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:View'))));
create policy hr_lifecycle_task_tenant_insert on public.hr_lifecycle_task for insert to authenticated
with check (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:Edit')));
create policy hr_lifecycle_task_tenant_update on public.hr_lifecycle_task for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:CompleteTask'))))
with check ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy hr_lifecycle_task_tenant_delete on public.hr_lifecycle_task for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Lifecycle:Edit'))));

create policy hr_employee_qualification_tenant_select on public.hr_employee_qualification for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:View'))));
create policy hr_employee_qualification_tenant_insert on public.hr_employee_qualification for insert to authenticated
with check (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:Add')));
create policy hr_employee_qualification_tenant_update on public.hr_employee_qualification for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy hr_employee_qualification_tenant_delete on public.hr_employee_qualification for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:Delete'))));

-- Contract history remains part of the employee profile, but the compliance workbench has its
-- own exact permissions. These additive policies avoid coupling compliance users to roster edits.
create policy hr_employee_contract_compliance_select on public.hr_employee_contract for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:View'))));
create policy hr_employee_contract_compliance_insert on public.hr_employee_contract for insert to authenticated
with check ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:Add'))));
create policy hr_employee_contract_compliance_update on public.hr_employee_contract for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy hr_employee_contract_compliance_delete on public.hr_employee_contract for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Compliance:Delete'))));

create or replace function app_private.execute_hr_workflow_business_callback(
  p_business_type text, p_business_id uuid, p_status text, p_actor text, p_comment text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.hr_lifecycle_case;
begin
  perform pg_catalog.set_config('app.workflow_engine', 'on', true);
  if p_business_type = 'hr_personnel_change' then
    update public.hr_personnel_change
    set status = case p_status
          when 'running' then 'pending' when 'approved' then 'approved'
          when 'rejected' then 'rejected' when 'withdrawn' then 'draft'
          when 'cancelled' then 'cancelled' else status end,
        workflow_instance_id = coalesce(workflow_instance_id, (
          select i.id from public.wf_instance i
          where i.tenant_id = hr_personnel_change.tenant_id
            and i.business_type = p_business_type and i.business_id = p_business_id
          order by i.started_at desc limit 1
        )),
        approved_at = case when p_status = 'approved' then now() else approved_at end,
        approved_by = case when p_status = 'approved' then p_actor else approved_by end,
        remark = case when p_status in ('rejected','cancelled')
          then concat_ws(E'\n', remark, nullif(btrim(coalesce(p_comment,'')),'')) else remark end
    where id = p_business_id;
    if not found then raise exception '人事异动单不存在或已被删除'; end if;
  elsif p_business_type = 'hr_lifecycle_case' then
    update public.hr_lifecycle_case
    set status = case p_status
          when 'running' then 'pending' when 'approved' then 'approved'
          when 'rejected' then 'rejected' when 'withdrawn' then 'draft'
          when 'cancelled' then 'cancelled' else status end,
        workflow_instance_id = coalesce(workflow_instance_id, (
          select i.id from public.wf_instance i
          where i.tenant_id = hr_lifecycle_case.tenant_id
            and i.business_type = p_business_type and i.business_id = p_business_id
          order by i.started_at desc limit 1
        )),
        approved_at = case when p_status = 'approved' then now() else approved_at end,
        approved_by = case when p_status = 'approved' then p_actor else approved_by end,
        remark = case when p_status in ('rejected','cancelled')
          then concat_ws(E'\n', remark, nullif(btrim(coalesce(p_comment,'')),'')) else remark end
    where id = p_business_id
    returning * into v_case;
    if not found then raise exception '入转调离事项不存在或已被删除'; end if;

    -- Approval materializes a reusable checklist. Existing manually-created tasks are preserved,
    -- and only missing defaults are inserted so workflow retries remain idempotent.
    if p_status = 'approved' then
      insert into public.hr_lifecycle_task(
        tenant_id,lifecycle_case_id,task_type,task_name,responsible_user_id,due_date,status,sort,
        create_by,update_by
      )
      select v_case.tenant_id,v_case.id,task.task_type,task.task_name,v_case.owner_user_id,
        v_case.planned_effective_date,'pending',task.sort,p_actor,p_actor
      from (values
        ('onboarding','organization','确认组织与岗位',10),
        ('onboarding','account','开通系统账号与权限',20),
        ('onboarding','document','归档入职资料',30),
        ('regularization','document','归档转正审批资料',10),
        ('transfer','organization','更新组织与岗位关系',10),
        ('transfer','account','调整系统角色与数据权限',20),
        ('offboarding','asset','完成资产与工作交接',10),
        ('offboarding','account','回收系统账号与权限',20),
        ('offboarding','document','归档离职资料',30)
      ) as task(case_type,task_type,task_name,sort)
      where task.case_type=v_case.case_type
        and not exists (
          select 1 from public.hr_lifecycle_task existing
          where existing.lifecycle_case_id=v_case.id
            and existing.task_type=task.task_type and existing.task_name=task.task_name
        );
    end if;
  end if;
end;
$$;

alter function app_private.execute_workflow_business_callback(text,uuid,text,text,text)
  rename to execute_workflow_business_callback_before_hr;

create or replace function app_private.execute_workflow_business_callback(
  p_business_type text, p_business_id uuid, p_status text, p_actor text, p_comment text
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_business_type in ('hr_personnel_change', 'hr_lifecycle_case') then
    perform app_private.execute_hr_workflow_business_callback(
      p_business_type, p_business_id, p_status, p_actor, p_comment
    );
  else
    perform app_private.execute_workflow_business_callback_before_hr(
      p_business_type, p_business_id, p_status, p_actor, p_comment
    );
  end if;
end;
$$;

create or replace function public.hr_submit_approval(p_business_type text, p_business_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_permission text;
  v_title text;
  v_context jsonb := '{}'::jsonb;
begin
  if p_business_type = 'hr_personnel_change' then
    v_permission := 'Hr:PersonnelChange:Submit';
    select '人事异动 ' || c.change_no,
           jsonb_build_object('changeNo',c.change_no,'changeType',c.change_type,
             'employeeId',c.employee_id,'effectiveDate',c.effective_date)
      into v_title,v_context
    from public.hr_personnel_change c
    where c.id=p_business_id
      and ((select app_private.is_platform_super()) or c.tenant_id=(select app_private.current_user_tenant_id()))
      and c.status in ('draft','rejected');
  elsif p_business_type = 'hr_lifecycle_case' then
    v_permission := 'Hr:Lifecycle:Submit';
    select '员工生命周期 ' || c.case_no,
           jsonb_build_object('caseNo',c.case_no,'caseType',c.case_type,
             'employeeId',c.employee_id,'plannedEffectiveDate',c.planned_effective_date)
      into v_title,v_context
    from public.hr_lifecycle_case c
    where c.id=p_business_id
      and ((select app_private.is_platform_super()) or c.tenant_id=(select app_private.current_user_tenant_id()))
      and c.status in ('draft','rejected');
  else
    raise exception '不支持的人事审批业务类型';
  end if;
  if v_title is null then raise exception '单据不存在或当前状态不可提交'; end if;
  if not (select app_private.is_platform_super())
     and not (select app_private.has_permission(v_permission)) then
    raise exception '当前账号没有提交该人事单据的权限' using errcode='42501';
  end if;
  return app_private.start_workflow(
    p_business_type,p_business_id,v_title,v_context,gen_random_uuid()::text
  );
end;
$$;

create or replace function public.hr_effect_personnel_change(p_change_id uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_change public.hr_personnel_change;
begin
  if not (select app_private.is_platform_super())
     and not (select app_private.has_permission('Hr:PersonnelChange:Effect')) then
    raise exception '当前账号没有生效人事异动的权限' using errcode='42501';
  end if;
  select * into v_change from public.hr_personnel_change
  where id=p_change_id
    and ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()))
  for update;
  if not found then raise exception '人事异动单不存在'; end if;
  if v_change.status <> 'approved' then raise exception '只有已批准异动单可以生效'; end if;
  if v_change.effective_date > current_date then raise exception '尚未到异动生效日期'; end if;

  update public.hr_employee
  set organization_id=coalesce(v_change.to_organization_id,organization_id),
      position_id=coalesce(v_change.to_position_id,position_id),
      employment_status=coalesce(v_change.to_employment_status,employment_status),
      job_title=coalesce(v_change.to_job_title,job_title),
      leave_date=case when v_change.to_employment_status='terminated'
        then v_change.effective_date else leave_date end
  where id=v_change.employee_id and tenant_id=v_change.tenant_id;

  perform pg_catalog.set_config('app.workflow_engine','on',true);
  update public.hr_personnel_change set status='effective',effected_at=now(),
    effected_by=coalesce((select u.user_email from public.sys_user u
      where u.id=(select app_private.current_app_user_id())),auth.uid()::text,'system')
  where id=v_change.id;
  return true;
end;
$$;

create or replace function public.hr_complete_lifecycle_task(
  p_task_id uuid, p_completion_note text default null, p_skip boolean default false
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_task public.hr_lifecycle_task; v_case public.hr_lifecycle_case;
begin
  if not (select app_private.is_platform_super())
     and not (select app_private.has_permission('Hr:Lifecycle:CompleteTask')) then
    raise exception '当前账号没有完成人事任务的权限' using errcode='42501';
  end if;
  select * into v_task from public.hr_lifecycle_task
  where id=p_task_id
    and ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()))
  for update;
  if not found then raise exception '人事任务不存在'; end if;
  select * into v_case from public.hr_lifecycle_case where id=v_task.lifecycle_case_id for update;
  if v_case.status <> 'approved' then raise exception '只有审批通过的事项可以执行任务'; end if;
  if v_task.status in ('completed','skipped','cancelled') then return true; end if;

  update public.hr_lifecycle_task set status=case when p_skip then 'skipped' else 'completed' end,
    completed_at=now(),completion_note=nullif(btrim(coalesce(p_completion_note,'')),'')
  where id=p_task_id;

  if not exists (select 1 from public.hr_lifecycle_task
    where lifecycle_case_id=v_case.id and status not in ('completed','skipped','cancelled')) then
    perform pg_catalog.set_config('app.workflow_engine','on',true);
    update public.hr_lifecycle_case set status='effective',completed_at=now(),
      completed_by=coalesce((select u.user_email from public.sys_user u
        where u.id=(select app_private.current_app_user_id())),auth.uid()::text,'system')
    where id=v_case.id;
  end if;
  return true;
end;
$$;

revoke all on function public.hr_submit_approval(text,uuid) from public, anon;
revoke all on function public.hr_effect_personnel_change(uuid) from public, anon;
revoke all on function public.hr_complete_lifecycle_task(uuid,text,boolean) from public, anon;
grant execute on function public.hr_submit_approval(text,uuid) to authenticated;
grant execute on function public.hr_effect_personnel_change(uuid) to authenticated;
grant execute on function public.hr_complete_lifecycle_task(uuid,text,boolean) to authenticated;

do $$
declare
  v_platform_tenant uuid := app_private.platform_tenant_id();
  v_hr_directory uuid;
  v_group record;
  v_type_id uuid;
  v_item record;
begin
  select id into v_hr_directory from public.sys_dict_type where code='hrManage';
  for v_group in select * from (values
    ('hrApprovalStatus','人事审批状态',101),
    ('hrPersonnelChangeType','人事异动类型',102),
    ('hrLifecycleCaseType','员工生命周期事项类型',103),
    ('hrLifecycleTaskType','员工生命周期任务类型',104),
    ('hrLifecycleTaskStatus','员工生命周期任务状态',105),
    ('hrQualificationType','员工资质类型',106),
    ('hrQualificationStatus','员工资质状态',107),
    ('hrExpiryRisk','到期风险',108)
  ) as x(code,name,sort) loop
    insert into public.sys_dict_type(name,code,status,create_by,update_by,tenant_id,parent_id,node_type,sort)
    values(v_group.name,v_group.code,'1','624944977@qq.com','624944977@qq.com',v_platform_tenant,v_hr_directory,'dictionary',v_group.sort)
    on conflict(code) do update set name=excluded.name,status='1',parent_id=excluded.parent_id,
      sort=excluded.sort,update_by='624944977@qq.com',update_time=now();
  end loop;

  for v_item in select * from (values
    ('hrApprovalStatus','draft','草稿',1,'info'),('hrApprovalStatus','pending','审批中',2,'warning'),
    ('hrApprovalStatus','approved','已批准',3,'success'),('hrApprovalStatus','effective','已生效',4,'primary'),
    ('hrApprovalStatus','rejected','已驳回',5,'danger'),('hrApprovalStatus','cancelled','已取消',6,'info'),
    ('hrPersonnelChangeType','regularization','转正',1,'success'),('hrPersonnelChangeType','transfer','调动',2,'primary'),
    ('hrPersonnelChangeType','position_change','调岗',3,'primary'),('hrPersonnelChangeType','promotion','晋升',4,'success'),
    ('hrPersonnelChangeType','demotion','降职',5,'warning'),('hrPersonnelChangeType','suspension','停职',6,'warning'),
    ('hrPersonnelChangeType','reinstatement','复职',7,'success'),('hrPersonnelChangeType','termination','离职',8,'danger'),
    ('hrLifecycleCaseType','onboarding','入职',1,'success'),('hrLifecycleCaseType','regularization','转正',2,'primary'),
    ('hrLifecycleCaseType','transfer','调动',3,'primary'),('hrLifecycleCaseType','offboarding','离职',4,'danger'),
    ('hrLifecycleTaskType','account','账号与权限',1,'primary'),('hrLifecycleTaskType','organization','组织岗位',2,'info'),
    ('hrLifecycleTaskType','driver_profile','司机档案',3,'warning'),('hrLifecycleTaskType','asset','资产交接',4,'info'),
    ('hrLifecycleTaskType','document','资料归档',5,'success'),('hrLifecycleTaskType','other','其他',6,'info'),
    ('hrLifecycleTaskStatus','pending','待处理',1,'warning'),('hrLifecycleTaskStatus','processing','处理中',2,'primary'),
    ('hrLifecycleTaskStatus','completed','已完成',3,'success'),('hrLifecycleTaskStatus','skipped','已跳过',4,'info'),
    ('hrLifecycleTaskStatus','cancelled','已取消',5,'info'),
    ('hrQualificationType','professional','职业资格',1,'primary'),('hrQualificationType','safety','安全资质',2,'warning'),
    ('hrQualificationType','training','培训证书',3,'success'),('hrQualificationType','health','健康证明',4,'info'),
    ('hrQualificationType','other','其他',5,'info'),
    ('hrQualificationStatus','valid','有效',1,'success'),('hrQualificationStatus','expiring','即将到期',2,'warning'),
    ('hrQualificationStatus','expired','已过期',3,'danger'),('hrQualificationStatus','revoked','已撤销',4,'info'),
    ('hrExpiryRisk','normal','正常',1,'success'),('hrExpiryRisk','expiring','即将到期',2,'warning'),
    ('hrExpiryRisk','expired','已过期',3,'danger')
  ) as x(type_code,value,label,sort,tag_type) loop
    select id into v_type_id from public.sys_dict_type where code=v_item.type_code;
    update public.sys_dictionary set label=v_item.label,sort=v_item.sort,tag_type=v_item.tag_type,
      status='1',update_by='624944977@qq.com',update_time=now()
    where type_id=v_type_id and value=v_item.value;
    if not found then
      insert into public.sys_dictionary(type_id,code,status,create_by,update_by,value,label,sort,tenant_id,tag_type)
      values(v_type_id,v_item.type_code || '_' || v_item.value,'1','624944977@qq.com','624944977@qq.com',
        v_item.value,v_item.label,v_item.sort,v_platform_tenant,v_item.tag_type);
    end if;
  end loop;
end $$;

-- Feed contract and qualification expiry dates into the existing unified reminder engine.
insert into public.sys_notification_scenario(
  scenario_code,scenario_name,module_code,description,route_path,sort,enabled,builtin,
  create_by,update_by
)
values
  ('hr_contract_expiry','员工合同到期','hr','劳动合同到期及续签提醒',
    '/hr/personnel/compliance',80,true,true,'624944977@qq.com','624944977@qq.com'),
  ('hr_qualification_expiry','员工资质到期','hr','职业资格、证书与健康证明到期提醒',
    '/hr/personnel/compliance',81,true,true,'624944977@qq.com','624944977@qq.com')
on conflict(scenario_code) do update set
  scenario_name=excluded.scenario_name,module_code=excluded.module_code,
  description=excluded.description,route_path=excluded.route_path,sort=excluded.sort,
  enabled=true,builtin=true,update_by=excluded.update_by,update_time=now();

create or replace function app_private.sync_hr_expiry_notification_subject()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row jsonb := case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_employee_name text;
  v_status text := case when tg_op='DELETE' then 'cancelled' else 'active' end;
  v_due_date date;
begin
  select e.employee_name into v_employee_name
  from public.hr_employee e
  where e.id=(v_row->>'employee_id')::uuid and e.tenant_id=(v_row->>'tenant_id')::uuid;

  if tg_table_name='hr_employee_contract' then
    v_due_date:=nullif(v_row->>'end_date','')::date;
    if coalesce(v_row->>'contract_status','') in ('expired','terminated') then
      v_status:='resolved';
    elsif coalesce(v_row->>'contract_status','') not in ('active','renewing') then
      v_status:='cancelled';
    end if;
    perform app_private.upsert_notification_subject(
      (v_row->>'tenant_id')::uuid,'hr_contract_expiry','hr_employee_contract',
      (v_row->>'id')::uuid,'end_date',coalesce(v_employee_name,'员工')||' 劳动合同到期',
      case when v_due_date is null then null else (v_due_date+time '09:00') at time zone 'Asia/Shanghai' end,
      null,'/hr/personnel/compliance',jsonb_build_object('contractId',v_row->>'id'),
      jsonb_build_object('employeeId',v_row->>'employee_id','contractNo',v_row->>'contract_no'),v_status
    );
  elsif tg_table_name='hr_employee_qualification' then
    v_due_date:=nullif(v_row->>'expiry_date','')::date;
    if coalesce(v_row->>'status','')='revoked' then v_status:='resolved'; end if;
    perform app_private.upsert_notification_subject(
      (v_row->>'tenant_id')::uuid,'hr_qualification_expiry','hr_employee_qualification',
      (v_row->>'id')::uuid,'expiry_date',coalesce(v_employee_name,'员工')||'「'||
        coalesce(v_row->>'qualification_name','资质')||'」到期',
      case when v_due_date is null then null else (v_due_date+time '09:00') at time zone 'Asia/Shanghai' end,
      null,'/hr/personnel/compliance',jsonb_build_object('qualificationId',v_row->>'id'),
      jsonb_build_object('employeeId',v_row->>'employee_id','certificateNo',v_row->>'certificate_no'),v_status
    );
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create trigger hr_employee_contract_expiry_subject
after insert or update of end_date,contract_status or delete on public.hr_employee_contract
for each row execute function app_private.sync_hr_expiry_notification_subject();
create trigger hr_employee_qualification_expiry_subject
after insert or update of expiry_date,status or delete on public.hr_employee_qualification
for each row execute function app_private.sync_hr_expiry_notification_subject();

do $$
declare v_row record;
begin
  for v_row in select c.*,e.employee_name from public.hr_employee_contract c
    join public.hr_employee e on e.id=c.employee_id and e.tenant_id=c.tenant_id
  loop
    perform app_private.upsert_notification_subject(
      v_row.tenant_id,'hr_contract_expiry','hr_employee_contract',v_row.id,'end_date',
      v_row.employee_name||' 劳动合同到期',
      case when v_row.end_date is null then null else (v_row.end_date+time '09:00') at time zone 'Asia/Shanghai' end,
      null,'/hr/personnel/compliance',jsonb_build_object('contractId',v_row.id),
      jsonb_build_object('employeeId',v_row.employee_id,'contractNo',v_row.contract_no),
      case when v_row.contract_status in ('expired','terminated') then 'resolved'
        when v_row.contract_status in ('active','renewing') then 'active' else 'cancelled' end
    );
  end loop;
  for v_row in select q.*,e.employee_name from public.hr_employee_qualification q
    join public.hr_employee e on e.id=q.employee_id and e.tenant_id=q.tenant_id
  loop
    perform app_private.upsert_notification_subject(
      v_row.tenant_id,'hr_qualification_expiry','hr_employee_qualification',v_row.id,'expiry_date',
      v_row.employee_name||'「'||v_row.qualification_name||'」到期',
      case when v_row.expiry_date is null then null else (v_row.expiry_date+time '09:00') at time zone 'Asia/Shanghai' end,
      null,'/hr/personnel/compliance',jsonb_build_object('qualificationId',v_row.id),
      jsonb_build_object('employeeId',v_row.employee_id,'certificateNo',v_row.certificate_no),
      case when v_row.status='revoked' then 'resolved' else 'active' end
    );
  end loop;
end $$;

do $$
declare
  v_type_id uuid;
  v_platform_tenant uuid := app_private.platform_tenant_id();
  v_item record;
begin
  select id into v_type_id from public.sys_dict_type where code='workflowBusinessType';
  if v_type_id is not null then
    for v_item in select * from (values
      ('hr_personnel_change','人事异动',80,'primary'),
      ('hr_lifecycle_case','员工生命周期',81,'success')
    ) as x(value,label,sort,tag_type) loop
      update public.sys_dictionary set label=v_item.label,sort=v_item.sort,tag_type=v_item.tag_type,
        status='1',update_by='624944977@qq.com',update_time=now()
      where type_id=v_type_id and value=v_item.value;
      if not found then
        insert into public.sys_dictionary(type_id,code,status,create_by,update_by,value,label,sort,tenant_id,tag_type)
        values(v_type_id,'workflowBusinessType_' || v_item.value,'1','624944977@qq.com','624944977@qq.com',
          v_item.value,v_item.label,v_item.sort,v_platform_tenant,v_item.tag_type);
      end if;
    end loop;
  end if;
end $$;

do $$
declare
  v_tenant record;
  v_flow record;
  v_definition_id uuid;
  v_version_id uuid;
  v_config jsonb;
begin
  for v_tenant in
    select distinct r.tenant_id, r.role_code
    from public.sys_role r
    join public.sys_role_menu rm on rm.role_id=r.id
    where r.enabled and rm.menu_id='aa71d8bd-c141-4aef-9697-8e75433de2c2'::uuid
      and r.tenant_id <> app_private.platform_tenant_id()
      and not exists (
        select 1 from public.sys_role preferred
        join public.sys_role_menu preferred_rm on preferred_rm.role_id=preferred.id
        where preferred.tenant_id=r.tenant_id and preferred.enabled
          and preferred_rm.menu_id='aa71d8bd-c141-4aef-9697-8e75433de2c2'::uuid
          and preferred.role_code < r.role_code
      )
  loop
    for v_flow in select * from (values
      ('HRPersonnelChangeDefault','人事异动默认审批','hr_personnel_change','人事负责人审批'),
      ('HRLifecycleDefault','员工生命周期默认审批','hr_lifecycle_case','人事负责人审批')
    ) as x(code,name,business_type,node_name) loop
      select id into v_definition_id from public.wf_definition
      where tenant_id=v_tenant.tenant_id and code=v_flow.code;
      if v_definition_id is null then
        v_definition_id := gen_random_uuid();
        v_version_id := gen_random_uuid();
        v_config := jsonb_build_object(
          'allowAutoApprove',false,
          'nodes',jsonb_build_array(jsonb_build_object(
            'key','node_hr_default','name',v_flow.node_name,'order',1,
            'approvalMode','any','approvalThresholdPercent',100,
            'rejectVetoEnabled',true,'allowSelfApproval',true,
            'dueHours',24,'reminderBeforeMinutes',60,
            'escalationEnabled',true,'escalateAfterHours',4,
            'assignee',jsonb_build_object('type','roles','userIds','[]'::jsonb,
              'roleCodes',jsonb_build_array(v_tenant.role_code)),
            'condition',jsonb_build_object('operator','always')
          ))
        );
        insert into public.wf_definition(id,code,name,business_type,description,status,current_version_id,
          published_at,published_by,create_by,update_by,tenant_id)
        values(v_definition_id,v_flow.code,v_flow.name,v_flow.business_type,
          '系统初始化的人力资源审批流程，可在流程设计中调整。','published',null,
          now(),'624944977@qq.com','624944977@qq.com','624944977@qq.com',v_tenant.tenant_id);
        insert into public.wf_version(id,definition_id,version_no,status,config,change_note,
          published_at,published_by,create_by,update_by,tenant_id)
        values(v_version_id,v_definition_id,1,'published',v_config,'初始化 HR 默认流程',now(),
          '624944977@qq.com','624944977@qq.com','624944977@qq.com',v_tenant.tenant_id);
        update public.wf_definition set current_version_id=v_version_id where id=v_definition_id;
      end if;
    end loop;
  end loop;
end $$;

do $$
declare
  v_personnel_parent uuid := 'aa71d8bd-c141-4aef-9697-8e75433de2c2';
  v_page record;
  v_button record;
begin
  for v_page in select * from (values
    ('c0de0000-0000-4000-8000-000000000101'::uuid,'HrPersonnelChange','personnel-change','/hr/personnel/personnel-change','人事异动','ri:swap-box-line',3),
    ('c0de0000-0000-4000-8000-000000000102'::uuid,'HrLifecycle','lifecycle','/hr/personnel/lifecycle','入转调离','ri:user-settings-line',4),
    ('c0de0000-0000-4000-8000-000000000103'::uuid,'HrCompliance','compliance','/hr/personnel/compliance','合同与资质','ri:verified-badge-line',5)
  ) as x(id,name,path,component,title,icon,sort) loop
    insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
    values(v_page.id,v_personnel_parent,v_page.name,v_page.path,v_page.component,'menu',v_page.sort,
      jsonb_build_object('title',v_page.title,'icon',v_page.icon,'roles',jsonb_build_array('R_SUPER','R_ADMIN'),
        'is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,
        'show_badge',false,'active_path','','is_hide_tab',false,'is_full_page',false,'show_text_badge',''),
      '624944977@qq.com','624944977@qq.com')
    on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,
      component=excluded.component,type=excluded.type,sort=excluded.sort,meta=excluded.meta,
      update_by='624944977@qq.com',update_time=now();
  end loop;

  for v_button in select * from (values
    ('c0de0000-0000-4000-8101-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000101'::uuid,'Hr:PersonnelChange:View','查看异动',1),
    ('c0de0000-0000-4000-8101-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000101'::uuid,'Hr:PersonnelChange:Add','新增异动',2),
    ('c0de0000-0000-4000-8101-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000101'::uuid,'Hr:PersonnelChange:Edit','编辑异动',3),
    ('c0de0000-0000-4000-8101-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000101'::uuid,'Hr:PersonnelChange:Delete','删除异动',4),
    ('c0de0000-0000-4000-8101-000000000005'::uuid,'c0de0000-0000-4000-8000-000000000101'::uuid,'Hr:PersonnelChange:Submit','提交审批',5),
    ('c0de0000-0000-4000-8101-000000000006'::uuid,'c0de0000-0000-4000-8000-000000000101'::uuid,'Hr:PersonnelChange:Effect','生效异动',6),
    ('c0de0000-0000-4000-8102-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000102'::uuid,'Hr:Lifecycle:View','查看事项',1),
    ('c0de0000-0000-4000-8102-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000102'::uuid,'Hr:Lifecycle:Add','新增事项',2),
    ('c0de0000-0000-4000-8102-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000102'::uuid,'Hr:Lifecycle:Edit','编辑事项',3),
    ('c0de0000-0000-4000-8102-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000102'::uuid,'Hr:Lifecycle:Delete','删除事项',4),
    ('c0de0000-0000-4000-8102-000000000005'::uuid,'c0de0000-0000-4000-8000-000000000102'::uuid,'Hr:Lifecycle:Submit','提交审批',5),
    ('c0de0000-0000-4000-8102-000000000006'::uuid,'c0de0000-0000-4000-8000-000000000102'::uuid,'Hr:Lifecycle:CompleteTask','完成任务',6),
    ('c0de0000-0000-4000-8103-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000103'::uuid,'Hr:Compliance:View','查看合同资质',1),
    ('c0de0000-0000-4000-8103-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000103'::uuid,'Hr:Compliance:Add','新增合同资质',2),
    ('c0de0000-0000-4000-8103-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000103'::uuid,'Hr:Compliance:Edit','编辑合同资质',3),
    ('c0de0000-0000-4000-8103-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000103'::uuid,'Hr:Compliance:Delete','删除资质',4)
  ) as x(id,parent_id,name,title,sort) loop
    insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
    values(v_button.id,v_button.parent_id,v_button.name,'','','button',v_button.sort,
      jsonb_build_object('title',v_button.title,'icon','','roles',jsonb_build_array('R_SUPER','R_ADMIN'),'is_enable',true),
      '624944977@qq.com','624944977@qq.com')
    on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,type='button',sort=excluded.sort,
      meta=excluded.meta,update_by='624944977@qq.com',update_time=now();
  end loop;

  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select distinct rm.role_id,m.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
  from public.sys_role_menu rm
  join public.sys_role r on r.id=rm.role_id
  join public.sys_menu m on m.id in (
    'c0de0000-0000-4000-8000-000000000101'::uuid,
    'c0de0000-0000-4000-8000-000000000102'::uuid,
    'c0de0000-0000-4000-8000-000000000103'::uuid)
  where rm.menu_id=v_personnel_parent
  on conflict(role_id,menu_id) do nothing;

  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select distinct rm.role_id,b.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
  from public.sys_role_menu rm
  join public.sys_role r on r.id=rm.role_id
  join public.sys_menu b on b.parent_id=rm.menu_id and b.type='button'
  where rm.menu_id in (
    'c0de0000-0000-4000-8000-000000000101'::uuid,
    'c0de0000-0000-4000-8000-000000000102'::uuid,
    'c0de0000-0000-4000-8000-000000000103'::uuid)
  on conflict(role_id,menu_id) do nothing;
end $$;

insert into public.sys_notification_rule(
  tenant_id,scenario_id,rule_name,lead_days,repeat_every_days,send_hour,
  recipient_strategy,recipient_role_codes,channels,enabled,create_by,update_by
)
select tenant.tenant_id,scenario.id,scenario.scenario_name||'（提前30天）',30,7,9,
  'owner_then_roles',tenant.role_codes,array['in_app']::text[],true,
  '624944977@qq.com','624944977@qq.com'
from (
  select r.tenant_id,array_agg(distinct r.role_code order by r.role_code) role_codes
  from public.sys_role r
  join public.sys_role_menu rm on rm.role_id=r.id
  where r.enabled and rm.menu_id='c0de0000-0000-4000-8000-000000000103'::uuid
  group by r.tenant_id
) tenant
cross join public.sys_notification_scenario scenario
where scenario.scenario_code in ('hr_contract_expiry','hr_qualification_expiry')
  and not exists (
    select 1 from public.sys_notification_rule existing
    where existing.tenant_id=tenant.tenant_id and existing.scenario_id=scenario.id
  );
;
