begin;
create or replace function app_private.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select user_row.id
  from public.sys_user user_row
  where user_row.auth_user_id = (select auth.uid())
    and user_row.deleted_at is null
  limit 1
$function$;
revoke all on function app_private.current_user_id() from public, anon;
grant execute on function app_private.current_user_id() to authenticated;
create table if not exists public.smis_document_category (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  parent_id uuid,
  category_name text not null,
  sort integer not null default 10,
  status text not null default 'enabled',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_document_category_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_document_category_id_tenant_key unique (id, tenant_id),
  constraint smis_document_category_parent_fkey foreign key (parent_id, tenant_id)
    references public.smis_document_category(id, tenant_id) on delete restrict,
  constraint smis_document_category_parent_check check (parent_id is null or parent_id <> id),
  constraint smis_document_category_name_check check (
    btrim(category_name) <> '' and char_length(category_name) <= 100
  ),
  constraint smis_document_category_sort_check check (sort between 0 and 999999),
  constraint smis_document_category_status_check check (status in ('enabled', 'disabled')),
  constraint smis_document_category_description_check check (
    description is null or char_length(description) <= 1000
  )
);
create unique index if not exists smis_document_category_sibling_name_unique
  on public.smis_document_category(
    tenant_id,
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(category_name)
  );
create index if not exists smis_document_category_parent_idx
  on public.smis_document_category(tenant_id, parent_id, sort, category_name);
create table if not exists public.smis_document (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  category_id uuid not null,
  title text not null,
  status text not null default 'draft',
  creator_user_id uuid not null default app_private.current_user_id(),
  summary text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_document_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_document_id_tenant_key unique (id, tenant_id),
  constraint smis_document_category_fkey foreign key (category_id, tenant_id)
    references public.smis_document_category(id, tenant_id) on delete restrict,
  constraint smis_document_creator_fkey foreign key (creator_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict,
  constraint smis_document_title_check check (
    btrim(title) <> '' and char_length(title) <= 200
  ),
  constraint smis_document_status_check check (
    status in ('published', 'draft', 'void', 'archived')
  ),
  constraint smis_document_summary_check check (
    summary is null or char_length(summary) <= 2000
  )
);
create index if not exists smis_document_scope_idx
  on public.smis_document(tenant_id, status, category_id, update_time desc);
create index if not exists smis_document_creator_idx
  on public.smis_document(creator_user_id, update_time desc);
create index if not exists smis_document_search_idx
  on public.smis_document(tenant_id, lower(title));
create table if not exists public.smis_document_version (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  document_id uuid not null,
  version_no integer not null,
  file_name text not null,
  file_url text not null,
  file_type text,
  file_size bigint,
  effective_date date not null,
  replacement_note text,
  uploaded_by_user_id uuid not null default app_private.current_user_id(),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_document_version_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_document_version_parent_fkey foreign key (document_id, tenant_id)
    references public.smis_document(id, tenant_id) on delete cascade,
  constraint smis_document_version_uploader_fkey foreign key (uploaded_by_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict,
  constraint smis_document_version_unique unique (document_id, version_no),
  constraint smis_document_version_no_check check (version_no > 0),
  constraint smis_document_version_name_check check (
    btrim(file_name) <> '' and char_length(file_name) <= 255
  ),
  constraint smis_document_version_url_check check (
    btrim(file_url) <> '' and char_length(file_url) <= 4000
  ),
  constraint smis_document_version_size_check check (file_size is null or file_size >= 0),
  constraint smis_document_version_note_check check (
    replacement_note is null or char_length(replacement_note) <= 1000
  )
);
create index if not exists smis_document_version_effective_idx
  on public.smis_document_version(document_id, effective_date desc, version_no desc);
create index if not exists smis_document_version_filename_idx
  on public.smis_document_version(tenant_id, lower(file_name));
create table if not exists public.smis_document_follow (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  document_id uuid not null,
  user_id uuid not null default app_private.current_user_id(),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_document_follow_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_document_follow_document_fkey foreign key (document_id, tenant_id)
    references public.smis_document(id, tenant_id) on delete cascade,
  constraint smis_document_follow_user_fkey foreign key (user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete cascade,
  constraint smis_document_follow_unique unique (document_id, user_id)
);
create index if not exists smis_document_follow_user_idx
  on public.smis_document_follow(user_id, create_time desc);
create table if not exists public.smis_document_share (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  document_id uuid not null,
  shared_by_user_id uuid not null default app_private.current_user_id(),
  shared_to_user_id uuid not null,
  message text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_document_share_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_document_share_document_fkey foreign key (document_id, tenant_id)
    references public.smis_document(id, tenant_id) on delete cascade,
  constraint smis_document_share_sender_fkey foreign key (shared_by_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete cascade,
  constraint smis_document_share_recipient_fkey foreign key (shared_to_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete cascade,
  constraint smis_document_share_self_check check (shared_by_user_id <> shared_to_user_id),
  constraint smis_document_share_unique unique (document_id, shared_by_user_id, shared_to_user_id),
  constraint smis_document_share_message_check check (
    message is null or char_length(message) <= 500
  )
);
create index if not exists smis_document_share_sender_idx
  on public.smis_document_share(shared_by_user_id, create_time desc);
create index if not exists smis_document_share_recipient_idx
  on public.smis_document_share(shared_to_user_id, create_time desc);
create trigger smis_document_category_create_audit
before insert on public.smis_document_category
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_document_category_update_audit
before update on public.smis_document_category
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_document_create_audit
before insert on public.smis_document
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_document_update_audit
before update on public.smis_document
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_document_version_create_audit
before insert on public.smis_document_version
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_document_version_update_audit
before update on public.smis_document_version
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_document_follow_create_audit
before insert on public.smis_document_follow
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_document_follow_update_audit
before update on public.smis_document_follow
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_document_share_create_audit
before insert on public.smis_document_share
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_document_share_update_audit
before update on public.smis_document_share
for each row execute function public.trg_set_update_time_and_by();
alter table public.smis_document_category enable row level security;
alter table public.smis_document enable row level security;
alter table public.smis_document_version enable row level security;
alter table public.smis_document_follow enable row level security;
alter table public.smis_document_share enable row level security;
create policy smis_document_category_tenant_select on public.smis_document_category
for select to authenticated using (
  app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id()
);
create policy smis_document_category_tenant_insert on public.smis_document_category
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:CategoryAdd')
);
create policy smis_document_category_tenant_update on public.smis_document_category
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:CategoryEdit')
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:CategoryEdit')
);
create policy smis_document_category_tenant_delete on public.smis_document_category
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:CategoryDelete')
);
create policy smis_document_tenant_select on public.smis_document
for select to authenticated using (
  app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id()
);
create policy smis_document_tenant_insert on public.smis_document
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:Add')
);
create policy smis_document_tenant_update on public.smis_document
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:Edit')
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:Edit')
);
create policy smis_document_tenant_delete on public.smis_document
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:Delete')
);
create policy smis_document_version_tenant_select on public.smis_document_version
for select to authenticated using (
  app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id()
);
create policy smis_document_version_tenant_insert on public.smis_document_version
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:Upload')
);
create policy smis_document_version_tenant_update on public.smis_document_version
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:Edit')
) with check (
  app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id()
);
create policy smis_document_version_tenant_delete on public.smis_document_version
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and app_private.has_permission('SmisAllDocuments:Delete')
);
create policy smis_document_follow_tenant_select on public.smis_document_follow
for select to authenticated using (
  app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id()
);
create policy smis_document_follow_tenant_insert on public.smis_document_follow
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and user_id = app_private.current_user_id()
  and app_private.has_permission('SmisAllDocuments:Follow')
);
create policy smis_document_follow_tenant_update on public.smis_document_follow
for update to authenticated using (false) with check (false);
create policy smis_document_follow_tenant_delete on public.smis_document_follow
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and user_id = app_private.current_user_id()
  and app_private.has_permission('SmisAllDocuments:Follow')
);
create policy smis_document_share_tenant_select on public.smis_document_share
for select to authenticated using (
  app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id()
);
create policy smis_document_share_tenant_insert on public.smis_document_share
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and shared_by_user_id = app_private.current_user_id()
  and app_private.has_permission('SmisAllDocuments:Share')
);
create policy smis_document_share_tenant_update on public.smis_document_share
for update to authenticated using (false) with check (false);
create policy smis_document_share_tenant_delete on public.smis_document_share
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
  and shared_by_user_id = app_private.current_user_id()
  and app_private.has_permission('SmisAllDocuments:Share')
);
revoke all on table public.smis_document_category from anon, authenticated;
revoke all on table public.smis_document from anon, authenticated;
revoke all on table public.smis_document_version from anon, authenticated;
revoke all on table public.smis_document_follow from anon, authenticated;
revoke all on table public.smis_document_share from anon, authenticated;
grant select on table public.smis_document_category to authenticated;
grant select on table public.smis_document to authenticated;
grant select on table public.smis_document_version to authenticated;
grant select on table public.smis_document_follow to authenticated;
grant select on table public.smis_document_share to authenticated;
create or replace function public.smis_list_document_categories_secure()
returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看文档分类' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAllDocuments:View') then
    raise exception '当前账号没有查看全部文档的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', category.id,
        'parentId', category.parent_id,
        'categoryName', category.category_name,
        'sort', category.sort,
        'status', category.status,
        'description', category.description,
        'documentCount', (
          select count(*) from public.smis_document document
          where document.tenant_id = category.tenant_id
            and document.category_id = category.id
            and document.status <> 'void'
        ),
        'createTime', category.create_time,
        'updateTime', category.update_time
      ) order by category.sort, category.category_name
    )
    from public.smis_document_category category
    where category.tenant_id = v_tenant_id
  ), '[]'::jsonb);
end;
$function$;
create or replace function public.smis_save_document_secure(
  p_id uuid,
  p_payload jsonb
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_user_id uuid := app_private.current_user_id();
  v_category_id uuid;
  v_title text := btrim(coalesce(p_payload->>'title', ''));
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'draft');
  v_summary text := nullif(btrim(coalesce(p_payload->>'summary', '')), '');
  v_file_name text := nullif(btrim(coalesce(p_payload->>'file_name', '')), '');
  v_file_url text := nullif(btrim(coalesce(p_payload->>'file_url', '')), '');
  v_file_type text := nullif(btrim(coalesce(p_payload->>'file_type', '')), '');
  v_file_size bigint;
  v_effective_date date;
  v_replacement_note text := nullif(btrim(coalesce(p_payload->>'replacement_note', '')), '');
  v_duplicate_action text := coalesce(nullif(p_payload->>'duplicate_action', ''), 'none');
  v_duplicate_document_id uuid;
  v_document_id uuid := p_id;
  v_version_no integer;
  v_scenario_id uuid;
  v_replaced boolean := false;
begin
  if v_user_id is null then
    raise exception '请先登录后再保存文档' using errcode = '42501';
  end if;
  begin
    v_category_id := nullif(p_payload->>'category_id', '')::uuid;
    v_duplicate_document_id := nullif(p_payload->>'duplicate_document_id', '')::uuid;
    v_file_size := nullif(p_payload->>'file_size', '')::bigint;
    v_effective_date := nullif(p_payload->>'effective_date', '')::date;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception '文档分类、文件大小或实施日期无效' using errcode = '22023';
  end;
  if v_title = '' or char_length(v_title) > 200 then
    raise exception '文档标题不能为空且不能超过 200 个字符' using errcode = '22023';
  end if;
  if v_status not in ('published', 'draft', 'void', 'archived') then
    raise exception '文档状态无效' using errcode = '22023';
  end if;
  if char_length(coalesce(v_summary, '')) > 2000 then
    raise exception '文档摘要不能超过 2000 个字符' using errcode = '22023';
  end if;
  if v_duplicate_action not in ('none', 'replace', 'keep_both') then
    raise exception '重复文件处理方式无效' using errcode = '22023';
  end if;
  if (v_file_name is null) <> (v_file_url is null) then
    raise exception '文件名称与访问地址必须同时提供' using errcode = '22023';
  end if;
  if v_file_name is not null and (
    char_length(v_file_name) > 255 or char_length(v_file_url) > 4000
    or v_effective_date is null or coalesce(v_file_size, 0) < 0
  ) then
    raise exception '文件信息不完整，请检查文件名、地址、大小和实施日期' using errcode = '22023';
  end if;
  if char_length(coalesce(v_replacement_note, '')) > 1000 then
    raise exception '更新说明不能超过 1000 个字符' using errcode = '22023';
  end if;

  v_tenant_id := app_private.current_user_tenant_id();
  if not exists (
    select 1 from public.smis_document_category category
    where category.id = v_category_id and category.tenant_id = v_tenant_id
      and category.status = 'enabled'
  ) then
    raise exception '文档分类不存在、已停用或不属于当前租户' using errcode = 'P0002';
  end if;

  if p_id is null then
    if v_file_url is null then
      if not app_private.has_permission('SmisAllDocuments:Add') then
        raise exception '当前账号没有新增文档的权限' using errcode = '42501';
      end if;
    elsif not app_private.has_permission('SmisAllDocuments:Upload') then
      raise exception '当前账号没有上传文档的权限' using errcode = '42501';
    end if;

    if v_duplicate_action = 'replace' then
      if v_duplicate_document_id is null then
        raise exception '请选择要替换的同名文档' using errcode = '22023';
      end if;
      select document.id into v_document_id
      from public.smis_document document
      where document.id = v_duplicate_document_id
        and document.tenant_id = v_tenant_id
        and document.category_id = v_category_id;
      if v_document_id is null then
        raise exception '待替换文档不存在或不属于当前分类' using errcode = 'P0002';
      end if;
      v_replaced := true;
      update public.smis_document set
        title = v_title,
        status = v_status,
        summary = v_summary
      where id = v_document_id and tenant_id = v_tenant_id;
    else
      insert into public.smis_document(
        tenant_id, category_id, title, status, creator_user_id, summary
      ) values (
        v_tenant_id, v_category_id, v_title, v_status, v_user_id, v_summary
      ) returning id into v_document_id;
    end if;
  else
    if v_file_url is not null then
      if not app_private.has_permission('SmisAllDocuments:Upload') then
        raise exception '当前账号没有上传文档新版本的权限' using errcode = '42501';
      end if;
    elsif not app_private.has_permission('SmisAllDocuments:Edit') then
      raise exception '当前账号没有编辑文档的权限' using errcode = '42501';
    end if;
    update public.smis_document set
      category_id = v_category_id,
      title = v_title,
      status = v_status,
      summary = v_summary
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_document_id;
    if v_document_id is null then
      raise exception '文档不存在或不属于当前租户' using errcode = 'P0002';
    end if;
  end if;

  if v_file_url is not null then
    select coalesce(max(version.version_no), 0) + 1 into v_version_no
    from public.smis_document_version version
    where version.document_id = v_document_id;
    insert into public.smis_document_version(
      tenant_id, document_id, version_no, file_name, file_url, file_type,
      file_size, effective_date, replacement_note, uploaded_by_user_id
    ) values (
      v_tenant_id, v_document_id, v_version_no, v_file_name, v_file_url, v_file_type,
      v_file_size, v_effective_date, v_replacement_note, v_user_id
    );
    update public.smis_document set update_time = now()
    where id = v_document_id and tenant_id = v_tenant_id;

    if v_effective_date > (now() at time zone 'Asia/Shanghai')::date then
      select scenario.id into v_scenario_id
      from public.sys_notification_scenario scenario
      where scenario.scenario_code = 'smis_document_effective' and scenario.enabled is true;
      if v_scenario_id is not null then
        insert into public.sys_notification_subject(
          tenant_id, scenario_id, business_type, business_id, subject_key,
          subject_title, due_at, owner_user_id, route_path, route_query,
          metadata, status, create_by, update_by
        ) values (
          v_tenant_id, v_scenario_id, 'smis_document', v_document_id,
          'version-' || v_version_no,
          '文档“' || v_title || '”第 ' || v_version_no || ' 版即将实施',
          (v_effective_date + time '09:00') at time zone 'Asia/Shanghai',
          v_user_id, '/safety-production/document-center/all-documents',
          jsonb_build_object('documentId', v_document_id),
          jsonb_build_object(
            'fileName', v_file_name,
            'versionNo', v_version_no,
            'effectiveDate', v_effective_date
          ),
          'active', 'system-document-center', 'system-document-center'
        ) on conflict (
          tenant_id, scenario_id, business_type, business_id, subject_key
        ) do update set
          subject_title = excluded.subject_title,
          due_at = excluded.due_at,
          owner_user_id = excluded.owner_user_id,
          route_path = excluded.route_path,
          route_query = excluded.route_query,
          metadata = excluded.metadata,
          status = 'active',
          update_by = 'system-document-center';
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'id', v_document_id,
    'versionNo', v_version_no,
    'replaced', v_replaced
  );
end;
$function$;
create or replace function public.smis_delete_documents_secure(p_ids uuid[])
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除文档' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAllDocuments:Delete') then
    raise exception '当前账号没有删除文档的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的文档' using errcode = '22023';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if exists (
    select 1 from public.smis_document document
    where document.tenant_id = v_tenant_id and document.id = any(v_ids)
      and document.status <> 'draft'
  ) then
    raise exception '仅草稿文档允许删除，已发布文档请改为作废或归档' using errcode = 'P0001';
  end if;
  update public.sys_notification_subject set status = 'cancelled', update_by = 'system-document-center'
  where tenant_id = v_tenant_id and business_type = 'smis_document'
    and business_id = any(v_ids) and status = 'active';
  delete from public.smis_document
  where tenant_id = v_tenant_id and status = 'draft' and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
create or replace function public.smis_toggle_document_follow_secure(
  p_document_id uuid,
  p_follow boolean
) returns boolean
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_user_id uuid := app_private.current_user_id();
begin
  if v_user_id is null then
    raise exception '请先登录后再关注文档' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAllDocuments:Follow') then
    raise exception '当前账号没有关注文档的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if not exists (
    select 1 from public.smis_document document
    where document.id = p_document_id and document.tenant_id = v_tenant_id
  ) then
    raise exception '文档不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  if coalesce(p_follow, false) then
    insert into public.smis_document_follow(tenant_id, document_id, user_id)
    values (v_tenant_id, p_document_id, v_user_id)
    on conflict (document_id, user_id) do nothing;
  else
    delete from public.smis_document_follow
    where tenant_id = v_tenant_id and document_id = p_document_id and user_id = v_user_id;
  end if;
  return coalesce(p_follow, false);
end;
$function$;
create or replace function public.smis_share_document_secure(
  p_document_id uuid,
  p_user_ids uuid[],
  p_message text default null
) returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_user_id uuid := app_private.current_user_id();
  v_user_ids uuid[] := coalesce(p_user_ids, array[]::uuid[]);
  v_message text := nullif(btrim(coalesce(p_message, '')), '');
  v_document_title text;
  v_sender_name text;
  v_share_id uuid;
  v_recipient_id uuid;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception '请先登录后再分享文档' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAllDocuments:Share') then
    raise exception '当前账号没有分享文档的权限' using errcode = '42501';
  end if;
  if cardinality(v_user_ids) = 0 then
    raise exception '请至少选择一名分享对象' using errcode = '22023';
  end if;
  if v_user_id = any(v_user_ids) then
    raise exception '不能将文档分享给自己' using errcode = '22023';
  end if;
  if char_length(coalesce(v_message, '')) > 500 then
    raise exception '分享留言不能超过 500 个字符' using errcode = '22023';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  select document.title into v_document_title
  from public.smis_document document
  where document.id = p_document_id and document.tenant_id = v_tenant_id;
  if v_document_title is null then
    raise exception '文档不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from unnest(v_user_ids) requested(user_id)
    left join public.sys_user user_row
      on user_row.id = requested.user_id and user_row.tenant_id = v_tenant_id
      and user_row.status = '1' and user_row.deleted_at is null
    where user_row.id is null
  ) then
    raise exception '分享对象包含无效、停用或跨租户用户' using errcode = 'P0002';
  end if;
  select coalesce(user_row.nick_name, user_row.user_name, user_row.user_email, '同事')
  into v_sender_name
  from public.sys_user user_row where user_row.id = v_user_id;

  foreach v_recipient_id in array v_user_ids loop
    insert into public.smis_document_share(
      tenant_id, document_id, shared_by_user_id, shared_to_user_id, message
    ) values (
      v_tenant_id, p_document_id, v_user_id, v_recipient_id, v_message
    ) on conflict (document_id, shared_by_user_id, shared_to_user_id)
    do update set message = excluded.message, update_time = now()
    returning id into v_share_id;
    perform app_private.enqueue_user_notification(
      v_recipient_id,
      v_tenant_id,
      'message',
      '收到共享文档',
      v_sender_name || '向你分享了文档“' || v_document_title || '”' ||
        case when v_message is null then '。' else '：' || v_message end,
      'info',
      'smis_document_share',
      v_share_id,
      'smis_document',
      p_document_id,
      null,
      '/safety-production/document-center/all-documents',
      jsonb_build_object('documentId', p_document_id)
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;
create or replace function public.smis_save_document_category_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_parent_id uuid;
  v_name text := btrim(coalesce(p_payload->>'category_name', ''));
  v_sort integer := coalesce(nullif(p_payload->>'sort', '')::integer, 10);
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'enabled');
  v_description text := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护文档分类' using errcode = '42501';
  end if;
  if not app_private.has_permission(
    case when p_id is null then 'SmisAllDocuments:CategoryAdd'
      else 'SmisAllDocuments:CategoryEdit' end
  ) then
    raise exception '当前账号没有维护文档分类的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  begin
    v_parent_id := nullif(p_payload->>'parent_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception '上级分类无效' using errcode = '22023';
  end;
  if v_name = '' or char_length(v_name) > 100 then
    raise exception '分类名称不能为空且不能超过 100 个字符' using errcode = '22023';
  end if;
  if v_sort < 0 or v_sort > 999999 then
    raise exception '分类排序须在 0 到 999999 之间' using errcode = '22023';
  end if;
  if v_status not in ('enabled', 'disabled') then
    raise exception '分类状态无效' using errcode = '22023';
  end if;
  if char_length(coalesce(v_description, '')) > 1000 then
    raise exception '分类说明不能超过 1000 个字符' using errcode = '22023';
  end if;
  if v_parent_id is not null and not exists (
    select 1 from public.smis_document_category category
    where category.id = v_parent_id and category.tenant_id = v_tenant_id
  ) then
    raise exception '上级分类不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  if p_id is not null and v_parent_id is not null and exists (
    with recursive descendants as (
      select category.id from public.smis_document_category category
      where category.id = p_id and category.tenant_id = v_tenant_id
      union all
      select child.id from public.smis_document_category child
      join descendants parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant_id
    )
    select 1 from descendants where id = v_parent_id
  ) then
    raise exception '不能将分类移动到自身或下级分类中' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.smis_document_category(
      tenant_id, parent_id, category_name, sort, status, description
    ) values (
      v_tenant_id, v_parent_id, v_name, v_sort, v_status, v_description
    ) returning id into v_result;
  else
    update public.smis_document_category set
      parent_id = v_parent_id,
      category_name = v_name,
      sort = v_sort,
      status = v_status,
      description = v_description
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result;
    if v_result is null then
      raise exception '文档分类不存在或不属于当前租户' using errcode = 'P0002';
    end if;
  end if;
  return v_result;
exception when unique_violation then
  raise exception '同一上级分类下已存在相同名称' using errcode = '23505';
end;
$function$;
create or replace function public.smis_delete_document_categories_secure(p_ids uuid[])
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除文档分类' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAllDocuments:CategoryDelete') then
    raise exception '当前账号没有删除文档分类的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的文档分类' using errcode = '22023';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if exists (
    select 1 from public.smis_document_category category
    where category.tenant_id = v_tenant_id
      and (category.parent_id = any(v_ids) or category.id = any(v_ids))
      and (
        category.parent_id = any(v_ids)
        or exists (
          select 1 from public.smis_document document
          where document.category_id = category.id and document.tenant_id = v_tenant_id
        )
      )
  ) then
    raise exception '分类下仍有子分类或文档，请先完成移动或清理' using errcode = 'P0001';
  end if;
  delete from public.smis_document_category
  where tenant_id = v_tenant_id and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
create or replace function public.smis_find_document_duplicate_secure(
  p_category_id uuid,
  p_file_name text,
  p_exclude_document_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再检查重复文档' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAllDocuments:View') then
    raise exception '当前账号没有查看全部文档的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  return coalesce((
    select jsonb_build_object(
      'id', document.id,
      'title', document.title,
      'status', document.status,
      'categoryId', document.category_id,
      'fileName', version.file_name,
      'versionNo', version.version_no,
      'effectiveDate', version.effective_date,
      'updateTime', document.update_time
    )
    from public.smis_document document
    join lateral (
      select item.* from public.smis_document_version item
      where item.document_id = document.id
      order by item.effective_date desc, item.version_no desc
      limit 1
    ) version on true
    where document.tenant_id = v_tenant_id
      and document.category_id = p_category_id
      and document.status <> 'void'
      and lower(version.file_name) = lower(btrim(coalesce(p_file_name, '')))
      and (p_exclude_document_id is null or document.id <> p_exclude_document_id)
    order by document.update_time desc
    limit 1
  ), 'null'::jsonb);
end;
$function$;
create or replace function public.smis_list_documents_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_category_id uuid default null,
  p_scope text default 'all',
  p_ids uuid[] default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_user_id uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_limit integer;
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看文档' using errcode = '42501';
  end if;
  if not app_private.has_permission(
    case when p_purpose = 'export' then 'SmisAllDocuments:Export'
      else 'SmisAllDocuments:View' end
  ) then
    raise exception '当前账号没有查看或导出文档的权限' using errcode = '42501';
  end if;
  if coalesce(p_scope, 'all') not in ('all', 'created', 'following', 'shared_by_me', 'shared_to_me') then
    raise exception '文档范围无效' using errcode = '22023';
  end if;
  if p_status is not null and p_status not in ('published', 'draft', 'void', 'archived') then
    raise exception '文档状态无效' using errcode = '22023';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  v_user_id := app_private.current_user_id();
  v_limit := least(v_to - v_from + 1, case when p_purpose = 'export' then 10000 else 200 end);

  with recursive category_paths as (
    select category.id, category.parent_id, category.category_name,
      category.category_name::text as category_path
    from public.smis_document_category category
    where category.tenant_id = v_tenant_id and category.parent_id is null
    union all
    select child.id, child.parent_id, child.category_name,
      parent.category_path || ' / ' || child.category_name
    from public.smis_document_category child
    join category_paths parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  ), selected_categories as (
    select category.id from public.smis_document_category category
    where category.id = p_category_id and category.tenant_id = v_tenant_id
    union all
    select child.id from public.smis_document_category child
    join selected_categories parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  ), base as (
    select
      document.*,
      category.category_name,
      category.category_path,
      coalesce(creator.nick_name, creator.user_name, creator.user_email, '未命名用户') creator_name,
      display_version.file_name,
      display_version.file_url,
      display_version.file_type,
      display_version.file_size,
      display_version.version_no current_version_no,
      display_version.effective_date current_effective_date,
      latest_version.version_no latest_version_no,
      latest_version.effective_date latest_effective_date,
      case when latest_version.effective_date > current_date
        then latest_version.effective_date else null end scheduled_effective_date,
      case
        when latest_version.id is null then 'no_file'
        when latest_version.effective_date > current_date then 'scheduled'
        else 'effective'
      end implementation_state,
      exists (
        select 1 from public.smis_document_follow follow
        where follow.document_id = document.id and follow.user_id = v_user_id
      ) is_following,
      (
        select count(*) from public.smis_document_share share
        where share.document_id = document.id and share.shared_by_user_id = v_user_id
      ) shared_by_me_count,
      exists (
        select 1 from public.smis_document_share share
        where share.document_id = document.id and share.shared_to_user_id = v_user_id
      ) shared_to_me
    from public.smis_document document
    join category_paths category on category.id = document.category_id
    join public.sys_user creator
      on creator.id = document.creator_user_id and creator.tenant_id = document.tenant_id
    left join lateral (
      select version.* from public.smis_document_version version
      where version.document_id = document.id
      order by version.effective_date desc, version.version_no desc
      limit 1
    ) latest_version on true
    left join lateral (
      select version.* from public.smis_document_version version
      where version.document_id = document.id and version.effective_date <= current_date
      order by version.effective_date desc, version.version_no desc
      limit 1
    ) effective_version on true
    left join lateral (
      select coalesce(effective_version.id, latest_version.id) id,
        coalesce(effective_version.version_no, latest_version.version_no) version_no,
        coalesce(effective_version.file_name, latest_version.file_name) file_name,
        coalesce(effective_version.file_url, latest_version.file_url) file_url,
        coalesce(effective_version.file_type, latest_version.file_type) file_type,
        coalesce(effective_version.file_size, latest_version.file_size) file_size,
        coalesce(effective_version.effective_date, latest_version.effective_date) effective_date
    ) display_version on true
    where document.tenant_id = v_tenant_id
      and (p_category_id is null or document.category_id in (select id from selected_categories))
      and (p_ids is null or document.id = any(p_ids))
  ), scoped as (
    select base.* from base
    where case coalesce(p_scope, 'all')
      when 'created' then base.creator_user_id = v_user_id
      when 'following' then base.is_following
      when 'shared_by_me' then base.shared_by_me_count > 0
      when 'shared_to_me' then base.shared_to_me
      else true end
  ), filtered as (
    select scoped.* from scoped
    where (p_status is null or scoped.status = p_status)
      and (
        v_keyword is null
        or scoped.title ilike '%' || v_keyword || '%'
        or scoped.file_name ilike '%' || v_keyword || '%'
        or scoped.category_path ilike '%' || v_keyword || '%'
      )
  ), page_rows as (
    select * from filtered
    order by
      case when implementation_state = 'scheduled' then 0 else 1 end,
      update_time desc,
      title
    offset v_from limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', row.id,
        'categoryId', row.category_id,
        'categoryName', row.category_name,
        'categoryPath', row.category_path,
        'title', row.title,
        'status', row.status,
        'summary', row.summary,
        'creatorUserId', row.creator_user_id,
        'creatorName', row.creator_name,
        'versionNo', row.current_version_no,
        'latestVersionNo', row.latest_version_no,
        'fileName', row.file_name,
        'fileUrl', row.file_url,
        'fileType', row.file_type,
        'fileSize', row.file_size,
        'effectiveDate', row.current_effective_date,
        'latestEffectiveDate', row.latest_effective_date,
        'scheduledEffectiveDate', row.scheduled_effective_date,
        'implementationState', row.implementation_state,
        'isFollowing', row.is_following,
        'sharedByMeCount', row.shared_by_me_count,
        'sharedToMe', row.shared_to_me,
        'createBy', row.create_by,
        'createTime', row.create_time,
        'updateBy', row.update_by,
        'updateTime', row.update_time
      ) order by
        case when row.implementation_state = 'scheduled' then 0 else 1 end,
        row.update_time desc,
        row.title
      ) from page_rows row
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', jsonb_build_object(
      'total', (select count(*) from scoped),
      'published', (select count(*) from scoped where status = 'published'),
      'draft', (select count(*) from scoped where status = 'draft'),
      'scheduled', (select count(*) from scoped where implementation_state = 'scheduled')
    )
  ) into v_result;
  return v_result;
end;
$function$;
revoke all on function public.smis_list_document_categories_secure() from public, anon;
grant execute on function public.smis_list_document_categories_secure() to authenticated;
revoke all on function public.smis_save_document_category_secure(uuid, jsonb) from public, anon;
grant execute on function public.smis_save_document_category_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_delete_document_categories_secure(uuid[]) from public, anon;
grant execute on function public.smis_delete_document_categories_secure(uuid[]) to authenticated;
revoke all on function public.smis_find_document_duplicate_secure(uuid, text, uuid) from public, anon;
grant execute on function public.smis_find_document_duplicate_secure(uuid, text, uuid) to authenticated;
revoke all on function public.smis_list_documents_secure(integer, integer, text, text, uuid, text, uuid[], text) from public, anon;
grant execute on function public.smis_list_documents_secure(integer, integer, text, text, uuid, text, uuid[], text) to authenticated;
revoke all on function public.smis_save_document_secure(uuid, jsonb) from public, anon;
grant execute on function public.smis_save_document_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_delete_documents_secure(uuid[]) from public, anon;
grant execute on function public.smis_delete_documents_secure(uuid[]) to authenticated;
revoke all on function public.smis_toggle_document_follow_secure(uuid, boolean) from public, anon;
grant execute on function public.smis_toggle_document_follow_secure(uuid, boolean) to authenticated;
revoke all on function public.smis_share_document_secure(uuid, uuid[], text) from public, anon;
grant execute on function public.smis_share_document_secure(uuid, uuid[], text) to authenticated;
insert into public.sys_notification_scenario(
  scenario_code, scenario_name, module_code, description, route_path,
  sort, enabled, builtin, create_by, update_by
) values (
  'smis_document_effective', '文档版本实施提醒', 'system',
  '文档新版本在实施日期前提醒创建人及租户管理角色。',
  '/safety-production/document-center/all-documents',
  660, true, true, '624944977@qq.com', '624944977@qq.com'
) on conflict (scenario_code) do update set
  scenario_name = excluded.scenario_name,
  module_code = excluded.module_code,
  description = excluded.description,
  route_path = excluded.route_path,
  enabled = true,
  update_by = '624944977@qq.com';
insert into public.sys_notification_rule(
  tenant_id, scenario_id, rule_name, lead_days, repeat_every_days,
  send_hour, recipient_strategy, recipient_role_codes, channels,
  enabled, create_by, update_by
)
select tenant.id, scenario.id, rule.rule_name, rule.lead_days,
  rule.repeat_every_days, 9, 'owner_then_roles',
  array['R_ADMIN', 'YQ_ADMIN', 'R_SUPER']::text[], array['in_app']::text[],
  true, 'system-document-center', 'system-document-center'
from public.sys_tenant tenant
cross join public.sys_notification_scenario scenario
cross join (
  values
    ('提前 7 天每天提醒'::text, 7::integer, 1::integer),
    ('实施当天提醒一次'::text, 0::integer, null::integer)
) rule(rule_name, lead_days, repeat_every_days)
where tenant.status = '1' and scenario.scenario_code = 'smis_document_effective'
on conflict (tenant_id, scenario_id, rule_name) do nothing;
with dictionary_type as (
  insert into public.sys_dict_type(
    id, parent_id, name, code, status, node_type, sort,
    tenant_id, create_by, update_by, remark
  )
  select gen_random_uuid(), parent.id, '文档状态', 'smisDocumentStatus',
    '1', 'dictionary', 70, app_private.platform_tenant_id(),
    '624944977@qq.com', '624944977@qq.com', 'SMIS 文档中心状态字典'
  from public.sys_dict_type parent
  where parent.code = 'smisSafetyProduction'
    and not exists (
      select 1 from public.sys_dict_type existing
      where existing.code = 'smisDocumentStatus'
    )
  returning id
)
select id from dictionary_type;
with dictionary_items(value, label, color, tag_type, sort) as (
  values
    ('published', '已发布', '#16a34a', 'success', 1),
    ('draft', '草稿', '#d97706', 'warning', 2),
    ('void', '作废', '#dc2626', 'danger', 3),
    ('archived', '归档', '#64748b', 'info', 4)
)
insert into public.sys_dictionary(
  id, type_id, code, status, value, label, color, tag_type, sort,
  tenant_id, create_by, update_by, remark
)
select gen_random_uuid(), type.id, 'smisDocumentStatus_' || item.value,
  '1', item.value, item.label, item.color, item.tag_type, item.sort,
  app_private.platform_tenant_id(), '624944977@qq.com', '624944977@qq.com',
  'SMIS 文档中心默认状态'
from dictionary_items item
join public.sys_dict_type type on type.code = 'smisDocumentStatus'
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = type.id and existing.value = item.value
);
with seed_categories(parent_name, category_name, sort) as (
  values
    (null::text, '企业制度', 10),
    (null::text, '销售相关', 20),
    (null::text, '检验标准', 30),
    (null::text, '常见问题', 40),
    (null::text, '知识地图', 50),
    (null::text, '党建建设', 60),
    (null::text, '协同理念', 70),
    (null::text, '工作执行体系', 80),
    (null::text, '知识管理体系', 90),
    (null::text, '暂存目录', 100)
)
insert into public.smis_document_category(
  tenant_id, parent_id, category_name, sort, status, description,
  create_by, update_by
)
select tenant.id, null, seed.category_name, seed.sort, 'enabled',
  '文档中心初始化分类', '624944977@qq.com', '624944977@qq.com'
from seed_categories seed
join public.sys_tenant tenant on tenant.tenant_code = 'public-register'
where not exists (
  select 1 from public.smis_document_category existing
  where existing.tenant_id = tenant.id and existing.parent_id is null
    and lower(existing.category_name) = lower(seed.category_name)
);
with child_categories(parent_name, category_name, sort) as (
  values
    ('企业制度', '人事制度', 10),
    ('企业制度', '行政制度', 20),
    ('企业制度', '财务制度', 30),
    ('企业制度', '图片存储', 40)
)
insert into public.smis_document_category(
  tenant_id, parent_id, category_name, sort, status, description,
  create_by, update_by
)
select tenant.id, parent.id, child.category_name, child.sort, 'enabled',
  '文档中心初始化分类', '624944977@qq.com', '624944977@qq.com'
from child_categories child
join public.sys_tenant tenant on tenant.tenant_code = 'public-register'
join public.smis_document_category parent
  on parent.tenant_id = tenant.id and parent.parent_id is null
  and parent.category_name = child.parent_name
where not exists (
  select 1 from public.smis_document_category existing
  where existing.tenant_id = tenant.id and existing.parent_id = parent.id
    and lower(existing.category_name) = lower(child.category_name)
);
with buttons(code, title, sort) as (
  values
    ('SmisAllDocuments:View', '查看全部文档', 1),
    ('SmisAllDocuments:Add', '新增文档', 2),
    ('SmisAllDocuments:Upload', '上传文档或新版本', 3),
    ('SmisAllDocuments:Edit', '编辑文档', 4),
    ('SmisAllDocuments:Delete', '删除草稿文档', 5),
    ('SmisAllDocuments:Export', '导出文档清单', 6),
    ('SmisAllDocuments:Follow', '关注或取消关注文档', 7),
    ('SmisAllDocuments:Share', '分享文档', 8),
    ('SmisAllDocuments:CategoryAdd', '新增文档分类', 9),
    ('SmisAllDocuments:CategoryEdit', '编辑文档分类', 10),
    ('SmisAllDocuments:CategoryDelete', '删除文档分类', 11)
)
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort,
  create_by, update_by, app_code
)
select gen_random_uuid(), parent.id, button.code, '', '', 'button',
  jsonb_build_object(
    'title', button.title, 'is_hide', true, 'is_enable', true, 'roles', '[]'::jsonb
  ), button.sort, '624944977@qq.com', '624944977@qq.com', 'smis'
from buttons button
join public.sys_menu parent on parent.name = 'SmisAllDocuments'
where not exists (
  select 1 from public.sys_menu existing where existing.name = button.code
);
insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by, update_by)
select distinct parent_grant.role_id, child.id, parent_grant.tenant_id,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu parent_grant
join public.sys_menu parent on parent.id = parent_grant.menu_id
join public.sys_menu child on child.parent_id = parent.id and child.type = 'button'
where parent.name = 'SmisAllDocuments'
on conflict (role_id, menu_id) do nothing;
commit;
