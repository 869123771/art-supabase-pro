begin;

create table public.smis_qualification_catalog (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  catalog_type text not null,
  parent_id uuid,
  item_code text not null,
  item_name text not null,
  sort integer not null default 10,
  status text not null default 'enabled',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_qualification_catalog_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_qualification_catalog_id_tenant_key unique (id, tenant_id),
  constraint smis_qualification_catalog_parent_fkey foreign key (parent_id, tenant_id)
    references public.smis_qualification_catalog(id, tenant_id) on delete restrict,
  constraint smis_qualification_catalog_type_check check (
    catalog_type in ('work_item', 'work_category', 'permitted_operation_item')
  ),
  constraint smis_qualification_catalog_parent_check check (parent_id is null or parent_id <> id),
  constraint smis_qualification_catalog_code_check check (
    btrim(item_code) <> '' and char_length(item_code) <= 50
  ),
  constraint smis_qualification_catalog_name_check check (
    btrim(item_name) <> '' and char_length(item_name) <= 120
  ),
  constraint smis_qualification_catalog_sort_check check (sort between 0 and 999999),
  constraint smis_qualification_catalog_status_check check (status in ('enabled', 'disabled')),
  constraint smis_qualification_catalog_remark_check check (
    remark is null or char_length(remark) <= 1000
  )
);

create unique index smis_qualification_catalog_code_unique
  on public.smis_qualification_catalog(tenant_id, catalog_type, upper(item_code));
create unique index smis_qualification_catalog_sibling_name_unique
  on public.smis_qualification_catalog(
    tenant_id,
    catalog_type,
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(item_name)
  );
create index smis_qualification_catalog_parent_idx
  on public.smis_qualification_catalog(tenant_id, catalog_type, parent_id, sort);

create table public.smis_personnel_certificate (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  certificate_category text not null,
  certificate_number text not null,
  issuing_authority text,
  archive_number text,
  certificate_photo_url text,
  warning_status text not null default 'normal',
  extra_fields jsonb not null default '{}'::jsonb,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_personnel_certificate_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_personnel_certificate_id_tenant_key unique (id, tenant_id),
  constraint smis_personnel_certificate_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_personnel_certificate_category_check check (
    certificate_category in (
      'special_equipment_personnel', 'special_equipment_operator',
      'special_operation', 'safety_manager', 'registered_safety_engineer'
    )
  ),
  constraint smis_personnel_certificate_number_check check (
    btrim(certificate_number) <> '' and char_length(certificate_number) <= 100
  ),
  constraint smis_personnel_certificate_warning_check check (warning_status in ('normal', 'warning')),
  constraint smis_personnel_certificate_extra_check check (jsonb_typeof(extra_fields) = 'object'),
  constraint smis_personnel_certificate_remark_check check (
    remark is null or char_length(remark) <= 1000
  )
);

create unique index smis_personnel_certificate_number_unique
  on public.smis_personnel_certificate(tenant_id, certificate_category, upper(certificate_number));
create index smis_personnel_certificate_employee_idx
  on public.smis_personnel_certificate(tenant_id, employee_id, update_time desc);
create index smis_personnel_certificate_category_idx
  on public.smis_personnel_certificate(tenant_id, certificate_category, update_time desc);

create table public.smis_personnel_certificate_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  certificate_id uuid not null,
  catalog_id uuid not null,
  approval_date date not null,
  effective_date date not null,
  reminder_days integer not null default 30,
  dismissal_reason text,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_personnel_certificate_item_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_personnel_certificate_item_id_tenant_key unique (id, tenant_id),
  constraint smis_personnel_certificate_item_parent_fkey foreign key (certificate_id, tenant_id)
    references public.smis_personnel_certificate(id, tenant_id) on delete cascade,
  constraint smis_personnel_certificate_item_catalog_fkey foreign key (catalog_id, tenant_id)
    references public.smis_qualification_catalog(id, tenant_id) on delete restrict,
  constraint smis_personnel_certificate_item_unique unique (certificate_id, catalog_id),
  constraint smis_personnel_certificate_item_date_check check (effective_date >= approval_date),
  constraint smis_personnel_certificate_item_reminder_check check (reminder_days between 0 and 730),
  constraint smis_personnel_certificate_item_dismissal_check check (
    dismissal_reason is null or dismissal_reason in ('offboarded', 'trained')
  ),
  constraint smis_personnel_certificate_item_sort_check check (sort between 0 and 999999)
);

create index smis_personnel_certificate_item_parent_idx
  on public.smis_personnel_certificate_item(certificate_id, sort);
create index smis_personnel_certificate_item_catalog_idx
  on public.smis_personnel_certificate_item(catalog_id);
create index smis_personnel_certificate_item_due_idx
  on public.smis_personnel_certificate_item(tenant_id, effective_date)
  where dismissal_reason is null;

create table public.smis_personnel_certificate_review_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  certificate_id uuid not null,
  certificate_item_id uuid not null,
  previous_approval_date date not null,
  previous_effective_date date not null,
  approval_date date not null,
  effective_date date not null,
  review_by text,
  review_time timestamptz not null default now(),
  constraint smis_certificate_review_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_certificate_review_parent_fkey foreign key (certificate_id, tenant_id)
    references public.smis_personnel_certificate(id, tenant_id) on delete cascade,
  constraint smis_certificate_review_item_fkey foreign key (certificate_item_id, tenant_id)
    references public.smis_personnel_certificate_item(id, tenant_id) on delete cascade,
  constraint smis_certificate_review_date_check check (effective_date >= approval_date)
);

create index smis_certificate_review_item_idx
  on public.smis_personnel_certificate_review_history(certificate_item_id, review_time desc);

drop trigger if exists smis_qualification_catalog_create_audit on public.smis_qualification_catalog;
create trigger smis_qualification_catalog_create_audit before insert on public.smis_qualification_catalog
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_qualification_catalog_update_audit on public.smis_qualification_catalog;
create trigger smis_qualification_catalog_update_audit before update on public.smis_qualification_catalog
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists smis_personnel_certificate_create_audit on public.smis_personnel_certificate;
create trigger smis_personnel_certificate_create_audit before insert on public.smis_personnel_certificate
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_personnel_certificate_update_audit on public.smis_personnel_certificate;
create trigger smis_personnel_certificate_update_audit before update on public.smis_personnel_certificate
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists smis_personnel_certificate_item_create_audit on public.smis_personnel_certificate_item;
create trigger smis_personnel_certificate_item_create_audit before insert on public.smis_personnel_certificate_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_personnel_certificate_item_update_audit on public.smis_personnel_certificate_item;
create trigger smis_personnel_certificate_item_update_audit before update on public.smis_personnel_certificate_item
for each row execute function public.trg_set_update_time_and_by();

create or replace function app_private.smis_capture_certificate_review()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if old.approval_date is distinct from new.approval_date
     or old.effective_date is distinct from new.effective_date then
    insert into public.smis_personnel_certificate_review_history(
      tenant_id, certificate_id, certificate_item_id,
      previous_approval_date, previous_effective_date,
      approval_date, effective_date, review_by
    ) values (
      old.tenant_id, old.certificate_id, old.id,
      old.approval_date, old.effective_date,
      new.approval_date, new.effective_date,
      coalesce((select auth.jwt()->>'email'), (select auth.uid())::text)
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists smis_personnel_certificate_item_review on public.smis_personnel_certificate_item;
create trigger smis_personnel_certificate_item_review
before update of approval_date, effective_date on public.smis_personnel_certificate_item
for each row execute function app_private.smis_capture_certificate_review();

alter table public.smis_qualification_catalog enable row level security;
alter table public.smis_personnel_certificate enable row level security;
alter table public.smis_personnel_certificate_item enable row level security;
alter table public.smis_personnel_certificate_review_history enable row level security;

revoke all on table public.smis_qualification_catalog from anon, authenticated;
revoke all on table public.smis_personnel_certificate from anon, authenticated;
revoke all on table public.smis_personnel_certificate_item from anon, authenticated;
revoke all on table public.smis_personnel_certificate_review_history from anon, authenticated;

create policy smis_qualification_catalog_select on public.smis_qualification_catalog
for select to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id()) and (
      (catalog_type = 'work_item' and (select app_private.has_permission('SmisWorkItem:View')))
      or (catalog_type = 'work_category' and (select app_private.has_permission('SmisWorkCategory:View')))
      or (catalog_type = 'permitted_operation_item' and (select app_private.has_permission('SmisPermittedOperationItem:View')))
      or (select app_private.has_permission('SmisPersonnelCertificateLedger:View'))
    )
  )
);
create policy smis_personnel_certificate_select on public.smis_personnel_certificate
for select to authenticated using (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))
  and (select app_private.has_permission('SmisPersonnelCertificateLedger:View'))
);
create policy smis_personnel_certificate_item_select on public.smis_personnel_certificate_item
for select to authenticated using (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))
  and (select app_private.has_permission('SmisPersonnelCertificateLedger:View'))
);
create policy smis_certificate_review_select on public.smis_personnel_certificate_review_history
for select to authenticated using (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))
  and (select app_private.has_permission('SmisPersonnelCertificateLedger:ViewHistory'))
);

create or replace function app_private.smis_catalog_permission(p_catalog_type text, p_action text)
returns text language sql immutable set search_path = ''
as $function$
  select case p_catalog_type
    when 'work_item' then 'SmisWorkItem:' || p_action
    when 'work_category' then 'SmisWorkCategory:' || p_action
    when 'permitted_operation_item' then 'SmisPermittedOperationItem:' || p_action
  end
$function$;

create or replace function public.smis_list_qualification_catalog_secure(
  p_catalog_type text,
  p_from integer default 0,
  p_to integer default 99,
  p_keyword text default null,
  p_status text default null,
  p_ancestor_id uuid default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 99), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
  v_permission text := app_private.smis_catalog_permission(p_catalog_type, 'View');
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看安全资质基础数据' using errcode='42501'; end if;
  if v_permission is null or not ((select app_private.is_platform_super()) or app_private.has_permission(v_permission)) then
    raise exception '当前账号没有查看该基础数据的权限' using errcode='42501';
  end if;
  if p_purpose = 'export' and not app_private.has_permission(app_private.smis_catalog_permission(p_catalog_type, 'Export')) then
    raise exception '当前账号没有导出该基础数据的权限' using errcode='42501';
  end if;
  if p_purpose not in ('list','export','option') then raise exception '查询用途无效' using errcode='22023'; end if;

  return (
    with recursive source as (
      select c.*,
        (select count(*) from public.smis_qualification_catalog child
         where child.tenant_id=c.tenant_id and child.parent_id=c.id)::integer child_count,
        (select p.item_name from public.smis_qualification_catalog p where p.id=c.parent_id) parent_name
      from public.smis_qualification_catalog c
      where c.tenant_id=app_private.current_read_tenant_id() and c.catalog_type=p_catalog_type
    ), subtree as (
      select id from source where id=p_ancestor_id
      union all select c.id from source c join subtree p on c.parent_id=p.id
    ), filtered as (
      select * from source
      where (p_ancestor_id is null or id in (select id from subtree))
        and (p_status is null or status=p_status)
        and (v_keyword is null or lower(item_code) like '%'||v_keyword||'%'
          or lower(item_name) like '%'||v_keyword||'%'
          or lower(coalesce(remark,'')) like '%'||v_keyword||'%')
    )
    select jsonb_build_object(
      'records', coalesce((select jsonb_agg(to_jsonb(r) order by r.sort,r."itemName") from (
        select id,tenant_id "tenantId",parent_id "parentId",parent_name "parentName",
          catalog_type "catalogType",item_code "itemCode",item_name "itemName",sort,status,remark,
          child_count "childCount",create_by "createBy",create_time "createTime",update_by "updateBy",update_time "updateTime"
        from filtered offset v_from limit v_to-v_from+1
      ) r),'[]'::jsonb),
      'total',(select count(*) from filtered),
      'tree',coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'parentId',parent_id,'catalogType',catalog_type,'itemCode',item_code,
        'itemName',item_name,'sort',sort,'status',status,'childCount',child_count
      ) order by sort,item_name) from source),'[]'::jsonb),
      'overview',(select jsonb_build_object(
        'total',count(*),'enabled',count(*) filter(where status='enabled'),
        'disabled',count(*) filter(where status='disabled'),
        'rootCount',count(*) filter(where parent_id is null)
      ) from source)
    )
  );
end;
$function$;

create or replace function public.smis_save_qualification_catalog_secure(p_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_type text := p_payload->>'catalog_type';
  v_parent uuid;
  v_code text := upper(btrim(coalesce(p_payload->>'item_code','')));
  v_name text := btrim(coalesce(p_payload->>'item_name',''));
  v_sort integer := coalesce(nullif(p_payload->>'sort','')::integer,10);
  v_status text := coalesce(nullif(p_payload->>'status',''),'enabled');
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark','')),'');
  v_result uuid;
  v_action text := case when p_id is null then 'Add' else 'Edit' end;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护安全资质基础数据' using errcode='42501'; end if;
  if v_type not in ('work_item','work_category','permitted_operation_item') then raise exception '基础数据类型无效' using errcode='22023'; end if;
  if not app_private.has_permission(app_private.smis_catalog_permission(v_type,v_action)) then raise exception '当前账号没有维护该基础数据的权限' using errcode='42501'; end if;
  v_tenant := app_private.resolve_mutation_tenant_id((select tenant_id from public.smis_qualification_catalog where id=p_id));
  begin v_parent := nullif(p_payload->>'parent_id','')::uuid; exception when invalid_text_representation then raise exception '上级节点无效' using errcode='22023'; end;
  if v_code='' or char_length(v_code)>50 then raise exception '请输入不超过 50 个字符的项目编码' using errcode='22023'; end if;
  if v_name='' or char_length(v_name)>120 then raise exception '请输入不超过 120 个字符的项目名称' using errcode='22023'; end if;
  if v_status not in ('enabled','disabled') then raise exception '启用状态无效' using errcode='22023'; end if;
  if v_parent is not null and not exists(select 1 from public.smis_qualification_catalog where id=v_parent and tenant_id=v_tenant and catalog_type=v_type) then raise exception '上级节点不存在或类型不一致' using errcode='P0002'; end if;
  if p_id is not null and (v_parent=p_id or exists(
    with recursive descendants(id) as (
      select id from public.smis_qualification_catalog where tenant_id=v_tenant and parent_id=p_id
      union all select c.id from public.smis_qualification_catalog c join descendants p on c.parent_id=p.id where c.tenant_id=v_tenant
    ) select 1 from descendants where id=v_parent
  )) then raise exception '不能把节点移动到自身或下级节点' using errcode='22023'; end if;
  if p_id is null then
    insert into public.smis_qualification_catalog(tenant_id,catalog_type,parent_id,item_code,item_name,sort,status,remark)
    values(v_tenant,v_type,v_parent,v_code,v_name,v_sort,v_status,v_remark) returning id into v_result;
  else
    update public.smis_qualification_catalog set parent_id=v_parent,item_code=v_code,item_name=v_name,sort=v_sort,status=v_status,remark=v_remark
    where id=p_id and tenant_id=v_tenant and catalog_type=v_type returning id into v_result;
    if v_result is null then raise exception '基础数据不存在或已删除' using errcode='P0002'; end if;
  end if;
  return v_result;
exception when unique_violation then raise exception '同类型项目编码或同级名称已存在' using errcode='23505';
end;
$function$;

create or replace function public.smis_delete_qualification_catalog_secure(p_catalog_type text,p_ids uuid[])
returns integer language plpgsql security definer set search_path = ''
as $function$
declare v_count integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再删除基础数据' using errcode='42501'; end if;
  if not app_private.has_permission(app_private.smis_catalog_permission(p_catalog_type,'Delete')) then raise exception '当前账号没有删除该基础数据的权限' using errcode='42501'; end if;
  if cardinality(coalesce(p_ids,'{}'::uuid[]))=0 then raise exception '请选择要删除的数据' using errcode='22023'; end if;
  if exists(select 1 from public.smis_qualification_catalog where tenant_id=app_private.current_read_tenant_id() and parent_id=any(p_ids) and not id=any(p_ids)) then raise exception '所选节点仍有下级，请先处理下级节点' using errcode='23503'; end if;
  delete from public.smis_qualification_catalog where tenant_id=app_private.current_read_tenant_id() and catalog_type=p_catalog_type and id=any(p_ids);
  get diagnostics v_count=row_count; return v_count;
exception when foreign_key_violation then raise exception '项目已被证件使用，请改为停用' using errcode='23503';
end;
$function$;

create or replace function public.smis_list_personnel_certificates_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_employee_name text default null,
  p_certificate_number text default null,
  p_certificate_category text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_warning_status text default null,
  p_purpose text default 'list'
) returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer:=greatest(coalesce(p_from,0),0);
  v_to integer:=greatest(coalesce(p_to,19),greatest(coalesce(p_from,0),0));
  v_name text:=nullif(lower(btrim(coalesce(p_employee_name,''))),'');
  v_number text:=nullif(lower(btrim(coalesce(p_certificate_number,''))),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看人员证件台账' using errcode='42501'; end if;
  if not ((select app_private.is_platform_super()) or app_private.has_permission('SmisPersonnelCertificateLedger:View')) then raise exception '当前账号没有查看人员证件台账的权限' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisPersonnelCertificateLedger:Export') then raise exception '当前账号没有导出台账的权限' using errcode='42501'; end if;
  return (
    with enriched as (
      select c.*,e.employee_no,e.employee_name,e.gender,e.phone,e.job_title,e.avatar_url,
        o.organization_name,
        coalesce((select jsonb_agg(jsonb_build_object(
          'id',i.id,'catalogId',q.id,'workCode',q.item_code,'workName',q.item_name,
          'catalogType',q.catalog_type,'approvalDate',i.approval_date,'effectiveDate',i.effective_date,
          'reminderDays',i.reminder_days,'dismissalReason',i.dismissal_reason,'sort',i.sort,
          'reminderState',case when i.dismissal_reason is not null then 'dismissed'
            when i.effective_date<current_date then 'expired'
            when i.effective_date<=current_date+i.reminder_days then 'warning' else 'normal' end,
          'reviewCount',(select count(*) from public.smis_personnel_certificate_review_history h where h.certificate_item_id=i.id),
          'reviewHistory',coalesce((select jsonb_agg(jsonb_build_object(
            'id',h.id,'previousApprovalDate',h.previous_approval_date,'previousEffectiveDate',h.previous_effective_date,
            'approvalDate',h.approval_date,'effectiveDate',h.effective_date,'reviewBy',h.review_by,'reviewTime',h.review_time
          ) order by h.review_time desc) from public.smis_personnel_certificate_review_history h where h.certificate_item_id=i.id),'[]'::jsonb)
        ) order by i.sort,q.item_name) from public.smis_personnel_certificate_item i
          join public.smis_qualification_catalog q on q.id=i.catalog_id where i.certificate_id=c.id),'[]'::jsonb) items,
        case
          when exists(select 1 from public.smis_personnel_certificate_item i where i.certificate_id=c.id and i.dismissal_reason is null and i.effective_date<current_date) then 'expired'
          when exists(select 1 from public.smis_personnel_certificate_item i where i.certificate_id=c.id and i.dismissal_reason is null and i.effective_date<=current_date+i.reminder_days) then 'warning'
          else 'normal'
        end reminder_state,
        (select min(i.effective_date) from public.smis_personnel_certificate_item i where i.certificate_id=c.id and i.dismissal_reason is null) nearest_effective_date
      from public.smis_personnel_certificate c
      join public.hr_employee e on e.id=c.employee_id and e.tenant_id=c.tenant_id
      left join public.sys_organization o on o.id=e.organization_id
      where c.tenant_id=app_private.current_read_tenant_id()
    ), filtered as (
      select * from enriched certificate
      where (v_name is null or lower(certificate.employee_name) like '%'||v_name||'%')
        and (v_number is null or lower(certificate.certificate_number) like '%'||v_number||'%')
        and (p_certificate_category is null or certificate.certificate_category=p_certificate_category)
        and (p_warning_status is null or (p_warning_status='normal' and certificate.reminder_state='normal') or (p_warning_status='warning' and certificate.reminder_state in ('warning','expired')))
        and (p_start_date is null or exists(select 1 from public.smis_personnel_certificate_item i where i.certificate_id=certificate.id and i.effective_date>=p_start_date))
        and (p_end_date is null or exists(select 1 from public.smis_personnel_certificate_item i where i.certificate_id=certificate.id and i.effective_date<=p_end_date))
    )
    select jsonb_build_object(
      'records',coalesce((select jsonb_agg(to_jsonb(r) order by r."nearestEffectiveDate" nulls last,r."employeeName") from (
        select id,tenant_id "tenantId",employee_id "employeeId",employee_no "employeeNo",employee_name "employeeName",
          gender,phone,job_title "jobTitle",avatar_url "avatarUrl",organization_name "organizationName",
          certificate_category "certificateCategory",certificate_number "certificateNumber",issuing_authority "issuingAuthority",
          archive_number "archiveNumber",certificate_photo_url "certificatePhotoUrl",warning_status "warningStatus",
          reminder_state "reminderState",nearest_effective_date "nearestEffectiveDate",extra_fields "extraFields",remark,items,
          create_by "createBy",create_time "createTime",update_by "updateBy",update_time "updateTime"
        from filtered offset v_from limit v_to-v_from+1
      ) r),'[]'::jsonb),
      'total',(select count(*) from filtered),
      'overview',(select jsonb_build_object(
        'total',count(*),'normal',count(*) filter(where reminder_state='normal'),
        'warning',count(*) filter(where reminder_state='warning'),'expired',count(*) filter(where reminder_state='expired'),
        'employees',count(distinct employee_id)
      ) from enriched)
    )
  );
end;
$function$;

create or replace function public.smis_save_personnel_certificate_secure(p_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_employee uuid;
  v_category text:=p_payload->>'certificate_category';
  v_number text:=btrim(coalesce(p_payload->>'certificate_number',''));
  v_items jsonb:=coalesce(p_payload->'items','[]'::jsonb);
  v_result uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护人员证件台账' using errcode='42501'; end if;
  if not app_private.has_permission(case when p_id is null then 'SmisPersonnelCertificateLedger:Add' else 'SmisPersonnelCertificateLedger:Edit' end) then raise exception '当前账号没有维护人员证件台账的权限' using errcode='42501'; end if;
  v_tenant:=app_private.resolve_mutation_tenant_id((select tenant_id from public.smis_personnel_certificate where id=p_id));
  begin v_employee:=(p_payload->>'employee_id')::uuid; exception when invalid_text_representation then raise exception '请选择员工' using errcode='22023'; end;
  if not exists(select 1 from public.hr_employee where id=v_employee and tenant_id=v_tenant) then raise exception '所选员工不存在或不属于当前租户' using errcode='P0002'; end if;
  if v_category not in ('special_equipment_personnel','special_equipment_operator','special_operation','safety_manager','registered_safety_engineer') then raise exception '证件类别无效' using errcode='22023'; end if;
  if v_number='' or char_length(v_number)>100 then raise exception '请输入不超过 100 个字符的证件编号' using errcode='22023'; end if;
  if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then raise exception '请至少维护一个作业项目' using errcode='22023'; end if;
  if p_id is null and exists(select 1 from jsonb_array_elements(v_items) i where nullif(i->>'dismissal_reason','') is not null) then raise exception '新增证件时不能填写消除提醒原因' using errcode='22023'; end if;

  if p_id is null then
    insert into public.smis_personnel_certificate(tenant_id,employee_id,certificate_category,certificate_number,issuing_authority,archive_number,certificate_photo_url,warning_status,extra_fields,remark)
    values(v_tenant,v_employee,v_category,v_number,nullif(btrim(p_payload->>'issuing_authority'),''),nullif(btrim(p_payload->>'archive_number'),''),nullif(btrim(p_payload->>'certificate_photo_url'),''),coalesce(nullif(p_payload->>'warning_status',''),'normal'),coalesce(p_payload->'extra_fields','{}'::jsonb),nullif(btrim(p_payload->>'remark'),''))
    returning id into v_result;
  else
    update public.smis_personnel_certificate set employee_id=v_employee,certificate_category=v_category,certificate_number=v_number,
      issuing_authority=nullif(btrim(p_payload->>'issuing_authority'),''),archive_number=nullif(btrim(p_payload->>'archive_number'),''),certificate_photo_url=nullif(btrim(p_payload->>'certificate_photo_url'),''),
      warning_status=coalesce(nullif(p_payload->>'warning_status',''),'normal'),extra_fields=coalesce(p_payload->'extra_fields','{}'::jsonb),remark=nullif(btrim(p_payload->>'remark'),'')
    where id=p_id and tenant_id=v_tenant returning id into v_result;
    if v_result is null then raise exception '证件不存在或已删除' using errcode='P0002'; end if;
  end if;

  delete from public.smis_personnel_certificate_item existing
  where existing.certificate_id=v_result and not exists(
    select 1 from jsonb_array_elements(v_items) item where nullif(item->>'id','')::uuid=existing.id
  );
  insert into public.smis_personnel_certificate_item(id,tenant_id,certificate_id,catalog_id,approval_date,effective_date,reminder_days,dismissal_reason,sort)
  select coalesce(nullif(item.value->>'id','')::uuid,gen_random_uuid()),v_tenant,v_result,
    (item.value->>'catalog_id')::uuid,(item.value->>'approval_date')::date,(item.value->>'effective_date')::date,
    coalesce(nullif(item.value->>'reminder_days','')::integer,30),nullif(item.value->>'dismissal_reason',''),(item.ordinality-1)*10
  from jsonb_array_elements(v_items) with ordinality item(value,ordinality)
  on conflict(id) do update set catalog_id=excluded.catalog_id,approval_date=excluded.approval_date,
    effective_date=excluded.effective_date,reminder_days=excluded.reminder_days,dismissal_reason=excluded.dismissal_reason,sort=excluded.sort
  where public.smis_personnel_certificate_item.certificate_id=v_result
    and public.smis_personnel_certificate_item.tenant_id=v_tenant;
  return v_result;
exception
  when unique_violation then raise exception '同类别证件编号或作业项目已存在' using errcode='23505';
  when foreign_key_violation then raise exception '所选作业项目不存在、已删除或不属于当前租户' using errcode='23503';
  when invalid_text_representation or datetime_field_overflow then raise exception '证件项目或日期格式无效' using errcode='22023';
end;
$function$;

create or replace function public.smis_delete_personnel_certificates_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = ''
as $function$
declare v_count integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再删除人员证件' using errcode='42501'; end if;
  if not app_private.has_permission('SmisPersonnelCertificateLedger:Delete') then raise exception '当前账号没有删除人员证件的权限' using errcode='42501'; end if;
  delete from public.smis_personnel_certificate where tenant_id=app_private.current_read_tenant_id() and id=any(coalesce(p_ids,'{}'::uuid[]));
  get diagnostics v_count=row_count; return v_count;
end;
$function$;

revoke all on function public.smis_list_qualification_catalog_secure(text,integer,integer,text,text,uuid,text) from public,anon;
grant execute on function public.smis_list_qualification_catalog_secure(text,integer,integer,text,text,uuid,text) to authenticated;
revoke all on function public.smis_save_qualification_catalog_secure(uuid,jsonb) from public,anon;
grant execute on function public.smis_save_qualification_catalog_secure(uuid,jsonb) to authenticated;
revoke all on function public.smis_delete_qualification_catalog_secure(text,uuid[]) from public,anon;
grant execute on function public.smis_delete_qualification_catalog_secure(text,uuid[]) to authenticated;
revoke all on function public.smis_list_personnel_certificates_secure(integer,integer,text,text,text,date,date,text,text) from public,anon;
grant execute on function public.smis_list_personnel_certificates_secure(integer,integer,text,text,text,date,date,text,text) to authenticated;
revoke all on function public.smis_save_personnel_certificate_secure(uuid,jsonb) from public,anon;
grant execute on function public.smis_save_personnel_certificate_secure(uuid,jsonb) to authenticated;
revoke all on function public.smis_delete_personnel_certificates_secure(uuid[]) from public,anon;
grant execute on function public.smis_delete_personnel_certificates_secure(uuid[]) to authenticated;

with dictionary_types(code,name,sort) as (values
  ('smisQualificationStatus','安全资质启用状态',80),
  ('smisCertificateCategory','人员证件类别',81),
  ('smisCertificateWarningStatus','证件预警状态',82),
  ('smisCertificateReminderDays','证件提前提醒时间',83),
  ('smisCertificateDismissalReason','证件消除提醒原因',84)
)
insert into public.sys_dict_type(id,parent_id,name,code,status,node_type,sort,tenant_id,create_by,update_by,remark)
select gen_random_uuid(),parent.id,item.name,item.code,'1','dictionary',item.sort,app_private.platform_tenant_id(),'624944977@qq.com','624944977@qq.com','安全资质管理业务字典'
from dictionary_types item join public.sys_dict_type parent on parent.code='smisSafetyProduction'
where not exists(select 1 from public.sys_dict_type existing where existing.code=item.code);

with items(type_code,suffix,value,label,color,tag_type,sort) as (values
  ('smisQualificationStatus','enabled','enabled','启用','#16a34a','success',1),
  ('smisQualificationStatus','disabled','disabled','停用','#64748b','info',2),
  ('smisCertificateCategory','special_equipment_personnel','special_equipment_personnel','特种设备人员证','#2563eb','primary',1),
  ('smisCertificateCategory','special_equipment_operator','special_equipment_operator','特种设备作业人员证','#0891b2','primary',2),
  ('smisCertificateCategory','special_operation','special_operation','特种作业操作证','#7c3aed','primary',3),
  ('smisCertificateCategory','safety_manager','safety_manager','安全管理人员证','#059669','success',4),
  ('smisCertificateCategory','registered_safety_engineer','registered_safety_engineer','注册安全工程师','#d97706','warning',5),
  ('smisCertificateWarningStatus','normal','normal','正常','#16a34a','success',1),
  ('smisCertificateWarningStatus','warning','warning','预警','#d97706','warning',2),
  ('smisCertificateReminderDays','30','30','提前 30 天','#2563eb','primary',1),
  ('smisCertificateReminderDays','60','60','提前 60 天','#2563eb','primary',2),
  ('smisCertificateReminderDays','90','90','提前 90 天','#2563eb','primary',3),
  ('smisCertificateReminderDays','180','180','提前 180 天','#2563eb','primary',4),
  ('smisCertificateDismissalReason','offboarded','offboarded','已离岗','#64748b','info',1),
  ('smisCertificateDismissalReason','trained','trained','已培训','#16a34a','success',2)
)
insert into public.sys_dictionary(id,type_id,code,status,value,label,color,tag_type,sort,tenant_id,create_by,update_by,remark)
select gen_random_uuid(),type.id,item.type_code||'_'||item.suffix,'1',item.value,item.label,item.color,item.tag_type,item.sort,app_private.platform_tenant_id(),'624944977@qq.com','624944977@qq.com','安全资质管理默认字典项'
from items item join public.sys_dict_type type on type.code=item.type_code
where not exists(select 1 from public.sys_dictionary d where d.type_id=type.id and d.value=item.value);

with buttons(menu_name,code,title,sort) as (values
  ('SmisWorkItem','SmisWorkItem:View','查看作业项目',1),('SmisWorkItem','SmisWorkItem:Add','新增作业项目',2),('SmisWorkItem','SmisWorkItem:Edit','编辑作业项目',3),('SmisWorkItem','SmisWorkItem:Delete','删除作业项目',4),('SmisWorkItem','SmisWorkItem:Export','导出作业项目',5),
  ('SmisWorkCategory','SmisWorkCategory:View','查看作业类别',1),('SmisWorkCategory','SmisWorkCategory:Add','新增作业类别',2),('SmisWorkCategory','SmisWorkCategory:Edit','编辑作业类别',3),('SmisWorkCategory','SmisWorkCategory:Delete','删除作业类别',4),('SmisWorkCategory','SmisWorkCategory:Export','导出作业类别',5),
  ('SmisPermittedOperationItem','SmisPermittedOperationItem:View','查看准操项目',1),('SmisPermittedOperationItem','SmisPermittedOperationItem:Add','新增准操项目',2),('SmisPermittedOperationItem','SmisPermittedOperationItem:Edit','编辑准操项目',3),('SmisPermittedOperationItem','SmisPermittedOperationItem:Delete','删除准操项目',4),('SmisPermittedOperationItem','SmisPermittedOperationItem:Export','导出准操项目',5),
  ('SmisSpecialEquipmentPersonnelCertificateLedger','SmisPersonnelCertificateLedger:View','查看人员证件台账',1),('SmisSpecialEquipmentPersonnelCertificateLedger','SmisPersonnelCertificateLedger:Add','新增人员证件',2),('SmisSpecialEquipmentPersonnelCertificateLedger','SmisPersonnelCertificateLedger:Copy','复制并新增人员证件',3),('SmisSpecialEquipmentPersonnelCertificateLedger','SmisPersonnelCertificateLedger:Edit','编辑人员证件',4),('SmisSpecialEquipmentPersonnelCertificateLedger','SmisPersonnelCertificateLedger:Delete','删除人员证件',5),('SmisSpecialEquipmentPersonnelCertificateLedger','SmisPersonnelCertificateLedger:Export','导出人员证件台账',6),('SmisSpecialEquipmentPersonnelCertificateLedger','SmisPersonnelCertificateLedger:ViewHistory','查看复审记录',7)
)
insert into public.sys_menu(id,parent_id,name,path,component,type,meta,sort,create_by,update_by,app_code)
select gen_random_uuid(),parent.id,button.code,'','','button',jsonb_build_object('title',button.title,'is_hide',true,'is_enable',true,'roles','[]'::jsonb),button.sort,'624944977@qq.com','624944977@qq.com','smis'
from buttons button join public.sys_menu parent on parent.name=button.menu_name
where not exists(select 1 from public.sys_menu existing where existing.name=button.code);

insert into public.sys_role_menu(role_id,menu_id,tenant_id,create_by,update_by)
select distinct grant_row.role_id,child.id,grant_row.tenant_id,'624944977@qq.com','624944977@qq.com'
from public.sys_role_menu grant_row join public.sys_menu parent on parent.id=grant_row.menu_id
join public.sys_menu child on child.parent_id=parent.id and child.type='button'
where parent.name in ('SmisWorkItem','SmisWorkCategory','SmisPermittedOperationItem','SmisSpecialEquipmentPersonnelCertificateLedger')
on conflict(role_id,menu_id) do nothing;

update public.sys_menu
set meta=jsonb_set(meta,'{title}','"人员证件台账"'::jsonb),update_time=now()
where name='SmisSpecialEquipmentPersonnelCertificateLedger';

commit;

;
