-- Secure period-close reads and writes with tenant field permissions.
-- Button permission definitions remain unchanged.

alter table public.fms_period_close_run
  add column if not exists created_by_user_id uuid;

update public.fms_period_close_run run_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id=run_row.tenant_id
    and lower(user_row.user_email)=lower(run_row.create_by)
  order by user_row.create_time,user_row.id
  limit 1
)
where run_row.created_by_user_id is null
  and nullif(btrim(coalesce(run_row.create_by,'')),'') is not null;

do $$
begin
  if exists(select 1 from public.fms_period_close_run where created_by_user_id is null) then
    raise exception 'Unable to backfill fms_period_close_run.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_period_close_run
  alter column created_by_user_id set not null;

create index if not exists fms_period_close_run_tenant_creator_idx
  on public.fms_period_close_run(tenant_id,created_by_user_id);
create index if not exists fms_period_close_run_creator_tenant_idx
  on public.fms_period_close_run(created_by_user_id,tenant_id);

alter table public.fms_period_close_run
  drop constraint if exists fms_period_close_run_creator_tenant_fkey;
alter table public.fms_period_close_run
  add constraint fms_period_close_run_creator_tenant_fkey
  foreign key (tenant_id,created_by_user_id)
  references public.sys_user(tenant_id,id);

create or replace function app_private.set_fms_period_close_run_creator_identity()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='INSERT' then
    if new.created_by_user_id is null then
      new.created_by_user_id:=app_private.current_app_user_id();
    end if;
    if new.created_by_user_id is null
       and nullif(btrim(coalesce(new.create_by,'')),'') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id=new.tenant_id
        and lower(user_row.user_email)=lower(new.create_by)
      order by user_row.create_time,user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve period-close creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Period-close creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_period_close_run_creator_identity on public.fms_period_close_run;
create trigger fms_period_close_run_creator_identity
before insert or update of created_by_user_id on public.fms_period_close_run
for each row execute function app_private.set_fms_period_close_run_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_period_close;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_period_close(p_tenant_id);
  insert into public.sys_permission_resource(
    tenant_id,resource_key,resource_label,menu_name,owner_column,create_by,update_by
  ) values(
    p_tenant_id,'fms.period_close','期末结账','FinancePeriodClose','created_by_user_id',
    '624944977@qq.com','624944977@qq.com'
  )
  on conflict(tenant_id,resource_key) do update
    set resource_label=excluded.resource_label,menu_name=excluded.menu_name,
        owner_column=excluded.owner_column,enabled=true,update_by=excluded.update_by,
        update_time=now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id,resource_id,field_key,field_label,default_access,mask_strategy,
    owner_override_enabled,sort,create_by,update_by
  ) values
    (p_tenant_id,v_resource_id,'closeDiagnostics','检查数量、检查结论与试算差额',
      'hidden','amount',true,10,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'voucherReferences','损益结转与年末结转凭证引用',
      'hidden','bank_account',true,20,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'closeAudit','结账人、取消人及反结账原因',
      'hidden','bank_account',true,30,'624944977@qq.com','624944977@qq.com')
  on conflict(tenant_id,resource_id,field_key) do update
    set field_label=excluded.field_label,mask_strategy=excluded.mask_strategy,
        owner_override_enabled=excluded.owner_override_enabled,sort=excluded.sort,
        sensitive=true,enabled=true,update_by=excluded.update_by,update_time=now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

insert into public.sys_role_field_permission(
  tenant_id,role_id,resource_id,field_id,access_level,create_by,update_by
)
select distinct resource_row.tenant_id,role_menu.role_id,resource_row.id,field_row.id,
  'edit','624944977@qq.com','624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id=resource_row.tenant_id and field_row.resource_id=resource_row.id
join public.sys_menu menu_row
  on menu_row.type='menu' and menu_row.name='FinancePeriodClose'
join public.sys_role_menu role_menu
  on role_menu.tenant_id=resource_row.tenant_id and role_menu.menu_id=menu_row.id
where resource_row.resource_key='fms.period_close'
  and resource_row.enabled and field_row.enabled
on conflict(tenant_id,role_id,resource_id,field_id) do nothing;

create or replace function app_private.fms_period_close_run_raw_json(p_run_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select (to_jsonb(run_row)-'tenant_id'-'created_by_user_id') ||
    jsonb_build_object('period',to_jsonb(period_row)-'tenant_id')
  from public.fms_period_close_run run_row
  join public.fms_accounting_period period_row
    on period_row.id=run_row.accounting_period_id and period_row.tenant_id=run_row.tenant_id
  where run_row.id=p_run_id
    and run_row.tenant_id=app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_period_close_run_to_secure_json(
  p_run jsonb,p_owner_id uuid,p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_access jsonb:=coalesce(
    p_access,app_private.field_access_map('fms.period_close',p_owner_id)
  );
  v_data jsonb:=coalesce(p_run,'{}'::jsonb)-'tenant_id'-'created_by_user_id';
begin
  v_data:=app_private.apply_jsonb_amount_access(
    v_data,array['passed_count','warning_count','blocking_count']::text[],
    coalesce(v_access->>'closeDiagnostics','hidden')
  );
  v_data:=app_private.apply_jsonb_text_access(
    v_data,array['profit_loss_voucher_id','year_end_voucher_id']::text[],
    coalesce(v_access->>'voucherReferences','hidden')
  );
  v_data:=app_private.apply_jsonb_text_access(
    v_data,array['completed_by','cancelled_by','cancel_reason']::text[],
    coalesce(v_access->>'closeAudit','hidden')
  );
  return v_data||jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_period_close_check_to_secure_json(
  p_check jsonb,p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_access jsonb:=app_private.field_access_map('fms.period_close',p_owner_id);
  v_data jsonb:=coalesce(p_check,'{}'::jsonb)-'tenant_id';
begin
  v_data:=app_private.apply_jsonb_amount_access(
    v_data,array['issue_count']::text[],coalesce(v_access->>'closeDiagnostics','hidden')
  );
  v_data:=app_private.apply_jsonb_text_access(
    v_data,array['summary','detail']::text[],coalesce(v_access->>'closeDiagnostics','hidden')
  );
  return v_data||jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_period_close_runs_secure(
  p_from integer default 0,p_to integer default 19,p_account_set_id uuid default null,
  p_status text default null,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_from integer:=greatest(coalesce(p_from,0),0);
  v_limit integer:=least(greatest(coalesce(p_to,19)-v_from+1,1),1000);
  v_total integer;
  v_records jsonb:='[]'::jsonb;
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant period-close access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinancePeriodClose',null,null,false) then
    raise exception 'Missing period-close menu permission' using errcode='42501';
  end if;
  if p_account_set_id is not null and not exists(
    select 1 from public.fms_account_set account_set
    where account_set.id=p_account_set_id and account_set.tenant_id=v_tenant_id
  ) then
    raise exception 'Period-close account set is outside the current tenant' using errcode='42501';
  end if;
  select count(*)::integer into v_total
  from public.fms_period_close_run run_row
  where run_row.tenant_id=v_tenant_id
    and (p_account_set_id is null or run_row.account_set_id=p_account_set_id)
    and (p_status is null or run_row.status=p_status);
  for v_row in
    select run_row.id,run_row.created_by_user_id
    from public.fms_period_close_run run_row
    where run_row.tenant_id=v_tenant_id
      and (p_account_set_id is null or run_row.account_set_id=p_account_set_id)
      and (p_status is null or run_row.status=p_status)
    order by run_row.create_time desc,run_row.id
    offset v_from limit v_limit
  loop
    v_records:=v_records||jsonb_build_array(
      app_private.fms_period_close_run_to_secure_json(
        app_private.fms_period_close_run_raw_json(v_row.id),v_row.created_by_user_id
      )
    );
  end loop;
  return jsonb_build_object(
    'records',v_records,'total',coalesce(v_total,0),
    'field_access',app_private.field_access_map('fms.period_close',null)
  );
end;
$$;

create or replace function public.fms_get_period_close_run_secure(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_owner_id uuid;
begin
  if not app_private.can_execute_business_action('FinancePeriodClose',null,null,false) then
    raise exception 'Missing period-close menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id
  from public.fms_period_close_run
  where id=p_run_id and tenant_id=app_private.current_user_tenant_id();
  if not found then
    raise exception 'Period-close run does not exist in the current tenant' using errcode='P0002';
  end if;
  return app_private.fms_period_close_run_to_secure_json(
    app_private.fms_period_close_run_raw_json(p_run_id),v_owner_id
  );
end;
$$;

create or replace function public.fms_list_period_close_checks_secure(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_owner_id uuid;
  v_records jsonb;
begin
  if not app_private.can_execute_business_action('FinancePeriodClose',null,null,false) then
    raise exception 'Missing period-close menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id
  from public.fms_period_close_run
  where id=p_run_id and tenant_id=v_tenant_id;
  if not found then
    raise exception 'Period-close run does not exist in the current tenant' using errcode='P0002';
  end if;
  select coalesce(jsonb_agg(
    app_private.fms_period_close_check_to_secure_json(
      to_jsonb(check_row)-'tenant_id',v_owner_id
    ) order by check_row.create_time,check_row.id
  ),'[]'::jsonb)
  into v_records
  from public.fms_period_close_check check_row
  where check_row.close_run_id=p_run_id and check_row.tenant_id=v_tenant_id;
  return jsonb_build_object(
    'records',v_records,
    'field_access',app_private.field_access_map('fms.period_close',v_owner_id),
    'is_record_owner',v_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_period_close_summary_secure(
  p_account_set_id uuid,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_access jsonb:=app_private.field_access_map('fms.period_close',null);
  v_diagnostic_access text:=coalesce(v_access->>'closeDiagnostics','hidden');
  v_audit_access text:=coalesce(v_access->>'closeAudit','hidden');
  v_summary record;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant period-close summary access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinancePeriodClose',null,null,false) then
    raise exception 'Missing period-close menu permission' using errcode='42501';
  end if;
  if p_account_set_id is null or not exists(
    select 1 from public.fms_account_set account_set
    where account_set.id=p_account_set_id and account_set.tenant_id=v_tenant_id
  ) then
    raise exception 'Period-close account set is outside the current tenant' using errcode='42501';
  end if;
  select count(*) period_count,count(*) filter(where status='closed') closed_count,
    count(*) filter(where status in('checking','ready')) checking_count,
    coalesce(sum(blocking_count) filter(where status in('checking','ready')),0) blocking_count,
    max(completed_at) latest_completed_at
  into v_summary
  from public.fms_period_close_run
  where tenant_id=v_tenant_id and account_set_id=p_account_set_id;
  return jsonb_build_object(
    'period_count',v_summary.period_count,'closed_count',v_summary.closed_count,
    'checking_count',case when v_diagnostic_access in('read','edit') then to_jsonb(v_summary.checking_count)
      when v_diagnostic_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'blocking_count',case when v_diagnostic_access in('read','edit') then to_jsonb(v_summary.blocking_count)
      when v_diagnostic_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'latest_completed_at',case when v_audit_access in('read','edit') then to_jsonb(v_summary.latest_completed_at)
      when v_audit_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'field_access',v_access
  );
end;
$$;

create or replace function public.run_fms_period_close_checks_secure(p_accounting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_existing public.fms_period_close_run%rowtype;
  v_saved public.fms_period_close_run%rowtype;
  v_access jsonb;
begin
  if not exists(
    select 1 from public.fms_accounting_period period_row
    where period_row.id=p_accounting_period_id and period_row.tenant_id=v_tenant_id
  ) then
    raise exception 'Period-close accounting period is outside the current tenant' using errcode='42501';
  end if;
  select * into v_existing
  from public.fms_period_close_run run_row
  where run_row.accounting_period_id=p_accounting_period_id and run_row.tenant_id=v_tenant_id
  for update;
  if found then
    v_access:=app_private.field_access_map('fms.period_close',v_existing.created_by_user_id);
    if coalesce(v_access->>'closeDiagnostics','hidden')<>'edit' then
      raise exception 'Period-close diagnostic fields are not editable' using errcode='42501';
    end if;
  end if;
  v_saved:=public.run_fms_period_close_checks(p_accounting_period_id);
  return app_private.fms_period_close_run_to_secure_json(
    app_private.fms_period_close_run_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.generate_fms_profit_loss_carryforward_secure(
  p_accounting_period_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_run public.fms_period_close_run%rowtype;
  v_voucher public.fms_voucher%rowtype;
  v_access jsonb;
begin
  select * into v_run
  from public.fms_period_close_run run_row
  where run_row.accounting_period_id=p_accounting_period_id
    and run_row.tenant_id=app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Period-close run does not exist in the current tenant' using errcode='P0002';
  end if;
  v_access:=app_private.field_access_map('fms.period_close',v_run.created_by_user_id);
  if coalesce(v_access->>'closeDiagnostics','hidden')<>'edit' then
    raise exception 'Period-close diagnostic fields are not editable' using errcode='42501';
  end if;
  if coalesce(v_access->>'voucherReferences','hidden')<>'edit' then
    raise exception 'Period-close voucher reference fields are not editable' using errcode='42501';
  end if;
  v_voucher:=public.generate_fms_profit_loss_carryforward(p_accounting_period_id);
  update public.fms_period_close_run
  set profit_loss_voucher_id=v_voucher.id
  where id=v_run.id;
  return jsonb_build_object('id',v_voucher.id);
end;
$$;

create or replace function public.act_fms_period_close_run_secure(
  p_run_id uuid,p_action text,p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_run public.fms_period_close_run%rowtype;
  v_saved public.fms_period_close_run%rowtype;
  v_access jsonb;
begin
  select * into v_run
  from public.fms_period_close_run run_row
  where run_row.id=p_run_id and run_row.tenant_id=app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Period-close run does not exist in the current tenant' using errcode='P0002';
  end if;
  v_access:=app_private.field_access_map('fms.period_close',v_run.created_by_user_id);
  if p_action='close' and coalesce(v_access->>'closeDiagnostics','hidden')<>'edit' then
    raise exception 'Period-close diagnostic fields are not editable' using errcode='42501';
  end if;
  if p_action in('cancel','reopen') and coalesce(v_access->>'closeAudit','hidden')<>'edit' then
    raise exception 'Period-close audit fields are not editable' using errcode='42501';
  end if;
  v_saved:=public.act_fms_period_close_run(p_run_id,p_action,p_reason);
  return app_private.fms_period_close_run_to_secure_json(
    app_private.fms_period_close_run_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

revoke all on table public.fms_period_close_run from anon,authenticated;
revoke all on table public.fms_period_close_check from anon,authenticated;

revoke execute on function public.fms_period_close_summary(uuid) from public,anon,authenticated;
revoke execute on function public.run_fms_period_close_checks(uuid) from public,anon,authenticated;
revoke execute on function public.generate_fms_profit_loss_carryforward(uuid)
  from public,anon,authenticated;
revoke execute on function public.act_fms_period_close_run(uuid,text,text)
  from public,anon,authenticated;

revoke all on function public.fms_list_period_close_runs_secure(integer,integer,uuid,text,uuid)
  from public,anon,authenticated;
revoke all on function public.fms_get_period_close_run_secure(uuid)
  from public,anon,authenticated;
revoke all on function public.fms_list_period_close_checks_secure(uuid)
  from public,anon,authenticated;
revoke all on function public.fms_period_close_summary_secure(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.run_fms_period_close_checks_secure(uuid)
  from public,anon,authenticated;
revoke all on function public.generate_fms_profit_loss_carryforward_secure(uuid)
  from public,anon,authenticated;
revoke all on function public.act_fms_period_close_run_secure(uuid,text,text)
  from public,anon,authenticated;

grant execute on function public.fms_list_period_close_runs_secure(integer,integer,uuid,text,uuid)
  to authenticated;
grant execute on function public.fms_get_period_close_run_secure(uuid) to authenticated;
grant execute on function public.fms_list_period_close_checks_secure(uuid) to authenticated;
grant execute on function public.fms_period_close_summary_secure(uuid,uuid) to authenticated;
grant execute on function public.run_fms_period_close_checks_secure(uuid) to authenticated;
grant execute on function public.generate_fms_profit_loss_carryforward_secure(uuid) to authenticated;
grant execute on function public.act_fms_period_close_run_secure(uuid,text,text) to authenticated;

do $$
begin
  if exists(select 1 from public.sys_tenant tenant_row where not exists(
    select 1 from public.sys_permission_resource resource_row
    where resource_row.tenant_id=tenant_row.id and resource_row.resource_key='fms.period_close'
      and resource_row.owner_column='created_by_user_id' and resource_row.enabled
  )) then raise exception 'Missing fms.period_close permission resource'; end if;
  if exists(select 1 from public.sys_permission_resource resource_row
    where resource_row.resource_key='fms.period_close' and (
      select count(*) from public.sys_permission_field field_row
      where field_row.tenant_id=resource_row.tenant_id
        and field_row.resource_id=resource_row.id and field_row.enabled
    )<>3
  ) then raise exception 'Unexpected fms.period_close field catalog'; end if;
  if has_table_privilege('authenticated','public.fms_period_close_run','select')
     or has_table_privilege('authenticated','public.fms_period_close_check','select')
     or has_table_privilege('anon','public.fms_period_close_run','select')
     or has_table_privilege('anon','public.fms_period_close_check','select') then
    raise exception 'Direct period-close reads remain exposed';
  end if;
  if has_function_privilege(
       'anon','public.fms_list_period_close_runs_secure(integer,integer,uuid,text,uuid)','execute'
     ) or has_function_privilege(
       'authenticated','public.run_fms_period_close_checks(uuid)','execute'
     ) then
    raise exception 'Period-close function privileges are not secure';
  end if;
end;
$$;

;
