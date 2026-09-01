-- Secure voucher-template narratives, entry definitions and maintenance audit fields.
-- Existing menu/button permission definitions and checks remain unchanged.

alter table public.fms_voucher_template
  add column if not exists created_by_user_id uuid;

with matched_creator as (
  select template_row.id, (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = template_row.tenant_id
      and lower(user_row.user_email) = lower(template_row.create_by)
    order by user_row.create_time, user_row.id
    limit 1
  ) user_id
  from public.fms_voucher_template template_row
  where template_row.created_by_user_id is null
    and nullif(btrim(coalesce(template_row.create_by, '')), '') is not null
)
update public.fms_voucher_template template_row
set created_by_user_id = matched_creator.user_id
from matched_creator
where template_row.id = matched_creator.id
  and matched_creator.user_id is not null;

create index if not exists fms_voucher_template_tenant_creator_idx
  on public.fms_voucher_template(tenant_id, created_by_user_id);
create index if not exists fms_voucher_template_creator_tenant_idx
  on public.fms_voucher_template(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

alter table public.fms_voucher_template
  drop constraint if exists fms_voucher_template_creator_tenant_fkey;
alter table public.fms_voucher_template
  add constraint fms_voucher_template_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_voucher_template_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null and v_current_tenant_id = new.tenant_id then
      if new.created_by_user_id is null then
        new.created_by_user_id := v_current_user_id;
      elsif new.created_by_user_id <> v_current_user_id then
        raise exception 'Voucher-template creator must be the current user'
          using errcode = '42501';
      end if;
    elsif v_current_user_id is not null and not app_private.is_platform_super() then
      raise exception 'Voucher-template tenant must match the current user tenant'
        using errcode = '42501';
    elsif new.created_by_user_id is null
      and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Voucher-template creator cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_voucher_template_creator_identity on public.fms_voucher_template;
create trigger fms_voucher_template_creator_identity
before insert or update of created_by_user_id on public.fms_voucher_template
for each row execute function app_private.set_fms_voucher_template_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_voucher_template;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_voucher_template(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.voucher_template', '凭证模板', 'FinanceVoucherTemplate',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (
      p_tenant_id, v_resource_id, 'templateNarrative',
      '默认摘要及模板说明',
      'hidden', 'none', true, 10, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'templateEntries',
      '凭证类型、科目方向、核算维度及默认金额',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'maintenanceAudit',
      '创建维护人员、时间及版本审计',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com'
    )
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

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id, role_menu.role_id, resource_row.id, field_row.id,
  'edit', '624944977@qq.com', '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'FinanceVoucherTemplate'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.voucher_template'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_fms_voucher_template_readable()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action(
    'FinanceVoucherTemplate', null, null, false
  ) then
    raise exception 'Missing voucher-template menu permission' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.fms_voucher_template_to_secure_json(
  p_template_id uuid,
  p_owner_id uuid,
  p_include_lines boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.voucher_template', p_owner_id);
  v_narrative_access text := coalesce(v_access ->> 'templateNarrative', 'hidden');
  v_entry_access text := coalesce(v_access ->> 'templateEntries', 'hidden');
  v_audit_access text := coalesce(v_access ->> 'maintenanceAudit', 'hidden');
  v_data jsonb;
  v_lines jsonb;
  v_line_count bigint;
begin
  select to_jsonb(template_row) - 'created_by_user_id'
    into v_data
  from public.fms_voucher_template template_row
  where template_row.id = p_template_id
    and (
      app_private.is_platform_super()
      or template_row.tenant_id = app_private.current_user_tenant_id()
    );
  if v_data is null then return null; end if;

  v_data := app_private.apply_jsonb_text_access(
    v_data, array['summary', 'remark']::text[], v_narrative_access
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data, array['voucher_type']::text[], v_entry_access
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['version', 'create_by', 'create_time', 'update_by', 'update_time']::text[],
    v_audit_access
  );

  if p_include_lines and v_entry_access <> 'hidden' then
    select count(*) into v_line_count
    from public.fms_voucher_template_line line_row
    where line_row.template_id = p_template_id;

    if v_entry_access = 'masked' then
      v_data := v_data || jsonb_build_object(
        'lines', '***',
        'line_count', v_line_count
      );
    else
      select coalesce(jsonb_agg(
        (to_jsonb(line_row)
          - 'tenant_id' - 'create_by' - 'create_time' - 'update_by' - 'update_time')
        || jsonb_build_object(
          'subject', jsonb_build_object(
            'id', subject_row.id,
            'subject_code', subject_row.subject_code,
            'subject_name', subject_row.subject_name
          ),
          'currency', case when currency_row.id is null then null else jsonb_build_object(
            'id', currency_row.id,
            'currency_code', currency_row.currency_code,
            'currency_name', currency_row.currency_name
          ) end
        ) order by line_row.line_no
      ), '[]'::jsonb)
      into v_lines
      from public.fms_voucher_template_line line_row
      join public.fms_subject subject_row
        on subject_row.id = line_row.subject_id
       and subject_row.account_set_id = line_row.account_set_id
       and subject_row.tenant_id = line_row.tenant_id
      left join public.fms_currency currency_row
        on currency_row.id = line_row.currency_id
       and currency_row.account_set_id = line_row.account_set_id
       and currency_row.tenant_id = line_row.tenant_id
      where line_row.template_id = p_template_id;
      v_data := v_data || jsonb_build_object(
        'lines', v_lines,
        'line_count', v_line_count
      );
    end if;
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_voucher_templates_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_voucher_type text default null,
  p_is_enabled boolean default null,
  p_keyword text default null
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
  v_limit integer := least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1), 1000);
  v_keyword text := nullif(btrim(p_keyword), '');
  v_narrative_access text := app_private.resolve_field_access(
    'fms.voucher_template', 'templateNarrative', null
  );
  v_entry_access text := app_private.resolve_field_access(
    'fms.voucher_template', 'templateEntries', null
  );
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  perform app_private.assert_fms_voucher_template_readable();
  if p_account_set_id is not null and not exists (
    select 1 from public.fms_account_set account_set_row
    where account_set_row.id = p_account_set_id
      and (app_private.is_platform_super() or account_set_row.tenant_id = v_tenant_id)
  ) then
    raise exception 'Voucher-template account set is outside the current tenant'
      using errcode = '42501';
  end if;

  select count(*) into v_total
  from public.fms_voucher_template template_row
  where (app_private.is_platform_super() or template_row.tenant_id = v_tenant_id)
    and (p_account_set_id is null or template_row.account_set_id = p_account_set_id)
    and (
      p_voucher_type is null
      or (
        v_entry_access in ('read', 'edit')
        and template_row.voucher_type = p_voucher_type
      )
    )
    and (p_is_enabled is null or template_row.is_enabled = p_is_enabled)
    and (
      v_keyword is null
      or template_row.template_code ilike '%' || v_keyword || '%'
      or template_row.template_name ilike '%' || v_keyword || '%'
      or (
        v_narrative_access in ('read', 'edit')
        and template_row.summary ilike '%' || v_keyword || '%'
      )
    );

  for v_row in
    select template_row.id, template_row.created_by_user_id
    from public.fms_voucher_template template_row
    where (app_private.is_platform_super() or template_row.tenant_id = v_tenant_id)
      and (p_account_set_id is null or template_row.account_set_id = p_account_set_id)
      and (
        p_voucher_type is null
        or (
          v_entry_access in ('read', 'edit')
          and template_row.voucher_type = p_voucher_type
        )
      )
      and (p_is_enabled is null or template_row.is_enabled = p_is_enabled)
      and (
        v_keyword is null
        or template_row.template_code ilike '%' || v_keyword || '%'
        or template_row.template_name ilike '%' || v_keyword || '%'
        or (
          v_narrative_access in ('read', 'edit')
          and template_row.summary ilike '%' || v_keyword || '%'
        )
      )
    order by template_row.sort, template_row.template_code
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_voucher_template_to_secure_json(
        v_row.id, v_row.created_by_user_id, false
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', app_private.field_access_map('fms.voucher_template', null)
  );
end;
$$;

create or replace function public.fms_get_voucher_template_secure(p_template_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app_private.assert_fms_voucher_template_readable();
  select template_row.created_by_user_id into v_owner_id
  from public.fms_voucher_template template_row
  where template_row.id = p_template_id
    and (
      app_private.is_platform_super()
      or template_row.tenant_id = app_private.current_user_tenant_id()
    );
  if not found then
    raise exception 'Voucher template not found' using errcode = 'P0002';
  end if;
  return app_private.fms_voucher_template_to_secure_json(
    p_template_id, v_owner_id, true
  );
end;
$$;

create or replace function public.save_fms_voucher_template_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_template_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set_id uuid := nullif(p_payload ->> 'accountSetId', '')::uuid;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_owner_id uuid;
  v_current public.fms_voucher_template%rowtype;
  v_narrative_access text;
  v_entry_access text;
  v_lines jsonb;
  v_safe_payload jsonb;
  v_saved public.fms_voucher_template%rowtype;
begin
  perform app_private.assert_fms_voucher_template_readable();

  if v_template_id is null then
    if v_account_set_id is null or not exists (
      select 1 from public.fms_account_set account_set_row
      where account_set_row.id = v_account_set_id
        and (app_private.is_platform_super() or account_set_row.tenant_id = v_tenant_id)
    ) then
      raise exception 'Voucher-template account set is outside the current tenant'
        using errcode = '42501';
    end if;
    select account_set_row.tenant_id into v_tenant_id
    from public.fms_account_set account_set_row
    where account_set_row.id = v_account_set_id;
    if app_private.current_user_tenant_id() = v_tenant_id then
      v_owner_id := app_private.current_app_user_id();
    end if;
  else
    select template_row.* into v_current
    from public.fms_voucher_template template_row
    where template_row.id = v_template_id
      and (
        app_private.is_platform_super()
        or template_row.tenant_id = v_tenant_id
      )
    for update;
    if not found then
      raise exception 'Voucher template not found' using errcode = 'P0002';
    end if;
    if v_account_set_id is not null and v_account_set_id <> v_current.account_set_id then
      raise exception 'Voucher-template account set cannot be changed' using errcode = '23514';
    end if;
    v_account_set_id := v_current.account_set_id;
    v_tenant_id := v_current.tenant_id;
    v_owner_id := v_current.created_by_user_id;
  end if;

  v_narrative_access := app_private.resolve_field_access(
    'fms.voucher_template', 'templateNarrative', v_owner_id
  );
  v_entry_access := app_private.resolve_field_access(
    'fms.voucher_template', 'templateEntries', v_owner_id
  );

  if v_template_id is null then
    if v_narrative_access <> 'edit' or v_entry_access <> 'edit' then
      raise exception 'New voucher-template sensitive fields are not editable'
        using errcode = '42501';
    end if;
    v_safe_payload := p_payload || jsonb_build_object('accountSetId', v_account_set_id);
  else
    if v_entry_access = 'edit' and p_payload ? 'lines' then
      v_lines := p_payload -> 'lines';
    else
      select coalesce(jsonb_agg(jsonb_build_object(
        'lineNo', line_row.line_no,
        'summary', line_row.summary,
        'subjectId', line_row.subject_id,
        'entryDirection', line_row.entry_direction,
        'defaultAmount', line_row.default_amount,
        'auxiliaryValues', line_row.auxiliary_values,
        'currencyId', line_row.currency_id,
        'exchangeRate', line_row.exchange_rate,
        'quantity', line_row.quantity
      ) order by line_row.line_no), '[]'::jsonb)
      into v_lines
      from public.fms_voucher_template_line line_row
      where line_row.template_id = v_template_id;
    end if;

    v_safe_payload := jsonb_build_object(
      'id', v_current.id,
      'accountSetId', v_current.account_set_id,
      'templateCode', case when p_payload ? 'templateCode'
        then p_payload -> 'templateCode' else to_jsonb(v_current.template_code) end,
      'templateName', case when p_payload ? 'templateName'
        then p_payload -> 'templateName' else to_jsonb(v_current.template_name) end,
      'voucherType', case
        when v_entry_access = 'edit' and p_payload ? 'voucherType'
          then p_payload -> 'voucherType'
        else to_jsonb(v_current.voucher_type) end,
      'summary', case
        when v_narrative_access = 'edit' and p_payload ? 'summary'
          then p_payload -> 'summary'
        else to_jsonb(v_current.summary) end,
      'isEnabled', case when p_payload ? 'isEnabled'
        then p_payload -> 'isEnabled' else to_jsonb(v_current.is_enabled) end,
      'sort', case when p_payload ? 'sort'
        then p_payload -> 'sort' else to_jsonb(v_current.sort) end,
      'remark', case
        when v_narrative_access = 'edit' and p_payload ? 'remark'
          then p_payload -> 'remark'
        else to_jsonb(v_current.remark) end,
      'lines', v_lines
    );
  end if;

  v_saved := public.save_fms_voucher_template(v_safe_payload);
  return app_private.fms_voucher_template_to_secure_json(
    v_saved.id, v_saved.created_by_user_id, true
  );
end;
$$;

create or replace function public.delete_fms_voucher_template_secure(p_template_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.assert_fms_voucher_template_readable();
  if not exists (
    select 1 from public.fms_voucher_template template_row
    where template_row.id = p_template_id
      and (
        app_private.is_platform_super()
        or template_row.tenant_id = app_private.current_user_tenant_id()
      )
  ) then
    raise exception 'Voucher template not found' using errcode = 'P0002';
  end if;
  perform public.delete_fms_voucher_template(p_template_id);
end;
$$;

revoke all privileges on table public.fms_voucher_template from anon, authenticated;
revoke all privileges on table public.fms_voucher_template_line from anon, authenticated;

revoke execute on function public.save_fms_voucher_template(jsonb)
  from public, anon, authenticated;
revoke execute on function public.delete_fms_voucher_template(uuid)
  from public, anon, authenticated;

grant execute on function public.fms_list_voucher_templates_secure(integer,integer,uuid,text,boolean,text)
  to authenticated;
grant execute on function public.fms_get_voucher_template_secure(uuid)
  to authenticated;
grant execute on function public.save_fms_voucher_template_secure(jsonb)
  to authenticated;
grant execute on function public.delete_fms_voucher_template_secure(uuid)
  to authenticated;

revoke execute on function public.fms_list_voucher_templates_secure(integer,integer,uuid,text,boolean,text)
  from public, anon;
revoke execute on function public.fms_get_voucher_template_secure(uuid)
  from public, anon;
revoke execute on function public.save_fms_voucher_template_secure(jsonb)
  from public, anon;
revoke execute on function public.delete_fms_voucher_template_secure(uuid)
  from public, anon;

revoke execute on function app_private.set_fms_voucher_template_creator_identity()
  from public, anon, authenticated;
revoke execute on function app_private.assert_fms_voucher_template_readable()
  from public, anon, authenticated;
revoke execute on function app_private.fms_voucher_template_to_secure_json(uuid,uuid,boolean)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_voucher_template(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog(uuid)
  from public, anon, authenticated;

do $$
begin
  if exists (
    select 1 from public.sys_tenant tenant_row
    where not exists (
      select 1 from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.voucher_template'
        and resource_row.owner_column = 'created_by_user_id'
    )
  ) then
    raise exception 'Missing fms.voucher_template permission resource';
  end if;
  if exists (
    select 1 from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.voucher_template'
      and (
        select count(*) from public.sys_permission_field field_row
        where field_row.resource_id = resource_row.id
          and field_row.enabled
          and field_row.field_key in (
            'templateNarrative', 'templateEntries', 'maintenanceAudit'
          )
      ) <> 3
  ) then
    raise exception 'Unexpected fms.voucher_template field catalog';
  end if;
end;
$$;

;
