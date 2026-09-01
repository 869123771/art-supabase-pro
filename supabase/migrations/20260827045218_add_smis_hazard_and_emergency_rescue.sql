create unique index if not exists smis_site_id_tenant_uq on public.smis_site(id, tenant_id);
create unique index if not exists hr_position_id_tenant_uq on public.hr_position(id, tenant_id);

create table public.smis_hazard_source (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  hazard_no text not null,
  hazard_name text not null,
  site_id uuid not null,
  hazard_level text not null,
  risk_level text not null default 'unidentified',
  control_organization_id uuid not null,
  responsible_employee_id uuid,
  image_urls jsonb not null default '[]'::jsonb,
  record_status text not null default 'draft',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_hazard_source_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_hazard_source_id_tenant_unique unique (id, tenant_id),
  constraint smis_hazard_source_site_fkey foreign key (site_id, tenant_id)
    references public.smis_site(id, tenant_id) on delete restrict,
  constraint smis_hazard_source_control_org_fkey foreign key (tenant_id, control_organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_hazard_source_employee_fkey foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_hazard_source_no_not_blank check (btrim(hazard_no) <> ''),
  constraint smis_hazard_source_name_not_blank check (btrim(hazard_name) <> ''),
  constraint smis_hazard_source_level_check check (hazard_level in ('level_1','level_2','level_3','level_4')),
  constraint smis_hazard_source_risk_check check (risk_level in ('major','high','general','low','unidentified')),
  constraint smis_hazard_source_status_check check (record_status in ('draft','submitted')),
  constraint smis_hazard_source_images_check check (jsonb_typeof(image_urls) = 'array' and jsonb_array_length(image_urls) <= 9),
  constraint smis_hazard_source_name_length check (char_length(hazard_name) <= 160),
  constraint smis_hazard_source_remark_length check (remark is null or char_length(remark) <= 1000)
);

comment on table public.smis_hazard_source is '租户级危险源台账，按场所、危险等级和风险等级结构化管理';
comment on column public.smis_hazard_source.record_status is 'draft=草稿，submitted=已提交';
create unique index smis_hazard_source_no_uq on public.smis_hazard_source(tenant_id, lower(btrim(hazard_no)));
create index smis_hazard_source_site_idx on public.smis_hazard_source(tenant_id, site_id, record_status);
create index smis_hazard_source_org_idx on public.smis_hazard_source(tenant_id, control_organization_id, hazard_level);
create index smis_hazard_source_risk_idx on public.smis_hazard_source(tenant_id, risk_level, update_time desc);

create table public.smis_emergency_rescue_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_no text not null,
  plan_name text not null,
  applicable_organization_id uuid not null,
  plan_category text not null,
  applicable_position_id uuid,
  frequency text not null,
  is_special_equipment_drill boolean not null default false,
  plan_level text not null,
  is_valid boolean not null default true,
  warning_status text not null default 'normal',
  record_status text not null default 'draft',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_emergency_rescue_plan_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_emergency_rescue_plan_id_tenant_unique unique (id, tenant_id),
  constraint smis_emergency_rescue_plan_org_fkey foreign key (tenant_id, applicable_organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_emergency_rescue_plan_position_fkey foreign key (applicable_position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint smis_emergency_rescue_plan_no_not_blank check (btrim(plan_no) <> ''),
  constraint smis_emergency_rescue_plan_name_not_blank check (btrim(plan_name) <> ''),
  constraint smis_emergency_rescue_plan_category_check check (plan_category in ('comprehensive','onsite','special')),
  constraint smis_emergency_rescue_plan_frequency_check check (frequency in ('once_per_shift','daily','weekly','biweekly','triweekly','monthly','bimonthly','quarterly','semiannual')),
  constraint smis_emergency_rescue_plan_level_check check (plan_level in ('company','operation_department','operation_area','team')),
  constraint smis_emergency_rescue_plan_warning_check check (warning_status in ('normal','warning')),
  constraint smis_emergency_rescue_plan_status_check check (record_status in ('draft','submitted')),
  constraint smis_emergency_rescue_plan_name_length check (char_length(plan_name) <= 160),
  constraint smis_emergency_rescue_plan_description_length check (description is null or char_length(description) <= 2000)
);

comment on table public.smis_emergency_rescue_plan is '租户级应急救援预案主档';
comment on column public.smis_emergency_rescue_plan.plan_level is '由适用单位组织类型与层级自动推导';
create unique index smis_emergency_rescue_plan_no_uq on public.smis_emergency_rescue_plan(tenant_id, lower(btrim(plan_no)));
create index smis_emergency_rescue_plan_org_idx on public.smis_emergency_rescue_plan(tenant_id, applicable_organization_id, is_valid);
create index smis_emergency_rescue_plan_query_idx on public.smis_emergency_rescue_plan(tenant_id, plan_category, record_status, warning_status);

create table public.smis_emergency_drill_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  source_plan_id uuid not null,
  drill_name text not null,
  applicable_organization_id uuid not null,
  plan_category text not null,
  planned_date date,
  status text not null default 'draft',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_emergency_drill_plan_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_emergency_drill_plan_source_fkey foreign key (source_plan_id, tenant_id)
    references public.smis_emergency_rescue_plan(id, tenant_id) on delete restrict,
  constraint smis_emergency_drill_plan_org_fkey foreign key (tenant_id, applicable_organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_emergency_drill_plan_status_check check (status in ('draft','planned','completed','cancelled')),
  constraint smis_emergency_drill_plan_source_draft_uq unique (tenant_id, source_plan_id, status)
);

comment on table public.smis_emergency_drill_plan is '由有效应急预案下推形成的演练计划草稿';
create index smis_emergency_drill_plan_org_idx on public.smis_emergency_drill_plan(tenant_id, applicable_organization_id, status);

create trigger smis_hazard_source_create_audit before insert on public.smis_hazard_source
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_hazard_source_update_audit before update on public.smis_hazard_source
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_emergency_rescue_plan_create_audit before insert on public.smis_emergency_rescue_plan
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_emergency_rescue_plan_update_audit before update on public.smis_emergency_rescue_plan
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_emergency_drill_plan_create_audit before insert on public.smis_emergency_drill_plan
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_emergency_drill_plan_update_audit before update on public.smis_emergency_drill_plan
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_hazard_source enable row level security;
alter table public.smis_emergency_rescue_plan enable row level security;
alter table public.smis_emergency_drill_plan enable row level security;

create policy smis_hazard_source_select on public.smis_hazard_source for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisHazardSourceLedger:View')))
  or (select app_private.is_platform_super())
);
create policy smis_hazard_source_insert on public.smis_hazard_source for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisHazardSourceLedger:Add'))
);
create policy smis_hazard_source_update on public.smis_hazard_source for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisHazardSourceLedger:Edit'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisHazardSourceLedger:Edit'))
);
create policy smis_hazard_source_delete on public.smis_hazard_source for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisHazardSourceLedger:Delete'))
);

create policy smis_emergency_rescue_plan_select on public.smis_emergency_rescue_plan for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEmergencyRescuePlan:View')))
  or (select app_private.is_platform_super())
);
create policy smis_emergency_rescue_plan_insert on public.smis_emergency_rescue_plan for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEmergencyRescuePlan:Add'))
);
create policy smis_emergency_rescue_plan_update on public.smis_emergency_rescue_plan for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEmergencyRescuePlan:Edit'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEmergencyRescuePlan:Edit'))
);
create policy smis_emergency_rescue_plan_delete on public.smis_emergency_rescue_plan for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEmergencyRescuePlan:Delete'))
);

create policy smis_emergency_drill_plan_select on public.smis_emergency_drill_plan for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisEmergencyDrillPlan:View')) or
    (select app_private.has_permission('SmisEmergencyRescuePlan:Push'))
  )) or (select app_private.is_platform_super())
);

revoke all on table public.smis_hazard_source from public, anon, authenticated;
revoke all on table public.smis_emergency_rescue_plan from public, anon, authenticated;
revoke all on table public.smis_emergency_drill_plan from public, anon, authenticated;

create or replace function app_private.smis_plan_level_for_organization(p_tenant_id uuid, p_organization_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  with recursive lineage as (
    select organization.id, organization.parent_id, organization.organization_type, 0 depth
    from public.sys_organization organization
    where organization.tenant_id = p_tenant_id and organization.id = p_organization_id
    union all
    select parent.id, parent.parent_id, parent.organization_type, lineage.depth + 1
    from public.sys_organization parent join lineage on lineage.parent_id = parent.id
    where parent.tenant_id = p_tenant_id
  ), selected as (
    select organization_type, (select count(*) from lineage) hierarchy_depth from lineage where depth = 0
  )
  select case
    when organization_type = 'company' then 'company'
    when organization_type = 'division' then 'operation_area'
    when hierarchy_depth >= 4 then 'team'
    else 'operation_department'
  end from selected;
$$;

create or replace function public.smis_list_hazard_sources_secure(
  p_from integer default 0, p_to integer default 19, p_keyword text default null,
  p_site_id uuid default null, p_hazard_level text default null, p_risk_level text default null,
  p_organization_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
  v_sites jsonb;
  v_organizations jsonb;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看危险源台账'; end if;
  if not app_private.has_permission('SmisHazardSourceLedger:View') then raise exception '当前账号无权查看危险源台账'; end if;
  v_tenant_id := app_private.current_user_tenant_id();
  with recursive site_scope as (
    select id from public.smis_site where tenant_id=v_tenant_id and id=p_site_id
    union all select child.id from public.smis_site child join site_scope parent on child.parent_id=parent.id where child.tenant_id=v_tenant_id
  ), filtered as (
    select hazard.* from public.smis_hazard_source hazard
    where hazard.tenant_id=v_tenant_id
      and (p_site_id is null or hazard.site_id in (select id from site_scope))
      and (p_hazard_level is null or hazard.hazard_level=p_hazard_level)
      and (p_risk_level is null or hazard.risk_level=p_risk_level)
      and (p_organization_id is null or hazard.control_organization_id=p_organization_id)
      and (nullif(btrim(p_keyword),'') is null or hazard.hazard_no ilike '%'||btrim(p_keyword)||'%' or hazard.hazard_name ilike '%'||btrim(p_keyword)||'%')
  )
  select count(*) into v_total from filtered;

  with recursive site_scope as (
    select id from public.smis_site where tenant_id=v_tenant_id and id=p_site_id
    union all select child.id from public.smis_site child join site_scope parent on child.parent_id=parent.id where child.tenant_id=v_tenant_id
  ), filtered as (
    select hazard.* from public.smis_hazard_source hazard
    where hazard.tenant_id=v_tenant_id
      and (p_site_id is null or hazard.site_id in (select id from site_scope))
      and (p_hazard_level is null or hazard.hazard_level=p_hazard_level)
      and (p_risk_level is null or hazard.risk_level=p_risk_level)
      and (p_organization_id is null or hazard.control_organization_id=p_organization_id)
      and (nullif(btrim(p_keyword),'') is null or hazard.hazard_no ilike '%'||btrim(p_keyword)||'%' or hazard.hazard_name ilike '%'||btrim(p_keyword)||'%')
  )
  select coalesce(jsonb_agg(item.payload order by item.update_time desc), '[]'::jsonb) into v_records
  from (
    select hazard.update_time, jsonb_build_object(
      'id',hazard.id,'hazardNo',hazard.hazard_no,'hazardName',hazard.hazard_name,'siteId',hazard.site_id,
      'siteName',site.site_name,'hazardLevel',hazard.hazard_level,'riskLevel',hazard.risk_level,
      'controlOrganizationId',hazard.control_organization_id,'controlOrganizationName',organization.organization_name,
      'responsibleEmployeeId',hazard.responsible_employee_id,'responsibleEmployeeName',employee.employee_name,
      'responsibleEmployeeNo',employee.employee_no,'imageUrls',hazard.image_urls,'recordStatus',hazard.record_status,
      'remark',hazard.remark,'createTime',hazard.create_time,'updateTime',hazard.update_time
    ) payload
    from filtered hazard
    join public.smis_site site on site.id=hazard.site_id and site.tenant_id=hazard.tenant_id
    join public.sys_organization organization on organization.id=hazard.control_organization_id and organization.tenant_id=hazard.tenant_id
    left join public.hr_employee employee on employee.id=hazard.responsible_employee_id and employee.tenant_id=hazard.tenant_id
    order by hazard.update_time desc offset greatest(p_from,0) limit greatest(p_to-p_from+1,0)
  ) item;

  select jsonb_build_object(
    'total',count(*),'submitted',count(*) filter(where record_status='submitted'),
    'majorRisk',count(*) filter(where risk_level='major'),'siteCount',count(distinct site_id)
  ) into v_overview from public.smis_hazard_source where tenant_id=v_tenant_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',site.id,'parentId',site.parent_id,'siteName',site.site_name,'organizationId',site.organization_id,
    'sort',site.sort,'children','[]'::jsonb
  ) order by site.sort,site.site_name),'[]'::jsonb) into v_sites from public.smis_site site where site.tenant_id=v_tenant_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',organization.id,'parentId',organization.parent_id,'organizationName',organization.organization_name,
    'organizationType',organization.organization_type,'sort',organization.sort,'children','[]'::jsonb
  ) order by organization.sort,organization.organization_name),'[]'::jsonb) into v_organizations
  from public.sys_organization organization where organization.tenant_id=v_tenant_id and organization.status='1';
  return jsonb_build_object('records',v_records,'total',v_total,'overview',v_overview,'sites',v_sites,'organizations',v_organizations);
end; $$;

create or replace function public.smis_save_hazard_source_secure(p_id uuid, p_payload jsonb, p_submit boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_hazard_no text := upper(btrim(coalesce(p_payload->>'hazard_no','')));
  v_hazard_name text := btrim(coalesce(p_payload->>'hazard_name',''));
  v_site_id uuid := nullif(p_payload->>'site_id','')::uuid;
  v_hazard_level text := p_payload->>'hazard_level';
  v_risk_level text := coalesce(nullif(p_payload->>'risk_level',''),'unidentified');
  v_org_id uuid := nullif(p_payload->>'control_organization_id','')::uuid;
  v_employee_id uuid := nullif(p_payload->>'responsible_employee_id','')::uuid;
  v_id uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护危险源'; end if;
  if p_id is null and not app_private.has_permission('SmisHazardSourceLedger:Add') then raise exception '当前账号无权新增危险源'; end if;
  if p_id is not null and not app_private.has_permission('SmisHazardSourceLedger:Edit') then raise exception '当前账号无权编辑危险源'; end if;
  if p_submit and not app_private.has_permission('SmisHazardSourceLedger:Submit') then raise exception '当前账号无权提交危险源'; end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if v_hazard_name='' then raise exception '请输入危险源名称'; end if;
  if v_site_id is null then raise exception '请选择场所'; end if;
  if v_hazard_level not in ('level_1','level_2','level_3','level_4') then raise exception '请选择有效的危险等级'; end if;
  if v_risk_level not in ('major','high','general','low','unidentified') then raise exception '请选择有效的风险等级'; end if;
  if v_org_id is null then raise exception '请选择管控部门'; end if;
  if not exists(select 1 from public.smis_site where id=v_site_id and tenant_id=v_tenant_id) then raise exception '所选场所不存在或不属于当前租户'; end if;
  if not exists(select 1 from public.sys_organization where id=v_org_id and tenant_id=v_tenant_id and status='1') then raise exception '所选管控部门不存在、已停用或不属于当前租户'; end if;
  if v_employee_id is not null and not exists(select 1 from public.hr_employee where id=v_employee_id and tenant_id=v_tenant_id and employment_status='active') then raise exception '所选责任人不存在、已离职或不属于当前租户'; end if;
  if jsonb_typeof(coalesce(p_payload->'image_urls','[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_payload->'image_urls','[]'::jsonb)) > 9 then raise exception '危险源照片最多上传9张'; end if;
  if p_id is null then
    if v_hazard_no='' then v_hazard_no := app_private.next_document_number('smis.hazard_source',v_tenant_id); end if;
    insert into public.smis_hazard_source(hazard_no,hazard_name,site_id,hazard_level,risk_level,control_organization_id,responsible_employee_id,image_urls,record_status,remark,tenant_id)
    values(v_hazard_no,v_hazard_name,v_site_id,v_hazard_level,v_risk_level,v_org_id,v_employee_id,coalesce(p_payload->'image_urls','[]'::jsonb),case when p_submit then 'submitted' else 'draft' end,nullif(btrim(p_payload->>'remark'),''),v_tenant_id)
    returning id into v_id;
  else
    select hazard_no into v_hazard_no from public.smis_hazard_source where id=p_id and tenant_id=v_tenant_id;
    if v_hazard_no is null then raise exception '危险源不存在或不属于当前租户'; end if;
    update public.smis_hazard_source set hazard_name=v_hazard_name,site_id=v_site_id,hazard_level=v_hazard_level,risk_level=v_risk_level,
      control_organization_id=v_org_id,responsible_employee_id=v_employee_id,image_urls=coalesce(p_payload->'image_urls','[]'::jsonb),
      record_status=case when p_submit then 'submitted' else record_status end,remark=nullif(btrim(p_payload->>'remark'),'')
    where id=p_id and tenant_id=v_tenant_id returning id into v_id;
  end if;
  return v_id;
exception when unique_violation then raise exception '危险源编号已存在，请检查编号规则'; end; $$;

create or replace function public.smis_delete_hazard_sources_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_count integer;
begin
  if not app_private.has_permission('SmisHazardSourceLedger:Delete') then raise exception '当前账号无权删除危险源'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  if exists(select 1 from public.smis_hazard_source where id=any(p_ids) and tenant_id=v_tenant_id and record_status<>'draft') then raise exception '仅草稿危险源可以删除'; end if;
  delete from public.smis_hazard_source where id=any(p_ids) and tenant_id=v_tenant_id;
  get diagnostics v_count=row_count; return v_count;
end; $$;

create or replace function public.smis_hazard_source_statistics_secure(p_organization_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_rows jsonb;
begin
  if not app_private.has_permission('SmisHazardSourceLedger:Statistics') then raise exception '当前账号无权查看危险源统计'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  with recursive org_scope as (
    select id from public.sys_organization where tenant_id=v_tenant_id and id=p_organization_id
    union all select child.id from public.sys_organization child join org_scope parent on child.parent_id=parent.id where child.tenant_id=v_tenant_id
  ), levels(value,sort) as (values('level_1',1),('level_2',2),('level_3',3),('level_4',4))
  select coalesce(jsonb_agg(jsonb_build_object('hazardLevel',levels.value,'count',coalesce(stats.count,0)) order by levels.sort),'[]'::jsonb)
  into v_rows from levels left join (
    select hazard_level,count(*) count from public.smis_hazard_source where tenant_id=v_tenant_id and record_status='submitted'
      and (p_organization_id is null or control_organization_id in(select id from org_scope)) group by hazard_level
  ) stats on stats.hazard_level=levels.value;
  return jsonb_build_object('rows',v_rows,'total',(select coalesce(sum((item->>'count')::int),0) from jsonb_array_elements(v_rows) item));
end; $$;

create or replace function public.smis_list_hazard_source_employees_secure(p_from integer default 0,p_to integer default 19,p_keyword text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_records jsonb; v_total bigint;
begin
  if not (app_private.has_permission('SmisHazardSourceLedger:Add') or app_private.has_permission('SmisHazardSourceLedger:Edit')) then raise exception '当前账号无权选择危险源责任人'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  with filtered as (select employee.*,organization.organization_name from public.hr_employee employee left join public.sys_organization organization on organization.id=employee.organization_id and organization.tenant_id=employee.tenant_id
    where employee.tenant_id=v_tenant_id and employee.employment_status='active' and (nullif(btrim(p_keyword),'') is null or employee.employee_name ilike '%'||btrim(p_keyword)||'%' or employee.employee_no ilike '%'||btrim(p_keyword)||'%'))
  select count(*) into v_total from filtered;
  with filtered as (select employee.*,organization.organization_name from public.hr_employee employee left join public.sys_organization organization on organization.id=employee.organization_id and organization.tenant_id=employee.tenant_id
    where employee.tenant_id=v_tenant_id and employee.employment_status='active' and (nullif(btrim(p_keyword),'') is null or employee.employee_name ilike '%'||btrim(p_keyword)||'%' or employee.employee_no ilike '%'||btrim(p_keyword)||'%'))
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'tenantId',tenant_id,'organizationId',organization_id,'employeeNo',employee_no,'employeeName',employee_name,'avatarUrl',avatar_url,'jobTitle',job_title,'employmentStatus',employment_status,'organization',jsonb_build_object('id',organization_id,'organizationName',organization_name)) order by employee_name),'[]'::jsonb)
  into v_records from (select * from filtered order by employee_name offset greatest(p_from,0) limit greatest(p_to-p_from+1,0)) page;
  return jsonb_build_object('records',v_records,'total',v_total);
end; $$;

create or replace function public.smis_list_emergency_rescue_plans_secure(
  p_from integer default 0,p_to integer default 19,p_keyword text default null,p_plan_category text default null,
  p_organization_id uuid default null,p_is_valid boolean default null,p_warning_status text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_records jsonb; v_total bigint; v_overview jsonb; v_orgs jsonb; v_positions jsonb;
begin
  if not app_private.has_permission('SmisEmergencyRescuePlan:View') then raise exception '当前账号无权查看应急救援预案'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  with filtered as (select plan.* from public.smis_emergency_rescue_plan plan where plan.tenant_id=v_tenant_id
    and (nullif(btrim(p_keyword),'') is null or plan.plan_no ilike '%'||btrim(p_keyword)||'%' or plan.plan_name ilike '%'||btrim(p_keyword)||'%')
    and (p_plan_category is null or plan.plan_category=p_plan_category) and (p_organization_id is null or plan.applicable_organization_id=p_organization_id)
    and (p_is_valid is null or plan.is_valid=p_is_valid) and (p_warning_status is null or plan.warning_status=p_warning_status))
  select count(*) into v_total from filtered;
  with filtered as (select plan.* from public.smis_emergency_rescue_plan plan where plan.tenant_id=v_tenant_id
    and (nullif(btrim(p_keyword),'') is null or plan.plan_no ilike '%'||btrim(p_keyword)||'%' or plan.plan_name ilike '%'||btrim(p_keyword)||'%')
    and (p_plan_category is null or plan.plan_category=p_plan_category) and (p_organization_id is null or plan.applicable_organization_id=p_organization_id)
    and (p_is_valid is null or plan.is_valid=p_is_valid) and (p_warning_status is null or plan.warning_status=p_warning_status))
  select coalesce(jsonb_agg(jsonb_build_object('id',plan.id,'planNo',plan.plan_no,'planName',plan.plan_name,'applicableOrganizationId',plan.applicable_organization_id,
    'applicableOrganizationName',organization.organization_name,'planCategory',plan.plan_category,'applicablePositionId',plan.applicable_position_id,
    'applicablePositionName',position.position_name,'frequency',plan.frequency,'isSpecialEquipmentDrill',plan.is_special_equipment_drill,
    'planLevel',plan.plan_level,'isValid',plan.is_valid,'warningStatus',plan.warning_status,'recordStatus',plan.record_status,'description',plan.description,
    'drillDraftCount',(select count(*) from public.smis_emergency_drill_plan drill where drill.tenant_id=plan.tenant_id and drill.source_plan_id=plan.id and drill.status='draft'),
    'createTime',plan.create_time,'updateTime',plan.update_time) order by plan.update_time desc),'[]'::jsonb) into v_records
  from (select * from filtered order by update_time desc offset greatest(p_from,0) limit greatest(p_to-p_from+1,0)) plan
  join public.sys_organization organization on organization.id=plan.applicable_organization_id and organization.tenant_id=plan.tenant_id
  left join public.hr_position position on position.id=plan.applicable_position_id and position.tenant_id=plan.tenant_id;
  select jsonb_build_object('total',count(*),'valid',count(*)filter(where is_valid),'warning',count(*)filter(where warning_status='warning'),'submitted',count(*)filter(where record_status='submitted'))
  into v_overview from public.smis_emergency_rescue_plan where tenant_id=v_tenant_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'parentId',parent_id,'organizationName',organization_name,'organizationType',organization_type,'sort',sort,'children','[]'::jsonb) order by sort,organization_name),'[]'::jsonb)
  into v_orgs from public.sys_organization where tenant_id=v_tenant_id and status='1';
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'positionCode',position_code,'positionName',position_name,'organizationId',organization_id) order by sort,position_name),'[]'::jsonb)
  into v_positions from public.hr_position where tenant_id=v_tenant_id and enabled;
  return jsonb_build_object('records',v_records,'total',v_total,'overview',v_overview,'organizations',v_orgs,'positions',v_positions);
end; $$;

create or replace function public.smis_save_emergency_rescue_plan_secure(p_id uuid,p_payload jsonb,p_submit boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_no text:=upper(btrim(coalesce(p_payload->>'plan_no',''))); v_name text:=btrim(coalesce(p_payload->>'plan_name',''));
  v_org uuid:=nullif(p_payload->>'applicable_organization_id','')::uuid; v_position uuid:=nullif(p_payload->>'applicable_position_id','')::uuid;
  v_category text:=p_payload->>'plan_category'; v_frequency text:=p_payload->>'frequency'; v_level text; v_id uuid;
begin
  if p_id is null and not app_private.has_permission('SmisEmergencyRescuePlan:Add') then raise exception '当前账号无权新增应急预案'; end if;
  if p_id is not null and not app_private.has_permission('SmisEmergencyRescuePlan:Edit') then raise exception '当前账号无权编辑应急预案'; end if;
  if p_submit and not app_private.has_permission('SmisEmergencyRescuePlan:Submit') then raise exception '当前账号无权提交应急预案'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  if v_name='' then raise exception '请输入预案名称'; end if;
  if not exists(select 1 from public.sys_organization where id=v_org and tenant_id=v_tenant_id and status='1') then raise exception '请选择有效的适用单位'; end if;
  if v_category not in ('comprehensive','onsite','special') then raise exception '请选择有效的预案类别'; end if;
  if v_frequency not in ('once_per_shift','daily','weekly','biweekly','triweekly','monthly','bimonthly','quarterly','semiannual') then raise exception '请选择有效的周期频次'; end if;
  if v_position is not null and not exists(select 1 from public.hr_position where id=v_position and tenant_id=v_tenant_id and enabled) then raise exception '所选岗位不存在、已停用或不属于当前租户'; end if;
  v_level:=app_private.smis_plan_level_for_organization(v_tenant_id,v_org);
  if p_id is null then
    if v_no='' then v_no:=app_private.next_document_number('smis.emergency_rescue_plan',v_tenant_id); end if;
    insert into public.smis_emergency_rescue_plan(plan_no,plan_name,applicable_organization_id,plan_category,applicable_position_id,frequency,is_special_equipment_drill,plan_level,is_valid,warning_status,record_status,description,tenant_id)
    values(v_no,v_name,v_org,v_category,v_position,v_frequency,coalesce((p_payload->>'is_special_equipment_drill')::boolean,false),v_level,coalesce((p_payload->>'is_valid')::boolean,true),coalesce(nullif(p_payload->>'warning_status',''),'normal'),case when p_submit then 'submitted' else 'draft' end,nullif(btrim(p_payload->>'description'),''),v_tenant_id)
    returning id into v_id;
  else
    if not exists(select 1 from public.smis_emergency_rescue_plan where id=p_id and tenant_id=v_tenant_id) then raise exception '应急预案不存在或不属于当前租户'; end if;
    update public.smis_emergency_rescue_plan set plan_name=v_name,applicable_organization_id=v_org,plan_category=v_category,applicable_position_id=v_position,
      frequency=v_frequency,is_special_equipment_drill=coalesce((p_payload->>'is_special_equipment_drill')::boolean,false),plan_level=v_level,
      warning_status=coalesce(nullif(p_payload->>'warning_status',''),'normal'),record_status=case when p_submit then 'submitted' else record_status end,
      description=nullif(btrim(p_payload->>'description'),'') where id=p_id and tenant_id=v_tenant_id returning id into v_id;
  end if;
  return v_id;
exception when unique_violation then raise exception '预案编码已存在，请检查编号规则'; end; $$;

create or replace function public.smis_delete_emergency_rescue_plans_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_count integer;
begin
  if not app_private.has_permission('SmisEmergencyRescuePlan:Delete') then raise exception '当前账号无权删除应急预案'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  if exists(select 1 from public.smis_emergency_rescue_plan where id=any(p_ids) and tenant_id=v_tenant_id and record_status<>'draft') then raise exception '仅草稿预案可以删除'; end if;
  delete from public.smis_emergency_rescue_plan where id=any(p_ids) and tenant_id=v_tenant_id; get diagnostics v_count=row_count; return v_count;
end; $$;

create or replace function public.smis_set_emergency_rescue_plan_validity_secure(p_ids uuid[],p_is_valid boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_count integer;
begin
  if not app_private.has_permission(case when p_is_valid then 'SmisEmergencyRescuePlan:Activate' else 'SmisEmergencyRescuePlan:Void' end) then raise exception '当前账号无权变更预案有效状态'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  if p_is_valid and exists(select 1 from public.smis_emergency_rescue_plan where id=any(p_ids) and tenant_id=v_tenant_id and record_status<>'submitted') then raise exception '仅已提交预案可以恢复有效'; end if;
  update public.smis_emergency_rescue_plan set is_valid=p_is_valid where id=any(p_ids) and tenant_id=v_tenant_id and is_valid is distinct from p_is_valid;
  get diagnostics v_count=row_count; return v_count;
end; $$;

create or replace function public.smis_push_emergency_rescue_plan_to_drill_secure(p_plan_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_plan public.smis_emergency_rescue_plan; v_id uuid;
begin
  if not app_private.has_permission('SmisEmergencyRescuePlan:Push') then raise exception '当前账号无权下推演练计划'; end if;
  v_tenant_id:=app_private.current_user_tenant_id();
  select * into v_plan from public.smis_emergency_rescue_plan where id=p_plan_id and tenant_id=v_tenant_id;
  if v_plan.id is null then raise exception '应急预案不存在或不属于当前租户'; end if;
  if v_plan.record_status<>'submitted' then raise exception '仅已提交预案可以下推演练计划'; end if;
  if not v_plan.is_valid then raise exception '已置废预案不能下推演练计划'; end if;
  if exists(select 1 from public.smis_emergency_drill_plan where source_plan_id=p_plan_id and tenant_id=v_tenant_id and status='draft') then raise exception '该预案已有待完善的演练计划草稿'; end if;
  insert into public.smis_emergency_drill_plan(source_plan_id,drill_name,applicable_organization_id,plan_category,tenant_id)
  values(v_plan.id,v_plan.plan_name||'演练',v_plan.applicable_organization_id,v_plan.plan_category,v_tenant_id) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.smis_list_active_emergency_rescue_plan_options_secure()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'planNo',plan_no,'planName',plan_name,'planCategory',plan_category,'applicableOrganizationId',applicable_organization_id) order by plan_name),'[]'::jsonb)
  from public.smis_emergency_rescue_plan where tenant_id=app_private.current_user_tenant_id() and is_valid and record_status='submitted';
$$;

revoke all on function public.smis_list_hazard_sources_secure(integer,integer,text,uuid,text,text,uuid) from public,anon;
revoke all on function public.smis_save_hazard_source_secure(uuid,jsonb,boolean) from public,anon;
revoke all on function public.smis_delete_hazard_sources_secure(uuid[]) from public,anon;
revoke all on function public.smis_hazard_source_statistics_secure(uuid) from public,anon;
revoke all on function public.smis_list_hazard_source_employees_secure(integer,integer,text) from public,anon;
revoke all on function public.smis_list_emergency_rescue_plans_secure(integer,integer,text,text,uuid,boolean,text) from public,anon;
revoke all on function public.smis_save_emergency_rescue_plan_secure(uuid,jsonb,boolean) from public,anon;
revoke all on function public.smis_delete_emergency_rescue_plans_secure(uuid[]) from public,anon;
revoke all on function public.smis_set_emergency_rescue_plan_validity_secure(uuid[],boolean) from public,anon;
revoke all on function public.smis_push_emergency_rescue_plan_to_drill_secure(uuid) from public,anon;
revoke all on function public.smis_list_active_emergency_rescue_plan_options_secure() from public,anon;
grant execute on function public.smis_list_hazard_sources_secure(integer,integer,text,uuid,text,text,uuid) to authenticated,service_role;
grant execute on function public.smis_save_hazard_source_secure(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.smis_delete_hazard_sources_secure(uuid[]) to authenticated,service_role;
grant execute on function public.smis_hazard_source_statistics_secure(uuid) to authenticated,service_role;
grant execute on function public.smis_list_hazard_source_employees_secure(integer,integer,text) to authenticated,service_role;
grant execute on function public.smis_list_emergency_rescue_plans_secure(integer,integer,text,text,uuid,boolean,text) to authenticated,service_role;
grant execute on function public.smis_save_emergency_rescue_plan_secure(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.smis_delete_emergency_rescue_plans_secure(uuid[]) to authenticated,service_role;
grant execute on function public.smis_set_emergency_rescue_plan_validity_secure(uuid[],boolean) to authenticated,service_role;
grant execute on function public.smis_push_emergency_rescue_plan_to_drill_secure(uuid) to authenticated,service_role;
grant execute on function public.smis_list_active_emergency_rescue_plan_options_secure() to authenticated,service_role;

with platform_tenant as (select id from public.sys_tenant where tenant_code='platform' limit 1), scenes(rule_key,rule_name,field_label,menu_id,target_table,target_column,template,remark) as (values
  ('smis.hazard_source','危险源编号','危险源编号','a1530000-0000-4000-8000-000000000021'::uuid,'smis_hazard_source','hazard_no','WXY{YYYY}{MM}-{SEQ:3}','危险源编号按月重置三位流水'),
  ('smis.emergency_rescue_plan','应急预案编码','预案编码','a1530000-0000-4000-8000-000000000022'::uuid,'smis_emergency_rescue_plan','plan_no','YA{YYYY}{MM}-{SEQ:3}','应急预案编码按月重置三位流水')
)
insert into public.sys_document_number_scene(rule_key,rule_name,field_label,category,menu_id,target_table,target_column,default_template,default_reset_cycle,manual_required,enabled,remark,create_by,update_by,tenant_id)
select scenes.rule_key,scenes.rule_name,scenes.field_label,'business_document',scenes.menu_id,scenes.target_table,scenes.target_column,scenes.template,'month',false,true,scenes.remark,'number-engine','number-engine',platform_tenant.id from scenes cross join platform_tenant
on conflict(rule_key) do update set rule_name=excluded.rule_name,field_label=excluded.field_label,menu_id=excluded.menu_id,target_table=excluded.target_table,target_column=excluded.target_column,default_template=excluded.default_template,default_reset_cycle=excluded.default_reset_cycle,manual_required=false,enabled=true,remark=excluded.remark,update_time=now();

with scenes(rule_key,rule_name,target_table,target_column,template,remark) as (values
  ('smis.hazard_source','危险源编号','smis_hazard_source','hazard_no','WXY{YYYY}{MM}-{SEQ:3}','危险源默认编号规则'),
  ('smis.emergency_rescue_plan','应急预案编码','smis_emergency_rescue_plan','plan_no','YA{YYYY}{MM}-{SEQ:3}','应急预案默认编号规则')
)
insert into public.sys_document_number_rule(tenant_id,rule_key,rule_name,category,target_table,target_column,auto_enabled,template,reset_cycle,sequence_start,timezone,manual_required,builtin,enabled,remark,create_by,update_by)
select tenant.id,scenes.rule_key,scenes.rule_name,'business_document',scenes.target_table,scenes.target_column,true,scenes.template,'month',1,'Asia/Shanghai',false,true,true,scenes.remark,'number-engine','number-engine'
from public.sys_tenant tenant cross join scenes on conflict(tenant_id,rule_key) do nothing;

create or replace function app_private.trg_seed_smis_hazard_emergency_number_rules()
returns trigger language plpgsql security definer set search_path='' as $$ begin
  insert into public.sys_document_number_rule(tenant_id,rule_key,rule_name,category,target_table,target_column,auto_enabled,template,reset_cycle,sequence_start,timezone,manual_required,builtin,enabled,remark,create_by,update_by)
  values
    (new.id,'smis.hazard_source','危险源编号','business_document','smis_hazard_source','hazard_no',true,'WXY{YYYY}{MM}-{SEQ:3}','month',1,'Asia/Shanghai',false,true,true,'危险源默认编号规则','number-engine','number-engine'),
    (new.id,'smis.emergency_rescue_plan','应急预案编码','business_document','smis_emergency_rescue_plan','plan_no',true,'YA{YYYY}{MM}-{SEQ:3}','month',1,'Asia/Shanghai',false,true,true,'应急预案默认编号规则','number-engine','number-engine')
  on conflict(tenant_id,rule_key) do nothing; return new; end; $$;
create trigger trg_seed_smis_hazard_emergency_number_rules after insert on public.sys_tenant for each row execute function app_private.trg_seed_smis_hazard_emergency_number_rules();

with platform_tenant as (select id from public.sys_tenant where tenant_code='platform' limit 1), types(name,code,remark,sort) as (values
  ('危险源危险等级','smisHazardSourceLevel','危险源一级至四级分级',60),('危险源风险等级','smisHazardSourceRiskLevel','风险管控分级',61),
  ('危险源记录状态','smisHazardSourceRecordStatus','危险源草稿与提交状态',62),('应急预案类别','smisEmergencyPlanCategory','应急预案分类',63),
  ('应急预案周期频次','smisEmergencyPlanFrequency','应急预案周期频次',64),('应急预案级别','smisEmergencyPlanLevel','由适用单位自动推导',65),
  ('应急预案预警状态','smisEmergencyPlanWarningStatus','预案正常与预警状态',66),('应急预案记录状态','smisEmergencyPlanRecordStatus','预案草稿与提交状态',67)
)
insert into public.sys_dict_type(id,name,code,status,create_by,update_by,remark,tenant_id,parent_id,node_type,sort)
select gen_random_uuid(),types.name,types.code,'1','system','system',types.remark,platform_tenant.id,(select id from public.sys_dict_type where code='smisSafetyProduction' limit 1),'dictionary',types.sort
from types cross join platform_tenant on conflict(code) do update set name=excluded.name,status='1',remark=excluded.remark,parent_id=excluded.parent_id,sort=excluded.sort,update_time=now();

with platform_tenant as (select id from public.sys_tenant where tenant_code='platform' limit 1), items(type_code,value,label,sort,tag_type) as (values
  ('smisHazardSourceLevel','level_1','一级',1,'danger'),('smisHazardSourceLevel','level_2','二级',2,'warning'),('smisHazardSourceLevel','level_3','三级',3,'primary'),('smisHazardSourceLevel','level_4','四级',4,'info'),
  ('smisHazardSourceRiskLevel','major','重大风险',1,'danger'),('smisHazardSourceRiskLevel','high','较大风险',2,'warning'),('smisHazardSourceRiskLevel','general','一般风险',3,'primary'),('smisHazardSourceRiskLevel','low','低风险',4,'success'),('smisHazardSourceRiskLevel','unidentified','未辨识',5,'info'),
  ('smisHazardSourceRecordStatus','draft','草稿',1,'info'),('smisHazardSourceRecordStatus','submitted','已提交',2,'success'),
  ('smisEmergencyPlanCategory','comprehensive','综合预案',1,'primary'),('smisEmergencyPlanCategory','onsite','现场处置方案',2,'success'),('smisEmergencyPlanCategory','special','专项预案',3,'warning'),
  ('smisEmergencyPlanFrequency','once_per_shift','1班1次',1,'info'),('smisEmergencyPlanFrequency','daily','1日1次',2,'info'),('smisEmergencyPlanFrequency','weekly','1周1次',3,'info'),('smisEmergencyPlanFrequency','biweekly','2周1次',4,'info'),('smisEmergencyPlanFrequency','triweekly','3周1次',5,'info'),('smisEmergencyPlanFrequency','monthly','1月1次',6,'info'),('smisEmergencyPlanFrequency','bimonthly','2月1次',7,'info'),('smisEmergencyPlanFrequency','quarterly','1季度1次',8,'info'),('smisEmergencyPlanFrequency','semiannual','2季度1次',9,'info'),
  ('smisEmergencyPlanLevel','company','公司',1,'primary'),('smisEmergencyPlanLevel','operation_department','作业部',2,'success'),('smisEmergencyPlanLevel','operation_area','作业区',3,'warning'),('smisEmergencyPlanLevel','team','班组',4,'info'),
  ('smisEmergencyPlanWarningStatus','normal','正常',1,'success'),('smisEmergencyPlanWarningStatus','warning','预警',2,'danger'),
  ('smisEmergencyPlanRecordStatus','draft','草稿',1,'info'),('smisEmergencyPlanRecordStatus','submitted','已提交',2,'success')
)
insert into public.sys_dictionary(id,type_id,code,status,create_by,update_by,value,label,tenant_id,tag_type,sort)
select gen_random_uuid(),dictionary_type.id,items.type_code||'_'||items.value,'1','system','system',items.value,items.label,platform_tenant.id,items.tag_type,items.sort
from items join public.sys_dict_type dictionary_type on dictionary_type.code=items.type_code cross join platform_tenant
where not exists(select 1 from public.sys_dictionary existing where existing.type_id=dictionary_type.id and existing.value=items.value);

insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,app_code,create_by,update_by)
select seed.id,seed.parent_id,seed.name,'','',jsonb_build_object('title',seed.title,'icon','','is_hide',true,'is_enable',true,'roles',jsonb_build_array()),seed.sort,'button','smis','system','system'
from (values
  ('a1530000-0000-4000-8210-000000000001'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:View','查看危险源台账',1),
  ('a1530000-0000-4000-8210-000000000002'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:Add','新增危险源',2),
  ('a1530000-0000-4000-8210-000000000003'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:Edit','编辑危险源',3),
  ('a1530000-0000-4000-8210-000000000004'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:Delete','删除危险源',4),
  ('a1530000-0000-4000-8210-000000000005'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:Submit','提交危险源',5),
  ('a1530000-0000-4000-8210-000000000006'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:Import','导入危险源',6),
  ('a1530000-0000-4000-8210-000000000007'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:Export','导出危险源',7),
  ('a1530000-0000-4000-8210-000000000008'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:Statistics','危险源统计分析',8),
  ('a1530000-0000-4000-8210-000000000009'::uuid,'a1530000-0000-4000-8000-000000000021'::uuid,'SmisHazardSourceLedger:DownloadTemplate','下载危险源导入模板',9),
  ('a1530000-0000-4000-8220-000000000001'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:View','查看应急预案',1),
  ('a1530000-0000-4000-8220-000000000002'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:Add','新增应急预案',2),
  ('a1530000-0000-4000-8220-000000000003'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:Edit','编辑应急预案',3),
  ('a1530000-0000-4000-8220-000000000004'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:Delete','删除应急预案',4),
  ('a1530000-0000-4000-8220-000000000005'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:Submit','提交应急预案',5),
  ('a1530000-0000-4000-8220-000000000006'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:Void','置废应急预案',6),
  ('a1530000-0000-4000-8220-000000000007'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:Activate','恢复有效预案',7),
  ('a1530000-0000-4000-8220-000000000008'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid,'SmisEmergencyRescuePlan:Push','下推演练计划',8)
) seed(id,parent_id,name,title,sort)
on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,meta=excluded.meta,sort=excluded.sort,type='button',app_code='smis',update_time=now();

insert into public.sys_role_menu(role_id,menu_id,tenant_id,permission,create_by,update_by)
select page_grant.role_id,button.id,role.tenant_id,'{}'::jsonb,'system','system'
from public.sys_role_menu page_grant join public.sys_role role on role.id=page_grant.role_id
join public.sys_menu button on button.parent_id=page_grant.menu_id and button.type='button'
where page_grant.menu_id in ('a1530000-0000-4000-8000-000000000021'::uuid,'a1530000-0000-4000-8000-000000000022'::uuid)
on conflict(role_id,menu_id) do nothing;

;
