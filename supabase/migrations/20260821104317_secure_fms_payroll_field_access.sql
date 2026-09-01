-- Secure payroll reads and writes with tenant field permissions.
-- Button permission definitions remain unchanged.

alter table public.fms_payroll_run
  add column if not exists created_by_user_id uuid;

update public.fms_payroll_run run_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = run_row.tenant_id
    and lower(user_row.user_email) = lower(run_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where run_row.created_by_user_id is null
  and nullif(btrim(coalesce(run_row.create_by, '')), '') is not null;

do $$
begin
  if exists (select 1 from public.fms_payroll_run where created_by_user_id is null) then
    raise exception 'Unable to backfill fms_payroll_run.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_payroll_run
  alter column created_by_user_id set not null;

create index if not exists fms_payroll_run_tenant_creator_idx
  on public.fms_payroll_run(tenant_id, created_by_user_id);
create index if not exists fms_payroll_run_creator_tenant_idx
  on public.fms_payroll_run(created_by_user_id, tenant_id);

alter table public.fms_payroll_run
  drop constraint if exists fms_payroll_run_creator_tenant_fkey;
alter table public.fms_payroll_run
  add constraint fms_payroll_run_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_payroll_run_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by_user_id is null then
      new.created_by_user_id := app_private.current_app_user_id();
    end if;
    if new.created_by_user_id is null
       and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve payroll run creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Payroll run creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_payroll_run_creator_identity on public.fms_payroll_run;
create trigger fms_payroll_run_creator_identity
before insert or update of created_by_user_id on public.fms_payroll_run
for each row execute function app_private.set_fms_payroll_run_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_payroll;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_payroll(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id,resource_key,resource_label,menu_name,owner_column,create_by,update_by
  ) values (
    p_tenant_id,'fms.payroll','薪资核算','FinancePayroll','created_by_user_id',
    '624944977@qq.com','624944977@qq.com'
  )
  on conflict (tenant_id,resource_key) do update
    set resource_label=excluded.resource_label,
        menu_name=excluded.menu_name,
        owner_column=excluded.owner_column,
        enabled=true,
        update_by=excluded.update_by,
        update_time=now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id,resource_id,field_key,field_label,default_access,mask_strategy,
    owner_override_enabled,sort,create_by,update_by
  ) values
    (p_tenant_id,v_resource_id,'employeeIdentity','员工姓名、工号与部门快照',
      'hidden','none',true,10,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'salaryAmounts','工资构成、应发、扣款、企业成本与实发金额',
      'hidden','amount',true,20,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'payrollReferences','薪资科目、审批人与会计付款凭证',
      'hidden','bank_account',true,30,'624944977@qq.com','624944977@qq.com')
  on conflict (tenant_id,resource_id,field_key) do update
    set field_label=excluded.field_label,
        mask_strategy=excluded.mask_strategy,
        owner_override_enabled=excluded.owner_override_enabled,
        sort=excluded.sort,
        sensitive=true,
        enabled=true,
        update_by=excluded.update_by,
        update_time=now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

insert into public.sys_role_field_permission (
  tenant_id,role_id,resource_id,field_id,access_level,create_by,update_by
)
select distinct resource_row.tenant_id,role_menu.role_id,resource_row.id,field_row.id,
       'edit','624944977@qq.com','624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id=resource_row.tenant_id and field_row.resource_id=resource_row.id
join public.sys_menu menu_row
  on menu_row.type='menu' and menu_row.name='FinancePayroll'
join public.sys_role_menu role_menu
  on role_menu.tenant_id=resource_row.tenant_id and role_menu.menu_id=menu_row.id
where resource_row.resource_key='fms.payroll'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id,role_id,resource_id,field_id) do nothing;

create or replace function app_private.fms_payroll_run_raw_json(p_run_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (to_jsonb(run_row)-'tenant_id'-'created_by_user_id') ||
         jsonb_build_object('period',to_jsonb(period_row)-'tenant_id')
  from public.fms_payroll_run run_row
  join public.fms_accounting_period period_row
    on period_row.id=run_row.accounting_period_id and period_row.tenant_id=run_row.tenant_id
  where run_row.id=p_run_id
    and run_row.tenant_id=app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_payroll_run_to_secure_json(
  p_run jsonb,p_owner_id uuid,p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(p_access,app_private.field_access_map('fms.payroll',p_owner_id));
  v_data jsonb := coalesce(p_run,'{}'::jsonb)-'tenant_id'-'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,array['employee_count']::text[],coalesce(v_access->>'employeeIdentity','hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,array['gross_amount','deduction_amount','employer_cost_amount','net_amount']::text[],
    coalesce(v_access->>'salaryAmounts','hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['salary_expense_subject_id','salary_payable_subject_id','tax_payable_subject_id',
      'social_security_payable_subject_id','voucher_id','approved_by']::text[],
    coalesce(v_access->>'payrollReferences','hidden')
  );
  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_payroll_line_to_secure_json(
  p_line jsonb,p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.payroll',p_owner_id);
  v_data jsonb := coalesce(p_line,'{}'::jsonb)-'tenant_id';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['employee_id','employee_no_snapshot','employee_name_snapshot','department_name_snapshot']::text[],
    coalesce(v_access->>'employeeIdentity','hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,array['earning_items','deduction_items','employer_cost_items']::text[],
    coalesce(v_access->>'salaryAmounts','hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,array['gross_amount','deduction_amount','employer_cost_amount','net_amount']::text[],
    coalesce(v_access->>'salaryAmounts','hidden')
  );
  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_payroll_runs_secure(
  p_from integer default 0,p_to integer default 19,p_account_set_id uuid default null,
  p_status text default null,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from,0),0);
  v_limit integer := least(greatest(coalesce(p_to,19)-v_from+1,1),1000);
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant payroll access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinancePayroll',null,null,false) then
    raise exception 'Missing payroll menu permission' using errcode='42501';
  end if;
  if p_account_set_id is not null and not exists(
    select 1 from public.fms_account_set s where s.id=p_account_set_id and s.tenant_id=v_tenant_id
  ) then
    raise exception 'Payroll account set is outside the current tenant' using errcode='42501';
  end if;
  select count(*)::integer into v_total
  from public.fms_payroll_run run_row
  where run_row.tenant_id=v_tenant_id
    and (p_account_set_id is null or run_row.account_set_id=p_account_set_id)
    and (p_status is null or run_row.status=p_status);

  for v_row in
    select run_row.id,run_row.created_by_user_id
    from public.fms_payroll_run run_row
    where run_row.tenant_id=v_tenant_id
      and (p_account_set_id is null or run_row.account_set_id=p_account_set_id)
      and (p_status is null or run_row.status=p_status)
    order by run_row.payroll_month desc,run_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_payroll_run_to_secure_json(
        app_private.fms_payroll_run_raw_json(v_row.id),v_row.created_by_user_id
      )
    );
  end loop;
  return jsonb_build_object(
    'records',v_records,'total',coalesce(v_total,0),
    'field_access',app_private.field_access_map('fms.payroll',null)
  );
end;
$$;

create or replace function public.fms_get_payroll_run_secure(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_owner_id uuid;
begin
  if not app_private.can_execute_business_action('FinancePayroll',null,null,false) then
    raise exception 'Missing payroll menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id
  from public.fms_payroll_run
  where id=p_run_id and tenant_id=app_private.current_user_tenant_id();
  if not found then raise exception 'Payroll run does not exist in the current tenant' using errcode='P0002'; end if;
  return app_private.fms_payroll_run_to_secure_json(
    app_private.fms_payroll_run_raw_json(p_run_id),v_owner_id
  );
end;
$$;

create or replace function public.fms_list_payroll_lines_secure(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_owner_id uuid;
  v_records jsonb;
begin
  if not app_private.can_execute_business_action('FinancePayroll',null,null,false) then
    raise exception 'Missing payroll menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id from public.fms_payroll_run
  where id=p_run_id and tenant_id=v_tenant_id;
  if not found then raise exception 'Payroll run does not exist in the current tenant' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(
    app_private.fms_payroll_line_to_secure_json(to_jsonb(line_row)-'tenant_id',v_owner_id)
    order by line_row.employee_no_snapshot,line_row.id
  ),'[]'::jsonb)
  into v_records
  from public.fms_payroll_line line_row
  where line_row.run_id=p_run_id and line_row.tenant_id=v_tenant_id;
  return jsonb_build_object(
    'records',v_records,
    'field_access',app_private.field_access_map('fms.payroll',v_owner_id),
    'is_record_owner',v_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_payroll_employee_options_secure(
  p_run_id uuid,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_owner_id uuid;
  v_access jsonb;
  v_result jsonb;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant payroll employee access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinancePayroll',null,null,false) then
    raise exception 'Missing payroll menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id from public.fms_payroll_run
  where id=p_run_id and tenant_id=v_tenant_id;
  if not found then raise exception 'Payroll run does not exist in the current tenant' using errcode='P0002'; end if;
  v_access := app_private.field_access_map('fms.payroll',v_owner_id);
  if coalesce(v_access->>'employeeIdentity','hidden')<>'edit' then
    raise exception 'Payroll employee identity fields are not editable' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',employee_row.id,
    'employee_no',employee_row.employee_no,
    'employee_name',employee_row.employee_name
  ) order by employee_row.employee_no,employee_row.id),'[]'::jsonb)
  into v_result
  from public.hr_employee employee_row
  where employee_row.tenant_id=v_tenant_id
    and employee_row.employment_status in ('probation','active');
  return v_result;
end;
$$;

create or replace function public.fms_payroll_summary_secure(
  p_account_set_id uuid,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb := app_private.field_access_map('fms.payroll',null);
  v_identity_access text := coalesce(v_access->>'employeeIdentity','hidden');
  v_amount_access text := coalesce(v_access->>'salaryAmounts','hidden');
  v_summary record;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant payroll summary access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinancePayroll',null,null,false) then
    raise exception 'Missing payroll menu permission' using errcode='42501';
  end if;
  if p_account_set_id is null or not exists(
    select 1 from public.fms_account_set s where s.id=p_account_set_id and s.tenant_id=v_tenant_id
  ) then raise exception 'Payroll account set is outside the current tenant' using errcode='42501'; end if;
  select count(*) run_count,coalesce(sum(employee_count),0) employee_count,
         coalesce(sum(gross_amount),0) gross_amount,coalesce(sum(net_amount),0) net_amount,
         count(*) filter(where status in ('draft','calculated','approved')) pending_count
  into v_summary
  from public.fms_payroll_run
  where tenant_id=v_tenant_id and account_set_id=p_account_set_id and status<>'cancelled';
  return jsonb_build_object(
    'run_count',v_summary.run_count,
    'employee_count',case when v_identity_access in ('read','edit') then to_jsonb(v_summary.employee_count)
      when v_identity_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'gross_amount',case when v_amount_access in ('read','edit') then to_jsonb(v_summary.gross_amount)
      when v_amount_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'net_amount',case when v_amount_access in ('read','edit') then to_jsonb(v_summary.net_amount)
      when v_amount_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'pending_count',v_summary.pending_count,
    'field_access',v_access
  );
end;
$$;

create or replace function public.save_fms_payroll_run_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := nullif(p_payload->>'id','')::uuid;
  v_period_id uuid := nullif(p_payload->>'accountingPeriodId','')::uuid;
  v_existing public.fms_payroll_run%rowtype;
  v_saved public.fms_payroll_run%rowtype;
  v_payload jsonb := coalesce(p_payload,'{}'::jsonb);
  v_access jsonb;
begin
  if v_period_id is null or not exists(
    select 1 from public.fms_accounting_period p
    where p.id=v_period_id and p.tenant_id=v_tenant_id
  ) then raise exception 'Payroll accounting period is outside the current tenant' using errcode='42501'; end if;
  if v_id is not null then
    select * into v_existing from public.fms_payroll_run r
    where r.id=v_id and r.tenant_id=v_tenant_id for update;
    if not found then raise exception 'Payroll run does not exist in the current tenant' using errcode='P0002'; end if;
    v_access := app_private.field_access_map('fms.payroll',v_existing.created_by_user_id);
    if coalesce(v_access->>'payrollReferences','hidden')<>'edit' then
      if (v_payload?'salaryExpenseSubjectId' and nullif(v_payload->>'salaryExpenseSubjectId','')::uuid is distinct from v_existing.salary_expense_subject_id)
         or (v_payload?'salaryPayableSubjectId' and nullif(v_payload->>'salaryPayableSubjectId','')::uuid is distinct from v_existing.salary_payable_subject_id)
         or (v_payload?'taxPayableSubjectId' and nullif(v_payload->>'taxPayableSubjectId','')::uuid is distinct from v_existing.tax_payable_subject_id)
         or (v_payload?'socialSecurityPayableSubjectId' and nullif(v_payload->>'socialSecurityPayableSubjectId','')::uuid is distinct from v_existing.social_security_payable_subject_id) then
        raise exception 'Payroll accounting reference fields are not editable' using errcode='42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'salaryExpenseSubjectId',v_existing.salary_expense_subject_id,
        'salaryPayableSubjectId',v_existing.salary_payable_subject_id,
        'taxPayableSubjectId',v_existing.tax_payable_subject_id,
        'socialSecurityPayableSubjectId',v_existing.social_security_payable_subject_id
      );
    end if;
  end if;
  v_saved := public.save_fms_payroll_run(v_payload);
  if v_saved.tenant_id<>v_tenant_id then raise exception 'Cross-tenant payroll write is forbidden' using errcode='42501'; end if;
  return app_private.fms_payroll_run_to_secure_json(
    app_private.fms_payroll_run_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.save_fms_payroll_line_secure(p_run_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.fms_payroll_run%rowtype;
  v_saved public.fms_payroll_line%rowtype;
  v_access jsonb;
begin
  select * into v_run from public.fms_payroll_run r
  where r.id=p_run_id and r.tenant_id=app_private.current_user_tenant_id() for update;
  if not found then raise exception 'Payroll run does not exist in the current tenant' using errcode='P0002'; end if;
  v_access := app_private.field_access_map('fms.payroll',v_run.created_by_user_id);
  if coalesce(v_access->>'employeeIdentity','hidden')<>'edit' then
    raise exception 'Payroll employee identity fields are not editable' using errcode='42501';
  end if;
  if coalesce(v_access->>'salaryAmounts','hidden')<>'edit' then
    raise exception 'Payroll salary amount fields are not editable' using errcode='42501';
  end if;
  v_saved := public.save_fms_payroll_line(p_run_id,p_payload);
  return app_private.fms_payroll_line_to_secure_json(to_jsonb(v_saved)-'tenant_id',v_run.created_by_user_id);
end;
$$;

create or replace function public.delete_fms_payroll_line_secure(p_line_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_run public.fms_payroll_run%rowtype; v_access jsonb;
begin
  select run_row.* into v_run
  from public.fms_payroll_line line_row
  join public.fms_payroll_run run_row
    on run_row.id=line_row.run_id and run_row.tenant_id=line_row.tenant_id
  where line_row.id=p_line_id and line_row.tenant_id=app_private.current_user_tenant_id()
  for update of run_row;
  if not found then raise exception 'Payroll line does not exist in the current tenant' using errcode='P0002'; end if;
  v_access := app_private.field_access_map('fms.payroll',v_run.created_by_user_id);
  if coalesce(v_access->>'employeeIdentity','hidden')<>'edit'
     or coalesce(v_access->>'salaryAmounts','hidden')<>'edit' then
    raise exception 'Payroll line fields are not editable' using errcode='42501';
  end if;
  perform public.delete_fms_payroll_line(p_line_id);
  return p_line_id;
end;
$$;

create or replace function public.act_fms_payroll_run_secure(
  p_run_id uuid,p_action text,p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.fms_payroll_run%rowtype;
  v_saved public.fms_payroll_run%rowtype;
  v_access jsonb;
begin
  select * into v_run from public.fms_payroll_run r
  where r.id=p_run_id and r.tenant_id=app_private.current_user_tenant_id() for update;
  if not found then raise exception 'Payroll run does not exist in the current tenant' using errcode='P0002'; end if;
  v_access := app_private.field_access_map('fms.payroll',v_run.created_by_user_id);
  if p_action in ('approve','pay') and coalesce(v_access->>'salaryAmounts','hidden')<>'edit' then
    raise exception 'Payroll salary amount fields are not editable' using errcode='42501';
  end if;
  if p_action in ('approve','pay') and coalesce(v_access->>'payrollReferences','hidden')<>'edit' then
    raise exception 'Payroll accounting reference fields are not editable' using errcode='42501';
  end if;
  v_saved := public.act_fms_payroll_run(p_run_id,p_action,p_payload);
  return app_private.fms_payroll_run_to_secure_json(
    app_private.fms_payroll_run_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

revoke all on table public.fms_payroll_run from anon,authenticated;
revoke all on table public.fms_payroll_line from anon,authenticated;

revoke execute on function public.save_fms_payroll_run(jsonb) from public,anon,authenticated;
revoke execute on function public.save_fms_payroll_line(uuid,jsonb) from public,anon,authenticated;
revoke execute on function public.delete_fms_payroll_line(uuid) from public,anon,authenticated;
revoke execute on function public.act_fms_payroll_run(uuid,text,jsonb) from public,anon,authenticated;
revoke execute on function public.fms_payroll_summary(uuid) from public,anon,authenticated;

revoke all on function public.fms_list_payroll_runs_secure(integer,integer,uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.fms_get_payroll_run_secure(uuid) from public,anon,authenticated;
revoke all on function public.fms_list_payroll_lines_secure(uuid) from public,anon,authenticated;
revoke all on function public.fms_list_payroll_employee_options_secure(uuid,uuid) from public,anon,authenticated;
revoke all on function public.fms_payroll_summary_secure(uuid,uuid) from public,anon,authenticated;
revoke all on function public.save_fms_payroll_run_secure(jsonb) from public,anon,authenticated;
revoke all on function public.save_fms_payroll_line_secure(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.delete_fms_payroll_line_secure(uuid) from public,anon,authenticated;
revoke all on function public.act_fms_payroll_run_secure(uuid,text,jsonb) from public,anon,authenticated;

grant execute on function public.fms_list_payroll_runs_secure(integer,integer,uuid,text,uuid) to authenticated;
grant execute on function public.fms_get_payroll_run_secure(uuid) to authenticated;
grant execute on function public.fms_list_payroll_lines_secure(uuid) to authenticated;
grant execute on function public.fms_list_payroll_employee_options_secure(uuid,uuid) to authenticated;
grant execute on function public.fms_payroll_summary_secure(uuid,uuid) to authenticated;
grant execute on function public.save_fms_payroll_run_secure(jsonb) to authenticated;
grant execute on function public.save_fms_payroll_line_secure(uuid,jsonb) to authenticated;
grant execute on function public.delete_fms_payroll_line_secure(uuid) to authenticated;
grant execute on function public.act_fms_payroll_run_secure(uuid,text,jsonb) to authenticated;

do $$
begin
  if exists(select 1 from public.sys_tenant t where not exists(
    select 1 from public.sys_permission_resource r
    where r.tenant_id=t.id and r.resource_key='fms.payroll'
      and r.owner_column='created_by_user_id' and r.enabled
  )) then raise exception 'Missing fms.payroll permission resource'; end if;
  if exists(select 1 from public.sys_permission_resource r
    where r.resource_key='fms.payroll' and (
      select count(*) from public.sys_permission_field f
      where f.tenant_id=r.tenant_id and f.resource_id=r.id and f.enabled
    )<>3) then raise exception 'Unexpected fms.payroll field catalog'; end if;
  if has_table_privilege('authenticated','public.fms_payroll_run','select')
     or has_table_privilege('authenticated','public.fms_payroll_line','select')
     or has_table_privilege('anon','public.fms_payroll_run','select')
     or has_table_privilege('anon','public.fms_payroll_line','select') then
    raise exception 'Direct payroll reads remain exposed';
  end if;
  if has_function_privilege('anon','public.fms_list_payroll_runs_secure(integer,integer,uuid,text,uuid)','execute')
     or has_function_privilege('authenticated','public.save_fms_payroll_run(jsonb)','execute') then
    raise exception 'Payroll function privileges are not secure';
  end if;
end;
$$;

;
