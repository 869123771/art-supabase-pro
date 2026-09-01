-- Protective equipment issuance standards and generated employee standards.

create table public.smis_ppe_issuance_standard (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  standard_no text not null,
  standard_name text not null,
  rated_quantity numeric(12,3) not null default 1,
  issuance_cycle text not null,
  issuance_frequency integer not null default 1,
  status text not null default 'enabled',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_issuance_standard_tenant_fkey foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_ppe_issuance_standard_id_tenant_unique unique (id, tenant_id),
  constraint smis_ppe_issuance_standard_no_check check (btrim(standard_no) <> '' and char_length(standard_no) <= 60),
  constraint smis_ppe_issuance_standard_name_check check (btrim(standard_name) <> '' and char_length(standard_name) <= 120),
  constraint smis_ppe_issuance_standard_quantity_check check (rated_quantity > 0),
  constraint smis_ppe_issuance_standard_cycle_check check (issuance_cycle in ('day','week','month','half_year','quarter','year')),
  constraint smis_ppe_issuance_standard_frequency_check check (issuance_frequency between 1 and 9999),
  constraint smis_ppe_issuance_standard_status_check check (status in ('enabled','disabled')),
  constraint smis_ppe_issuance_standard_description_check check (description is null or char_length(description) <= 1000)
);
create unique index smis_ppe_issuance_standard_no_unique on public.smis_ppe_issuance_standard(tenant_id, lower(btrim(standard_no)));
create index smis_ppe_issuance_standard_name_idx on public.smis_ppe_issuance_standard(tenant_id, status, standard_name);

create table public.smis_ppe_issuance_standard_position (
  standard_id uuid not null,
  position_id uuid not null,
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  create_by text,
  create_time timestamptz not null default now(),
  primary key (standard_id, position_id),
  constraint smis_ppe_standard_position_standard_fkey foreign key (standard_id, tenant_id) references public.smis_ppe_issuance_standard(id, tenant_id) on delete cascade,
  constraint smis_ppe_standard_position_position_fkey foreign key (position_id) references public.hr_position(id) on delete restrict
);
create index smis_ppe_standard_position_tenant_idx on public.smis_ppe_issuance_standard_position(tenant_id, position_id);

create table public.smis_ppe_issuance_standard_organization (
  standard_id uuid not null,
  organization_id uuid not null,
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  create_by text,
  create_time timestamptz not null default now(),
  primary key (standard_id, organization_id),
  constraint smis_ppe_standard_org_standard_fkey foreign key (standard_id, tenant_id) references public.smis_ppe_issuance_standard(id, tenant_id) on delete cascade,
  constraint smis_ppe_standard_org_org_fkey foreign key (organization_id) references public.sys_organization(id) on delete restrict
);
create index smis_ppe_standard_org_tenant_idx on public.smis_ppe_issuance_standard_organization(tenant_id, organization_id);

create table public.smis_ppe_issuance_standard_detail (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  standard_id uuid not null,
  material_id uuid not null,
  quota_quantity numeric(12,3) not null,
  issuance_cycle text not null,
  issuance_frequency integer not null default 1,
  status text not null default 'enabled',
  remark text,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_standard_detail_tenant_fkey foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_ppe_standard_detail_standard_fkey foreign key (standard_id, tenant_id) references public.smis_ppe_issuance_standard(id, tenant_id) on delete cascade,
  constraint smis_ppe_standard_detail_material_fkey foreign key (material_id) references public.smis_material(id) on delete restrict,
  constraint smis_ppe_standard_detail_unique unique (standard_id, material_id),
  constraint smis_ppe_standard_detail_quantity_check check (quota_quantity > 0),
  constraint smis_ppe_standard_detail_cycle_check check (issuance_cycle in ('day','week','month','half_year','quarter','year')),
  constraint smis_ppe_standard_detail_frequency_check check (issuance_frequency between 1 and 9999),
  constraint smis_ppe_standard_detail_status_check check (status in ('enabled','disabled')),
  constraint smis_ppe_standard_detail_remark_check check (remark is null or char_length(remark) <= 500)
);
create index smis_ppe_standard_detail_standard_idx on public.smis_ppe_issuance_standard_detail(tenant_id, standard_id, sort);
create index smis_ppe_standard_detail_material_idx on public.smis_ppe_issuance_standard_detail(tenant_id, material_id);

create table public.smis_ppe_personal_standard (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  organization_id uuid,
  position_id uuid,
  generated_at timestamptz not null default now(),
  status text not null default 'enabled',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_personal_tenant_fkey foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_ppe_personal_employee_fkey foreign key (employee_id) references public.hr_employee(id) on delete cascade,
  constraint smis_ppe_personal_org_fkey foreign key (organization_id) references public.sys_organization(id) on delete set null,
  constraint smis_ppe_personal_position_fkey foreign key (position_id) references public.hr_position(id) on delete set null,
  constraint smis_ppe_personal_tenant_employee_unique unique (tenant_id, employee_id),
  constraint smis_ppe_personal_id_tenant_unique unique (id, tenant_id),
  constraint smis_ppe_personal_status_check check (status in ('enabled','disabled'))
);
create index smis_ppe_personal_scope_idx on public.smis_ppe_personal_standard(tenant_id, organization_id, position_id);

create table public.smis_ppe_personal_standard_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  personal_standard_id uuid not null,
  source_standard_id uuid not null,
  source_detail_id uuid not null,
  material_id uuid not null,
  quota_quantity numeric(12,3) not null,
  issuance_cycle text not null,
  issuance_frequency integer not null,
  status text not null default 'enabled',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_personal_item_tenant_fkey foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_ppe_personal_item_personal_fkey foreign key (personal_standard_id, tenant_id) references public.smis_ppe_personal_standard(id, tenant_id) on delete cascade,
  constraint smis_ppe_personal_item_standard_fkey foreign key (source_standard_id, tenant_id) references public.smis_ppe_issuance_standard(id, tenant_id) on delete restrict,
  constraint smis_ppe_personal_item_detail_fkey foreign key (source_detail_id) references public.smis_ppe_issuance_standard_detail(id) on delete restrict,
  constraint smis_ppe_personal_item_material_fkey foreign key (material_id) references public.smis_material(id) on delete restrict,
  constraint smis_ppe_personal_item_source_unique unique (personal_standard_id, source_detail_id),
  constraint smis_ppe_personal_item_quantity_check check (quota_quantity > 0),
  constraint smis_ppe_personal_item_cycle_check check (issuance_cycle in ('day','week','month','half_year','quarter','year')),
  constraint smis_ppe_personal_item_frequency_check check (issuance_frequency between 1 and 9999),
  constraint smis_ppe_personal_item_status_check check (status in ('enabled','disabled'))
);
create index smis_ppe_personal_item_parent_idx on public.smis_ppe_personal_standard_item(tenant_id, personal_standard_id);

create trigger smis_ppe_issuance_standard_create_audit before insert on public.smis_ppe_issuance_standard for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_issuance_standard_update_audit before update on public.smis_ppe_issuance_standard for each row execute function public.trg_set_update_time_and_by();
create trigger smis_ppe_standard_position_create_audit before insert on public.smis_ppe_issuance_standard_position for each row execute function public.trg_set_create_time_and_by('true','false');
create trigger smis_ppe_standard_org_create_audit before insert on public.smis_ppe_issuance_standard_organization for each row execute function public.trg_set_create_time_and_by('true','false');
create trigger smis_ppe_standard_detail_create_audit before insert on public.smis_ppe_issuance_standard_detail for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_standard_detail_update_audit before update on public.smis_ppe_issuance_standard_detail for each row execute function public.trg_set_update_time_and_by();
create trigger smis_ppe_personal_create_audit before insert on public.smis_ppe_personal_standard for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_personal_update_audit before update on public.smis_ppe_personal_standard for each row execute function public.trg_set_update_time_and_by();
create trigger smis_ppe_personal_item_create_audit before insert on public.smis_ppe_personal_standard_item for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_personal_item_update_audit before update on public.smis_ppe_personal_standard_item for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_ppe_issuance_standard enable row level security;
alter table public.smis_ppe_issuance_standard_position enable row level security;
alter table public.smis_ppe_issuance_standard_organization enable row level security;
alter table public.smis_ppe_issuance_standard_detail enable row level security;
alter table public.smis_ppe_personal_standard enable row level security;
alter table public.smis_ppe_personal_standard_item enable row level security;

do $$
declare v_table text;
begin
  foreach v_table in array array['smis_ppe_issuance_standard','smis_ppe_issuance_standard_position','smis_ppe_issuance_standard_organization','smis_ppe_issuance_standard_detail'] loop
    execute format('create policy %I on public.%I for select to authenticated using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission(''SmisPpeIssuanceStandard:View''))))', v_table || '_select', v_table);
  end loop;
  foreach v_table in array array['smis_ppe_personal_standard','smis_ppe_personal_standard_item'] loop
    execute format('create policy %I on public.%I for select to authenticated using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission(''SmisPpePersonalStandard:View''))))', v_table || '_select', v_table);
  end loop;
end $$;

create or replace function public.smis_list_ppe_scope_options_secure(p_kind text, p_keyword text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_keyword text := nullif(btrim(coalesce(p_keyword,'')), '');
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisPpeIssuanceStandard:View') or app_private.has_permission('SmisPpeIssuanceStandard:Add') or app_private.has_permission('SmisPpeIssuanceStandard:Edit') or app_private.has_permission('SmisPpePersonalStandard:View')) then raise exception '当前账号没有查看适用范围的权限' using errcode='42501'; end if;
  if p_kind = 'position' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.position_code,'name',p.position_name,'organizationId',p.organization_id,'organizationName',o.organization_name) order by p.sort,p.position_name)
      from public.hr_position p left join public.sys_organization o on o.id=p.organization_id
      where (app_private.current_read_tenant_id() is null or p.tenant_id=app_private.current_read_tenant_id()) and p.enabled
        and (v_keyword is null or p.position_name ilike '%'||v_keyword||'%' or p.position_code ilike '%'||v_keyword||'%')), '[]'::jsonb);
  elsif p_kind = 'organization' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'parentId',o.parent_id,'code',o.organization_code,'name',o.organization_name,'type',o.organization_type,'sort',o.sort) order by o.sort,o.organization_name)
      from public.sys_organization o where (app_private.current_read_tenant_id() is null or o.tenant_id=app_private.current_read_tenant_id()) and o.status='1'
        and (v_keyword is null or o.organization_name ilike '%'||v_keyword||'%' or o.organization_code ilike '%'||v_keyword||'%')), '[]'::jsonb);
  end if;
  raise exception '适用范围类型无效' using errcode='22023';
end $$;

create or replace function public.smis_list_ppe_issuance_standards_secure(p_from integer default 0, p_to integer default 19, p_keyword text default null, p_status text default null, p_purpose text default 'list')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看发放标准' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisPpeIssuanceStandard:Export') then raise exception '当前账号没有导出权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisPpeIssuanceStandard:View')) then raise exception '当前账号没有查看权限' using errcode='42501'; end if;
  return (with filtered as (
    select s.* from public.smis_ppe_issuance_standard s where (app_private.current_read_tenant_id() is null or s.tenant_id=app_private.current_read_tenant_id()) and (p_status is null or s.status=p_status) and (v_keyword is null or s.standard_no ilike '%'||v_keyword||'%' or s.standard_name ilike '%'||v_keyword||'%')
  ), rows as (
    select s.id,s.tenant_id as "tenantId",s.standard_no as "standardNo",s.standard_name as "standardName",s.rated_quantity as "ratedQuantity",s.issuance_cycle as "issuanceCycle",s.issuance_frequency as "issuanceFrequency",s.status,s.description,s.create_time as "createTime",s.update_time as "updateTime",
      coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.position_code,'name',p.position_name,'organizationName',o.organization_name) order by p.sort,p.position_name) from public.smis_ppe_issuance_standard_position sp join public.hr_position p on p.id=sp.position_id left join public.sys_organization o on o.id=p.organization_id where sp.standard_id=s.id),'[]'::jsonb) positions,
      coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'parentId',o.parent_id,'code',o.organization_code,'name',o.organization_name,'type',o.organization_type) order by o.sort,o.organization_name) from public.smis_ppe_issuance_standard_organization so join public.sys_organization o on o.id=so.organization_id where so.standard_id=s.id),'[]'::jsonb) organizations,
      coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'materialId',m.id,'materialCode',m.material_code,'materialName',m.material_name,'categoryName',c.category_name,'specificationModel',m.specification_model,'basicUnit',m.basic_unit,'imageUrls',m.image_urls,'quotaQuantity',d.quota_quantity,'issuanceCycle',d.issuance_cycle,'issuanceFrequency',d.issuance_frequency,'status',d.status,'remark',d.remark,'sort',d.sort) order by d.sort,m.material_name) from public.smis_ppe_issuance_standard_detail d join public.smis_material m on m.id=d.material_id join public.smis_material_category c on c.id=m.category_id where d.standard_id=s.id),'[]'::jsonb) details
    from filtered s order by s.update_time desc offset v_from limit v_to-v_from+1
  ) select jsonb_build_object('records',coalesce((select jsonb_agg(rows order by "updateTime" desc) from rows),'[]'::jsonb),'total',(select count(*) from filtered),'overview',(select jsonb_build_object('total',count(*),'enabled',count(*) filter(where status='enabled'),'disabled',count(*) filter(where status='disabled'),'detailTotal',coalesce(sum((select count(*) from public.smis_ppe_issuance_standard_detail d where d.standard_id=filtered.id)),0)) from filtered)));
end $$;

create or replace function public.smis_save_ppe_issuance_standard_secure(p_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_id uuid; v_standard_no text:=nullif(btrim(coalesce(p_payload->>'standard_no','')),''); v_name text:=btrim(coalesce(p_payload->>'standard_name','')); v_positions jsonb:=coalesce(p_payload->'position_ids','[]'); v_orgs jsonb:=coalesce(p_payload->'organization_ids','[]'); v_details jsonb:=coalesce(p_payload->'details','[]'); v_detail jsonb; v_material uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护发放标准' using errcode='42501'; end if;
  if p_id is null and not app_private.has_permission('SmisPpeIssuanceStandard:Add') then raise exception '当前账号没有新增权限' using errcode='42501'; end if;
  if p_id is not null and not app_private.has_permission('SmisPpeIssuanceStandard:Edit') then raise exception '当前账号没有编辑权限' using errcode='42501'; end if;
  v_tenant:=app_private.resolve_mutation_tenant_id((select tenant_id from public.smis_ppe_issuance_standard where id=p_id)); if v_tenant is null then raise exception '当前账号未绑定有效租户' using errcode='42501'; end if;
  if v_name='' then raise exception '请输入发放标准名称' using errcode='22023'; end if;
  if jsonb_typeof(v_positions)<>'array' or jsonb_typeof(v_orgs)<>'array' or jsonb_typeof(v_details)<>'array' then raise exception '发放标准数据格式无效' using errcode='22023'; end if;
  if jsonb_array_length(v_positions)=0 and jsonb_array_length(v_orgs)=0 then raise exception '适用岗位和适用公司/部门至少选择一项' using errcode='22023'; end if;
  if jsonb_array_length(v_details)=0 then raise exception '请至少添加一条防护用品明细' using errcode='22023'; end if;
  if p_id is null and v_standard_no is null then v_standard_no:=app_private.next_document_number('smis.ppe_issuance_standard',v_tenant); end if;
  if v_standard_no is null then raise exception '标准编号生成失败，请检查编号规则' using errcode='22023'; end if;
  if not app_private.is_enabled_dictionary_value('smisPpeIssuanceCycle',p_payload->>'issuance_cycle') then raise exception '发放周期无效' using errcode='22023'; end if;
  if p_id is null then insert into public.smis_ppe_issuance_standard(tenant_id,standard_no,standard_name,rated_quantity,issuance_cycle,issuance_frequency,status,description) values(v_tenant,v_standard_no,v_name,(p_payload->>'rated_quantity')::numeric,p_payload->>'issuance_cycle',(p_payload->>'issuance_frequency')::integer,coalesce(p_payload->>'status','enabled'),nullif(btrim(p_payload->>'description'),'')) returning id into v_id;
  else update public.smis_ppe_issuance_standard set standard_name=v_name,rated_quantity=(p_payload->>'rated_quantity')::numeric,issuance_cycle=p_payload->>'issuance_cycle',issuance_frequency=(p_payload->>'issuance_frequency')::integer,status=coalesce(p_payload->>'status','enabled'),description=nullif(btrim(p_payload->>'description'),'') where id=p_id and tenant_id=v_tenant returning id into v_id; if v_id is null then raise exception '发放标准不存在或已删除' using errcode='P0002'; end if; end if;
  delete from public.smis_ppe_issuance_standard_position where standard_id=v_id;
  insert into public.smis_ppe_issuance_standard_position(standard_id,position_id,tenant_id) select v_id,value::uuid,v_tenant from jsonb_array_elements_text(v_positions);
  delete from public.smis_ppe_issuance_standard_organization where standard_id=v_id;
  insert into public.smis_ppe_issuance_standard_organization(standard_id,organization_id,tenant_id) select v_id,value::uuid,v_tenant from jsonb_array_elements_text(v_orgs);
  delete from public.smis_ppe_issuance_standard_detail where standard_id=v_id;
  for v_detail in select value from jsonb_array_elements(v_details) loop
    v_material:=(v_detail->>'material_id')::uuid;
    if not exists(select 1 from public.smis_material where id=v_material and tenant_id=v_tenant and material_type='protective_equipment' and status='enabled') then raise exception '所选防护用品不存在、已停用或不属于当前租户' using errcode='P0002'; end if;
    insert into public.smis_ppe_issuance_standard_detail(tenant_id,standard_id,material_id,quota_quantity,issuance_cycle,issuance_frequency,status,remark,sort) values(v_tenant,v_id,v_material,(v_detail->>'quota_quantity')::numeric,v_detail->>'issuance_cycle',(v_detail->>'issuance_frequency')::integer,coalesce(v_detail->>'status','enabled'),nullif(btrim(v_detail->>'remark'),''),coalesce((v_detail->>'sort')::integer,10));
  end loop;
  return v_id;
exception when unique_violation then raise exception '标准编号或明细物料重复，请检查后重试' using errcode='23505';
end $$;

create or replace function public.smis_delete_ppe_issuance_standards_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$ declare v_count integer; begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if; if not app_private.has_permission('SmisPpeIssuanceStandard:Delete') then raise exception '当前账号没有删除权限' using errcode='42501'; end if;
  if exists(select 1 from public.smis_ppe_personal_standard_item where source_standard_id=any(coalesce(p_ids,array[]::uuid[]))) then raise exception '所选标准已生成个人标准，请改为停用' using errcode='23503'; end if;
  delete from public.smis_ppe_issuance_standard where (app_private.is_platform_super() or tenant_id=app_private.auth_user_tenant_id()) and id=any(coalesce(p_ids,array[]::uuid[])); get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function public.smis_list_ppe_personal_standards_secure(p_from integer default 0,p_to integer default 19,p_keyword text default null,p_organization_ids uuid[] default null,p_position_id uuid default null,p_only_missing boolean default false,p_purpose text default 'list')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看个人标准' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisPpePersonalStandard:Export') then raise exception '当前账号没有导出权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisPpePersonalStandard:View')) then raise exception '当前账号没有查看权限' using errcode='42501'; end if;
  return (with filtered as (
    select e.id employee_id,e.employee_no,e.employee_name,e.avatar_url,e.organization_id,e.position_id,o.organization_name,p.position_name,ps.id personal_id,ps.generated_at,ps.status,
      coalesce((select count(*) from public.smis_ppe_personal_standard_item i where i.personal_standard_id=ps.id),0) item_count
    from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id left join public.smis_ppe_personal_standard ps on ps.employee_id=e.id and ps.tenant_id=e.tenant_id
    where (app_private.current_read_tenant_id() is null or e.tenant_id=app_private.current_read_tenant_id()) and e.employment_status in ('active','probation')
      and (p_organization_ids is null or e.organization_id=any(p_organization_ids)) and (p_position_id is null or e.position_id=p_position_id) and (not p_only_missing or ps.id is null)
      and (v_keyword is null or e.employee_name ilike '%'||v_keyword||'%' or e.employee_no ilike '%'||v_keyword||'%' or coalesce(p.position_name,'') ilike '%'||v_keyword||'%')
  ), rows as (select employee_id as "employeeId",employee_no as "employeeNo",employee_name as "employeeName",avatar_url as "avatarUrl",organization_id as "organizationId",organization_name as "organizationName",position_id as "positionId",position_name as "positionName",personal_id as "personalStandardId",generated_at as "generatedAt",status,item_count as "itemCount" from filtered order by organization_name,employee_name offset v_from limit v_to-v_from+1)
  select jsonb_build_object('records',coalesce((select jsonb_agg(rows) from rows),'[]'::jsonb),'total',(select count(*) from filtered),'overview',jsonb_build_object('employeeTotal',(select count(*) from filtered),'generatedTotal',(select count(*) from filtered where personal_id is not null),'missingTotal',(select count(*) from filtered where personal_id is null),'itemTotal',(select coalesce(sum(item_count),0) from filtered))));
end $$;

create or replace function public.smis_list_ppe_personal_standard_items_secure(p_employee_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$ begin
  if (select auth.uid()) is null or not (app_private.is_platform_super() or app_private.has_permission('SmisPpePersonalStandard:View')) then raise exception '当前账号没有查看个人标准明细的权限' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'sourceStandardId',s.id,'sourceStandardNo',s.standard_no,'sourceStandardName',s.standard_name,'materialId',m.id,'materialCode',m.material_code,'materialName',m.material_name,'categoryName',c.category_name,'specificationModel',m.specification_model,'basicUnit',m.basic_unit,'imageUrls',m.image_urls,'quotaQuantity',i.quota_quantity,'issuanceCycle',i.issuance_cycle,'issuanceFrequency',i.issuance_frequency,'status',i.status) order by c.category_name,m.material_name)
    from public.smis_ppe_personal_standard ps join public.smis_ppe_personal_standard_item i on i.personal_standard_id=ps.id join public.smis_ppe_issuance_standard s on s.id=i.source_standard_id join public.smis_material m on m.id=i.material_id join public.smis_material_category c on c.id=m.category_id
    where ps.employee_id=p_employee_id and (app_private.current_read_tenant_id() is null or ps.tenant_id=app_private.current_read_tenant_id())), '[]'::jsonb);
end $$;

create or replace function public.smis_generate_ppe_personal_standards_secure(p_employee_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_employee record; v_personal uuid; v_employees integer:=0; v_items integer:=0; v_unmatched integer:=0; v_inserted integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if; if not app_private.has_permission('SmisPpePersonalStandard:Generate') then raise exception '当前账号没有生成个人标准的权限' using errcode='42501'; end if;
  if cardinality(coalesce(p_employee_ids,array[]::uuid[]))=0 then raise exception '请选择需要生成个人标准的员工' using errcode='22023'; end if;
  for v_employee in select e.* from public.hr_employee e where e.id=any(p_employee_ids) and (app_private.is_platform_super() or e.tenant_id=app_private.auth_user_tenant_id()) loop
    insert into public.smis_ppe_personal_standard(tenant_id,employee_id,organization_id,position_id,generated_at,status) values(v_employee.tenant_id,v_employee.id,v_employee.organization_id,v_employee.position_id,now(),'enabled')
    on conflict(tenant_id,employee_id) do update set organization_id=excluded.organization_id,position_id=excluded.position_id,generated_at=excluded.generated_at,status='enabled' returning id into v_personal;
    delete from public.smis_ppe_personal_standard_item where personal_standard_id=v_personal;
    insert into public.smis_ppe_personal_standard_item(tenant_id,personal_standard_id,source_standard_id,source_detail_id,material_id,quota_quantity,issuance_cycle,issuance_frequency,status)
    select v_employee.tenant_id,v_personal,s.id,d.id,d.material_id,d.quota_quantity,d.issuance_cycle,d.issuance_frequency,d.status
    from public.smis_ppe_issuance_standard s join public.smis_ppe_issuance_standard_detail d on d.standard_id=s.id
    where s.tenant_id=v_employee.tenant_id and s.status='enabled' and d.status='enabled'
      and (not exists(select 1 from public.smis_ppe_issuance_standard_position sp where sp.standard_id=s.id) or exists(select 1 from public.smis_ppe_issuance_standard_position sp where sp.standard_id=s.id and sp.position_id=v_employee.position_id))
      and (not exists(select 1 from public.smis_ppe_issuance_standard_organization so where so.standard_id=s.id) or exists(select 1 from public.smis_ppe_issuance_standard_organization so where so.standard_id=s.id and so.organization_id=v_employee.organization_id));
    get diagnostics v_inserted=row_count; v_items:=v_items+v_inserted; v_employees:=v_employees+1; if v_inserted=0 then v_unmatched:=v_unmatched+1; end if;
  end loop;
  return jsonb_build_object('employeeCount',v_employees,'itemCount',v_items,'unmatchedCount',v_unmatched);
end $$;

revoke all on function public.smis_list_ppe_scope_options_secure(text,text) from public,anon;
revoke all on function public.smis_list_ppe_issuance_standards_secure(integer,integer,text,text,text) from public,anon;
revoke all on function public.smis_save_ppe_issuance_standard_secure(uuid,jsonb) from public,anon;
revoke all on function public.smis_delete_ppe_issuance_standards_secure(uuid[]) from public,anon;
revoke all on function public.smis_list_ppe_personal_standards_secure(integer,integer,text,uuid[],uuid,boolean,text) from public,anon;
revoke all on function public.smis_list_ppe_personal_standard_items_secure(uuid) from public,anon;
revoke all on function public.smis_generate_ppe_personal_standards_secure(uuid[]) from public,anon;
grant execute on function public.smis_list_ppe_scope_options_secure(text,text) to authenticated;
grant execute on function public.smis_list_ppe_issuance_standards_secure(integer,integer,text,text,text) to authenticated;
grant execute on function public.smis_save_ppe_issuance_standard_secure(uuid,jsonb) to authenticated;
grant execute on function public.smis_delete_ppe_issuance_standards_secure(uuid[]) to authenticated;
grant execute on function public.smis_list_ppe_personal_standards_secure(integer,integer,text,uuid[],uuid,boolean,text) to authenticated;
grant execute on function public.smis_list_ppe_personal_standard_items_secure(uuid) to authenticated;
grant execute on function public.smis_generate_ppe_personal_standards_secure(uuid[]) to authenticated;

do $$
declare v_platform uuid; v_parent_type uuid; v_cycle_type uuid; v_menu record; v_button record;
begin
  select id into v_platform from public.sys_tenant where tenant_code='platform' limit 1;
  select id into v_parent_type from public.sys_dict_type where tenant_id=v_platform and code='smisProtectiveEquipmentManagement' limit 1;
  insert into public.sys_dict_type(name,code,status,create_by,update_by,remark,tenant_id,parent_id,node_type,sort)
  select '发放周期','smisPpeIssuanceCycle','1','system','system','防护用品标准发放周期',v_platform,v_parent_type,'dictionary',30
  where not exists(select 1 from public.sys_dict_type where tenant_id=v_platform and code='smisPpeIssuanceCycle');
  select id into v_cycle_type from public.sys_dict_type where tenant_id=v_platform and code='smisPpeIssuanceCycle' limit 1;
  insert into public.sys_dictionary(type_id,code,status,create_by,update_by,remark,value,label,i18n_scope,sort,tenant_id,tag_type)
  select v_cycle_type,'smisPpeIssuanceCycle_'||x.value,'1','system','system','',x.value,x.label,'1',x.sort,v_platform,'info'
  from (values('day','天',1::bigint),('week','周',2::bigint),('month','月',3::bigint),('half_year','半年',4::bigint),('quarter','季',5::bigint),('year','年',6::bigint)) x(value,label,sort)
  where not exists(select 1 from public.sys_dictionary d where d.type_id=v_cycle_type and d.value=x.value);
  update public.sys_menu set meta=meta||jsonb_build_object('icon',case name when 'SmisPpeIssuanceStandard' then 'ri:shield-check-line' else 'ri:user-settings-line' end,'keep_alive',true,'is_hide',false,'is_enable',true),update_time=now() where app_code='smis' and name in('SmisPpeIssuanceStandard','SmisPpePersonalStandard');
  for v_button in select * from (values
    ('SmisPpeIssuanceStandard','SmisPpeIssuanceStandard:View','查看发放标准',1),('SmisPpeIssuanceStandard','SmisPpeIssuanceStandard:Add','新增发放标准',2),('SmisPpeIssuanceStandard','SmisPpeIssuanceStandard:Edit','编辑发放标准',3),('SmisPpeIssuanceStandard','SmisPpeIssuanceStandard:Delete','删除发放标准',4),('SmisPpeIssuanceStandard','SmisPpeIssuanceStandard:Export','导出发放标准',5),
    ('SmisPpePersonalStandard','SmisPpePersonalStandard:View','查看个人标准',1),('SmisPpePersonalStandard','SmisPpePersonalStandard:Generate','生成个人标准',2),('SmisPpePersonalStandard','SmisPpePersonalStandard:Export','导出个人标准',3)
  ) t(parent_name,button_name,title,sort) loop
    insert into public.sys_menu(id,name,path,component,meta,sort,create_by,update_by,parent_id,type,app_code)
    select gen_random_uuid(),v_button.button_name,'','',jsonb_build_object('title',v_button.title,'roles',jsonb_build_array(),'is_hide',true,'is_enable',true),v_button.sort,'system','system',p.id,'button','smis' from public.sys_menu p where p.app_code='smis' and p.name=v_button.parent_name and not exists(select 1 from public.sys_menu e where e.app_code='smis' and e.name=v_button.button_name) order by p.create_time limit 1;
  end loop;
  insert into public.sys_document_number_scene(rule_key,rule_name,field_label,category,menu_id,target_table,target_column,default_template,default_reset_cycle,manual_required,enabled,remark,create_by,update_by,tenant_id)
  select 'smis.ppe_issuance_standard','防护用品发放标准编号','标准编号','master_data',m.id,'smis_ppe_issuance_standard','standard_no','FFBZ{YYYY}-{SEQ:3}','year',false,true,'保存时自动生成 3 位流水码','system','system',v_platform from public.sys_menu m
  where m.app_code='smis' and m.name='SmisPpeIssuanceStandard' and not exists(select 1 from public.sys_document_number_scene s where s.rule_key='smis.ppe_issuance_standard') order by m.create_time limit 1;
  insert into public.sys_document_number_rule(tenant_id,rule_key,rule_name,category,target_table,target_column,auto_enabled,template,reset_cycle,sequence_start,timezone,rule_version,manual_required,builtin,enabled,remark,create_by,update_by)
  select t.id,'smis.ppe_issuance_standard','防护用品发放标准编号','master_data','smis_ppe_issuance_standard','standard_no',true,'FFBZ{YYYY}-{SEQ:3}','year',1,'Asia/Shanghai',1,false,true,true,'保存时自动生成 3 位流水码','system','system' from public.sys_tenant t
  where not exists(select 1 from public.sys_document_number_rule r where r.tenant_id=t.id and r.rule_key='smis.ppe_issuance_standard');
end $$;

;
