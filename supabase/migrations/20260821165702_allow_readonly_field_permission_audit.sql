-- Separate field-permission page visibility from mutation authority and expose
-- tenant-scoped permission change history through one guarded RPC.

create or replace function app_private.can_view_field_permissions()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (
      app_private.can_access_business_menu('FieldPermission')
      or app_private.can_manage_field_permissions()
    );
$$;

create or replace function public.get_field_permission_resources()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_view_field_permissions() then
    raise exception 'Missing field permission page access' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', resource_row.id,
        'resourceKey', resource_row.resource_key,
        'resourceLabel', resource_row.resource_label,
        'menuName', resource_row.menu_name,
        'fieldCount', (
          select count(*)
          from public.sys_permission_field field_row
          where field_row.tenant_id = resource_row.tenant_id
            and field_row.resource_id = resource_row.id
            and field_row.enabled is true
        )
      )
      order by resource_row.resource_label, resource_row.resource_key
    )
    from public.sys_permission_resource resource_row
    where resource_row.tenant_id = app_private.current_user_tenant_id()
      and resource_row.enabled is true
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_field_permission_configuration(
  p_resource_key text,
  p_subject_type text,
  p_subject_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_resource public.sys_permission_resource%rowtype;
begin
  if not app_private.can_view_field_permissions() then
    raise exception 'Missing field permission page access' using errcode = '42501';
  end if;

  if p_subject_type not in ('role', 'user') then
    raise exception 'Invalid permission subject type';
  end if;

  select * into v_resource
  from public.sys_permission_resource
  where tenant_id = v_tenant_id
    and resource_key = p_resource_key
    and enabled is true;

  if not found then
    raise exception 'Permission resource not found';
  end if;

  if p_subject_type = 'role' and not exists (
    select 1 from public.sys_role
    where id = p_subject_id and tenant_id = v_tenant_id and enabled is true
  ) then
    raise exception 'Role not found or access denied';
  end if;

  if p_subject_type = 'user' and not exists (
    select 1 from public.sys_user
    where id = p_subject_id
      and tenant_id = v_tenant_id
      and status = '1'
      and deleted_at is null
  ) then
    raise exception 'User not found or access denied';
  end if;

  return jsonb_build_object(
    'resourceId', v_resource.id,
    'resourceKey', v_resource.resource_key,
    'resourceLabel', v_resource.resource_label,
    'subjectType', p_subject_type,
    'subjectId', p_subject_id,
    'fields', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', field_row.id,
          'fieldKey', field_row.field_key,
          'fieldLabel', field_row.field_label,
          'defaultAccess', field_row.default_access,
          'maskStrategy', field_row.mask_strategy,
          'ownerOverrideEnabled', field_row.owner_override_enabled,
          'inheritedAccess', case
            when p_subject_type = 'user' then coalesce((
              select case max(app_private.permission_access_rank(role_permission.access_level))
                when 3 then 'edit'
                when 2 then 'read'
                when 1 then 'masked'
                when 0 then 'hidden'
                else null
              end
              from public.sys_user subject_user
              join public.sys_role role_row
                on role_row.tenant_id = subject_user.tenant_id
               and role_row.enabled is true
               and role_row.role_code = any(coalesce(subject_user.user_roles, array[]::text[]))
              join public.sys_role_field_permission role_permission
                on role_permission.tenant_id = role_row.tenant_id
               and role_permission.role_id = role_row.id
               and role_permission.resource_id = v_resource.id
               and role_permission.field_id = field_row.id
              where subject_user.id = p_subject_id
                and subject_user.tenant_id = v_tenant_id
            ), field_row.default_access)
            else field_row.default_access
          end,
          'explicitAccess', case
            when p_subject_type = 'role' then (
              select role_permission.access_level
              from public.sys_role_field_permission role_permission
              where role_permission.tenant_id = v_tenant_id
                and role_permission.role_id = p_subject_id
                and role_permission.resource_id = v_resource.id
                and role_permission.field_id = field_row.id
            )
            else (
              select user_permission.access_level
              from public.sys_user_field_permission user_permission
              where user_permission.tenant_id = v_tenant_id
                and user_permission.user_id = p_subject_id
                and user_permission.resource_id = v_resource.id
                and user_permission.field_id = field_row.id
            )
          end
        )
        order by field_row.sort, field_row.id
      )
      from public.sys_permission_field field_row
      where field_row.tenant_id = v_tenant_id
        and field_row.resource_id = v_resource.id
        and field_row.enabled is true
        and field_row.sensitive is true
    ), '[]'::jsonb)
  );
end;
$$;

create index if not exists sys_permission_audit_log_subject_lookup_idx
  on public.sys_permission_audit_log (
    tenant_id,
    resource_id,
    target_type,
    target_id,
    create_time desc
  );

create or replace function public.get_field_permission_audit_logs(
  p_resource_key text,
  p_subject_type text,
  p_subject_id uuid,
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_resource_id uuid;
  v_target_type text;
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 50);
begin
  if not app_private.can_view_field_permissions() then
    raise exception 'Missing field permission page access' using errcode = '42501';
  end if;

  if p_subject_type not in ('role', 'user') then
    raise exception 'Invalid permission subject type';
  end if;

  select resource_row.id
  into v_resource_id
  from public.sys_permission_resource resource_row
  where resource_row.tenant_id = v_tenant_id
    and resource_row.resource_key = p_resource_key
    and resource_row.enabled is true;

  if v_resource_id is null then
    raise exception 'Permission resource not found';
  end if;

  if p_subject_type = 'role' and not exists (
    select 1 from public.sys_role role_row
    where role_row.id = p_subject_id
      and role_row.tenant_id = v_tenant_id
      and role_row.enabled is true
  ) then
    raise exception 'Role not found or access denied';
  end if;

  if p_subject_type = 'user' and not exists (
    select 1 from public.sys_user user_row
    where user_row.id = p_subject_id
      and user_row.tenant_id = v_tenant_id
      and user_row.status = '1'
      and user_row.deleted_at is null
  ) then
    raise exception 'User not found or access denied';
  end if;

  v_target_type := p_subject_type || '_field';

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', audit_row.id,
        'action', audit_row.action,
        'beforeValue', coalesce(audit_row.before_value, '{}'::jsonb),
        'afterValue', coalesce(audit_row.after_value, '{}'::jsonb),
        'actorName', coalesce(
          nullif(actor_user.nick_name, ''),
          nullif(actor_user.user_name, ''),
          nullif(actor_user.user_email, ''),
          audit_row.create_by
        ),
        'actorEmail', actor_user.user_email,
        'createTime', audit_row.create_time
      )
      order by audit_row.create_time desc, audit_row.id desc
    )
    from (
      select audit_log.*
      from public.sys_permission_audit_log audit_log
      where audit_log.tenant_id = v_tenant_id
        and audit_log.resource_id = v_resource_id
        and audit_log.target_type = v_target_type
        and audit_log.target_id = p_subject_id
      order by audit_log.create_time desc, audit_log.id desc
      limit v_limit
    ) audit_row
    left join public.sys_user actor_user
      on actor_user.id = audit_row.actor_user_id
     and actor_user.tenant_id = audit_row.tenant_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function app_private.can_view_field_permissions() from public, anon, authenticated;
grant execute on function app_private.can_view_field_permissions() to service_role;

revoke all on function public.get_field_permission_resources() from public, anon;
revoke all on function public.get_field_permission_configuration(text, text, uuid)
  from public, anon;
revoke all on function public.get_field_permission_audit_logs(text, text, uuid, integer)
  from public, anon;

grant execute on function public.get_field_permission_resources()
  to authenticated, service_role;
grant execute on function public.get_field_permission_configuration(text, text, uuid)
  to authenticated, service_role;
grant execute on function public.get_field_permission_audit_logs(text, text, uuid, integer)
  to authenticated, service_role;

;
