-- Secure tax-management reads and writes with tenant field permissions.
-- Button permission definitions remain unchanged.

alter table public.fms_tax_period
  add column if not exists created_by_user_id uuid;

update public.fms_tax_period period_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = period_row.tenant_id
    and lower(user_row.user_email) = lower(period_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where period_row.created_by_user_id is null
  and nullif(btrim(coalesce(period_row.create_by, '')), '') is not null;

do $$
begin
  if exists (select 1 from public.fms_tax_period where created_by_user_id is null) then
    raise exception 'Unable to backfill fms_tax_period.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_tax_period
  alter column created_by_user_id set not null;

create index if not exists fms_tax_period_tenant_creator_idx
  on public.fms_tax_period(tenant_id, created_by_user_id);
create index if not exists fms_tax_period_creator_tenant_idx
  on public.fms_tax_period(created_by_user_id, tenant_id);

alter table public.fms_tax_period
  drop constraint if exists fms_tax_period_creator_tenant_fkey;
alter table public.fms_tax_period
  add constraint fms_tax_period_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_tax_period_creator_identity()
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
      raise exception 'Unable to resolve tax-period creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Tax-period creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_tax_period_creator_identity on public.fms_tax_period;
create trigger fms_tax_period_creator_identity
before insert or update of created_by_user_id on public.fms_tax_period
for each row execute function app_private.set_fms_tax_period_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_tax_management;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_tax_management(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id,resource_key,resource_label,menu_name,owner_column,create_by,update_by
  ) values (
    p_tenant_id,'fms.tax_management','税务管理','FinanceTaxManagement','created_by_user_id',
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
    (p_tenant_id,v_resource_id,'taxAmounts','计税金额、税率、税额与应纳税额',
      'hidden','amount',true,10,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'taxSources','税务来源单据、来源编号与来源标识',
      'hidden','bank_account',true,20,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'filingReferences','申报凭证、申报人与缴税引用',
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
  on menu_row.type='menu' and menu_row.name='FinanceTaxManagement'
join public.sys_role_menu role_menu
  on role_menu.tenant_id=resource_row.tenant_id and role_menu.menu_id=menu_row.id
where resource_row.resource_key='fms.tax_management'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id,role_id,resource_id,field_id) do nothing;

create or replace function app_private.fms_tax_period_raw_json(p_period_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (to_jsonb(period_row)-'tenant_id'-'created_by_user_id') ||
         jsonb_build_object('period',to_jsonb(accounting_period)-'tenant_id')
  from public.fms_tax_period period_row
  join public.fms_accounting_period accounting_period
    on accounting_period.id=period_row.accounting_period_id
   and accounting_period.tenant_id=period_row.tenant_id
  where period_row.id=p_period_id
    and period_row.tenant_id=app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_tax_period_to_secure_json(
  p_period jsonb,p_owner_id uuid,p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_access,app_private.field_access_map('fms.tax_management',p_owner_id)
  );
  v_data jsonb := coalesce(p_period,'{}'::jsonb)-'tenant_id'-'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['output_tax_amount','input_tax_amount','transferable_input_amount',
      'adjustment_amount','payable_amount']::text[],
    coalesce(v_access->>'taxAmounts','hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,array['filing_reference','filed_by']::text[],
    coalesce(v_access->>'filingReferences','hidden')
  );
  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_tax_line_to_secure_json(
  p_line jsonb,p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.tax_management',p_owner_id);
  v_data jsonb := coalesce(p_line,'{}'::jsonb)-'tenant_id';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,array['source_type','source_id','source_no']::text[],
    coalesce(v_access->>'taxSources','hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,array['taxable_amount','tax_rate','tax_amount']::text[],
    coalesce(v_access->>'taxAmounts','hidden')
  );
  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_tax_periods_secure(
  p_from integer default 0,p_to integer default 19,p_account_set_id uuid default null,
  p_tax_type text default null,p_status text default null,p_tenant_id uuid default null
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
    raise exception 'Cross-tenant tax-period access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinanceTaxManagement',null,null,false) then
    raise exception 'Missing tax-management menu permission' using errcode='42501';
  end if;
  if p_account_set_id is not null and not exists(
    select 1 from public.fms_account_set account_set
    where account_set.id=p_account_set_id and account_set.tenant_id=v_tenant_id
  ) then
    raise exception 'Tax-management account set is outside the current tenant' using errcode='42501';
  end if;
  select count(*)::integer into v_total
  from public.fms_tax_period period_row
  where period_row.tenant_id=v_tenant_id
    and (p_account_set_id is null or period_row.account_set_id=p_account_set_id)
    and (p_tax_type is null or period_row.tax_type=p_tax_type)
    and (p_status is null or period_row.status=p_status);

  for v_row in
    select period_row.id,period_row.created_by_user_id
    from public.fms_tax_period period_row
    where period_row.tenant_id=v_tenant_id
      and (p_account_set_id is null or period_row.account_set_id=p_account_set_id)
      and (p_tax_type is null or period_row.tax_type=p_tax_type)
      and (p_status is null or period_row.status=p_status)
    order by period_row.create_time desc,period_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_tax_period_to_secure_json(
        app_private.fms_tax_period_raw_json(v_row.id),v_row.created_by_user_id
      )
    );
  end loop;
  return jsonb_build_object(
    'records',v_records,'total',coalesce(v_total,0),
    'field_access',app_private.field_access_map('fms.tax_management',null)
  );
end;
$$;

create or replace function public.fms_get_tax_period_secure(p_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_owner_id uuid;
begin
  if not app_private.can_execute_business_action('FinanceTaxManagement',null,null,false) then
    raise exception 'Missing tax-management menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id
  from public.fms_tax_period
  where id=p_period_id and tenant_id=app_private.current_user_tenant_id();
  if not found then
    raise exception 'Tax period does not exist in the current tenant' using errcode='P0002';
  end if;
  return app_private.fms_tax_period_to_secure_json(
    app_private.fms_tax_period_raw_json(p_period_id),v_owner_id
  );
end;
$$;

create or replace function public.fms_list_tax_ledger_lines_secure(p_period_id uuid)
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
  if not app_private.can_execute_business_action('FinanceTaxManagement',null,null,false) then
    raise exception 'Missing tax-management menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id
  from public.fms_tax_period
  where id=p_period_id and tenant_id=v_tenant_id;
  if not found then
    raise exception 'Tax period does not exist in the current tenant' using errcode='P0002';
  end if;
  select coalesce(jsonb_agg(
    app_private.fms_tax_line_to_secure_json(to_jsonb(line_row)-'tenant_id',v_owner_id)
    order by line_row.occurred_on,line_row.create_time,line_row.id
  ),'[]'::jsonb)
  into v_records
  from public.fms_tax_ledger_line line_row
  where line_row.tax_period_id=p_period_id and line_row.tenant_id=v_tenant_id;
  return jsonb_build_object(
    'records',v_records,
    'field_access',app_private.field_access_map('fms.tax_management',v_owner_id),
    'is_record_owner',v_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_tax_summary_secure(
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
  v_access jsonb := app_private.field_access_map('fms.tax_management',null);
  v_amount_access text := coalesce(v_access->>'taxAmounts','hidden');
  v_summary record;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant tax summary access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinanceTaxManagement',null,null,false) then
    raise exception 'Missing tax-management menu permission' using errcode='42501';
  end if;
  if p_account_set_id is null or not exists(
    select 1 from public.fms_account_set account_set
    where account_set.id=p_account_set_id and account_set.tenant_id=v_tenant_id
  ) then
    raise exception 'Tax-management account set is outside the current tenant' using errcode='42501';
  end if;
  select count(*) period_count,coalesce(sum(output_tax_amount),0) output_tax_amount,
         coalesce(sum(input_tax_amount),0) input_tax_amount,
         coalesce(sum(payable_amount),0) payable_amount,
         count(*) filter(where status in ('draft','calculated','reviewed','filed')) pending_count
  into v_summary
  from public.fms_tax_period
  where tenant_id=v_tenant_id and account_set_id=p_account_set_id and status<>'cancelled';
  return jsonb_build_object(
    'period_count',v_summary.period_count,
    'output_tax_amount',case when v_amount_access in ('read','edit') then to_jsonb(v_summary.output_tax_amount)
      when v_amount_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'input_tax_amount',case when v_amount_access in ('read','edit') then to_jsonb(v_summary.input_tax_amount)
      when v_amount_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'payable_amount',case when v_amount_access in ('read','edit') then to_jsonb(v_summary.payable_amount)
      when v_amount_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'pending_count',v_summary.pending_count,
    'field_access',v_access
  );
end;
$$;

create or replace function public.save_fms_tax_period_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := nullif(p_payload->>'id','')::uuid;
  v_accounting_period_id uuid := nullif(p_payload->>'accountingPeriodId','')::uuid;
  v_existing public.fms_tax_period%rowtype;
  v_saved public.fms_tax_period%rowtype;
  v_payload jsonb := coalesce(p_payload,'{}'::jsonb);
  v_access jsonb;
begin
  if v_accounting_period_id is null or not exists(
    select 1 from public.fms_accounting_period accounting_period
    where accounting_period.id=v_accounting_period_id
      and accounting_period.tenant_id=v_tenant_id
  ) then
    raise exception 'Tax accounting period is outside the current tenant' using errcode='42501';
  end if;
  if v_id is not null then
    select * into v_existing
    from public.fms_tax_period period_row
    where period_row.id=v_id and period_row.tenant_id=v_tenant_id
    for update;
    if not found then
      raise exception 'Tax period does not exist in the current tenant' using errcode='P0002';
    end if;
    v_access := app_private.field_access_map(
      'fms.tax_management',v_existing.created_by_user_id
    );
    if coalesce(v_access->>'taxAmounts','hidden')<>'edit' then
      if (v_payload?'transferableInputAmount'
          and nullif(v_payload->>'transferableInputAmount','')::numeric
            is distinct from v_existing.transferable_input_amount)
         or (v_payload?'adjustmentAmount'
          and nullif(v_payload->>'adjustmentAmount','')::numeric
            is distinct from v_existing.adjustment_amount) then
        raise exception 'Tax amount fields are not editable' using errcode='42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'transferableInputAmount',v_existing.transferable_input_amount,
        'adjustmentAmount',v_existing.adjustment_amount
      );
    end if;
  end if;
  v_saved := public.save_fms_tax_period(v_payload);
  if v_saved.tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant tax-period write is forbidden' using errcode='42501';
  end if;
  return app_private.fms_tax_period_to_secure_json(
    app_private.fms_tax_period_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.save_fms_tax_ledger_line_secure(
  p_period_id uuid,p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period public.fms_tax_period%rowtype;
  v_saved public.fms_tax_ledger_line%rowtype;
  v_access jsonb;
begin
  select * into v_period
  from public.fms_tax_period period_row
  where period_row.id=p_period_id
    and period_row.tenant_id=app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Tax period does not exist in the current tenant' using errcode='P0002';
  end if;
  v_access := app_private.field_access_map(
    'fms.tax_management',v_period.created_by_user_id
  );
  if coalesce(v_access->>'taxSources','hidden')<>'edit' then
    raise exception 'Tax source fields are not editable' using errcode='42501';
  end if;
  if coalesce(v_access->>'taxAmounts','hidden')<>'edit' then
    raise exception 'Tax amount fields are not editable' using errcode='42501';
  end if;
  v_saved := public.save_fms_tax_ledger_line(p_period_id,p_payload);
  return app_private.fms_tax_line_to_secure_json(
    to_jsonb(v_saved)-'tenant_id',v_period.created_by_user_id
  );
end;
$$;

create or replace function public.delete_fms_tax_ledger_line_secure(p_line_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_period public.fms_tax_period%rowtype; v_access jsonb;
begin
  select period_row.* into v_period
  from public.fms_tax_ledger_line line_row
  join public.fms_tax_period period_row
    on period_row.id=line_row.tax_period_id and period_row.tenant_id=line_row.tenant_id
  where line_row.id=p_line_id
    and line_row.tenant_id=app_private.current_user_tenant_id()
  for update of period_row;
  if not found then
    raise exception 'Tax ledger line does not exist in the current tenant' using errcode='P0002';
  end if;
  v_access := app_private.field_access_map(
    'fms.tax_management',v_period.created_by_user_id
  );
  if coalesce(v_access->>'taxSources','hidden')<>'edit'
     or coalesce(v_access->>'taxAmounts','hidden')<>'edit' then
    raise exception 'Tax ledger fields are not editable' using errcode='42501';
  end if;
  perform public.delete_fms_tax_ledger_line(p_line_id);
  return p_line_id;
end;
$$;

create or replace function public.act_fms_tax_period_secure(
  p_period_id uuid,p_action text,p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period public.fms_tax_period%rowtype;
  v_saved public.fms_tax_period%rowtype;
  v_access jsonb;
begin
  select * into v_period
  from public.fms_tax_period period_row
  where period_row.id=p_period_id
    and period_row.tenant_id=app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Tax period does not exist in the current tenant' using errcode='P0002';
  end if;
  v_access := app_private.field_access_map(
    'fms.tax_management',v_period.created_by_user_id
  );
  if p_action in ('review','file','pay')
     and coalesce(v_access->>'taxAmounts','hidden')<>'edit' then
    raise exception 'Tax amount fields are not editable' using errcode='42501';
  end if;
  if p_action in ('file','pay')
     and coalesce(v_access->>'filingReferences','hidden')<>'edit' then
    raise exception 'Tax filing reference fields are not editable' using errcode='42501';
  end if;
  v_saved := public.act_fms_tax_period(p_period_id,p_action,p_payload);
  return app_private.fms_tax_period_to_secure_json(
    app_private.fms_tax_period_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

revoke all on table public.fms_tax_period from anon,authenticated;
revoke all on table public.fms_tax_ledger_line from anon,authenticated;

revoke execute on function public.save_fms_tax_period(jsonb) from public,anon,authenticated;
revoke execute on function public.save_fms_tax_ledger_line(uuid,jsonb) from public,anon,authenticated;
revoke execute on function public.delete_fms_tax_ledger_line(uuid) from public,anon,authenticated;
revoke execute on function public.act_fms_tax_period(uuid,text,jsonb) from public,anon,authenticated;
revoke execute on function public.fms_tax_summary(uuid) from public,anon,authenticated;

revoke all on function public.fms_list_tax_periods_secure(integer,integer,uuid,text,text,uuid)
  from public,anon,authenticated;
revoke all on function public.fms_get_tax_period_secure(uuid)
  from public,anon,authenticated;
revoke all on function public.fms_list_tax_ledger_lines_secure(uuid)
  from public,anon,authenticated;
revoke all on function public.fms_tax_summary_secure(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.save_fms_tax_period_secure(jsonb)
  from public,anon,authenticated;
revoke all on function public.save_fms_tax_ledger_line_secure(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.delete_fms_tax_ledger_line_secure(uuid)
  from public,anon,authenticated;
revoke all on function public.act_fms_tax_period_secure(uuid,text,jsonb)
  from public,anon,authenticated;

grant execute on function public.fms_list_tax_periods_secure(integer,integer,uuid,text,text,uuid)
  to authenticated;
grant execute on function public.fms_get_tax_period_secure(uuid) to authenticated;
grant execute on function public.fms_list_tax_ledger_lines_secure(uuid) to authenticated;
grant execute on function public.fms_tax_summary_secure(uuid,uuid) to authenticated;
grant execute on function public.save_fms_tax_period_secure(jsonb) to authenticated;
grant execute on function public.save_fms_tax_ledger_line_secure(uuid,jsonb) to authenticated;
grant execute on function public.delete_fms_tax_ledger_line_secure(uuid) to authenticated;
grant execute on function public.act_fms_tax_period_secure(uuid,text,jsonb) to authenticated;

do $$
begin
  if exists(select 1 from public.sys_tenant tenant_row where not exists(
    select 1 from public.sys_permission_resource resource_row
    where resource_row.tenant_id=tenant_row.id
      and resource_row.resource_key='fms.tax_management'
      and resource_row.owner_column='created_by_user_id'
      and resource_row.enabled
  )) then
    raise exception 'Missing fms.tax_management permission resource';
  end if;
  if exists(select 1 from public.sys_permission_resource resource_row
    where resource_row.resource_key='fms.tax_management' and (
      select count(*) from public.sys_permission_field field_row
      where field_row.tenant_id=resource_row.tenant_id
        and field_row.resource_id=resource_row.id and field_row.enabled
    )<>3) then
    raise exception 'Unexpected fms.tax_management field catalog';
  end if;
  if has_table_privilege('authenticated','public.fms_tax_period','select')
     or has_table_privilege('authenticated','public.fms_tax_ledger_line','select')
     or has_table_privilege('anon','public.fms_tax_period','select')
     or has_table_privilege('anon','public.fms_tax_ledger_line','select') then
    raise exception 'Direct tax-management reads remain exposed';
  end if;
  if has_function_privilege(
       'anon','public.fms_list_tax_periods_secure(integer,integer,uuid,text,text,uuid)','execute'
     )
     or has_function_privilege(
       'authenticated','public.save_fms_tax_period(jsonb)','execute'
     ) then
    raise exception 'Tax-management function privileges are not secure';
  end if;
end;
$$;

;
