create or replace function public.get_organization_list_secure(
  p_keyword text default null,
  p_tenant_id uuid default null,
  p_organization_type text default null,
  p_status text default null,
  p_record_id uuid default null
)
returns table (
  id uuid,
  tenant_id uuid,
  tenant jsonb,
  parent_id uuid,
  organization_code text,
  organization_name text,
  organization_type text,
  leader_user_id uuid,
  leader jsonb,
  status text,
  sort integer,
  phone text,
  email text,
  address text,
  description text,
  is_system boolean,
  create_by text,
  create_time timestamptz,
  update_by text,
  update_time timestamptz,
  member_count integer,
  role_count integer,
  menu_count integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    organization.id,
    organization.tenant_id,
    case
      when tenant.id is null then null
      else jsonb_build_object(
        'tenant_code', tenant.tenant_code,
        'tenant_name', tenant.tenant_name
      )
    end as tenant,
    organization.parent_id,
    organization.organization_code,
    organization.organization_name,
    organization.organization_type,
    organization.leader_user_id,
    case
      when leader.id is null then null
      else jsonb_build_object(
        'id', leader.id,
        'avatar', leader.avatar,
        'user_name', leader.user_name,
        'nick_name', leader.nick_name,
        'user_email', leader.user_email
      )
    end as leader,
    organization.status,
    organization.sort,
    organization.phone,
    organization.email,
    organization.address,
    organization.description,
    organization.is_system,
    organization.create_by,
    organization.create_time,
    organization.update_by,
    organization.update_time,
    (
      select count(*)::integer
      from public.sys_user as member
      where member.organization_id = organization.id
        and member.deleted_at is null
    ) as member_count,
    (
      select count(*)::integer
      from public.sys_role as organization_role
      where organization_role.organization_id = organization.id
    ) as role_count,
    (
      select count(distinct role_menu.menu_id)::integer
      from public.sys_role as organization_role
      join public.sys_role_menu as role_menu
        on role_menu.role_id = organization_role.id
      where organization_role.organization_id = organization.id
    ) as menu_count
  from public.sys_organization as organization
  left join public.sys_tenant as tenant
    on tenant.id = organization.tenant_id
  left join public.sys_user as leader
    on leader.id = organization.leader_user_id
  where (p_record_id is null or organization.id = p_record_id)
    and (p_tenant_id is null or organization.tenant_id = p_tenant_id)
    and (
      p_organization_type is null
      or organization.organization_type = p_organization_type
    )
    and (p_status is null or organization.status = p_status)
    and (
      nullif(btrim(p_keyword), '') is null
      or organization.organization_name ilike '%' || btrim(p_keyword) || '%'
      or organization.organization_code ilike '%' || btrim(p_keyword) || '%'
      or organization.description ilike '%' || btrim(p_keyword) || '%'
    )
  order by organization.sort asc, organization.organization_name asc;
$$;

revoke all on function public.get_organization_list_secure(text, uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.get_organization_list_secure(text, uuid, text, text, uuid)
  to authenticated;

comment on function public.get_organization_list_secure(text, uuid, text, text, uuid) is
  'Returns the RLS-scoped organization workspace summary without expanding member and role-menu detail payloads.';

;
