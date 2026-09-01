alter table public.wf_definition
  add constraint wf_definition_tenant_id_fkey
  foreign key (tenant_id) references public.sys_tenant(id) on delete restrict not valid;
alter table public.wf_definition
  validate constraint wf_definition_tenant_id_fkey;
create or replace function app_private.save_workflow_definition(p_definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_target_tenant_id uuid;
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_definition public.wf_definition;
  v_version public.wf_version;
  v_definition_id uuid;
  v_config jsonb := coalesce(p_definition -> 'config', '{"nodes":[]}'::jsonb);
  v_actor text;
begin
  if (select auth.uid()) is null or not v_is_platform_super then
    raise exception '当前账号没有流程配置权限' using errcode = '42501';
  end if;

  perform app_private.validate_workflow_config(v_config);
  v_actor := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);

  begin
    v_definition_id := nullif(p_definition ->> 'id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception '流程 ID 格式不正确';
  end;

  if v_definition_id is null then
    begin
      v_target_tenant_id := nullif(p_definition ->> 'tenantId', '')::uuid;
    exception
      when invalid_text_representation then
        raise exception '所属租户格式不正确';
    end;

    if not v_is_platform_super then
      v_target_tenant_id := v_current_tenant_id;
    else
      v_target_tenant_id := coalesce(v_target_tenant_id, v_current_tenant_id);
    end if;

    if not exists (
      select 1
      from public.sys_tenant t
      where t.id = v_target_tenant_id
        and t.status = '1'
    ) then
      raise exception '所属租户不存在或已停用';
    end if;

    insert into public.wf_definition(
      code,
      name,
      business_type,
      description,
      tenant_id,
      create_by,
      update_by
    )
    values (
      btrim(p_definition ->> 'code'),
      btrim(p_definition ->> 'name'),
      btrim(p_definition ->> 'businessType'),
      nullif(btrim(coalesce(p_definition ->> 'description', '')), ''),
      v_target_tenant_id,
      v_actor,
      v_actor
    )
    returning * into v_definition;

    insert into public.wf_version(
      definition_id,
      version_no,
      config,
      change_note,
      tenant_id,
      create_by,
      update_by
    )
    values (
      v_definition.id,
      1,
      v_config,
      nullif(btrim(coalesce(p_definition ->> 'changeNote', '')), ''),
      v_target_tenant_id,
      v_actor,
      v_actor
    )
    returning * into v_version;
  else
    select *
    into v_definition
    from public.wf_definition d
    where d.id = v_definition_id
      and (v_is_platform_super or d.tenant_id = v_current_tenant_id)
    for update;

    if not found then
      raise exception '流程不存在或无权编辑';
    end if;

    v_target_tenant_id := v_definition.tenant_id;

    if v_definition.current_version_id is not null and (
      v_definition.code <> btrim(p_definition ->> 'code')
      or v_definition.business_type <> btrim(p_definition ->> 'businessType')
    ) then
      raise exception '流程发布后不可修改流程编码和业务类型';
    end if;

    update public.wf_definition
    set name = btrim(p_definition ->> 'name'),
        description = nullif(btrim(coalesce(p_definition ->> 'description', '')), ''),
        update_by = v_actor
    where id = v_definition.id
    returning * into v_definition;

    select *
    into v_version
    from public.wf_version v
    where v.definition_id = v_definition.id
      and v.status = 'draft'
    for update;

    if found then
      update public.wf_version
      set config = v_config,
          change_note = nullif(btrim(coalesce(p_definition ->> 'changeNote', '')), ''),
          update_by = v_actor
      where id = v_version.id
      returning * into v_version;
    else
      insert into public.wf_version(
        definition_id,
        version_no,
        config,
        change_note,
        tenant_id,
        create_by,
        update_by
      )
      select v_definition.id,
             coalesce(max(v.version_no), 0) + 1,
             v_config,
             nullif(btrim(coalesce(p_definition ->> 'changeNote', '')), ''),
             v_target_tenant_id,
             v_actor,
             v_actor
      from public.wf_version v
      where v.definition_id = v_definition.id
      returning * into v_version;
    end if;
  end if;

  return jsonb_build_object(
    'definitionId', v_definition.id,
    'versionId', v_version.id,
    'versionNo', v_version.version_no,
    'tenantId', v_definition.tenant_id
  );
end;
$$;
create or replace function app_private.publish_workflow_definition(p_definition_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_target_tenant_id uuid;
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_definition public.wf_definition;
  v_version public.wf_version;
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);
begin
  if (select auth.uid()) is null or not v_is_platform_super then
    raise exception '当前账号没有流程发布权限' using errcode = '42501';
  end if;

  select *
  into v_definition
  from public.wf_definition d
  where d.id = p_definition_id
    and (v_is_platform_super or d.tenant_id = v_current_tenant_id)
  for update;

  if not found then
    raise exception '流程不存在或无权发布';
  end if;

  v_target_tenant_id := v_definition.tenant_id;
  perform pg_advisory_xact_lock(
    hashtextextended(v_target_tenant_id::text || ':' || v_definition.business_type, 81173)
  );

  if exists (
    select 1
    from public.wf_definition d
    where d.tenant_id = v_target_tenant_id
      and d.business_type = v_definition.business_type
      and d.status = 'published'
      and d.id <> v_definition.id
  ) then
    raise exception '该业务类型已有启用流程，请先停用后再发布';
  end if;

  select *
  into v_version
  from public.wf_version v
  where v.definition_id = v_definition.id
    and v.status = 'draft'
  for update;

  if not found then
    raise exception '没有可发布的草稿版本';
  end if;

  perform app_private.validate_workflow_config(v_version.config);

  update public.wf_version
  set status = 'retired', update_by = v_actor
  where definition_id = v_definition.id
    and status = 'published';

  update public.wf_version
  set status = 'published',
      published_at = now(),
      published_by = v_actor,
      update_by = v_actor
  where id = v_version.id
  returning * into v_version;

  update public.wf_definition
  set status = 'published',
      current_version_id = v_version.id,
      published_at = now(),
      published_by = v_actor,
      update_by = v_actor
  where id = v_definition.id;

  return jsonb_build_object(
    'definitionId', v_definition.id,
    'versionId', v_version.id,
    'versionNo', v_version.version_no,
    'tenantId', v_target_tenant_id
  );
end;
$$;
create or replace function app_private.set_workflow_definition_enabled(
  p_definition_id uuid,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_target_tenant_id uuid;
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_definition public.wf_definition;
begin
  if (select auth.uid()) is null or not v_is_platform_super then
    raise exception '当前账号没有流程启停权限' using errcode = '42501';
  end if;

  select *
  into v_definition
  from public.wf_definition d
  where d.id = p_definition_id
    and (v_is_platform_super or d.tenant_id = v_current_tenant_id)
  for update;

  if not found then
    raise exception '流程不存在或无权操作';
  end if;

  v_target_tenant_id := v_definition.tenant_id;

  if p_enabled and v_definition.current_version_id is null then
    raise exception '流程尚未发布，不能启用';
  end if;

  if p_enabled and exists (
    select 1
    from public.wf_definition d
    where d.tenant_id = v_target_tenant_id
      and d.business_type = v_definition.business_type
      and d.status = 'published'
      and d.id <> v_definition.id
  ) then
    raise exception '该业务类型已有启用流程';
  end if;

  update public.wf_definition
  set status = case when p_enabled then 'published' else 'disabled' end
  where id = p_definition_id;
end;
$$;
create or replace function app_private.delete_workflow_definition(p_definition_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_definition public.wf_definition;
begin
  if (select auth.uid()) is null or not v_is_platform_super then
    raise exception '当前账号没有流程删除权限' using errcode = '42501';
  end if;

  select *
  into v_definition
  from public.wf_definition d
  where d.id = p_definition_id
    and (v_is_platform_super or d.tenant_id = v_current_tenant_id)
  for update;

  if not found then
    raise exception '流程不存在或无权删除';
  end if;

  if exists (
    select 1
    from public.wf_instance i
    where i.definition_id = p_definition_id
  ) then
    raise exception '流程已有审批记录，不能删除，只能停用';
  end if;

  if not v_is_platform_super and v_definition.current_version_id is not null then
    raise exception '普通租户管理员只能删除未发布流程';
  end if;

  delete from public.wf_definition
  where id = p_definition_id;
end;
$$;
comment on constraint wf_definition_tenant_id_fkey on public.wf_definition is
  'Makes tenant ownership explicit for PostgREST joins and prevents orphan workflow definitions.';
update public.sys_menu
set meta = meta - 'roles',
    update_by = '624944977@qq.com',
    update_time = now()
where name = 'WorkflowDefinition';
insert into public.sys_role_menu(
  id,
  role_id,
  menu_id,
  permission,
  create_by,
  update_by,
  tenant_id
)
select gen_random_uuid(),
       r.id,
       m.id,
       '{}'::jsonb,
       '624944977@qq.com',
       '624944977@qq.com',
       r.tenant_id
from public.sys_role r
cross join public.sys_menu m
where r.enabled
  and m.name = 'WorkflowDefinition'
on conflict (role_id, menu_id) do nothing;
