create or replace function app_private.auth_user_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select user_row.tenant_id
  from public.sys_user user_row
  join public.sys_tenant tenant_row on tenant_row.id = user_row.tenant_id
  where user_row.auth_user_id = (select auth.uid())
    and user_row.status = '1'
    and user_row.deleted_at is null
    and tenant_row.status = '1'
    and (
      tenant_row.service_start_date is null
      or tenant_row.service_start_date <= (now() at time zone 'Asia/Shanghai')::date
    )
    and (
      tenant_row.service_end_date is null
      or tenant_row.service_end_date >= (now() at time zone 'Asia/Shanghai')::date
    )
  limit 1;
$function$;

revoke all on function app_private.auth_user_tenant_id() from public, anon, authenticated;
grant execute on function app_private.auth_user_tenant_id() to service_role;

create or replace function app_private.current_user_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_auth_tenant_id uuid := app_private.auth_user_tenant_id();
  v_requested_text text;
  v_requested_tenant_id uuid;
begin
  if not app_private.is_platform_super() then
    return v_auth_tenant_id;
  end if;

  v_requested_text := nullif(
    btrim(
      coalesce(
        current_setting('request.headers', true)::jsonb->>'x-art-tenant-scope',
        ''
      )
    ),
    ''
  );
  if v_requested_text is null then
    return v_auth_tenant_id;
  end if;

  begin
    v_requested_tenant_id := v_requested_text::uuid;
  exception
    when invalid_text_representation then
      raise exception '租户范围标识无效' using errcode = '22023';
  end;

  if not exists (
    select 1
    from public.sys_tenant tenant
    where tenant.id = v_requested_tenant_id
      and tenant.status = '1'
      and tenant.builtin_type is distinct from 'platform'
      and (
        tenant.service_start_date is null
        or tenant.service_start_date <= (now() at time zone 'Asia/Shanghai')::date
      )
      and (
        tenant.service_end_date is null
        or tenant.service_end_date >= (now() at time zone 'Asia/Shanghai')::date
      )
  ) then
    raise exception '所选租户不存在、已停用或不在服务期' using errcode = '22023';
  end if;

  return v_requested_tenant_id;
end;
$function$;

revoke all on function app_private.current_user_tenant_id() from public, anon;
grant execute on function app_private.current_user_tenant_id() to authenticated, service_role;

create or replace function app_private.resolve_read_tenant_id(p_requested_tenant_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_current_tenant_id uuid := app_private.auth_user_tenant_id();
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再读取租户数据' using errcode = '42501';
  end if;
  if v_current_tenant_id is null then
    raise exception '当前账号未绑定有效租户' using errcode = '42501';
  end if;

  if app_private.is_platform_super() then
    if p_requested_tenant_id is null then
      return null;
    end if;
    if not exists (
      select 1
      from public.sys_tenant tenant
      where tenant.id = p_requested_tenant_id
        and tenant.status = '1'
        and tenant.builtin_type is distinct from 'platform'
        and (
          tenant.service_start_date is null
          or tenant.service_start_date <= (now() at time zone 'Asia/Shanghai')::date
        )
        and (
          tenant.service_end_date is null
          or tenant.service_end_date >= (now() at time zone 'Asia/Shanghai')::date
        )
    ) then
      raise exception '所选租户不存在或已停用' using errcode = '22023';
    end if;
    return p_requested_tenant_id;
  end if;

  if p_requested_tenant_id is not null and p_requested_tenant_id <> v_current_tenant_id then
    raise exception '不能读取当前租户之外的数据' using errcode = '42501';
  end if;
  return v_current_tenant_id;
end;
$function$;

revoke all on function app_private.resolve_read_tenant_id(uuid) from public, anon, authenticated;
grant execute on function app_private.resolve_read_tenant_id(uuid) to service_role;

create or replace function app_private.resolve_write_tenant_id(p_requested_tenant_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_current_tenant_id uuid := app_private.auth_user_tenant_id();
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护租户数据' using errcode = '42501';
  end if;
  if v_current_tenant_id is null then
    raise exception '当前账号未绑定有效租户' using errcode = '42501';
  end if;

  if app_private.is_platform_super() then
    if p_requested_tenant_id is null then
      raise exception '平台管理员维护数据前必须选择具体租户' using errcode = '22023';
    end if;
    if not exists (
      select 1
      from public.sys_tenant tenant
      where tenant.id = p_requested_tenant_id
        and tenant.status = '1'
        and tenant.builtin_type is distinct from 'platform'
        and (
          tenant.service_start_date is null
          or tenant.service_start_date <= (now() at time zone 'Asia/Shanghai')::date
        )
        and (
          tenant.service_end_date is null
          or tenant.service_end_date >= (now() at time zone 'Asia/Shanghai')::date
        )
    ) then
      raise exception '所选业务租户不存在或已停用' using errcode = '22023';
    end if;
    return p_requested_tenant_id;
  end if;

  if p_requested_tenant_id is not null and p_requested_tenant_id <> v_current_tenant_id then
    raise exception '不能维护当前租户之外的数据' using errcode = '42501';
  end if;
  return v_current_tenant_id;
end;
$function$;

revoke all on function app_private.resolve_write_tenant_id(uuid) from public, anon, authenticated;
grant execute on function app_private.resolve_write_tenant_id(uuid) to service_role;

drop function if exists public.smis_list_inspection_categories_secure(integer, integer, text, text);

create or replace function public.smis_list_inspection_categories_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_scope_tenant_id uuid := app_private.resolve_read_tenant_id(p_tenant_id);
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
begin
  if not app_private.has_permission('SmisInspectionCategory:View') then
    raise exception '当前账号没有查看检验类别的权限' using errcode = '42501';
  end if;

  if p_status is not null and p_status not in ('enabled', 'disabled') then
    raise exception '启用状态筛选值无效' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        to_jsonb(record_row)
        order by record_row."tenantName", record_row."categoryName", record_row."categoryCode"
      )
      from (
        select
          category.id,
          category.tenant_id as "tenantId",
          tenant.tenant_name as "tenantName",
          tenant.tenant_code as "tenantCode",
          category.category_code as "categoryCode",
          category.category_name as "categoryName",
          category.remark,
          category.status,
          category.create_by as "createBy",
          category.create_time as "createTime",
          category.update_by as "updateBy",
          category.update_time as "updateTime"
        from public.smis_inspection_category category
        join public.sys_tenant tenant on tenant.id = category.tenant_id
        where (v_scope_tenant_id is null or category.tenant_id = v_scope_tenant_id)
          and (p_status is null or category.status = p_status)
          and (
            v_keyword is null
            or lower(category.category_code) like '%' || v_keyword || '%'
            or lower(category.category_name) like '%' || v_keyword || '%'
            or lower(coalesce(category.remark, '')) like '%' || v_keyword || '%'
            or lower(tenant.tenant_name) like '%' || v_keyword || '%'
            or lower(tenant.tenant_code) like '%' || v_keyword || '%'
          )
        order by tenant.tenant_name, category.category_name, category.category_code
        offset v_from
        limit v_to - v_from + 1
      ) record_row
    ), '[]'::jsonb),
    'total', (
      select count(*)
      from public.smis_inspection_category category
      join public.sys_tenant tenant on tenant.id = category.tenant_id
      where (v_scope_tenant_id is null or category.tenant_id = v_scope_tenant_id)
        and (p_status is null or category.status = p_status)
        and (
          v_keyword is null
          or lower(category.category_code) like '%' || v_keyword || '%'
          or lower(category.category_name) like '%' || v_keyword || '%'
          or lower(coalesce(category.remark, '')) like '%' || v_keyword || '%'
          or lower(tenant.tenant_name) like '%' || v_keyword || '%'
          or lower(tenant.tenant_code) like '%' || v_keyword || '%'
        )
    ),
    'overview', (
      select jsonb_build_object(
        'total', count(*),
        'enabled', count(*) filter (where category.status = 'enabled'),
        'disabled', count(*) filter (where category.status = 'disabled'),
        'recentlyUpdated', count(*) filter (where category.update_time >= now() - interval '30 days')
      )
      from public.smis_inspection_category category
      where v_scope_tenant_id is null or category.tenant_id = v_scope_tenant_id
    )
  );
end;
$function$;

revoke all on function public.smis_list_inspection_categories_secure(integer, integer, text, text, uuid)
from public, anon;
grant execute on function public.smis_list_inspection_categories_secure(integer, integer, text, text, uuid)
to authenticated, service_role;

drop function if exists public.smis_save_inspection_category_secure(uuid, jsonb);

create or replace function public.smis_save_inspection_category_secure(
  p_id uuid,
  p_payload jsonb,
  p_tenant_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.resolve_write_tenant_id(p_tenant_id);
  v_id uuid;
  v_category_code text := upper(btrim(coalesce(p_payload->>'category_code', '')));
  v_category_name text := btrim(coalesce(p_payload->>'category_name', ''));
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
  v_status text := btrim(coalesce(p_payload->>'status', 'enabled'));
begin
  if p_id is null and not app_private.has_permission('SmisInspectionCategory:Add') then
    raise exception '当前账号没有新增检验类别的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisInspectionCategory:Edit') then
    raise exception '当前账号没有编辑检验类别的权限' using errcode = '42501';
  end if;
  if v_category_code = '' then
    raise exception '请输入检验类别编码' using errcode = '22023';
  end if;
  if v_category_code !~ '^[A-Z][A-Z0-9_]{0,39}$' then
    raise exception '检验类别编码须以字母开头，仅支持大写字母、数字和下划线' using errcode = '22023';
  end if;
  if v_category_name = '' then
    raise exception '请输入检验类别名称' using errcode = '22023';
  end if;
  if char_length(v_category_name) > 80 then
    raise exception '检验类别名称不能超过 80 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_remark, '')) > 500 then
    raise exception '备注不能超过 500 个字符' using errcode = '22023';
  end if;
  if v_status not in ('enabled', 'disabled') then
    raise exception '启用状态无效' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_inspection_category(
      tenant_id, category_code, category_name, remark, status
    ) values (
      v_tenant_id, v_category_code, v_category_name, v_remark, v_status
    ) returning id into v_id;
  else
    update public.smis_inspection_category
    set category_code = v_category_code,
        category_name = v_category_name,
        remark = v_remark,
        status = v_status
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_id;

    if v_id is null then
      raise exception '检验类别不存在、已删除或不属于所选租户' using errcode = 'P0002';
    end if;
  end if;

  return v_id;
exception
  when unique_violation then
    raise exception '检验类别编码或名称已存在，请更换后重试' using errcode = '23505';
end;
$function$;

drop function if exists public.smis_delete_inspection_categories_secure(uuid[]);

create or replace function public.smis_delete_inspection_categories_secure(
  p_ids uuid[],
  p_tenant_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.resolve_write_tenant_id(p_tenant_id);
  v_count integer;
begin
  if not app_private.has_permission('SmisInspectionCategory:Delete') then
    raise exception '当前账号没有删除检验类别的权限' using errcode = '42501';
  end if;

  delete from public.smis_inspection_category
  where tenant_id = v_tenant_id
    and id = any(coalesce(p_ids, array[]::uuid[]));
  get diagnostics v_count = row_count;
  return v_count;
exception
  when foreign_key_violation then
    raise exception '检验类别已被业务记录使用，请改为停用' using errcode = '23503';
end;
$function$;

revoke all on function public.smis_save_inspection_category_secure(uuid, jsonb, uuid)
from public, anon;
revoke all on function public.smis_delete_inspection_categories_secure(uuid[], uuid)
from public, anon;
grant execute on function public.smis_save_inspection_category_secure(uuid, jsonb, uuid)
to authenticated, service_role;
grant execute on function public.smis_delete_inspection_categories_secure(uuid[], uuid)
to authenticated, service_role;

;
