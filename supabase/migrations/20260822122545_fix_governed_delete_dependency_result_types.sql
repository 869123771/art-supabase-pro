-- Keep governed deletion usable when an optional business module is not installed.
-- Core governance resources are resolved in isolated branches so PostgreSQL does not
-- plan unrelated module tables. Module-owned dependencies are queried only when the
-- backing relation exists.
create or replace function public.get_governed_delete_dependency_details(
  p_resource_type text,
  p_resource_ids uuid[]
)
returns table(
  resource_id uuid,
  dependency_code text,
  record_id uuid,
  target_id uuid,
  record_no text,
  record_summary text,
  record_status text,
  record_amount numeric,
  created_at timestamptz,
  cleanup_allowed boolean
)
language plpgsql
stable
set search_path = ''
as $function$
begin
  if p_resource_type = any(array['carrier', 'driver', 'cargo', 'customer_address', 'vehicle']) then
    return query
    select *
    from public.get_master_data_delete_dependency_details(p_resource_type, p_resource_ids);
    return;
  end if;

  if p_resource_type = 'organization' then
    return query
    with requested as (
      select distinct unnest(coalesce(p_resource_ids, '{}'::uuid[])) as resource_id
    )
    select details.*
    from (
      select child.parent_id, 'organization_child'::text, child.id, child.id,
        child.organization_name, child.organization_code, child.status,
        null::numeric, child.create_time, false
      from public.sys_organization child
      join requested on requested.resource_id = child.parent_id

      union all

      select app_user.organization_id, 'organization_user', app_user.id, app_user.id,
        coalesce(nullif(app_user.nick_name, ''), app_user.user_name), app_user.user_email,
        app_user.status, null::numeric, app_user.create_time, false
      from public.sys_user app_user
      join requested on requested.resource_id = app_user.organization_id

      union all

      select role.organization_id, 'organization_role', role.id, role.id,
        role.role_name, role.role_code, case when role.enabled then 'enabled' else 'disabled' end,
        null::numeric, role.create_time, false
      from public.sys_role role
      join requested on requested.resource_id = role.organization_id
    ) details(
      resource_id,
      dependency_code,
      record_id,
      target_id,
      record_no,
      record_summary,
      record_status,
      record_amount,
      created_at,
      cleanup_allowed
    )
    order by details.resource_id, details.dependency_code, details.created_at desc, details.record_id;
    return;
  end if;

  if p_resource_type = 'role' then
    return query
    with requested as (
      select distinct unnest(coalesce(p_resource_ids, '{}'::uuid[])) as resource_id
    )
    select details.*
    from (
      select role_menu.role_id, 'role_menu_grant'::text, role_menu.id, role_menu.menu_id,
        coalesce(menu.meta ->> 'title', menu.name, role_menu.menu_id::text),
        coalesce(menu.path, role_menu.permission::text), null::text,
        null::numeric, role_menu.create_time, true
      from public.sys_role_menu role_menu
      join requested on requested.resource_id = role_menu.role_id
      left join public.sys_menu menu on menu.id = role_menu.menu_id

      union all

      select role.id, 'role_user_assignment', app_user.id, app_user.id,
        coalesce(nullif(app_user.nick_name, ''), app_user.user_name), app_user.user_email,
        app_user.status, null::numeric, app_user.create_time, true
      from public.sys_role role
      join requested on requested.resource_id = role.id
      join public.sys_user app_user
        on role.role_code = any(coalesce(app_user.user_roles, '{}'::text[]))
    ) details(
      resource_id,
      dependency_code,
      record_id,
      target_id,
      record_no,
      record_summary,
      record_status,
      record_amount,
      created_at,
      cleanup_allowed
    )
    order by details.resource_id, details.cleanup_allowed desc, details.dependency_code,
      details.created_at desc, details.record_id;
    return;
  end if;

  if p_resource_type = 'menu' then
    return query
    with requested as (
      select distinct unnest(coalesce(p_resource_ids, '{}'::uuid[])) as resource_id
    )
    select details.*
    from (
      select role_menu.menu_id, 'menu_role_grant'::text, role_menu.id, role_menu.role_id,
        role.role_name, role.role_code, case when role.enabled then 'enabled' else 'disabled' end,
        null::numeric, role_menu.create_time, true
      from public.sys_role_menu role_menu
      join requested on requested.resource_id = role_menu.menu_id
      left join public.sys_role role on role.id = role_menu.role_id

      union all

      select scene.menu_id, 'menu_document_number_scene', md5(scene.rule_key)::uuid, scene.menu_id,
        scene.rule_key, concat_ws(' · ', scene.rule_name, scene.target_table, scene.target_column),
        case when scene.enabled then 'enabled' else 'disabled' end,
        null::numeric, scene.create_time, false
      from public.sys_document_number_scene scene
      join requested on requested.resource_id = scene.menu_id
    ) details(
      resource_id,
      dependency_code,
      record_id,
      target_id,
      record_no,
      record_summary,
      record_status,
      record_amount,
      created_at,
      cleanup_allowed
    )
    order by details.resource_id, details.cleanup_allowed desc, details.dependency_code,
      details.created_at desc, details.record_id;
    return;
  end if;

  if p_resource_type = 'dict_type' then
    return query
    with requested as (
      select distinct unnest(coalesce(p_resource_ids, '{}'::uuid[])) as resource_id
    )
    select
      details.resource_id,
      details.dependency_code,
      details.record_id,
      details.target_id,
      details.record_no::text,
      details.record_summary::text,
      details.record_status::text,
      details.record_amount,
      details.created_at,
      details.cleanup_allowed
    from (
      select child.parent_id, 'dict_type_child'::text, child.id, child.id,
        child.name, child.code, child.status, null::numeric, child.create_time, false
      from public.sys_dict_type child
      join requested on requested.resource_id = child.parent_id

      union all

      select dictionary.type_id, 'dict_type_item', dictionary.id, dictionary.id,
        coalesce(nullif(dictionary.label, ''), dictionary.code), dictionary.value,
        dictionary.status, null::numeric, dictionary.create_time, true
      from public.sys_dictionary dictionary
      join requested on requested.resource_id = dictionary.type_id
    ) details(
      resource_id,
      dependency_code,
      record_id,
      target_id,
      record_no,
      record_summary,
      record_status,
      record_amount,
      created_at,
      cleanup_allowed
    )
    order by details.resource_id, details.cleanup_allowed desc, details.dependency_code,
      details.created_at desc, details.record_id;
    return;
  end if;

  if p_resource_type = 'dictionary' then
    return query
    with requested as (
      select distinct unnest(coalesce(p_resource_ids, '{}'::uuid[])) as resource_id
    )
    select child.parent_id, 'dictionary_child'::text, child.id, child.id,
      coalesce(nullif(child.label, ''), child.code)::text, child.value::text,
      child.status::text, null::numeric, child.create_time, true
    from public.sys_dictionary child
    join requested on requested.resource_id = child.parent_id
    order by child.parent_id, child.create_time desc, child.id;
    return;
  end if;

  if p_resource_type = 'attachment' then
    if to_regclass('public.tms_waybill_proof') is not null then
      return query execute $query$
        with requested as (
          select distinct unnest(coalesce($1, '{}'::uuid[])) as resource_id
        )
        select proof.attachment_id, 'attachment_waybill_proof'::text, proof.id, proof.waybill_id,
          coalesce(nullif(proof.file_name, ''), proof.id::text), proof.proof_type,
          null::text, null::numeric, proof.create_time, false
        from public.tms_waybill_proof proof
        join requested on requested.resource_id = proof.attachment_id
        order by proof.attachment_id, proof.create_time desc, proof.id
      $query$ using p_resource_ids;
    end if;
    return;
  end if;

  if p_resource_type = 'order' then
    if to_regclass('public.tms_waybill') is not null then
      return query execute $query$
        with requested as (
          select distinct unnest(coalesce($1, '{}'::uuid[])) as resource_id
        )
        select waybill.order_id, 'order_waybill'::text, waybill.id, waybill.id,
          waybill.waybill_no, concat_ws(' -> ', waybill.origin_city, waybill.destination_city),
          waybill.status, waybill.freight_amount, waybill.create_time, false
        from public.tms_waybill waybill
        join requested on requested.resource_id = waybill.order_id
        order by waybill.order_id, waybill.create_time desc, waybill.id
      $query$ using p_resource_ids;
    end if;

    if to_regclass('public.tms_in_transit_expense') is not null then
      return query execute $query$
        with requested as (
          select distinct unnest(coalesce($1, '{}'::uuid[])) as resource_id
        )
        select expense.order_id, 'order_expense'::text, expense.id, expense.id,
          expense.expense_no, expense.expense_type, expense.report_status,
          expense.amount, expense.create_time, false
        from public.tms_in_transit_expense expense
        join requested on requested.resource_id = expense.order_id
        order by expense.order_id, expense.create_time desc, expense.id
      $query$ using p_resource_ids;
    end if;

    if to_regclass('public.tms_receipt_exception_work_order') is not null then
      return query execute $query$
        with requested as (
          select distinct unnest(coalesce($1, '{}'::uuid[])) as resource_id
        )
        select work_order.order_id, 'order_receipt_work_order'::text,
          work_order.id, work_order.id, work_order.work_order_no, work_order.summary,
          work_order.status, null::numeric, work_order.create_time, false
        from public.tms_receipt_exception_work_order work_order
        join requested on requested.resource_id = work_order.order_id
        order by work_order.order_id, work_order.create_time desc, work_order.id
      $query$ using p_resource_ids;
    end if;

    if to_regclass('public.tms_customer_statement_item') is not null then
      return query execute $query$
        with requested as (
          select distinct unnest(coalesce($1, '{}'::uuid[])) as resource_id
        )
        select item.order_id, 'order_statement_item'::text, item.id, item.statement_id,
          coalesce(nullif(item.order_no_snapshot, ''), item.id::text),
          concat_ws(' -> ', item.origin_station_snapshot, item.destination_station_snapshot),
          case when item.is_active then 'active' else 'inactive' end,
          item.line_amount, item.create_time, false
        from public.tms_customer_statement_item item
        join requested on requested.resource_id = item.order_id
        order by item.order_id, item.create_time desc, item.id
      $query$ using p_resource_ids;
    end if;
    return;
  end if;
end;
$function$;

comment on function public.get_governed_delete_dependency_details(text, uuid[]) is
  'Returns governed delete dependencies without requiring unrelated optional module tables.';

;
