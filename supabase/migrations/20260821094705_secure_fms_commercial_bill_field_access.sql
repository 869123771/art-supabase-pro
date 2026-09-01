-- Secure commercial bill reads and writes with tenant-scoped field permissions.
-- Button permissions remain owned by the existing operation permission functions.

alter table public.fms_commercial_bill
  add column if not exists created_by_user_id uuid;

update public.fms_commercial_bill bill_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = bill_row.tenant_id
    and lower(user_row.user_email) = lower(bill_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where bill_row.created_by_user_id is null
  and nullif(btrim(coalesce(bill_row.create_by, '')), '') is not null;

do $$
begin
  if exists (
    select 1
    from public.fms_commercial_bill
    where created_by_user_id is null
  ) then
    raise exception 'Unable to backfill fms_commercial_bill.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_commercial_bill
  alter column created_by_user_id set not null;

create index if not exists fms_commercial_bill_tenant_creator_idx
  on public.fms_commercial_bill(tenant_id, created_by_user_id);

create index if not exists fms_commercial_bill_creator_tenant_idx
  on public.fms_commercial_bill(created_by_user_id, tenant_id);

alter table public.fms_commercial_bill
  drop constraint if exists fms_commercial_bill_creator_tenant_fkey;

alter table public.fms_commercial_bill
  add constraint fms_commercial_bill_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_commercial_bill_creator_identity()
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
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve commercial bill creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Commercial bill creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_commercial_bill_creator_identity
  on public.fms_commercial_bill;
create trigger fms_commercial_bill_creator_identity
before insert or update of created_by_user_id
on public.fms_commercial_bill
for each row execute function app_private.set_fms_commercial_bill_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_commercial_bill;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_commercial_bill(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.commercial_bill', '商业票据',
    'FinanceCommercialBill', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'billParties', '出票人、收款人、承兑人与往来单位',
      'hidden', 'none', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'billAmounts', '票面金额与已结金额',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'billReferences', '票面号码、来源单据与结算参考',
      'hidden', 'bank_account', true, 30, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

-- Preserve current behavior for roles that already own the menu. Tenant admins can
-- tighten these defaults afterwards without changing button grants.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'FinanceCommercialBill'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.commercial_bill'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.fms_commercial_bill_raw_json(p_bill_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(bill_row)
    - 'tenant_id'
    - 'created_by_user_id'
  from public.fms_commercial_bill bill_row
  where bill_row.id = p_bill_id
    and bill_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_commercial_bill_to_secure_json(
  p_bill jsonb,
  p_owner_id uuid,
  p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_access,
    app_private.field_access_map('fms.commercial_bill', p_owner_id)
  );
  v_reference_access text := coalesce(v_access->>'billReferences', 'hidden');
  v_data jsonb := coalesce(p_bill, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['drawer_name', 'payee_name', 'acceptor_name', 'counterparty_name']::text[],
    coalesce(v_access->>'billParties', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['face_amount', 'settled_amount']::text[],
    coalesce(v_access->>'billAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['external_bill_no', 'source_type', 'source_id', 'source_no']::text[],
    v_reference_access
  );
  if v_reference_access not in ('read', 'edit') then
    v_data := v_data - 'attachment_ids';
  end if;
  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_commercial_bill_event_to_secure_json(
  p_event jsonb,
  p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.commercial_bill', p_owner_id);
  v_data jsonb := coalesce(p_event, '{}'::jsonb) - 'tenant_id';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['counterparty_name']::text[],
    coalesce(v_access->>'billParties', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['amount']::text[],
    coalesce(v_access->>'billAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['fund_account_id', 'reference_no', 'voucher_id']::text[],
    coalesce(v_access->>'billReferences', 'hidden')
  );
  return v_data;
end;
$$;

create or replace function public.fms_list_commercial_bills_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_direction text default null,
  p_bill_type text default null,
  p_status text default null,
  p_keyword text default null,
  p_due_start_date date default null,
  p_due_end_date date default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - v_from + 1, 1), 1000);
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('fms.commercial_bill', null);
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant commercial bill access is forbidden'
      using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCommercialBill', null, null, false
  ) then
    raise exception 'Missing commercial bill menu permission'
      using errcode = '42501';
  end if;
  if p_account_set_id is not null and not exists (
    select 1
    from public.fms_account_set account_set_row
    where account_set_row.id = p_account_set_id
      and account_set_row.tenant_id = v_tenant_id
  ) then
    raise exception 'Commercial bill account set is outside the current tenant'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.fms_commercial_bill bill_row
  where bill_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or bill_row.account_set_id = p_account_set_id)
    and (p_direction is null or bill_row.direction = p_direction)
    and (p_bill_type is null or bill_row.bill_type = p_bill_type)
    and (p_status is null or bill_row.status = p_status)
    and (p_due_start_date is null or bill_row.due_date >= p_due_start_date)
    and (p_due_end_date is null or bill_row.due_date <= p_due_end_date)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or bill_row.bill_no ilike '%' || btrim(p_keyword) || '%'
      or (
        app_private.resolve_field_access(
          'fms.commercial_bill', 'billReferences', bill_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          bill_row.external_bill_no ilike '%' || btrim(p_keyword) || '%'
          or bill_row.source_no ilike '%' || btrim(p_keyword) || '%'
        )
      )
      or (
        app_private.resolve_field_access(
          'fms.commercial_bill', 'billParties', bill_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          bill_row.drawer_name ilike '%' || btrim(p_keyword) || '%'
          or bill_row.payee_name ilike '%' || btrim(p_keyword) || '%'
          or bill_row.acceptor_name ilike '%' || btrim(p_keyword) || '%'
          or bill_row.counterparty_name ilike '%' || btrim(p_keyword) || '%'
        )
      )
    );

  for v_row in
    select bill_row.id, bill_row.created_by_user_id
    from public.fms_commercial_bill bill_row
    where bill_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or bill_row.account_set_id = p_account_set_id)
      and (p_direction is null or bill_row.direction = p_direction)
      and (p_bill_type is null or bill_row.bill_type = p_bill_type)
      and (p_status is null or bill_row.status = p_status)
      and (p_due_start_date is null or bill_row.due_date >= p_due_start_date)
      and (p_due_end_date is null or bill_row.due_date <= p_due_end_date)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or bill_row.bill_no ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'fms.commercial_bill', 'billReferences', bill_row.created_by_user_id
          ) in ('read', 'edit')
          and (
            bill_row.external_bill_no ilike '%' || btrim(p_keyword) || '%'
            or bill_row.source_no ilike '%' || btrim(p_keyword) || '%'
          )
        )
        or (
          app_private.resolve_field_access(
            'fms.commercial_bill', 'billParties', bill_row.created_by_user_id
          ) in ('read', 'edit')
          and (
            bill_row.drawer_name ilike '%' || btrim(p_keyword) || '%'
            or bill_row.payee_name ilike '%' || btrim(p_keyword) || '%'
            or bill_row.acceptor_name ilike '%' || btrim(p_keyword) || '%'
            or bill_row.counterparty_name ilike '%' || btrim(p_keyword) || '%'
          )
        )
      )
    order by bill_row.due_date, bill_row.create_time desc, bill_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_commercial_bill_to_secure_json(
        app_private.fms_commercial_bill_raw_json(v_row.id),
        v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', coalesce(v_total, 0),
    'field_access', v_base_access
  );
end;
$$;

create or replace function public.fms_get_commercial_bill_secure(p_bill_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceCommercialBill', null, null, false
  ) then
    raise exception 'Missing commercial bill menu permission'
      using errcode = '42501';
  end if;
  select bill_row.created_by_user_id
  into v_owner_id
  from public.fms_commercial_bill bill_row
  where bill_row.id = p_bill_id
    and bill_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Commercial bill does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  return app_private.fms_commercial_bill_to_secure_json(
    app_private.fms_commercial_bill_raw_json(p_bill_id),
    v_owner_id
  );
end;
$$;

create or replace function public.fms_list_commercial_bill_events_secure(p_bill_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_result jsonb := '[]'::jsonb;
  v_event record;
begin
  if not app_private.can_execute_business_action(
    'FinanceCommercialBill', null, null, false
  ) then
    raise exception 'Missing commercial bill menu permission'
      using errcode = '42501';
  end if;
  select bill_row.created_by_user_id
  into v_owner_id
  from public.fms_commercial_bill bill_row
  where bill_row.id = p_bill_id
    and bill_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Commercial bill does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  for v_event in
    select event_row.id
    from public.fms_commercial_bill_event event_row
    where event_row.bill_id = p_bill_id
      and event_row.tenant_id = app_private.current_user_tenant_id()
    order by event_row.event_date, event_row.create_time, event_row.id
  loop
    v_result := v_result || jsonb_build_array(
      app_private.fms_commercial_bill_event_to_secure_json(
        (
          select to_jsonb(event_row) - 'tenant_id'
          from public.fms_commercial_bill_event event_row
          where event_row.id = v_event.id
            and event_row.tenant_id = app_private.current_user_tenant_id()
        ),
        v_owner_id
      )
    );
  end loop;
  return v_result;
end;
$$;

create or replace function public.fms_commercial_bill_summary_secure(
  p_account_set_id uuid,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb := app_private.field_access_map('fms.commercial_bill', null);
  v_amount_access text := coalesce(v_access->>'billAmounts', 'hidden');
  v_summary record;
begin
  if p_tenant_id is not null and p_tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant commercial bill summary access is forbidden'
      using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCommercialBill', null, null, false
  ) then
    raise exception 'Missing commercial bill menu permission'
      using errcode = '42501';
  end if;
  if p_account_set_id is null or not exists (
    select 1
    from public.fms_account_set account_set_row
    where account_set_row.id = p_account_set_id
      and account_set_row.tenant_id = v_tenant_id
  ) then
    raise exception 'Commercial bill account set is outside the current tenant'
      using errcode = '42501';
  end if;

  select
    count(*)::bigint as total_count,
    count(*) filter (where bill_row.status in ('draft', 'held'))::bigint as active_count,
    coalesce(sum(bill_row.face_amount - bill_row.settled_amount) filter (
      where bill_row.direction = 'receivable' and bill_row.status in ('draft', 'held')
    ), 0) as receivable_outstanding,
    coalesce(sum(bill_row.face_amount - bill_row.settled_amount) filter (
      where bill_row.direction = 'payable' and bill_row.status in ('draft', 'held')
    ), 0) as payable_outstanding,
    count(*) filter (
      where bill_row.status = 'held'
        and bill_row.due_date between current_date and current_date + 30
    )::bigint as due_within_30_days,
    count(*) filter (
      where bill_row.status = 'held' and bill_row.due_date < current_date
    )::bigint as overdue_count
  into v_summary
  from public.fms_commercial_bill bill_row
  where bill_row.tenant_id = v_tenant_id
    and bill_row.account_set_id = p_account_set_id;

  return jsonb_build_object(
    'total_count', v_summary.total_count,
    'active_count', v_summary.active_count,
    'receivable_outstanding', case
      when v_amount_access in ('read', 'edit') then to_jsonb(v_summary.receivable_outstanding)
      when v_amount_access = 'masked' then to_jsonb('***'::text)
      else 'null'::jsonb
    end,
    'payable_outstanding', case
      when v_amount_access in ('read', 'edit') then to_jsonb(v_summary.payable_outstanding)
      when v_amount_access = 'masked' then to_jsonb('***'::text)
      else 'null'::jsonb
    end,
    'due_within_30_days', v_summary.due_within_30_days,
    'overdue_count', v_summary.overdue_count,
    'field_access', v_access
  );
end;
$$;

create or replace function public.save_fms_commercial_bill_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_account_set_id uuid := nullif(p_payload->>'accountSetId', '')::uuid;
  v_existing public.fms_commercial_bill%rowtype;
  v_saved public.fms_commercial_bill%rowtype;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_access jsonb;
begin
  if v_account_set_id is null or not exists (
    select 1
    from public.fms_account_set account_set_row
    where account_set_row.id = v_account_set_id
      and account_set_row.tenant_id = v_tenant_id
  ) then
    raise exception 'Commercial bill account set is outside the current tenant'
      using errcode = '42501';
  end if;

  if v_id is not null then
    select *
    into v_existing
    from public.fms_commercial_bill bill_row
    where bill_row.id = v_id
      and bill_row.tenant_id = v_tenant_id
    for update;
    if not found then
      raise exception 'Commercial bill does not exist in the current tenant'
        using errcode = 'P0002';
    end if;
    v_access := app_private.field_access_map(
      'fms.commercial_bill', v_existing.created_by_user_id
    );

    if coalesce(v_access->>'billParties', 'hidden') <> 'edit' then
      if (v_payload ? 'drawerName'
          and nullif(btrim(v_payload->>'drawerName'), '') is distinct from v_existing.drawer_name)
         or (v_payload ? 'payeeName'
          and nullif(btrim(v_payload->>'payeeName'), '') is distinct from v_existing.payee_name)
         or (v_payload ? 'acceptorName'
          and nullif(btrim(v_payload->>'acceptorName'), '') is distinct from v_existing.acceptor_name)
         or (v_payload ? 'counterpartyName'
          and nullif(btrim(v_payload->>'counterpartyName'), '') is distinct from v_existing.counterparty_name) then
        raise exception 'Commercial bill party fields are not editable'
          using errcode = '42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'drawerName', v_existing.drawer_name,
        'payeeName', v_existing.payee_name,
        'acceptorName', v_existing.acceptor_name,
        'counterpartyName', v_existing.counterparty_name
      );
    end if;

    if coalesce(v_access->>'billAmounts', 'hidden') <> 'edit' then
      if v_payload ? 'faceAmount'
         and nullif(v_payload->>'faceAmount', '')::numeric is distinct from v_existing.face_amount then
        raise exception 'Commercial bill amount fields are not editable'
          using errcode = '42501';
      end if;
      v_payload := v_payload || jsonb_build_object('faceAmount', v_existing.face_amount);
    end if;

    if coalesce(v_access->>'billReferences', 'hidden') <> 'edit' then
      if (v_payload ? 'externalBillNo'
          and nullif(btrim(v_payload->>'externalBillNo'), '') is distinct from v_existing.external_bill_no)
         or (v_payload ? 'sourceType'
          and nullif(v_payload->>'sourceType', '') is distinct from v_existing.source_type)
         or (v_payload ? 'sourceId'
          and nullif(v_payload->>'sourceId', '')::uuid is distinct from v_existing.source_id)
         or (v_payload ? 'sourceNo'
          and nullif(btrim(v_payload->>'sourceNo'), '') is distinct from v_existing.source_no)
         or (v_payload ? 'attachmentIds'
          and coalesce(v_payload->'attachmentIds', '[]'::jsonb) is distinct from v_existing.attachment_ids) then
        raise exception 'Commercial bill reference fields are not editable'
          using errcode = '42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'externalBillNo', v_existing.external_bill_no,
        'sourceType', v_existing.source_type,
        'sourceId', v_existing.source_id,
        'sourceNo', v_existing.source_no,
        'attachmentIds', v_existing.attachment_ids
      );
    end if;
  end if;

  v_saved := public.save_fms_commercial_bill(v_payload);
  if v_saved.tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant commercial bill write is forbidden'
      using errcode = '42501';
  end if;
  return app_private.fms_commercial_bill_to_secure_json(
    app_private.fms_commercial_bill_raw_json(v_saved.id),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.act_fms_commercial_bill_secure(
  p_bill_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bill public.fms_commercial_bill%rowtype;
  v_saved public.fms_commercial_bill%rowtype;
  v_access jsonb;
begin
  select *
  into v_bill
  from public.fms_commercial_bill bill_row
  where bill_row.id = p_bill_id
    and bill_row.tenant_id = app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Commercial bill does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_access := app_private.field_access_map(
    'fms.commercial_bill', v_bill.created_by_user_id
  );
  if p_action in ('endorse', 'discount', 'settle')
     and coalesce(v_access->>'billAmounts', 'hidden') not in ('read', 'edit') then
    raise exception 'Commercial bill amount access is required for this action'
      using errcode = '42501';
  end if;
  if p_action in ('discount', 'settle')
     and coalesce(v_access->>'billReferences', 'hidden') <> 'edit' then
    raise exception 'Commercial bill settlement references are not editable'
      using errcode = '42501';
  end if;
  v_saved := public.act_fms_commercial_bill(p_bill_id, p_action, p_payload);
  return app_private.fms_commercial_bill_to_secure_json(
    app_private.fms_commercial_bill_raw_json(v_saved.id),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.delete_fms_commercial_bill_secure(p_bill_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.fms_commercial_bill bill_row
    where bill_row.id = p_bill_id
      and bill_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Commercial bill does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  perform public.delete_fms_commercial_bill(p_bill_id);
  return p_bill_id;
end;
$$;

revoke all on table public.fms_commercial_bill from anon, authenticated;
revoke all on table public.fms_commercial_bill_event from anon, authenticated;

revoke execute on function public.save_fms_commercial_bill(jsonb)
  from public, anon, authenticated;
revoke execute on function public.act_fms_commercial_bill(uuid, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.delete_fms_commercial_bill(uuid)
  from public, anon, authenticated;
revoke execute on function public.fms_commercial_bill_summary(uuid)
  from public, anon, authenticated;

revoke all on function public.fms_list_commercial_bills_secure(
  integer, integer, uuid, text, text, text, text, date, date, uuid
) from public, anon, authenticated;
revoke all on function public.fms_get_commercial_bill_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.fms_list_commercial_bill_events_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.fms_commercial_bill_summary_secure(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.save_fms_commercial_bill_secure(jsonb)
  from public, anon, authenticated;
revoke all on function public.act_fms_commercial_bill_secure(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.delete_fms_commercial_bill_secure(uuid)
  from public, anon, authenticated;

grant execute on function public.fms_list_commercial_bills_secure(
  integer, integer, uuid, text, text, text, text, date, date, uuid
) to authenticated;
grant execute on function public.fms_get_commercial_bill_secure(uuid)
  to authenticated;
grant execute on function public.fms_list_commercial_bill_events_secure(uuid)
  to authenticated;
grant execute on function public.fms_commercial_bill_summary_secure(uuid, uuid)
  to authenticated;
grant execute on function public.save_fms_commercial_bill_secure(jsonb)
  to authenticated;
grant execute on function public.act_fms_commercial_bill_secure(uuid, text, jsonb)
  to authenticated;
grant execute on function public.delete_fms_commercial_bill_secure(uuid)
  to authenticated;

do $$
begin
  if exists (
    select 1
    from public.sys_tenant tenant_row
    where not exists (
      select 1
      from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.commercial_bill'
        and resource_row.owner_column = 'created_by_user_id'
        and resource_row.enabled is true
    )
  ) then
    raise exception 'Missing fms.commercial_bill permission resource';
  end if;
  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.commercial_bill'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.tenant_id = resource_row.tenant_id
          and field_row.resource_id = resource_row.id
          and field_row.enabled is true
      ) <> 3
  ) then
    raise exception 'Unexpected fms.commercial_bill field catalog';
  end if;
  if has_table_privilege('authenticated', 'public.fms_commercial_bill', 'select')
     or has_table_privilege('authenticated', 'public.fms_commercial_bill_event', 'select')
     or has_table_privilege('anon', 'public.fms_commercial_bill', 'select')
     or has_table_privilege('anon', 'public.fms_commercial_bill_event', 'select') then
    raise exception 'Direct commercial bill reads remain exposed';
  end if;
  if has_function_privilege(
    'anon',
    'public.fms_list_commercial_bills_secure(integer,integer,uuid,text,text,text,text,date,date,uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.save_fms_commercial_bill_secure(jsonb)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.save_fms_commercial_bill(jsonb)',
    'execute'
  ) then
    raise exception 'Commercial bill function privileges are not secure';
  end if;
end;
$$;

;
