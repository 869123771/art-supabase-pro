begin;
alter table public.smis_document
  add column if not exists document_kind text not null default 'general',
  add column if not exists document_code text,
  add column if not exists promulgation_date date,
  add column if not exists obtained_date date,
  add column if not exists obtained_organization_id uuid,
  add column if not exists is_special_equipment boolean not null default false;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'smis_document_kind_check'
      and conrelid = 'public.smis_document'::regclass
  ) then
    alter table public.smis_document
      add constraint smis_document_kind_check check (
        document_kind in (
          'general', 'required_knowledge', 'safety_management_system', 'legal_regulation'
        )
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'smis_document_code_check'
      and conrelid = 'public.smis_document'::regclass
  ) then
    alter table public.smis_document
      add constraint smis_document_code_check check (
        document_code is null
        or (btrim(document_code) <> '' and char_length(document_code) <= 100)
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'smis_document_obtained_organization_fkey'
      and conrelid = 'public.smis_document'::regclass
  ) then
    alter table public.smis_document
      add constraint smis_document_obtained_organization_fkey
      foreign key (tenant_id, obtained_organization_id)
      references public.sys_organization(tenant_id, id) on delete restrict;
  end if;
end $$;
create unique index if not exists smis_document_kind_code_unique
  on public.smis_document(tenant_id, document_kind, lower(document_code))
  where document_code is not null and status <> 'void';
create index if not exists smis_document_kind_search_idx
  on public.smis_document(tenant_id, document_kind, update_time desc);
create index if not exists smis_document_kind_category_idx
  on public.smis_document(tenant_id, document_kind, category_id, update_time desc);
create index if not exists smis_document_obtained_organization_idx
  on public.smis_document(obtained_organization_id)
  where obtained_organization_id is not null;
create table if not exists public.smis_legal_compliance_evaluation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  legal_document_id uuid not null,
  related_clause text not null,
  control_status text not null,
  evaluation_conclusion text not null,
  evaluation_date date not null,
  evaluator_name text not null,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_legal_compliance_evaluation_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_legal_compliance_evaluation_document_fkey
    foreign key (legal_document_id, tenant_id)
    references public.smis_document(id, tenant_id) on delete cascade,
  constraint smis_legal_compliance_related_clause_check check (
    btrim(related_clause) <> '' and char_length(related_clause) <= 1000
  ),
  constraint smis_legal_compliance_control_status_check check (
    btrim(control_status) <> '' and char_length(control_status) <= 1000
  ),
  constraint smis_legal_compliance_conclusion_check check (
    btrim(evaluation_conclusion) <> '' and char_length(evaluation_conclusion) <= 500
  ),
  constraint smis_legal_compliance_evaluator_check check (
    btrim(evaluator_name) <> '' and char_length(evaluator_name) <= 100
  ),
  constraint smis_legal_compliance_remark_check check (
    remark is null or char_length(remark) <= 1000
  )
);
create index if not exists smis_legal_compliance_document_date_idx
  on public.smis_legal_compliance_evaluation(
    tenant_id, legal_document_id, evaluation_date desc, update_time desc
  );
drop trigger if exists smis_legal_compliance_evaluation_create_audit
  on public.smis_legal_compliance_evaluation;
create trigger smis_legal_compliance_evaluation_create_audit
before insert on public.smis_legal_compliance_evaluation
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_legal_compliance_evaluation_update_audit
  on public.smis_legal_compliance_evaluation;
create trigger smis_legal_compliance_evaluation_update_audit
before update on public.smis_legal_compliance_evaluation
for each row execute function public.trg_set_update_time_and_by();
alter table public.smis_legal_compliance_evaluation enable row level security;
drop policy if exists smis_legal_compliance_tenant_select
  on public.smis_legal_compliance_evaluation;
create policy smis_legal_compliance_tenant_select
  on public.smis_legal_compliance_evaluation for select to authenticated
  using (
    tenant_id = (select app_private.current_user_tenant_id())
    or (select app_private.is_platform_super())
  );
drop policy if exists smis_legal_compliance_tenant_insert
  on public.smis_legal_compliance_evaluation;
create policy smis_legal_compliance_tenant_insert
  on public.smis_legal_compliance_evaluation for insert to authenticated
  with check (tenant_id = (select app_private.current_user_tenant_id()));
drop policy if exists smis_legal_compliance_tenant_update
  on public.smis_legal_compliance_evaluation;
create policy smis_legal_compliance_tenant_update
  on public.smis_legal_compliance_evaluation for update to authenticated
  using (tenant_id = (select app_private.current_user_tenant_id()))
  with check (tenant_id = (select app_private.current_user_tenant_id()));
drop policy if exists smis_legal_compliance_tenant_delete
  on public.smis_legal_compliance_evaluation;
create policy smis_legal_compliance_tenant_delete
  on public.smis_legal_compliance_evaluation for delete to authenticated
  using (tenant_id = (select app_private.current_user_tenant_id()));
revoke all on table public.smis_legal_compliance_evaluation from anon, authenticated;
grant select on table public.smis_legal_compliance_evaluation to authenticated;
create or replace function app_private.smis_document_permission_prefix(p_kind text)
returns text
language sql immutable
set search_path = ''
as $function$
  select case p_kind
    when 'required_knowledge' then 'SmisRequiredKnowledge'
    when 'safety_management_system' then 'SmisSafetyManagementSystem'
    when 'legal_regulation' then 'SmisLegalRegulation'
    else null
  end
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
  if not (
    case when p_id is null then
      app_private.has_permission('SmisAllDocuments:CategoryAdd')
      or app_private.has_permission('SmisRequiredKnowledge:CategoryAdd')
    else
      app_private.has_permission('SmisAllDocuments:CategoryEdit')
      or app_private.has_permission('SmisRequiredKnowledge:CategoryEdit')
    end
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
  if not (
    app_private.has_permission('SmisAllDocuments:CategoryDelete')
    or app_private.has_permission('SmisRequiredKnowledge:CategoryDelete')
  ) then
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
revoke all on function app_private.smis_document_permission_prefix(text)
  from public, anon, authenticated;
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
  if not (
    app_private.has_permission('SmisAllDocuments:View')
    or app_private.has_permission('SmisRequiredKnowledge:View')
    or app_private.has_permission('SmisSafetyManagementSystem:View')
    or app_private.has_permission('SmisLegalRegulation:View')
  ) then
    raise exception '当前账号没有查看文档分类的权限' using errcode = '42501';
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
create or replace function public.smis_list_document_registers_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_file_name text default null,
  p_document_code text default null,
  p_category_id uuid default null,
  p_kind text default 'required_knowledge',
  p_is_special_equipment boolean default null,
  p_obtained_from date default null,
  p_obtained_to date default null,
  p_evaluated_from date default null,
  p_evaluated_to date default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_prefix text := app_private.smis_document_permission_prefix(p_kind);
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_limit integer;
  v_file_name text := nullif(btrim(coalesce(p_file_name, '')), '');
  v_document_code text := nullif(btrim(coalesce(p_document_code, '')), '');
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看文档台账' using errcode = '42501';
  end if;
  if v_prefix is null then
    raise exception '文档业务类型无效' using errcode = '22023';
  end if;
  if p_purpose not in ('list', 'export') then
    raise exception '文档查询用途无效' using errcode = '22023';
  end if;
  if not app_private.has_permission(
    v_prefix || case when p_purpose = 'export' then ':Export' else ':View' end
  ) then
    raise exception '当前账号没有查看或导出该文档台账的权限' using errcode = '42501';
  end if;
  if p_obtained_from is not null and p_obtained_to is not null
    and p_obtained_from > p_obtained_to then
    raise exception '获取日期起始值不能晚于结束值' using errcode = '22023';
  end if;
  if p_evaluated_from is not null and p_evaluated_to is not null
    and p_evaluated_from > p_evaluated_to then
    raise exception '评价日期起始值不能晚于结束值' using errcode = '22023';
  end if;

  v_tenant_id := app_private.current_user_tenant_id();
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
      organization.organization_name obtained_organization_name,
      version.version_no,
      version.file_name,
      version.file_url,
      version.file_type,
      version.file_size,
      version.effective_date,
      coalesce(evaluation_stats.evaluation_count, 0) evaluation_count,
      evaluation_stats.last_evaluation_date
    from public.smis_document document
    join category_paths category on category.id = document.category_id
    left join public.sys_organization organization
      on organization.id = document.obtained_organization_id
      and organization.tenant_id = document.tenant_id
    left join lateral (
      select item.* from public.smis_document_version item
      where item.document_id = document.id and item.tenant_id = document.tenant_id
      order by item.effective_date desc, item.version_no desc
      limit 1
    ) version on true
    left join lateral (
      select count(*)::integer evaluation_count,
        max(evaluation.evaluation_date) last_evaluation_date
      from public.smis_legal_compliance_evaluation evaluation
      where evaluation.tenant_id = document.tenant_id
        and evaluation.legal_document_id = document.id
    ) evaluation_stats on true
    where document.tenant_id = v_tenant_id
      and document.document_kind = p_kind
      and document.status <> 'void'
      and (p_category_id is null or document.category_id in (select id from selected_categories))
      and (p_ids is null or document.id = any(p_ids))
  ), filtered as (
    select base.* from base
    where (
      v_file_name is null
      or base.title ilike '%' || v_file_name || '%'
      or base.file_name ilike '%' || v_file_name || '%'
    )
      and (v_document_code is null or base.document_code ilike '%' || v_document_code || '%')
      and (p_is_special_equipment is null or base.is_special_equipment = p_is_special_equipment)
      and (p_obtained_from is null or base.obtained_date >= p_obtained_from)
      and (p_obtained_to is null or base.obtained_date <= p_obtained_to)
      and (
        p_evaluated_from is null
        or exists (
          select 1 from public.smis_legal_compliance_evaluation evaluation
          where evaluation.tenant_id = base.tenant_id
            and evaluation.legal_document_id = base.id
            and evaluation.evaluation_date >= p_evaluated_from
        )
      )
      and (
        p_evaluated_to is null
        or exists (
          select 1 from public.smis_legal_compliance_evaluation evaluation
          where evaluation.tenant_id = base.tenant_id
            and evaluation.legal_document_id = base.id
            and evaluation.evaluation_date <= p_evaluated_to
        )
      )
  ), page_rows as (
    select * from filtered
    order by update_time desc, title
    offset v_from limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', row.id,
        'documentKind', row.document_kind,
        'categoryId', row.category_id,
        'categoryName', row.category_name,
        'categoryPath', row.category_path,
        'fileName', row.title,
        'documentCode', row.document_code,
        'status', row.status,
        'effectiveDate', row.effective_date,
        'promulgationDate', row.promulgation_date,
        'obtainedDate', row.obtained_date,
        'obtainedOrganizationId', row.obtained_organization_id,
        'obtainedOrganizationName', row.obtained_organization_name,
        'isSpecialEquipment', row.is_special_equipment,
        'attachmentName', row.file_name,
        'attachmentUrl', row.file_url,
        'attachmentType', row.file_type,
        'attachmentSize', row.file_size,
        'versionNo', row.version_no,
        'remark', row.summary,
        'evaluationCount', row.evaluation_count,
        'lastEvaluationDate', row.last_evaluation_date,
        'createBy', row.create_by,
        'createTime', row.create_time,
        'updateBy', row.update_by,
        'updateTime', row.update_time
      ) order by row.update_time desc, row.title)
      from page_rows row
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', jsonb_build_object(
      'total', (select count(*) from filtered),
      'withAttachment', (select count(*) from filtered where file_url is not null),
      'specialEquipment', (
        select count(*) from filtered where is_special_equipment is true
      ),
      'evaluated', (select count(*) from filtered where evaluation_count > 0)
    )
  ) into v_result;
  return v_result;
end;
$function$;
create or replace function public.smis_save_document_register_secure(
  p_id uuid,
  p_kind text,
  p_payload jsonb,
  p_copy_source_id uuid default null
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_user_id uuid := app_private.current_user_id();
  v_prefix text := app_private.smis_document_permission_prefix(p_kind);
  v_category_id uuid;
  v_obtained_organization_id uuid;
  v_title text := btrim(coalesce(p_payload->>'file_name', ''));
  v_document_code text := nullif(btrim(coalesce(p_payload->>'document_code', '')), '');
  v_promulgation_date date;
  v_obtained_date date;
  v_effective_date date;
  v_is_special_equipment boolean := false;
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
  v_attachment_name text := nullif(btrim(coalesce(p_payload->>'attachment_name', '')), '');
  v_attachment_url text := nullif(btrim(coalesce(p_payload->>'attachment_url', '')), '');
  v_attachment_type text := nullif(btrim(coalesce(p_payload->>'attachment_type', '')), '');
  v_attachment_size bigint;
  v_document_id uuid := p_id;
  v_version_no integer;
begin
  if (select auth.uid()) is null or v_user_id is null then
    raise exception '请先登录后再保存文档台账' using errcode = '42501';
  end if;
  if v_prefix is null then
    raise exception '文档业务类型无效' using errcode = '22023';
  end if;
  if not app_private.has_permission(
    v_prefix || case
      when p_id is not null then ':Edit'
      when p_copy_source_id is not null then ':Copy'
      else ':Add'
    end
  ) then
    raise exception '当前账号没有保存该文档台账的权限' using errcode = '42501';
  end if;

  begin
    v_category_id := nullif(p_payload->>'category_id', '')::uuid;
    v_obtained_organization_id := nullif(p_payload->>'obtained_organization_id', '')::uuid;
    v_promulgation_date := nullif(p_payload->>'promulgation_date', '')::date;
    v_obtained_date := nullif(p_payload->>'obtained_date', '')::date;
    v_effective_date := nullif(p_payload->>'effective_date', '')::date;
    v_attachment_size := nullif(p_payload->>'attachment_size', '')::bigint;
    v_is_special_equipment := coalesce(
      nullif(p_payload->>'is_special_equipment', '')::boolean,
      false
    );
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception '文档分类、部门、日期或附件大小无效' using errcode = '22023';
  end;

  if v_title = '' or char_length(v_title) > 200 then
    raise exception '文件名称不能为空且不能超过 200 个字符' using errcode = '22023';
  end if;
  if v_document_code is null or char_length(v_document_code) > 100 then
    raise exception '文件编号不能为空且不能超过 100 个字符' using errcode = '22023';
  end if;
  if v_effective_date is null then
    raise exception '请选择生效日期' using errcode = '22023';
  end if;
  if char_length(coalesce(v_remark, '')) > 2000 then
    raise exception '备注不能超过 2000 个字符' using errcode = '22023';
  end if;
  if (v_attachment_name is null) <> (v_attachment_url is null) then
    raise exception '附件名称与访问地址必须同时提供' using errcode = '22023';
  end if;
  if p_id is null and v_attachment_url is null then
    raise exception '请上传文档附件' using errcode = '22023';
  end if;
  if v_attachment_name is not null and (
    char_length(v_attachment_name) > 255
    or char_length(v_attachment_url) > 4000
    or coalesce(v_attachment_size, 0) < 0
  ) then
    raise exception '附件信息不完整或超出限制' using errcode = '22023';
  end if;

  v_tenant_id := app_private.current_user_tenant_id();
  if not exists (
    select 1 from public.smis_document_category category
    where category.id = v_category_id and category.tenant_id = v_tenant_id
      and category.status = 'enabled'
  ) then
    raise exception '文档分类不存在、已停用或不属于当前租户' using errcode = 'P0002';
  end if;

  if p_kind = 'legal_regulation' then
    if v_obtained_organization_id is null then
      raise exception '请选择获取部门' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.sys_organization organization
      where organization.id = v_obtained_organization_id
        and organization.tenant_id = v_tenant_id
        and organization.status = '1'
    ) then
      raise exception '获取部门不存在、已停用或不属于当前租户' using errcode = 'P0002';
    end if;
  else
    v_obtained_organization_id := null;
    v_obtained_date := null;
    v_is_special_equipment := false;
  end if;

  if p_copy_source_id is not null and not exists (
    select 1 from public.smis_document source
    where source.id = p_copy_source_id and source.tenant_id = v_tenant_id
      and source.document_kind = p_kind and source.status <> 'void'
  ) then
    raise exception '复制来源不存在或不属于当前文档台账' using errcode = 'P0002';
  end if;

  if p_id is null then
    insert into public.smis_document(
      tenant_id, category_id, title, status, creator_user_id, summary,
      document_kind, document_code, promulgation_date, obtained_date,
      obtained_organization_id, is_special_equipment
    ) values (
      v_tenant_id, v_category_id, v_title, 'published', v_user_id, v_remark,
      p_kind, v_document_code, v_promulgation_date, v_obtained_date,
      v_obtained_organization_id, v_is_special_equipment
    ) returning id into v_document_id;
  else
    update public.smis_document set
      category_id = v_category_id,
      title = v_title,
      summary = v_remark,
      document_code = v_document_code,
      promulgation_date = v_promulgation_date,
      obtained_date = v_obtained_date,
      obtained_organization_id = v_obtained_organization_id,
      is_special_equipment = v_is_special_equipment
    where id = p_id and tenant_id = v_tenant_id and document_kind = p_kind
    returning id into v_document_id;
    if v_document_id is null then
      raise exception '文档不存在或不属于当前台账' using errcode = 'P0002';
    end if;
  end if;

  if v_attachment_url is not null then
    select coalesce(max(version.version_no), 0) + 1 into v_version_no
    from public.smis_document_version version
    where version.document_id = v_document_id and version.tenant_id = v_tenant_id;

    insert into public.smis_document_version(
      tenant_id, document_id, version_no, file_name, file_url, file_type,
      file_size, effective_date, replacement_note, uploaded_by_user_id
    ) values (
      v_tenant_id, v_document_id, v_version_no, v_attachment_name,
      v_attachment_url, v_attachment_type, v_attachment_size, v_effective_date,
      case when p_copy_source_id is not null then '复制并新增' else '文档台账附件' end,
      v_user_id
    );
  end if;

  return v_document_id;
exception when unique_violation then
  raise exception '当前台账已存在相同文件编号' using errcode = '23505';
end;
$function$;
create or replace function public.smis_delete_document_registers_secure(
  p_kind text,
  p_ids uuid[]
) returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_prefix text := app_private.smis_document_permission_prefix(p_kind);
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除文档台账' using errcode = '42501';
  end if;
  if v_prefix is null then
    raise exception '文档业务类型无效' using errcode = '22023';
  end if;
  if not app_private.has_permission(v_prefix || ':Delete') then
    raise exception '当前账号没有删除该文档台账的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的文档' using errcode = '22023';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  delete from public.smis_document
  where tenant_id = v_tenant_id and document_kind = p_kind and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
create or replace function public.smis_list_legal_compliance_evaluations_secure(
  p_document_id uuid,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看合规性评价' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisLegalRegulation:ComplianceView') then
    raise exception '当前账号没有查看合规性评价的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if not exists (
    select 1 from public.smis_document document
    where document.id = p_document_id and document.tenant_id = v_tenant_id
      and document.document_kind = 'legal_regulation' and document.status <> 'void'
  ) then
    raise exception '法律法规不存在或不属于当前租户' using errcode = 'P0002';
  end if;

  with filtered as (
    select evaluation.*
    from public.smis_legal_compliance_evaluation evaluation
    where evaluation.tenant_id = v_tenant_id
      and evaluation.legal_document_id = p_document_id
      and (
        v_keyword is null
        or evaluation.related_clause ilike '%' || v_keyword || '%'
        or evaluation.control_status ilike '%' || v_keyword || '%'
        or evaluation.evaluation_conclusion ilike '%' || v_keyword || '%'
        or evaluation.evaluator_name ilike '%' || v_keyword || '%'
      )
  ), page_rows as (
    select * from filtered
    order by evaluation_date desc, update_time desc
    offset v_from limit least(v_to - v_from + 1, 200)
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', row.id,
        'legalDocumentId', row.legal_document_id,
        'relatedClause', row.related_clause,
        'controlStatus', row.control_status,
        'evaluationConclusion', row.evaluation_conclusion,
        'evaluationDate', row.evaluation_date,
        'evaluatorName', row.evaluator_name,
        'remark', row.remark,
        'createBy', row.create_by,
        'createTime', row.create_time,
        'updateBy', row.update_by,
        'updateTime', row.update_time
      ) order by row.evaluation_date desc, row.update_time desc)
      from page_rows row
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end;
$function$;
create or replace function public.smis_save_legal_compliance_evaluation_secure(
  p_id uuid,
  p_document_id uuid,
  p_payload jsonb,
  p_copy_source_id uuid default null
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_related_clause text := btrim(coalesce(p_payload->>'related_clause', ''));
  v_control_status text := btrim(coalesce(p_payload->>'control_status', ''));
  v_conclusion text := btrim(coalesce(p_payload->>'evaluation_conclusion', ''));
  v_evaluation_date date;
  v_evaluator_name text := btrim(coalesce(p_payload->>'evaluator_name', ''));
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再保存合规性评价' using errcode = '42501';
  end if;
  if not app_private.has_permission(
    'SmisLegalRegulation:Compliance' || case
      when p_id is not null then 'Edit'
      when p_copy_source_id is not null then 'Copy'
      else 'Add'
    end
  ) then
    raise exception '当前账号没有保存合规性评价的权限' using errcode = '42501';
  end if;
  begin
    v_evaluation_date := nullif(p_payload->>'evaluation_date', '')::date;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception '评价日期无效' using errcode = '22023';
  end;
  if v_related_clause = '' or char_length(v_related_clause) > 1000 then
    raise exception '相关条款不能为空且不能超过 1000 个字符' using errcode = '22023';
  end if;
  if v_control_status = '' or char_length(v_control_status) > 1000 then
    raise exception '控制现状不能为空且不能超过 1000 个字符' using errcode = '22023';
  end if;
  if v_conclusion = '' or char_length(v_conclusion) > 500 then
    raise exception '评价结论不能为空且不能超过 500 个字符' using errcode = '22023';
  end if;
  if v_evaluation_date is null then
    raise exception '请选择评价日期' using errcode = '22023';
  end if;
  if v_evaluator_name = '' or char_length(v_evaluator_name) > 100 then
    raise exception '评价人不能为空且不能超过 100 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_remark, '')) > 1000 then
    raise exception '备注不能超过 1000 个字符' using errcode = '22023';
  end if;

  v_tenant_id := app_private.current_user_tenant_id();
  if not exists (
    select 1 from public.smis_document document
    where document.id = p_document_id and document.tenant_id = v_tenant_id
      and document.document_kind = 'legal_regulation' and document.status <> 'void'
  ) then
    raise exception '法律法规不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  if p_copy_source_id is not null and not exists (
    select 1 from public.smis_legal_compliance_evaluation source
    where source.id = p_copy_source_id and source.tenant_id = v_tenant_id
      and source.legal_document_id = p_document_id
  ) then
    raise exception '复制来源不存在或不属于当前法律法规' using errcode = 'P0002';
  end if;

  if p_id is null then
    insert into public.smis_legal_compliance_evaluation(
      tenant_id, legal_document_id, related_clause, control_status,
      evaluation_conclusion, evaluation_date, evaluator_name, remark
    ) values (
      v_tenant_id, p_document_id, v_related_clause, v_control_status,
      v_conclusion, v_evaluation_date, v_evaluator_name, v_remark
    ) returning id into v_result;
  else
    update public.smis_legal_compliance_evaluation set
      related_clause = v_related_clause,
      control_status = v_control_status,
      evaluation_conclusion = v_conclusion,
      evaluation_date = v_evaluation_date,
      evaluator_name = v_evaluator_name,
      remark = v_remark
    where id = p_id and tenant_id = v_tenant_id and legal_document_id = p_document_id
    returning id into v_result;
    if v_result is null then
      raise exception '合规性评价不存在或不属于当前法律法规' using errcode = 'P0002';
    end if;
  end if;
  return v_result;
end;
$function$;
create or replace function public.smis_delete_legal_compliance_evaluations_secure(
  p_document_id uuid,
  p_ids uuid[]
) returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除合规性评价' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisLegalRegulation:ComplianceDelete') then
    raise exception '当前账号没有删除合规性评价的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的合规性评价' using errcode = '22023';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  delete from public.smis_legal_compliance_evaluation
  where tenant_id = v_tenant_id and legal_document_id = p_document_id and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
revoke all on function public.smis_list_document_registers_secure(
  integer, integer, text, text, uuid, text, boolean, date, date, date, date, uuid[], text
) from public, anon;
grant execute on function public.smis_list_document_registers_secure(
  integer, integer, text, text, uuid, text, boolean, date, date, date, date, uuid[], text
) to authenticated;
revoke all on function public.smis_save_document_register_secure(uuid, text, jsonb, uuid)
  from public, anon;
grant execute on function public.smis_save_document_register_secure(uuid, text, jsonb, uuid)
  to authenticated;
revoke all on function public.smis_delete_document_registers_secure(text, uuid[])
  from public, anon;
grant execute on function public.smis_delete_document_registers_secure(text, uuid[])
  to authenticated;
revoke all on function public.smis_list_legal_compliance_evaluations_secure(
  uuid, integer, integer, text
) from public, anon;
grant execute on function public.smis_list_legal_compliance_evaluations_secure(
  uuid, integer, integer, text
) to authenticated;
revoke all on function public.smis_save_legal_compliance_evaluation_secure(
  uuid, uuid, jsonb, uuid
) from public, anon;
grant execute on function public.smis_save_legal_compliance_evaluation_secure(
  uuid, uuid, jsonb, uuid
) to authenticated;
revoke all on function public.smis_delete_legal_compliance_evaluations_secure(uuid, uuid[])
  from public, anon;
grant execute on function public.smis_delete_legal_compliance_evaluations_secure(uuid, uuid[])
  to authenticated;
with seed_categories(category_name, sort, description) as (
  values
    ('应知应会'::text, 110::integer, '应知应会文件分类'),
    ('安全管理制度'::text, 120::integer, '安全管理制度文件分类'),
    ('法律法规'::text, 130::integer, '法律、法规、标准及规范分类')
)
insert into public.smis_document_category(
  tenant_id, parent_id, category_name, sort, status, description, create_by, update_by
)
select tenant.id, null, seed.category_name, seed.sort, 'enabled', seed.description,
  '624944977@qq.com', '624944977@qq.com'
from seed_categories seed
join public.sys_tenant tenant on tenant.tenant_code = 'public-register'
where not exists (
  select 1 from public.smis_document_category existing
  where existing.tenant_id = tenant.id and existing.parent_id is null
    and lower(existing.category_name) = lower(seed.category_name)
);
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort,
  create_by, update_by, app_code
)
select gen_random_uuid(), parent.id, 'SmisLegalRegulation', 'legal-regulation',
  '/smis/safety-production/document-center/legal-regulation', 'menu',
  jsonb_build_object(
    'title', '法律法规',
    'icon', 'ri:scales-3-line',
    'is_hide', false,
    'is_enable', true,
    'keep_alive', false,
    'roles', '[]'::jsonb
  ), 4, '624944977@qq.com', '624944977@qq.com', 'smis'
from public.sys_menu parent
where parent.name = 'SmisDocumentCenter'
  and not exists (
    select 1 from public.sys_menu existing where existing.name = 'SmisLegalRegulation'
  );
with buttons(parent_name, code, title, sort) as (
  values
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:View', '查看应知应会', 1),
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:Add', '新增应知应会', 2),
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:Edit', '编辑应知应会', 3),
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:Delete', '删除应知应会', 4),
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:Export', '导出应知应会', 5),
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:CategoryAdd', '新增文档分类', 6),
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:CategoryEdit', '编辑文档分类', 7),
    ('SmisRequiredKnowledge', 'SmisRequiredKnowledge:CategoryDelete', '删除文档分类', 8),
    ('SmisSafetyManagementSystem', 'SmisSafetyManagementSystem:View', '查看安全管理制度', 1),
    ('SmisSafetyManagementSystem', 'SmisSafetyManagementSystem:Add', '新增安全管理制度', 2),
    ('SmisSafetyManagementSystem', 'SmisSafetyManagementSystem:Edit', '编辑安全管理制度', 3),
    ('SmisSafetyManagementSystem', 'SmisSafetyManagementSystem:Delete', '删除安全管理制度', 4),
    ('SmisSafetyManagementSystem', 'SmisSafetyManagementSystem:Export', '导出安全管理制度', 5),
    ('SmisLegalRegulation', 'SmisLegalRegulation:View', '查看法律法规', 1),
    ('SmisLegalRegulation', 'SmisLegalRegulation:Add', '新增法律法规', 2),
    ('SmisLegalRegulation', 'SmisLegalRegulation:Copy', '复制并新增法律法规', 3),
    ('SmisLegalRegulation', 'SmisLegalRegulation:Edit', '编辑法律法规', 4),
    ('SmisLegalRegulation', 'SmisLegalRegulation:Delete', '删除法律法规', 5),
    ('SmisLegalRegulation', 'SmisLegalRegulation:Export', '导出法律法规', 6),
    ('SmisLegalRegulation', 'SmisLegalRegulation:ComplianceView', '查看合规性评价', 7),
    ('SmisLegalRegulation', 'SmisLegalRegulation:ComplianceAdd', '新增合规性评价', 8),
    ('SmisLegalRegulation', 'SmisLegalRegulation:ComplianceCopy', '复制并新增合规性评价', 9),
    ('SmisLegalRegulation', 'SmisLegalRegulation:ComplianceEdit', '编辑合规性评价', 10),
    ('SmisLegalRegulation', 'SmisLegalRegulation:ComplianceDelete', '删除合规性评价', 11)
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
join public.sys_menu parent on parent.name = button.parent_name
where not exists (
  select 1 from public.sys_menu existing where existing.name = button.code
);
insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by, update_by)
select distinct page_grant.role_id, legal_menu.id, page_grant.tenant_id,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_menu source_menu on source_menu.id = page_grant.menu_id
join public.sys_menu legal_menu on legal_menu.name = 'SmisLegalRegulation'
where source_menu.name = 'SmisSafetyManagementSystem'
on conflict (role_id, menu_id) do nothing;
insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by, update_by)
select distinct parent_grant.role_id, child.id, parent_grant.tenant_id,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu parent_grant
join public.sys_menu parent on parent.id = parent_grant.menu_id
join public.sys_menu child on child.parent_id = parent.id and child.type = 'button'
where parent.name in (
  'SmisRequiredKnowledge', 'SmisSafetyManagementSystem', 'SmisLegalRegulation'
)
on conflict (role_id, menu_id) do nothing;
commit;
