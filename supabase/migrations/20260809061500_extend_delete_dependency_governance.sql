create or replace function public.get_governed_delete_dependency_details(
  p_resource_type text,
  p_resource_ids uuid[]
)
returns table (
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
security invoker
set search_path = ''
as $$
begin
  if p_resource_type = any(array['carrier', 'driver', 'cargo', 'customer_address', 'vehicle']) then
    return query
    select *
    from public.get_master_data_delete_dependency_details(p_resource_type, p_resource_ids);
    return;
  end if;

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
    where p_resource_type = 'organization'

    union all

    select app_user.organization_id, 'organization_user', app_user.id, app_user.id,
      coalesce(nullif(app_user.nick_name, ''), app_user.user_name), app_user.user_email,
      app_user.status, null::numeric, app_user.create_time, false
    from public.sys_user app_user
    join requested on requested.resource_id = app_user.organization_id
    where p_resource_type = 'organization'

    union all

    select role.organization_id, 'organization_role', role.id, role.id,
      role.role_name, role.role_code, case when role.enabled then 'enabled' else 'disabled' end,
      null::numeric, role.create_time, false
    from public.sys_role role
    join requested on requested.resource_id = role.organization_id
    where p_resource_type = 'organization'

    union all

    select role_menu.role_id, 'role_menu_grant', role_menu.id, role_menu.menu_id,
      coalesce(menu.meta ->> 'title', menu.name, role_menu.menu_id::text),
      coalesce(menu.path, role_menu.permission::text), null::text,
      null::numeric, role_menu.create_time, true
    from public.sys_role_menu role_menu
    join requested on requested.resource_id = role_menu.role_id
    left join public.sys_menu menu on menu.id = role_menu.menu_id
    where p_resource_type = 'role'

    union all

    select role.id, 'role_user_assignment', app_user.id, app_user.id,
      coalesce(nullif(app_user.nick_name, ''), app_user.user_name), app_user.user_email,
      app_user.status, null::numeric, app_user.create_time, true
    from public.sys_role role
    join requested on requested.resource_id = role.id
    join public.sys_user app_user on role.role_code = any(coalesce(app_user.user_roles, '{}'::text[]))
    where p_resource_type = 'role'

    union all

    select role_menu.menu_id, 'menu_role_grant', role_menu.id, role_menu.role_id,
      role.role_name, role.role_code, case when role.enabled then 'enabled' else 'disabled' end,
      null::numeric, role_menu.create_time, true
    from public.sys_role_menu role_menu
    join requested on requested.resource_id = role_menu.menu_id
    left join public.sys_role role on role.id = role_menu.role_id
    where p_resource_type = 'menu'

    union all

    select scene.menu_id, 'menu_document_number_scene', md5(scene.rule_key)::uuid, scene.menu_id,
      scene.rule_key, concat_ws(' · ', scene.rule_name, scene.target_table, scene.target_column),
      case when scene.enabled then 'enabled' else 'disabled' end,
      null::numeric, scene.create_time, false
    from public.sys_document_number_scene scene
    join requested on requested.resource_id = scene.menu_id
    where p_resource_type = 'menu'

    union all

    select child.parent_id, 'dict_type_child', child.id, child.id,
      child.name, child.code, child.status, null::numeric, child.create_time, false
    from public.sys_dict_type child
    join requested on requested.resource_id = child.parent_id
    where p_resource_type = 'dict_type'

    union all

    select dictionary.type_id, 'dict_type_item', dictionary.id, dictionary.id,
      coalesce(nullif(dictionary.label, ''), dictionary.code), dictionary.value,
      dictionary.status, null::numeric, dictionary.create_time, true
    from public.sys_dictionary dictionary
    join requested on requested.resource_id = dictionary.type_id
    where p_resource_type = 'dict_type'

    union all

    select child.parent_id, 'dictionary_child', child.id, child.id,
      coalesce(nullif(child.label, ''), child.code), child.value,
      child.status, null::numeric, child.create_time, true
    from public.sys_dictionary child
    join requested on requested.resource_id = child.parent_id
    where p_resource_type = 'dictionary'

    union all

    select proof.attachment_id, 'attachment_waybill_proof', proof.id, proof.waybill_id,
      coalesce(nullif(proof.file_name, ''), proof.id::text), proof.proof_type,
      null::text, null::numeric, proof.create_time, false
    from public.tms_waybill_proof proof
    join requested on requested.resource_id = proof.attachment_id
    where p_resource_type = 'attachment'

    union all

    select waybill.order_id, 'order_waybill', waybill.id, waybill.id,
      waybill.waybill_no, concat_ws(' -> ', waybill.origin_city, waybill.destination_city),
      waybill.status, waybill.freight_amount, waybill.create_time, false
    from public.tms_waybill waybill
    join requested on requested.resource_id = waybill.order_id
    where p_resource_type = 'order'

    union all

    select expense.order_id, 'order_expense', expense.id, expense.id,
      expense.expense_no, expense.expense_type, expense.report_status,
      expense.amount, expense.create_time, false
    from public.tms_in_transit_expense expense
    join requested on requested.resource_id = expense.order_id
    where p_resource_type = 'order'

    union all

    select work_order.order_id, 'order_receipt_work_order', work_order.id, work_order.id,
      work_order.work_order_no, work_order.summary, work_order.status,
      null::numeric, work_order.create_time, false
    from public.tms_receipt_exception_work_order work_order
    join requested on requested.resource_id = work_order.order_id
    where p_resource_type = 'order'

    union all

    select item.order_id, 'order_statement_item', item.id, item.statement_id,
      coalesce(nullif(item.order_no_snapshot, ''), item.id::text),
      concat_ws(' -> ', item.origin_station_snapshot, item.destination_station_snapshot),
      case when item.is_active then 'active' else 'inactive' end,
      item.line_amount, item.create_time, false
    from public.tms_customer_statement_item item
    join requested on requested.resource_id = item.order_id
    where p_resource_type = 'order'
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
end;
$$;

comment on function public.get_governed_delete_dependency_details(text, uuid[]) is
  'Returns exact tenant-scoped dependency details for governed deletion across TMS, vehicle, system, and data-center resources.';

revoke all on function public.get_governed_delete_dependency_details(text, uuid[]) from public, anon;
grant execute on function public.get_governed_delete_dependency_details(text, uuid[]) to authenticated;

create or replace function public.cleanup_governed_delete_dependencies(
  p_resource_type text,
  p_resource_ids uuid[],
  p_dependency_code text,
  p_record_ids uuid[]
)
returns bigint
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  affected_count bigint := 0;
begin
  if coalesce(array_length(p_resource_ids, 1), 0) = 0
    or coalesce(array_length(p_record_ids, 1), 0) = 0 then
    return 0;
  end if;

  if p_resource_type = any(array['carrier', 'driver', 'cargo', 'customer_address', 'vehicle']) then
    return public.cleanup_master_data_delete_dependencies(
      p_resource_type,
      p_resource_ids,
      p_dependency_code,
      p_record_ids
    );
  end if;

  if p_resource_type = 'role' and p_dependency_code = 'role_menu_grant' then
    delete from public.sys_role_menu role_menu
    where role_menu.role_id = any(p_resource_ids)
      and role_menu.id = any(p_record_ids);
    get diagnostics affected_count = row_count;
    return affected_count;
  end if;

  if p_resource_type = 'role' and p_dependency_code = 'role_user_assignment' then
    update public.sys_user app_user
    set user_roles = array_remove(app_user.user_roles, role.role_code)
    from public.sys_role role
    where role.id = any(p_resource_ids)
      and app_user.id = any(p_record_ids)
      and role.role_code = any(coalesce(app_user.user_roles, '{}'::text[]));
    get diagnostics affected_count = row_count;
    return affected_count;
  end if;

  if p_resource_type = 'menu' and p_dependency_code = 'menu_role_grant' then
    delete from public.sys_role_menu role_menu
    where role_menu.menu_id = any(p_resource_ids)
      and role_menu.id = any(p_record_ids);
    get diagnostics affected_count = row_count;
    return affected_count;
  end if;

  if p_resource_type = 'dict_type' and p_dependency_code = 'dict_type_item' then
    delete from public.sys_dictionary dictionary
    where dictionary.type_id = any(p_resource_ids)
      and dictionary.id = any(p_record_ids);
    get diagnostics affected_count = row_count;
    return affected_count;
  end if;

  if p_resource_type = 'dictionary' and p_dependency_code = 'dictionary_child' then
    delete from public.sys_dictionary dictionary
    where dictionary.parent_id = any(p_resource_ids)
      and dictionary.id = any(p_record_ids);
    get diagnostics affected_count = row_count;
    return affected_count;
  end if;

  raise exception 'unsupported safe cleanup: % / %', p_resource_type, p_dependency_code
    using errcode = '22023';
end;
$$;

comment on function public.cleanup_governed_delete_dependencies(text, uuid[], text, uuid[]) is
  'Cleans only explicitly selected configuration links and terminal records; business and audit history remain protected.';

revoke all on function public.cleanup_governed_delete_dependencies(text, uuid[], text, uuid[]) from public, anon;
grant execute on function public.cleanup_governed_delete_dependencies(text, uuid[], text, uuid[]) to authenticated;

;
