create table if not exists public.smis_position_work_instruction (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  instruction_name text not null,
  file_number text,
  file_type text,
  upload_date date,
  version_no text,
  file_url text,
  original_file_name text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_position_work_instruction_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint smis_position_work_instruction_name_check
    check (btrim(instruction_name) <> '' and char_length(instruction_name) <= 200),
  constraint smis_position_work_instruction_file_number_check
    check (file_number is null or char_length(file_number) <= 100),
  constraint smis_position_work_instruction_file_type_check
    check (file_type is null or char_length(file_type) <= 120),
  constraint smis_position_work_instruction_version_check
    check (version_no is null or char_length(version_no) <= 50),
  constraint smis_position_work_instruction_file_url_check
    check (file_url is null or char_length(file_url) <= 2048),
  constraint smis_position_work_instruction_original_name_check
    check (original_file_name is null or char_length(original_file_name) <= 500)
);

create table if not exists public.smis_position_work_instruction_scope (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  instruction_id uuid not null,
  organization_id uuid not null,
  position_id uuid not null,
  create_by text,
  create_time timestamptz not null default now(),
  constraint smis_position_work_instruction_scope_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint smis_position_work_instruction_scope_instruction_fkey
    foreign key (instruction_id) references public.smis_position_work_instruction(id) on delete cascade,
  constraint smis_position_work_instruction_scope_organization_fkey
    foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_position_work_instruction_scope_position_fkey
    foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint smis_position_work_instruction_scope_unique
    unique (tenant_id, instruction_id, organization_id, position_id)
);

comment on table public.smis_position_work_instruction is
  'SMIS 岗位作业指导书主档';
comment on table public.smis_position_work_instruction_scope is
  'SMIS 岗位作业指导书适用组织岗位范围';
comment on column public.smis_position_work_instruction.instruction_name is '作业指导名称';
comment on column public.smis_position_work_instruction.file_number is '文件编号';
comment on column public.smis_position_work_instruction.file_type is '文件类型';
comment on column public.smis_position_work_instruction.upload_date is '上传日期';
comment on column public.smis_position_work_instruction.version_no is '版本号';
comment on column public.smis_position_work_instruction.file_url is '文件地址';

create index if not exists smis_position_work_instruction_tenant_update_idx
  on public.smis_position_work_instruction (tenant_id, update_time desc);
create index if not exists smis_position_work_instruction_file_idx
  on public.smis_position_work_instruction (tenant_id, file_type, upload_date desc);
create index if not exists smis_position_work_instruction_scope_position_idx
  on public.smis_position_work_instruction_scope (
    tenant_id, organization_id, position_id, instruction_id
  );

alter table public.smis_position_work_instruction enable row level security;
alter table public.smis_position_work_instruction_scope enable row level security;

drop policy if exists tenant_select on public.smis_position_work_instruction;
create policy tenant_select
on public.smis_position_work_instruction
for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionWorkInstruction:View'))
  )
);

drop policy if exists tenant_select on public.smis_position_work_instruction_scope;
create policy tenant_select
on public.smis_position_work_instruction_scope
for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionWorkInstruction:View'))
  )
);

revoke all on table public.smis_position_work_instruction from public, anon, authenticated;
revoke all on table public.smis_position_work_instruction_scope from public, anon, authenticated;
grant select on table public.smis_position_work_instruction to authenticated, service_role;
grant select on table public.smis_position_work_instruction_scope to authenticated, service_role;
grant insert, update, delete on table public.smis_position_work_instruction to service_role;
grant insert, update, delete on table public.smis_position_work_instruction_scope to service_role;

create or replace function public.smis_get_work_instruction_position_tree_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'SmisPositionWorkInstruction',
    'SmisPositionWorkInstruction:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS work instruction view permission' using errcode = '42501';
  end if;

  return (
    with position_scope as (
      select position_row.organization_id, position_row.id as position_id
      from public.hr_position position_row
      where position_row.tenant_id = v_tenant_id
        and position_row.enabled
        and position_row.organization_id is not null
      union
      select headcount_row.organization_id, headcount_row.position_id
      from public.hr_position_headcount headcount_row
      join public.hr_position position_row
        on position_row.id = headcount_row.position_id
       and position_row.tenant_id = headcount_row.tenant_id
       and position_row.enabled
      where headcount_row.tenant_id = v_tenant_id
        and headcount_row.enabled
        and headcount_row.effective_from <= current_date
        and (headcount_row.effective_to is null or headcount_row.effective_to >= current_date)
      union
      select employee_row.organization_id, employee_row.position_id
      from public.hr_employee employee_row
      join public.hr_position position_row
        on position_row.id = employee_row.position_id
       and position_row.tenant_id = employee_row.tenant_id
       and position_row.enabled
      where employee_row.tenant_id = v_tenant_id
        and employee_row.position_id is not null
        and employee_row.employment_status <> 'terminated'
      union
      select scope_row.organization_id, scope_row.position_id
      from public.smis_position_work_instruction_scope scope_row
      where scope_row.tenant_id = v_tenant_id
    ), position_records as (
      select
        position_scope.organization_id,
        position_row.id as position_id,
        position_row.position_code,
        position_row.position_name,
        position_row.sort,
        (
          select count(*)
          from public.hr_employee employee_row
          where employee_row.tenant_id = v_tenant_id
            and employee_row.organization_id = position_scope.organization_id
            and employee_row.position_id = position_row.id
            and employee_row.employment_status <> 'terminated'
        )::integer as employee_count,
        (
          select count(distinct scope_row.instruction_id)
          from public.smis_position_work_instruction_scope scope_row
          where scope_row.tenant_id = v_tenant_id
            and scope_row.organization_id = position_scope.organization_id
            and scope_row.position_id = position_row.id
        )::integer as instruction_count
      from position_scope
      join public.hr_position position_row
        on position_row.id = position_scope.position_id
       and position_row.tenant_id = v_tenant_id
       and position_row.enabled
    )
    select jsonb_build_object(
      'organizations', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', organization_row.id,
            'parent_id', organization_row.parent_id,
            'organization_code', organization_row.organization_code,
            'organization_name', organization_row.organization_name,
            'organization_type', organization_row.organization_type,
            'sort', organization_row.sort
          ) order by organization_row.sort, organization_row.organization_name
        )
        from public.sys_organization organization_row
        where organization_row.tenant_id = v_tenant_id
          and organization_row.status = '1'
      ), '[]'::jsonb),
      'positions', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'scope_key', 'scope:' || position_records.organization_id::text || ':' || position_records.position_id::text,
            'organization_id', position_records.organization_id,
            'position_id', position_records.position_id,
            'position_code', position_records.position_code,
            'position_name', position_records.position_name,
            'sort', position_records.sort,
            'employee_count', position_records.employee_count,
            'instruction_count', position_records.instruction_count
          ) order by position_records.sort, position_records.position_name, position_records.position_code
        )
        from position_records
      ), '[]'::jsonb)
    )
  );
end;
$function$;

create or replace function public.smis_list_position_work_instructions_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_file_type text default null,
  p_organization_id uuid default null,
  p_position_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionWorkInstruction',
    'SmisPositionWorkInstruction:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS work instruction view permission' using errcode = '42501';
  end if;

  v_limit := least(200, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));

  with filtered as materialized (
    select instruction_row.*
    from public.smis_position_work_instruction instruction_row
    where instruction_row.tenant_id = v_tenant_id
      and (
        nullif(btrim(p_keyword), '') is null
        or instruction_row.instruction_name ilike '%' || btrim(p_keyword) || '%'
        or coalesce(instruction_row.file_number, '') ilike '%' || btrim(p_keyword) || '%'
        or coalesce(instruction_row.version_no, '') ilike '%' || btrim(p_keyword) || '%'
      )
      and (
        nullif(btrim(p_file_type), '') is null
        or instruction_row.file_type ilike '%' || btrim(p_file_type) || '%'
      )
      and (
        p_organization_id is null
        or exists (
          select 1 from public.smis_position_work_instruction_scope scope_row
          where scope_row.instruction_id = instruction_row.id
            and scope_row.tenant_id = v_tenant_id
            and scope_row.organization_id = p_organization_id
            and (p_position_id is null or scope_row.position_id = p_position_id)
        )
      )
  ), paged as (
    select * from filtered
    order by update_time desc, instruction_name
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        to_jsonb(paged) || jsonb_build_object(
          'scopes', coalesce((
            select jsonb_agg(jsonb_build_object(
              'scope_key', 'scope:' || scope_row.organization_id::text || ':' || scope_row.position_id::text,
              'organization_id', scope_row.organization_id,
              'organization_name', organization_row.organization_name,
              'organization_code', organization_row.organization_code,
              'position_id', scope_row.position_id,
              'position_name', position_row.position_name,
              'position_code', position_row.position_code
            ) order by organization_row.sort, organization_row.organization_name, position_row.sort, position_row.position_name)
            from public.smis_position_work_instruction_scope scope_row
            join public.sys_organization organization_row on organization_row.id = scope_row.organization_id
            join public.hr_position position_row on position_row.id = scope_row.position_id
            where scope_row.instruction_id = paged.id
              and scope_row.tenant_id = v_tenant_id
          ), '[]'::jsonb)
        ) order by paged.update_time desc, paged.instruction_name
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;

  return v_result;
end;
$function$;

create or replace function public.smis_save_position_work_instruction_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_instruction_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_is_edit boolean := v_instruction_id is not null;
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), 'unknown');
  v_scopes jsonb := coalesce(p_payload -> 'scopes', '[]'::jsonb);
begin
  if jsonb_typeof(v_scopes) <> 'array' or jsonb_array_length(v_scopes) = 0 then
    raise exception '请至少选择一个适用组织岗位' using errcode = '22023';
  end if;

  if not app_private.can_execute_business_action(
    'SmisPositionWorkInstruction',
    case when v_is_edit then 'SmisPositionWorkInstruction:Edit' else 'SmisPositionWorkInstruction:Add' end,
    null,
    true
  ) then
    raise exception 'Missing SMIS work instruction write permission' using errcode = '42501';
  end if;

  if nullif(btrim(p_payload ->> 'instruction_name'), '') is null then
    raise exception '作业指导名称不能为空' using errcode = '22023';
  end if;

  if exists (
    select 1
    from (
      select distinct
        nullif(scope_item ->> 'organization_id', '')::uuid as organization_id,
        nullif(scope_item ->> 'position_id', '')::uuid as position_id
      from jsonb_array_elements(v_scopes) scope_item
    ) selected_scope
    where selected_scope.organization_id is null
       or selected_scope.position_id is null
       or not exists (
         select 1
         from public.sys_organization organization_row
         join public.hr_position position_row
           on position_row.id = selected_scope.position_id
          and position_row.tenant_id = v_tenant_id
          and position_row.enabled
         where organization_row.id = selected_scope.organization_id
           and organization_row.tenant_id = v_tenant_id
           and organization_row.status = '1'
           and (
             position_row.organization_id = organization_row.id
             or exists (
               select 1 from public.hr_position_headcount headcount_row
               where headcount_row.tenant_id = v_tenant_id
                 and headcount_row.organization_id = organization_row.id
                 and headcount_row.position_id = position_row.id
                 and headcount_row.enabled
             )
             or exists (
               select 1 from public.hr_employee employee_row
               where employee_row.tenant_id = v_tenant_id
                 and employee_row.organization_id = organization_row.id
                 and employee_row.position_id = position_row.id
                 and employee_row.employment_status <> 'terminated'
             )
             or exists (
               select 1 from public.smis_position_work_instruction_scope existing_scope
               where existing_scope.tenant_id = v_tenant_id
                 and existing_scope.organization_id = organization_row.id
                 and existing_scope.position_id = position_row.id
             )
           )
       )
  ) then
    raise exception '适用组织岗位不存在、已停用或超出当前租户范围' using errcode = '42501';
  end if;

  if v_is_edit then
    update public.smis_position_work_instruction
    set instruction_name = btrim(p_payload ->> 'instruction_name'),
        file_number = nullif(btrim(p_payload ->> 'file_number'), ''),
        file_type = nullif(btrim(p_payload ->> 'file_type'), ''),
        upload_date = nullif(p_payload ->> 'upload_date', '')::date,
        version_no = nullif(btrim(p_payload ->> 'version_no'), ''),
        file_url = nullif(btrim(p_payload ->> 'file_url'), ''),
        original_file_name = nullif(btrim(p_payload ->> 'original_file_name'), ''),
        update_by = v_actor,
        update_time = now()
    where id = v_instruction_id and tenant_id = v_tenant_id;

    if not found then
      raise exception '作业指导书不存在或超出当前租户范围' using errcode = 'P0002';
    end if;

    delete from public.smis_position_work_instruction_scope
    where instruction_id = v_instruction_id and tenant_id = v_tenant_id;
  else
    insert into public.smis_position_work_instruction (
      tenant_id, instruction_name, file_number, file_type, upload_date,
      version_no, file_url, original_file_name, create_by, update_by
    ) values (
      v_tenant_id,
      btrim(p_payload ->> 'instruction_name'),
      nullif(btrim(p_payload ->> 'file_number'), ''),
      nullif(btrim(p_payload ->> 'file_type'), ''),
      nullif(p_payload ->> 'upload_date', '')::date,
      nullif(btrim(p_payload ->> 'version_no'), ''),
      nullif(btrim(p_payload ->> 'file_url'), ''),
      nullif(btrim(p_payload ->> 'original_file_name'), ''),
      v_actor,
      v_actor
    ) returning id into v_instruction_id;
  end if;

  insert into public.smis_position_work_instruction_scope (
    tenant_id, instruction_id, organization_id, position_id, create_by
  )
  select distinct
    v_tenant_id,
    v_instruction_id,
    nullif(scope_item ->> 'organization_id', '')::uuid,
    nullif(scope_item ->> 'position_id', '')::uuid,
    v_actor
  from jsonb_array_elements(v_scopes) scope_item;

  return v_instruction_id;
end;
$function$;

create or replace function public.smis_delete_position_work_instructions_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_deleted integer;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionWorkInstruction',
    'SmisPositionWorkInstruction:Delete',
    null,
    true
  ) then
    raise exception 'Missing SMIS work instruction delete permission' using errcode = '42501';
  end if;

  delete from public.smis_position_work_instruction
  where tenant_id = v_tenant_id and id = any(coalesce(p_ids, array[]::uuid[]));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$;

revoke all on function public.smis_get_work_instruction_position_tree_secure() from public, anon;
revoke all on function public.smis_list_position_work_instructions_secure(integer, integer, text, text, uuid, uuid) from public, anon;
revoke all on function public.smis_save_position_work_instruction_secure(jsonb) from public, anon;
revoke all on function public.smis_delete_position_work_instructions_secure(uuid[]) from public, anon;
grant execute on function public.smis_get_work_instruction_position_tree_secure() to authenticated, service_role;
grant execute on function public.smis_list_position_work_instructions_secure(integer, integer, text, text, uuid, uuid) to authenticated, service_role;
grant execute on function public.smis_save_position_work_instruction_secure(jsonb) to authenticated, service_role;
grant execute on function public.smis_delete_position_work_instructions_secure(uuid[]) to authenticated, service_role;

with page_menu as (
  select id from public.sys_menu where name = 'SmisPositionWorkInstruction' limit 1
), button_seed(name, title, sort) as (
  values
    ('SmisPositionWorkInstruction:View', '查看岗位作业指导书', 1),
    ('SmisPositionWorkInstruction:Add', '新增岗位作业指导书', 2),
    ('SmisPositionWorkInstruction:Edit', '编辑岗位作业指导书', 3),
    ('SmisPositionWorkInstruction:Delete', '删除岗位作业指导书', 4)
)
insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select
  gen_random_uuid(), page_menu.id, seed.name, '', '',
  jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()
  ),
  seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from button_seed seed cross join page_menu
where not exists (
  select 1 from public.sys_menu existing_button
  where existing_button.parent_id = page_menu.id and existing_button.name = seed.name
);

insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select
  page_grant.role_id, button_menu.id, page_grant.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_menu page_menu
  on page_menu.id = page_grant.menu_id and page_menu.name = 'SmisPositionWorkInstruction'
join public.sys_menu button_menu
  on button_menu.parent_id = page_menu.id
 and button_menu.name in (
   'SmisPositionWorkInstruction:View',
   'SmisPositionWorkInstruction:Add',
   'SmisPositionWorkInstruction:Edit',
   'SmisPositionWorkInstruction:Delete'
 )
on conflict (role_id, menu_id) do nothing;

;
