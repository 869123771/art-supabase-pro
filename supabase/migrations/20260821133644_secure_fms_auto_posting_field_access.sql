-- Secure automatic-posting rules and event payloads with tenant field permissions.
-- Existing button permission definitions and checks remain unchanged.

alter table public.fms_posting_rule
  add column if not exists created_by_user_id uuid;
alter table public.fms_posting_event
  add column if not exists created_by_user_id uuid;

with matched_creator as (
  select rule_row.id, (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = rule_row.tenant_id
      and lower(user_row.user_email) = lower(rule_row.create_by)
    order by user_row.create_time, user_row.id
    limit 1
  ) user_id
  from public.fms_posting_rule rule_row
  where rule_row.created_by_user_id is null
    and nullif(btrim(coalesce(rule_row.create_by, '')), '') is not null
)
update public.fms_posting_rule rule_row
set created_by_user_id = matched_creator.user_id
from matched_creator
where rule_row.id = matched_creator.id
  and matched_creator.user_id is not null;

with matched_creator as (
  select event_row.id, (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = event_row.tenant_id
      and lower(user_row.user_email) = lower(event_row.create_by)
    order by user_row.create_time, user_row.id
    limit 1
  ) user_id
  from public.fms_posting_event event_row
  where event_row.created_by_user_id is null
    and nullif(btrim(coalesce(event_row.create_by, '')), '') is not null
)
update public.fms_posting_event event_row
set created_by_user_id = matched_creator.user_id
from matched_creator
where event_row.id = matched_creator.id
  and matched_creator.user_id is not null;

create index if not exists fms_posting_rule_tenant_creator_idx
  on public.fms_posting_rule(tenant_id, created_by_user_id);
create index if not exists fms_posting_rule_creator_tenant_idx
  on public.fms_posting_rule(created_by_user_id, tenant_id)
  where created_by_user_id is not null;
create index if not exists fms_posting_event_tenant_creator_idx
  on public.fms_posting_event(tenant_id, created_by_user_id);
create index if not exists fms_posting_event_creator_tenant_idx
  on public.fms_posting_event(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

alter table public.fms_posting_rule
  drop constraint if exists fms_posting_rule_creator_tenant_fkey;
alter table public.fms_posting_rule
  add constraint fms_posting_rule_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);
alter table public.fms_posting_event
  drop constraint if exists fms_posting_event_creator_tenant_fkey;
alter table public.fms_posting_event
  add constraint fms_posting_event_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_auto_posting_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      if new.created_by_user_id is null then
        new.created_by_user_id := v_current_user_id;
      elsif new.created_by_user_id <> v_current_user_id then
        raise exception 'Automatic-posting creator must be the current user'
          using errcode = '42501';
      end if;
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
    raise exception 'Automatic-posting creator cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_posting_rule_creator_identity on public.fms_posting_rule;
create trigger fms_posting_rule_creator_identity
before insert or update of created_by_user_id on public.fms_posting_rule
for each row execute function app_private.set_fms_auto_posting_creator_identity();

drop trigger if exists fms_posting_event_creator_identity on public.fms_posting_event;
create trigger fms_posting_event_creator_identity
before insert or update of created_by_user_id on public.fms_posting_event
for each row execute function app_private.set_fms_auto_posting_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_auto_posting;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_auto_posting(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.auto_posting', '自动入账', 'FinanceAutoPosting',
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
      p_tenant_id, v_resource_id, 'ruleConfiguration',
      '制证科目、金额映射、匹配条件及辅助核算规则',
      'hidden', 'none', true, 10, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'eventAmounts',
      '业务事件金额、价格、成本、税额及生成凭证金额',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'eventPayloadDetails',
      '业务事件载荷中的客户、承运商、司机、发票及运单信息',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'eventSourceReferences',
      '来源单号、来源标识、事件摘要、命中规则及生成凭证引用',
      'hidden', 'none', true, 40, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'processingDiagnostics',
      '处理次数、异常原因、处理时间及操作审计信息',
      'hidden', 'none', true, 50, '624944977@qq.com', '624944977@qq.com'
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
 and menu_row.name = 'FinanceAutoPosting'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.auto_posting'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_fms_auto_posting_readable()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action('FinanceAutoPosting', null, null, false) then
    raise exception 'Missing automatic-posting menu permission' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.fms_posting_event_payload_to_secure_json(
  p_payload jsonb,
  p_amount_access text,
  p_detail_access text
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_result jsonb := '{}'::jsonb;
  v_item record;
  v_is_amount boolean;
begin
  for v_item in select key, value from jsonb_each(coalesce(p_payload, '{}'::jsonb))
  loop
    v_is_amount := v_item.key ~ '(_amount|_price|_value|_cost|_gain|_loss)$'
      or v_item.key in ('amount', 'price', 'freight', 'tax');
    if v_is_amount then
      if p_amount_access in ('read', 'edit') then
        v_result := v_result || jsonb_build_object(v_item.key, v_item.value);
      elsif p_amount_access = 'masked' then
        v_result := v_result || jsonb_build_object(v_item.key, '***');
      end if;
    else
      if p_detail_access in ('read', 'edit') then
        v_result := v_result || jsonb_build_object(v_item.key, v_item.value);
      elsif p_detail_access = 'masked' then
        v_result := v_result || jsonb_build_object(v_item.key, '***');
      end if;
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function app_private.fms_posting_rule_raw_json(
  p_rule_id uuid,
  p_include_lines boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    (to_jsonb(rule_row) - 'tenant_id' - 'created_by_user_id')
    || jsonb_build_object(
      'account_set', jsonb_build_object(
        'id', account_set_row.id,
        'account_set_code', account_set_row.account_set_code,
        'account_set_name', account_set_row.account_set_name
      )
    )
    || case when p_include_lines then jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(
          (to_jsonb(line_row) - 'tenant_id')
          || jsonb_build_object(
            'subject', jsonb_build_object(
              'id', subject_row.id,
              'subject_code', subject_row.subject_code,
              'subject_name', subject_row.subject_name
            )
          )
          order by line_row.line_no, line_row.id
        )
        from public.fms_posting_rule_line line_row
        join public.fms_subject subject_row
          on subject_row.id = line_row.subject_id
         and subject_row.tenant_id = line_row.tenant_id
         and subject_row.account_set_id = line_row.account_set_id
        where line_row.rule_id = rule_row.id
          and line_row.tenant_id = rule_row.tenant_id
      ), '[]'::jsonb)
    ) else '{}'::jsonb end
  from public.fms_posting_rule rule_row
  join public.fms_account_set account_set_row
    on account_set_row.id = rule_row.account_set_id
   and account_set_row.tenant_id = rule_row.tenant_id
  where rule_row.id = p_rule_id
    and rule_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_posting_rule_to_secure_json(
  p_rule_id uuid,
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
  v_access jsonb := app_private.field_access_map('fms.auto_posting', p_owner_id);
  v_config_access text := coalesce(v_access ->> 'ruleConfiguration', 'hidden');
  v_data jsonb := app_private.fms_posting_rule_raw_json(p_rule_id, p_include_lines);
begin
  if v_data is null then return null; end if;

  v_data := app_private.apply_jsonb_text_access(
    v_data, array['voucher_type', 'submission_mode', 'remark']::text[], v_config_access
  );
  if v_config_access = 'hidden' then
    v_data := v_data - 'match_conditions' - 'lines';
  elsif v_config_access = 'masked' then
    v_data := (v_data - 'match_conditions' - 'lines')
      || jsonb_build_object('configuration_masked', true);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_posting_event_raw_json(p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    (to_jsonb(event_row) - 'tenant_id' - 'created_by_user_id')
    || jsonb_build_object(
      'account_set', case when account_set_row.id is null then null else jsonb_build_object(
        'id', account_set_row.id,
        'account_set_code', account_set_row.account_set_code,
        'account_set_name', account_set_row.account_set_name
      ) end,
      'rule', case when rule_row.id is null then null else jsonb_build_object(
        'id', rule_row.id, 'rule_code', rule_row.rule_code, 'rule_name', rule_row.rule_name
      ) end,
      'voucher', case when voucher_row.id is null then null else jsonb_build_object(
        'id', voucher_row.id, 'voucher_no', voucher_row.voucher_no,
        'status', voucher_row.status, 'total_debit', voucher_row.total_debit
      ) end
    )
  from public.fms_posting_event event_row
  left join public.fms_account_set account_set_row
    on account_set_row.id = event_row.account_set_id
   and account_set_row.tenant_id = event_row.tenant_id
  left join public.fms_posting_rule rule_row
    on rule_row.id = event_row.rule_id
   and rule_row.tenant_id = event_row.tenant_id
  left join public.fms_voucher voucher_row
    on voucher_row.id = event_row.voucher_id
   and voucher_row.tenant_id = event_row.tenant_id
  where event_row.id = p_event_id
    and event_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_posting_event_to_secure_json(
  p_event_id uuid,
  p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.auto_posting', p_owner_id);
  v_amount_access text := coalesce(v_access ->> 'eventAmounts', 'hidden');
  v_payload_access text := coalesce(v_access ->> 'eventPayloadDetails', 'hidden');
  v_source_access text := coalesce(v_access ->> 'eventSourceReferences', 'hidden');
  v_diagnostic_access text := coalesce(v_access ->> 'processingDiagnostics', 'hidden');
  v_data jsonb := app_private.fms_posting_event_raw_json(p_event_id);
  v_relation jsonb;
begin
  if v_data is null then return null; end if;

  v_data := jsonb_set(
    v_data, '{payload}',
    app_private.fms_posting_event_payload_to_secure_json(
      v_data -> 'payload', v_amount_access, v_payload_access
    )
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'source_id', 'source_no', 'summary', 'rule_id', 'origin_voucher_id', 'voucher_id'
    ]::text[],
    v_source_access
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data, array['attempt_count']::text[], v_diagnostic_access
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['last_error', 'processed_at', 'create_by', 'update_by']::text[],
    v_diagnostic_access
  );

  if v_source_access = 'hidden' then
    v_data := v_data - 'rule' - 'voucher';
  elsif v_source_access = 'masked' then
    v_data := v_data || jsonb_build_object(
      'rule', case when v_data -> 'rule' is null then null else
        jsonb_build_object('id', '***', 'rule_code', '***', 'rule_name', '***') end,
      'voucher', case when v_data -> 'voucher' is null then null else
        jsonb_build_object('id', '***', 'voucher_no', '***', 'status', '***') end
    );
  elsif v_data -> 'voucher' is not null then
    v_relation := app_private.apply_jsonb_amount_access(
      v_data -> 'voucher', array['total_debit']::text[], v_amount_access
    );
    v_data := jsonb_set(v_data, '{voucher}', v_relation);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_posting_rules_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_source_type text default null,
  p_event_code text default null,
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
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  perform app_private.assert_fms_auto_posting_readable();
  if p_account_set_id is not null and not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = p_account_set_id and account_set.tenant_id = v_tenant_id
  ) then
    raise exception 'Posting-rule account set is outside the current tenant'
      using errcode = '42501';
  end if;
  v_to := least(v_to, v_from + 499);

  select count(*) into v_total
  from public.fms_posting_rule rule_row
  where rule_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or rule_row.account_set_id = p_account_set_id)
    and (p_source_type is null or rule_row.source_type = p_source_type)
    and (p_event_code is null or rule_row.event_code = p_event_code)
    and (p_is_enabled is null or rule_row.is_enabled = p_is_enabled)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or rule_row.rule_code ilike '%' || btrim(p_keyword) || '%'
      or rule_row.rule_name ilike '%' || btrim(p_keyword) || '%'
    );

  for v_row in
    select rule_row.id, rule_row.created_by_user_id
    from public.fms_posting_rule rule_row
    where rule_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or rule_row.account_set_id = p_account_set_id)
      and (p_source_type is null or rule_row.source_type = p_source_type)
      and (p_event_code is null or rule_row.event_code = p_event_code)
      and (p_is_enabled is null or rule_row.is_enabled = p_is_enabled)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or rule_row.rule_code ilike '%' || btrim(p_keyword) || '%'
        or rule_row.rule_name ilike '%' || btrim(p_keyword) || '%'
      )
    order by rule_row.priority, rule_row.rule_code, rule_row.id
    limit v_to - v_from + 1 offset v_from
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_posting_rule_to_secure_json(
        v_row.id, v_row.created_by_user_id, false
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records, 'total', v_total,
    'field_access', app_private.field_access_map('fms.auto_posting', null)
  );
end;
$$;

create or replace function public.fms_get_posting_rule_secure(p_rule_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_result jsonb;
begin
  perform app_private.assert_fms_auto_posting_readable();
  select rule_row.created_by_user_id into v_owner_id
  from public.fms_posting_rule rule_row
  where rule_row.id = p_rule_id
    and rule_row.tenant_id = app_private.current_user_tenant_id();
  if not found then raise exception 'Posting rule not found' using errcode = 'P0002'; end if;
  v_result := app_private.fms_posting_rule_to_secure_json(p_rule_id, v_owner_id, true);
  return v_result;
end;
$$;

create or replace function public.fms_list_posting_events_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_status text default null,
  p_source_type text default null,
  p_event_code text default null,
  p_date_from date default null,
  p_date_to date default null,
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
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_base_access jsonb := app_private.field_access_map('fms.auto_posting', null);
  v_source_searchable boolean;
  v_diagnostic_searchable boolean;
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  perform app_private.assert_fms_auto_posting_readable();
  if p_account_set_id is not null and not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = p_account_set_id and account_set.tenant_id = v_tenant_id
  ) then
    raise exception 'Posting-event account set is outside the current tenant'
      using errcode = '42501';
  end if;
  v_to := least(v_to, v_from + 499);
  v_source_searchable := coalesce(v_base_access ->> 'eventSourceReferences', 'hidden')
    in ('read', 'edit');
  v_diagnostic_searchable := coalesce(v_base_access ->> 'processingDiagnostics', 'hidden')
    in ('read', 'edit');

  select count(*) into v_total
  from public.fms_posting_event event_row
  where event_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or event_row.account_set_id = p_account_set_id)
    and (p_status is null or event_row.status = p_status)
    and (p_source_type is null or event_row.source_type = p_source_type)
    and (p_event_code is null or event_row.event_code = p_event_code)
    and (p_date_from is null or event_row.event_date >= p_date_from)
    and (p_date_to is null or event_row.event_date <= p_date_to)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or (v_source_searchable and (
        event_row.source_no ilike '%' || btrim(p_keyword) || '%'
        or event_row.summary ilike '%' || btrim(p_keyword) || '%'
      ))
      or (v_diagnostic_searchable and event_row.last_error ilike '%' || btrim(p_keyword) || '%')
    );

  for v_row in
    select event_row.id, event_row.created_by_user_id
    from public.fms_posting_event event_row
    where event_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or event_row.account_set_id = p_account_set_id)
      and (p_status is null or event_row.status = p_status)
      and (p_source_type is null or event_row.source_type = p_source_type)
      and (p_event_code is null or event_row.event_code = p_event_code)
      and (p_date_from is null or event_row.event_date >= p_date_from)
      and (p_date_to is null or event_row.event_date <= p_date_to)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or (v_source_searchable and (
          event_row.source_no ilike '%' || btrim(p_keyword) || '%'
          or event_row.summary ilike '%' || btrim(p_keyword) || '%'
        ))
        or (v_diagnostic_searchable and event_row.last_error ilike '%' || btrim(p_keyword) || '%')
      )
    order by event_row.event_date desc, event_row.create_time desc, event_row.id
    limit v_to - v_from + 1 offset v_from
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_posting_event_to_secure_json(v_row.id, v_row.created_by_user_id)
    );
  end loop;

  return jsonb_build_object(
    'records', v_records, 'total', v_total, 'field_access', v_base_access
  );
end;
$$;

create or replace function public.fms_get_posting_event_secure(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app_private.assert_fms_auto_posting_readable();
  select event_row.created_by_user_id into v_owner_id
  from public.fms_posting_event event_row
  where event_row.id = p_event_id
    and event_row.tenant_id = app_private.current_user_tenant_id();
  if not found then raise exception 'Posting event not found' using errcode = 'P0002'; end if;
  return app_private.fms_posting_event_to_secure_json(p_event_id, v_owner_id);
end;
$$;

create or replace function public.save_fms_posting_rule_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set_id uuid := nullif(p_payload ->> 'accountSetId', '')::uuid;
  v_owner_id uuid;
  v_saved public.fms_posting_rule%rowtype;
begin
  perform app_private.assert_fms_auto_posting_readable();
  if v_account_set_id is null or not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = v_account_set_id
      and account_set.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Posting-rule account set is outside the current tenant'
      using errcode = '42501';
  end if;
  if v_rule_id is null then
    v_owner_id := app_private.current_app_user_id();
  else
    select rule_row.created_by_user_id into v_owner_id
    from public.fms_posting_rule rule_row
    where rule_row.id = v_rule_id
      and rule_row.account_set_id = v_account_set_id
      and rule_row.tenant_id = app_private.current_user_tenant_id();
    if not found then raise exception 'Posting rule not found' using errcode = 'P0002'; end if;
  end if;
  if app_private.resolve_field_access(
    'fms.auto_posting', 'ruleConfiguration', v_owner_id
  ) <> 'edit' then
    raise exception 'Posting-rule configuration is not editable' using errcode = '42501';
  end if;
  v_saved := public.save_fms_posting_rule(p_payload);
  return app_private.fms_posting_rule_to_secure_json(
    v_saved.id, v_saved.created_by_user_id, true
  );
end;
$$;

create or replace function public.delete_fms_posting_rule_secure(p_rule_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app_private.assert_fms_auto_posting_readable();
  select rule_row.created_by_user_id into v_owner_id
  from public.fms_posting_rule rule_row
  where rule_row.id = p_rule_id
    and rule_row.tenant_id = app_private.current_user_tenant_id();
  if not found then raise exception 'Posting rule not found' using errcode = 'P0002'; end if;
  if app_private.resolve_field_access(
    'fms.auto_posting', 'ruleConfiguration', v_owner_id
  ) <> 'edit' then
    raise exception 'Posting-rule configuration is not editable' using errcode = '42501';
  end if;
  return public.delete_fms_posting_rule(p_rule_id);
end;
$$;

create or replace function public.retry_fms_posting_event_secure(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_saved public.fms_posting_event%rowtype;
begin
  perform app_private.assert_fms_auto_posting_readable();
  select event_row.created_by_user_id into v_owner_id
  from public.fms_posting_event event_row
  where event_row.id = p_event_id
    and event_row.tenant_id = app_private.current_user_tenant_id();
  if not found then raise exception 'Posting event not found' using errcode = 'P0002'; end if;
  if app_private.resolve_field_access(
    'fms.auto_posting', 'processingDiagnostics', v_owner_id
  ) <> 'edit' then
    raise exception 'Posting-event diagnostics are not editable' using errcode = '42501';
  end if;
  v_saved := public.retry_fms_posting_event(p_event_id);
  return app_private.fms_posting_event_to_secure_json(v_saved.id, v_owner_id);
end;
$$;

create or replace function public.process_pending_fms_posting_events_secure(
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_records jsonb;
begin
  perform app_private.assert_fms_auto_posting_readable();
  if app_private.resolve_field_access(
    'fms.auto_posting', 'processingDiagnostics', null
  ) <> 'edit' then
    raise exception 'Posting-event diagnostics are not editable' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(result_row)), '[]'::jsonb) into v_records
  from public.process_pending_fms_posting_events(p_limit) result_row;
  return v_records;
end;
$$;

create or replace function public.fms_accounting_workload_summary_secure(
  p_account_set_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('FinanceWorkbench', null, null, false) then
    raise exception 'Missing finance-workbench menu permission' using errcode = '42501';
  end if;
  if p_account_set_id is not null and not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = p_account_set_id and account_set.tenant_id = v_tenant_id
  ) then
    raise exception 'Accounting workload account set is outside the current tenant'
      using errcode = '42501';
  end if;
  return jsonb_build_object(
    'failed_posting_event_count', (
      select count(*) from public.fms_posting_event event_row
      where event_row.tenant_id = v_tenant_id and event_row.status = 'failed'
        and (p_account_set_id is null or event_row.account_set_id = p_account_set_id)
    ),
    'pending_configuration_event_count', (
      select count(*) from public.fms_posting_event event_row
      where event_row.tenant_id = v_tenant_id and event_row.status = 'pending_configuration'
        and (p_account_set_id is null or event_row.account_set_id = p_account_set_id)
    ),
    'pending_posting_event_count', (
      select count(*) from public.fms_posting_event event_row
      where event_row.tenant_id = v_tenant_id and event_row.status = 'pending'
        and (p_account_set_id is null or event_row.account_set_id = p_account_set_id)
    ),
    'pending_voucher_review_count', (
      select count(*) from public.fms_voucher voucher_row
      where voucher_row.tenant_id = v_tenant_id and voucher_row.status = 'pending_review'
        and (p_account_set_id is null or voucher_row.account_set_id = p_account_set_id)
    ),
    'approved_voucher_count', (
      select count(*) from public.fms_voucher voucher_row
      where voucher_row.tenant_id = v_tenant_id and voucher_row.status = 'approved'
        and (p_account_set_id is null or voucher_row.account_set_id = p_account_set_id)
    ),
    'closing_period_count', (
      select count(*) from public.fms_accounting_period period_row
      where period_row.tenant_id = v_tenant_id and period_row.status = 'closing'
        and (p_account_set_id is null or period_row.account_set_id = p_account_set_id)
    )
  );
end;
$$;

revoke select, insert, update, delete on table public.fms_posting_rule
  from anon, authenticated;
revoke select, insert, update, delete on table public.fms_posting_rule_line
  from anon, authenticated;
revoke select, insert, update, delete on table public.fms_posting_event
  from anon, authenticated;

revoke execute on function public.save_fms_posting_rule(jsonb)
  from public, anon, authenticated;
revoke execute on function public.delete_fms_posting_rule(uuid)
  from public, anon, authenticated;
revoke execute on function public.retry_fms_posting_event(uuid)
  from public, anon, authenticated;
revoke execute on function public.process_pending_fms_posting_events(integer)
  from public, anon, authenticated;

grant execute on function public.fms_list_posting_rules_secure(
  integer, integer, uuid, text, text, boolean, text
) to authenticated;
grant execute on function public.fms_get_posting_rule_secure(uuid) to authenticated;
grant execute on function public.fms_list_posting_events_secure(
  integer, integer, uuid, text, text, text, date, date, text
) to authenticated;
grant execute on function public.fms_get_posting_event_secure(uuid) to authenticated;
grant execute on function public.save_fms_posting_rule_secure(jsonb) to authenticated;
grant execute on function public.delete_fms_posting_rule_secure(uuid) to authenticated;
grant execute on function public.retry_fms_posting_event_secure(uuid) to authenticated;
grant execute on function public.process_pending_fms_posting_events_secure(integer)
  to authenticated;
grant execute on function public.fms_accounting_workload_summary_secure(uuid)
  to authenticated;

revoke execute on function public.fms_list_posting_rules_secure(
  integer, integer, uuid, text, text, boolean, text
) from public, anon;
revoke execute on function public.fms_get_posting_rule_secure(uuid) from public, anon;
revoke execute on function public.fms_list_posting_events_secure(
  integer, integer, uuid, text, text, text, date, date, text
) from public, anon;
revoke execute on function public.fms_get_posting_event_secure(uuid) from public, anon;
revoke execute on function public.save_fms_posting_rule_secure(jsonb) from public, anon;
revoke execute on function public.delete_fms_posting_rule_secure(uuid) from public, anon;
revoke execute on function public.retry_fms_posting_event_secure(uuid) from public, anon;
revoke execute on function public.process_pending_fms_posting_events_secure(integer)
  from public, anon;
revoke execute on function public.fms_accounting_workload_summary_secure(uuid)
  from public, anon;

revoke execute on function app_private.set_fms_auto_posting_creator_identity()
  from public, anon, authenticated;
revoke execute on function app_private.assert_fms_auto_posting_readable()
  from public, anon, authenticated;
revoke execute on function app_private.fms_posting_event_payload_to_secure_json(jsonb,text,text)
  from public, anon, authenticated;
revoke execute on function app_private.fms_posting_rule_raw_json(uuid,boolean)
  from public, anon, authenticated;
revoke execute on function app_private.fms_posting_rule_to_secure_json(uuid,uuid,boolean)
  from public, anon, authenticated;
revoke execute on function app_private.fms_posting_event_raw_json(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.fms_posting_event_to_secure_json(uuid,uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_auto_posting(uuid)
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
        and resource_row.resource_key = 'fms.auto_posting'
        and resource_row.owner_column = 'created_by_user_id'
    )
  ) then
    raise exception 'Missing fms.auto_posting permission resource';
  end if;
  if exists (
    select 1 from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.auto_posting'
      and (
        select count(*) from public.sys_permission_field field_row
        where field_row.resource_id = resource_row.id
          and field_row.enabled
          and field_row.field_key in (
            'ruleConfiguration', 'eventAmounts', 'eventPayloadDetails',
            'eventSourceReferences', 'processingDiagnostics'
          )
      ) <> 5
  ) then
    raise exception 'Unexpected fms.auto_posting field catalog';
  end if;
end;
$$;

;
