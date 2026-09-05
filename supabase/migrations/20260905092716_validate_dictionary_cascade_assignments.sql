begin;

create or replace function app_private.validate_dict_type_cascade_parent()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  parent_row public.sys_dict_type%rowtype;
begin
  if new.cascade_parent_type_id is not null then
    if new.node_type <> 'dictionary' then
      raise exception using
        errcode = '23514',
        message = '只有字典类型可以配置级联上级类型';
    end if;

    select *
    into parent_row
    from public.sys_dict_type
    where id = new.cascade_parent_type_id;

    if not found or parent_row.node_type <> 'dictionary' then
      raise exception using
        errcode = '23514',
        message = '级联上级必须是有效的字典类型';
    end if;

    if parent_row.tenant_id <> new.tenant_id then
      raise exception using
        errcode = '23514',
        message = '级联上下级字典类型必须属于同一租户';
    end if;

    if exists (
      with recursive ancestors as (
        select parent.id, parent.cascade_parent_type_id, array[parent.id] as visited
        from public.sys_dict_type parent
        where parent.id = new.cascade_parent_type_id

        union all

        select parent.id, parent.cascade_parent_type_id, ancestors.visited || parent.id
        from public.sys_dict_type parent
        join ancestors on parent.id = ancestors.cascade_parent_type_id
        where not parent.id = any(ancestors.visited)
      )
      select 1
      from ancestors
      where id = new.id
    ) then
      raise exception using
        errcode = '23514',
        message = '字典类型级联关系不能形成循环';
    end if;
  end if;

  if exists (
    select 1
    from public.sys_dictionary child_entry
    join public.sys_dictionary parent_entry
      on parent_entry.id = child_entry.cascade_parent_id
    where child_entry.type_id = new.id
      and child_entry.cascade_parent_id is not null
      and (
        new.cascade_parent_type_id is null
        or parent_entry.type_id <> new.cascade_parent_type_id
        or parent_entry.tenant_id <> child_entry.tenant_id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = '已有字典项的级联归属与新配置不一致，请先调整字典项';
  end if;

  return new;
end;
$function$;

create or replace function app_private.validate_dictionary_cascade_assignment()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  expected_parent_type_id uuid;
  parent_entry public.sys_dictionary%rowtype;
begin
  if new.cascade_parent_id is null then
    return new;
  end if;

  select cascade_parent_type_id
  into expected_parent_type_id
  from public.sys_dict_type
  where id = new.type_id
    and tenant_id = new.tenant_id;

  if expected_parent_type_id is null then
    raise exception using
      errcode = '23514',
      message = '当前字典类型未配置级联上级类型';
  end if;

  select *
  into parent_entry
  from public.sys_dictionary
  where id = new.cascade_parent_id;

  if not found
    or parent_entry.type_id <> expected_parent_type_id
    or parent_entry.tenant_id <> new.tenant_id then
    raise exception using
      errcode = '23514',
      message = '所选级联上级字典项与类型配置不一致';
  end if;

  return new;
end;
$function$;

revoke all on function app_private.validate_dictionary_cascade_assignment() from public;

drop trigger if exists sys_dictionary_validate_cascade_assignment on public.sys_dictionary;
create trigger sys_dictionary_validate_cascade_assignment
before insert or update of cascade_parent_id, type_id, tenant_id
on public.sys_dictionary
for each row
execute function app_private.validate_dictionary_cascade_assignment();

commit;
