alter table public.smis_hazard_source
  add column quantity numeric(14, 3),
  add column location text,
  add column evaluation_date date,
  add column evaluation_organization text,
  add column filing_date date,
  add column filing_organization text,
  add column filing_no text;

alter table public.smis_hazard_source
  add constraint smis_hazard_source_quantity_check
    check (quantity is null or quantity > 0),
  add constraint smis_hazard_source_location_length
    check (location is null or char_length(location) <= 200),
  add constraint smis_hazard_source_evaluation_org_length
    check (evaluation_organization is null or char_length(evaluation_organization) <= 200),
  add constraint smis_hazard_source_filing_org_length
    check (filing_organization is null or char_length(filing_organization) <= 200),
  add constraint smis_hazard_source_filing_no_length
    check (filing_no is null or char_length(filing_no) <= 100);

comment on column public.smis_hazard_source.quantity is '危险源数量';
comment on column public.smis_hazard_source.location is '危险源具体地点';
comment on column public.smis_hazard_source.evaluation_date is '危险源评价日期';
comment on column public.smis_hazard_source.evaluation_organization is '危险源评价单位';
comment on column public.smis_hazard_source.filing_date is '危险源备案日期';
comment on column public.smis_hazard_source.filing_organization is '危险源备案单位';
comment on column public.smis_hazard_source.filing_no is '危险源备案号';

create or replace function public.smis_list_hazard_sources_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_site_id uuid default null,
  p_hazard_level text default null,
  p_risk_level text default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
  v_sites jsonb;
  v_organizations jsonb;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看危险源台账'; end if;
  if not app_private.has_permission('SmisHazardSourceLedger:View') then raise exception '当前账号无权查看危险源台账'; end if;

  with recursive site_scope as (
    select id
    from public.smis_site
    where (app_private.current_read_tenant_id() is null or tenant_id = app_private.current_read_tenant_id())
      and id = p_site_id
    union all
    select child.id
    from public.smis_site child
    join site_scope parent on child.parent_id = parent.id
    where app_private.current_read_tenant_id() is null
       or child.tenant_id = app_private.current_read_tenant_id()
  ), filtered as (
    select hazard.*
    from public.smis_hazard_source hazard
    where (app_private.current_read_tenant_id() is null or hazard.tenant_id = app_private.current_read_tenant_id())
      and (p_site_id is null or hazard.site_id in (select id from site_scope))
      and (p_hazard_level is null or hazard.hazard_level = p_hazard_level)
      and (p_risk_level is null or hazard.risk_level = p_risk_level)
      and (p_organization_id is null or hazard.control_organization_id = p_organization_id)
      and (
        nullif(btrim(p_keyword), '') is null
        or hazard.hazard_no ilike '%' || btrim(p_keyword) || '%'
        or hazard.hazard_name ilike '%' || btrim(p_keyword) || '%'
        or hazard.location ilike '%' || btrim(p_keyword) || '%'
        or hazard.filing_no ilike '%' || btrim(p_keyword) || '%'
      )
  )
  select count(*) into v_total from filtered;

  with recursive site_scope as (
    select id
    from public.smis_site
    where (app_private.current_read_tenant_id() is null or tenant_id = app_private.current_read_tenant_id())
      and id = p_site_id
    union all
    select child.id
    from public.smis_site child
    join site_scope parent on child.parent_id = parent.id
    where app_private.current_read_tenant_id() is null
       or child.tenant_id = app_private.current_read_tenant_id()
  ), filtered as (
    select hazard.*
    from public.smis_hazard_source hazard
    where (app_private.current_read_tenant_id() is null or hazard.tenant_id = app_private.current_read_tenant_id())
      and (p_site_id is null or hazard.site_id in (select id from site_scope))
      and (p_hazard_level is null or hazard.hazard_level = p_hazard_level)
      and (p_risk_level is null or hazard.risk_level = p_risk_level)
      and (p_organization_id is null or hazard.control_organization_id = p_organization_id)
      and (
        nullif(btrim(p_keyword), '') is null
        or hazard.hazard_no ilike '%' || btrim(p_keyword) || '%'
        or hazard.hazard_name ilike '%' || btrim(p_keyword) || '%'
        or hazard.location ilike '%' || btrim(p_keyword) || '%'
        or hazard.filing_no ilike '%' || btrim(p_keyword) || '%'
      )
  )
  select coalesce(jsonb_agg(item.payload order by item.update_time desc), '[]'::jsonb)
    into v_records
  from (
    select hazard.update_time, jsonb_build_object(
      'id', hazard.id,
      'hazardNo', hazard.hazard_no,
      'hazardName', hazard.hazard_name,
      'siteId', hazard.site_id,
      'siteName', site.site_name,
      'hazardLevel', hazard.hazard_level,
      'riskLevel', hazard.risk_level,
      'controlOrganizationId', hazard.control_organization_id,
      'controlOrganizationName', organization.organization_name,
      'responsibleEmployeeId', hazard.responsible_employee_id,
      'responsibleEmployeeName', employee.employee_name,
      'responsibleEmployeeNo', employee.employee_no,
      'quantity', hazard.quantity,
      'location', hazard.location,
      'evaluationDate', hazard.evaluation_date,
      'evaluationOrganization', hazard.evaluation_organization,
      'filingDate', hazard.filing_date,
      'filingOrganization', hazard.filing_organization,
      'filingNo', hazard.filing_no,
      'imageUrls', hazard.image_urls,
      'recordStatus', hazard.record_status,
      'remark', hazard.remark,
      'createTime', hazard.create_time,
      'updateTime', hazard.update_time
    ) payload
    from filtered hazard
    join public.smis_site site
      on site.id = hazard.site_id and site.tenant_id = hazard.tenant_id
    join public.sys_organization organization
      on organization.id = hazard.control_organization_id and organization.tenant_id = hazard.tenant_id
    left join public.hr_employee employee
      on employee.id = hazard.responsible_employee_id and employee.tenant_id = hazard.tenant_id
    order by hazard.update_time desc
    offset greatest(p_from, 0)
    limit greatest(p_to - p_from + 1, 0)
  ) item;

  select jsonb_build_object(
    'total', count(*),
    'submitted', count(*) filter (where record_status = 'submitted'),
    'majorRisk', count(*) filter (where risk_level = 'major'),
    'siteCount', count(distinct site_id)
  )
  into v_overview
  from public.smis_hazard_source
  where app_private.current_read_tenant_id() is null
     or tenant_id = app_private.current_read_tenant_id();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', site.id,
    'parentId', site.parent_id,
    'siteName', site.site_name,
    'organizationId', site.organization_id,
    'sort', site.sort,
    'children', '[]'::jsonb
  ) order by site.sort, site.site_name), '[]'::jsonb)
  into v_sites
  from public.smis_site site
  where app_private.current_read_tenant_id() is null
     or site.tenant_id = app_private.current_read_tenant_id();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', organization.id,
    'parentId', organization.parent_id,
    'organizationName', organization.organization_name,
    'organizationType', organization.organization_type,
    'sort', organization.sort,
    'children', '[]'::jsonb
  ) order by organization.sort, organization.organization_name), '[]'::jsonb)
  into v_organizations
  from public.sys_organization organization
  where (app_private.current_read_tenant_id() is null or organization.tenant_id = app_private.current_read_tenant_id())
    and organization.status = '1';

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'overview', v_overview,
    'sites', v_sites,
    'organizations', v_organizations
  );
end;
$function$;

create or replace function public.smis_save_hazard_source_secure(
  p_id uuid,
  p_payload jsonb,
  p_submit boolean default false
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tenant_id uuid;
  v_hazard_no text := upper(btrim(coalesce(p_payload->>'hazard_no', '')));
  v_hazard_name text := btrim(coalesce(p_payload->>'hazard_name', ''));
  v_site_id uuid := nullif(p_payload->>'site_id', '')::uuid;
  v_hazard_level text := p_payload->>'hazard_level';
  v_risk_level text := coalesce(nullif(p_payload->>'risk_level', ''), 'unidentified');
  v_org_id uuid := nullif(p_payload->>'control_organization_id', '')::uuid;
  v_employee_id uuid := nullif(p_payload->>'responsible_employee_id', '')::uuid;
  v_quantity numeric(14, 3) := nullif(p_payload->>'quantity', '')::numeric;
  v_location text := nullif(btrim(coalesce(p_payload->>'location', '')), '');
  v_evaluation_date date := nullif(p_payload->>'evaluation_date', '')::date;
  v_evaluation_organization text := nullif(btrim(coalesce(p_payload->>'evaluation_organization', '')), '');
  v_filing_date date := nullif(p_payload->>'filing_date', '')::date;
  v_filing_organization text := nullif(btrim(coalesce(p_payload->>'filing_organization', '')), '');
  v_filing_no text := nullif(btrim(coalesce(p_payload->>'filing_no', '')), '');
  v_id uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护危险源'; end if;
  if p_id is null and not app_private.has_permission('SmisHazardSourceLedger:Add') then raise exception '当前账号无权新增危险源'; end if;
  if p_id is not null and not app_private.has_permission('SmisHazardSourceLedger:Edit') then raise exception '当前账号无权编辑危险源'; end if;
  if p_submit and not app_private.has_permission('SmisHazardSourceLedger:Submit') then raise exception '当前账号无权提交危险源'; end if;

  v_tenant_id := app_private.resolve_mutation_tenant_id(
    (select target.tenant_id from public.smis_hazard_source target where target.id = p_id)
  );

  if v_hazard_name = '' then raise exception '请输入危险源名称'; end if;
  if v_site_id is null then raise exception '请选择场所'; end if;
  if v_hazard_level not in ('level_1', 'level_2', 'level_3', 'level_4') then raise exception '请选择有效的危险等级'; end if;
  if v_risk_level not in ('major', 'high', 'general', 'low', 'unidentified') then raise exception '请选择有效的风险等级'; end if;
  if v_org_id is null then raise exception '请选择管控部门'; end if;
  if v_quantity is not null and v_quantity <= 0 then raise exception '数量必须大于0'; end if;
  if char_length(coalesce(v_location, '')) > 200 then raise exception '地点不能超过200个字符'; end if;
  if char_length(coalesce(v_evaluation_organization, '')) > 200 then raise exception '评价单位不能超过200个字符'; end if;
  if char_length(coalesce(v_filing_organization, '')) > 200 then raise exception '备案单位不能超过200个字符'; end if;
  if char_length(coalesce(v_filing_no, '')) > 100 then raise exception '备案号不能超过100个字符'; end if;

  if not exists (
    select 1 from public.smis_site where id = v_site_id and tenant_id = v_tenant_id
  ) then raise exception '所选场所不存在或不属于当前租户'; end if;
  if not exists (
    select 1 from public.sys_organization
    where id = v_org_id and tenant_id = v_tenant_id and status = '1'
  ) then raise exception '所选管控部门不存在、已停用或不属于当前租户'; end if;
  if v_employee_id is not null and not exists (
    select 1 from public.hr_employee
    where id = v_employee_id and tenant_id = v_tenant_id and employment_status = 'active'
  ) then raise exception '所选责任人不存在、已离职或不属于当前租户'; end if;
  if jsonb_typeof(coalesce(p_payload->'image_urls', '[]'::jsonb)) <> 'array'
    or jsonb_array_length(coalesce(p_payload->'image_urls', '[]'::jsonb)) > 9
  then raise exception '危险源照片最多上传9张'; end if;

  if p_id is null then
    if v_hazard_no = '' then
      v_hazard_no := app_private.next_document_number('smis.hazard_source', v_tenant_id);
    end if;
    insert into public.smis_hazard_source (
      hazard_no,
      hazard_name,
      site_id,
      hazard_level,
      risk_level,
      control_organization_id,
      responsible_employee_id,
      quantity,
      location,
      evaluation_date,
      evaluation_organization,
      filing_date,
      filing_organization,
      filing_no,
      image_urls,
      record_status,
      remark,
      tenant_id
    ) values (
      v_hazard_no,
      v_hazard_name,
      v_site_id,
      v_hazard_level,
      v_risk_level,
      v_org_id,
      v_employee_id,
      v_quantity,
      v_location,
      v_evaluation_date,
      v_evaluation_organization,
      v_filing_date,
      v_filing_organization,
      v_filing_no,
      coalesce(p_payload->'image_urls', '[]'::jsonb),
      case when p_submit then 'submitted' else 'draft' end,
      nullif(btrim(p_payload->>'remark'), ''),
      v_tenant_id
    ) returning id into v_id;
  else
    select hazard_no
      into v_hazard_no
    from public.smis_hazard_source
    where id = p_id and tenant_id = v_tenant_id;
    if v_hazard_no is null then raise exception '危险源不存在或不属于当前租户'; end if;

    update public.smis_hazard_source
    set hazard_name = v_hazard_name,
        site_id = v_site_id,
        hazard_level = v_hazard_level,
        risk_level = v_risk_level,
        control_organization_id = v_org_id,
        responsible_employee_id = v_employee_id,
        quantity = case when p_payload ? 'quantity' then v_quantity else quantity end,
        location = case when p_payload ? 'location' then v_location else location end,
        evaluation_date = case when p_payload ? 'evaluation_date' then v_evaluation_date else evaluation_date end,
        evaluation_organization = case when p_payload ? 'evaluation_organization' then v_evaluation_organization else evaluation_organization end,
        filing_date = case when p_payload ? 'filing_date' then v_filing_date else filing_date end,
        filing_organization = case when p_payload ? 'filing_organization' then v_filing_organization else filing_organization end,
        filing_no = case when p_payload ? 'filing_no' then v_filing_no else filing_no end,
        image_urls = coalesce(p_payload->'image_urls', '[]'::jsonb),
        record_status = case when p_submit then 'submitted' else record_status end,
        remark = nullif(btrim(p_payload->>'remark'), '')
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_id;
  end if;

  return v_id;
exception
  when unique_violation then raise exception '危险源编号已存在，请检查编号规则';
end;
$function$;

;
