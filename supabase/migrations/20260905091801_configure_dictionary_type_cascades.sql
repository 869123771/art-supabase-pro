begin;

alter table public.sys_dict_type
  add column if not exists cascade_parent_type_id uuid;

comment on column public.sys_dict_type.cascade_parent_type_id is
  'Optional dictionary type whose entries can be selected through sys_dictionary.cascade_parent_id.';

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.sys_dict_type'::regclass
      and conname = 'sys_dict_type_cascade_parent_type_not_self'
  ) then
    alter table public.sys_dict_type
      add constraint sys_dict_type_cascade_parent_type_not_self
      check (cascade_parent_type_id is null or cascade_parent_type_id <> id);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.sys_dict_type'::regclass
      and conname = 'sys_dict_type_cascade_parent_type_id_fkey'
  ) then
    alter table public.sys_dict_type
      add constraint sys_dict_type_cascade_parent_type_id_fkey
      foreign key (cascade_parent_type_id)
      references public.sys_dict_type(id)
      on delete restrict;
  end if;
end;
$migration$;

create index if not exists sys_dict_type_cascade_parent_type_idx
  on public.sys_dict_type (cascade_parent_type_id)
  where cascade_parent_type_id is not null;

create or replace function app_private.validate_dict_type_cascade_parent()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  parent_row public.sys_dict_type%rowtype;
begin
  if new.cascade_parent_type_id is null then
    return new;
  end if;

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

  return new;
end;
$function$;

revoke all on function app_private.validate_dict_type_cascade_parent() from public;

drop trigger if exists sys_dict_type_validate_cascade_parent on public.sys_dict_type;
create trigger sys_dict_type_validate_cascade_parent
before insert or update of cascade_parent_type_id, node_type, tenant_id
on public.sys_dict_type
for each row
execute function app_private.validate_dict_type_cascade_parent();

update public.sys_dict_type child_type
set cascade_parent_type_id = parent_type.id
from public.sys_dict_type parent_type
where child_type.code = 'smisSecondaryHazardCategory'
  and parent_type.code = 'smisPrimaryHazardCategory'
  and child_type.tenant_id = parent_type.tenant_id
  and child_type.cascade_parent_type_id is distinct from parent_type.id;

update public.sys_dict_type child_type
set cascade_parent_type_id = parent_type.id
from public.sys_dict_type parent_type
where child_type.code = 'smisHazardContent'
  and parent_type.code = 'smisSecondaryHazardCategory'
  and child_type.tenant_id = parent_type.tenant_id
  and child_type.cascade_parent_type_id is distinct from parent_type.id;

commit;
