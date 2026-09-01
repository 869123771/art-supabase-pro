-- Risk-point master data and hazard/activity maintenance for SMIS risk identification.

create table public.smis_risk_point (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id),
  point_no text not null,
  point_name text not null,
  risk_type text not null default 'unset'
    check (risk_type in ('unset', 'location', 'equipment', 'activity')),
  site_id uuid not null references public.smis_site(id) on delete restrict,
  equipment_id uuid references public.smis_equipment(id) on delete restrict,
  equipment_name text not null,
  is_special_equipment boolean not null default false,
  control_plan_name text,
  control_plan_attachment_urls jsonb not null default '[]'::jsonb,
  photo_urls jsonb not null default '[]'::jsonb,
  attachment_urls jsonb not null default '[]'::jsonb,
  status text not null default 'enabled' check (status in ('enabled', 'voided')),
  sort integer not null default 0 check (sort between 0 and 9999),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_point_tenant_no_key unique (tenant_id, point_no),
  constraint smis_risk_point_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_point_no_check check (point_no ~ '^[0-9]{5}$'),
  constraint smis_risk_point_equipment_name_check check (btrim(equipment_name) <> ''),
  constraint smis_risk_point_special_equipment_check check (
    not is_special_equipment or equipment_id is not null
  ),
  constraint smis_risk_point_control_plan_attachments_check check (
    jsonb_typeof(control_plan_attachment_urls) = 'array'
  ),
  constraint smis_risk_point_photos_check check (jsonb_typeof(photo_urls) = 'array'),
  constraint smis_risk_point_attachments_check check (jsonb_typeof(attachment_urls) = 'array')
);

create index smis_risk_point_tenant_status_sort_idx
  on public.smis_risk_point(tenant_id, status, sort, point_no);
create index smis_risk_point_site_idx on public.smis_risk_point(tenant_id, site_id);
create index smis_risk_point_equipment_idx on public.smis_risk_point(tenant_id, equipment_id)
  where equipment_id is not null;

create table public.smis_risk_point_organization (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id),
  risk_point_id uuid not null,
  organization_id uuid not null references public.sys_organization(id) on delete restrict,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_point_organization_key unique (risk_point_id, organization_id),
  constraint smis_risk_point_organization_point_fk foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id) on delete cascade
);
create index smis_risk_point_organization_org_idx
  on public.smis_risk_point_organization(tenant_id, organization_id, risk_point_id);

create table public.smis_risk_activity (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id),
  risk_point_id uuid not null,
  activity_name text not null,
  work_step text not null,
  sort integer not null default 0 check (sort between 0 and 9999),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_activity_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_activity_point_fk foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id) on delete cascade,
  constraint smis_risk_activity_name_check check (btrim(activity_name) <> ''),
  constraint smis_risk_activity_step_check check (btrim(work_step) <> '')
);
create index smis_risk_activity_point_sort_idx
  on public.smis_risk_activity(tenant_id, risk_point_id, sort, create_time);

alter table public.smis_risk_item
  add column risk_point_id uuid,
  add column accident_types text[] not null default '{}'::text[],
  add column consequence text;

alter table public.smis_risk_item
  add constraint smis_risk_item_point_fk foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id) on delete cascade,
  add constraint smis_risk_item_no_check check (item_no ~ '^[0-9]{5}-WHYS-[0-9]{3}$');

create index smis_risk_item_point_sort_idx
  on public.smis_risk_item(tenant_id, risk_point_id, status, sort, item_no);

create table public.smis_risk_item_activity (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id),
  risk_item_id uuid not null,
  activity_id uuid not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_item_activity_key unique (risk_item_id, activity_id),
  constraint smis_risk_item_activity_item_fk foreign key (tenant_id, risk_item_id)
    references public.smis_risk_item(tenant_id, id) on delete cascade,
  constraint smis_risk_item_activity_activity_fk foreign key (tenant_id, activity_id)
    references public.smis_risk_activity(tenant_id, id) on delete cascade
);
create index smis_risk_item_activity_activity_idx
  on public.smis_risk_item_activity(tenant_id, activity_id, risk_item_id);

do $audit$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_risk_point', 'smis_risk_point_organization',
    'smis_risk_activity', 'smis_risk_item_activity'
  ] loop
    execute format(
      'create trigger %I_create_audit before insert on public.%I for each row execute function public.trg_set_create_time_and_by(''true'', ''true'')',
      v_table, v_table
    );
    execute format(
      'create trigger %I_update_audit before update on public.%I for each row execute function public.trg_set_update_time_and_by()',
      v_table, v_table
    );
  end loop;
end
$audit$;

create or replace function app_private.smis_guard_risk_item_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'voided' and new.status <> 'voided' then
    raise exception '已作废风险因素不能恢复，请重新辨识' using errcode = '22023';
  end if;
  if old.status <> 'voided' and new.status = 'voided' then
    if not app_private.has_permission('SmisDualControlRiskIdentification:Void') then
      raise exception '当前账号没有作废风险因素的权限' using errcode = '42501';
    end if;
  elsif old.status is distinct from new.status and new.status = 'evaluated' then
    if not app_private.has_permission('SmisDualControlRiskEvaluationControl:Evaluate') then
      raise exception '当前账号没有风险评价权限' using errcode = '42501';
    end if;
  elsif not (
    app_private.has_permission('SmisDualControlRiskIdentification:Edit')
    or app_private.has_permission('SmisDualControlRiskIdentification:MaintainHazards')
  ) then
    raise exception '当前账号没有编辑风险因素的权限' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function app_private.smis_guard_risk_item_update() from public, anon, authenticated;

do $security$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_risk_point', 'smis_risk_point_organization',
    'smis_risk_activity', 'smis_risk_item_activity'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from anon', v_table);
    execute format('grant select, insert, update, delete on table public.%I to authenticated', v_table);
  end loop;
end
$security$;

create policy smis_risk_point_select on public.smis_risk_point for select to authenticated
using ((select app_private.is_platform_super()) or (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskIdentification:View'))
));
create policy smis_risk_point_insert on public.smis_risk_point for insert to authenticated
with check ((select app_private.is_platform_super()) or (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskIdentification:Add'))
));
create policy smis_risk_point_update on public.smis_risk_point for update to authenticated
using ((select app_private.is_platform_super()) or (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskIdentification:Edit'))
))
with check ((select app_private.is_platform_super()) or (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskIdentification:Edit'))
));
create policy smis_risk_point_delete on public.smis_risk_point for delete to authenticated
using ((select app_private.is_platform_super()) or (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskIdentification:Delete'))
));

do $child_policies$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_risk_point_organization', 'smis_risk_activity', 'smis_risk_item_activity'
  ] loop
    execute format(
      'create policy %I_select on public.%I for select to authenticated using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission(''SmisDualControlRiskIdentification:View''))))',
      v_table, v_table
    );
    execute format(
      'create policy %I_insert on public.%I for insert to authenticated with check ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id()) and ((select app_private.has_permission(''SmisDualControlRiskIdentification:Edit'')) or (select app_private.has_permission(''SmisDualControlRiskIdentification:MaintainHazards'')))))',
      v_table, v_table
    );
    execute format(
      'create policy %I_update on public.%I for update to authenticated using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id()) and ((select app_private.has_permission(''SmisDualControlRiskIdentification:Edit'')) or (select app_private.has_permission(''SmisDualControlRiskIdentification:MaintainHazards''))))) with check ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id()) and ((select app_private.has_permission(''SmisDualControlRiskIdentification:Edit'')) or (select app_private.has_permission(''SmisDualControlRiskIdentification:MaintainHazards'')))))',
      v_table, v_table
    );
    execute format(
      'create policy %I_delete on public.%I for delete to authenticated using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.current_user_tenant_id()) and ((select app_private.has_permission(''SmisDualControlRiskIdentification:Edit'')) or (select app_private.has_permission(''SmisDualControlRiskIdentification:MaintainHazards'')))))',
      v_table, v_table
    );
  end loop;
end
$child_policies$;

create or replace function app_private.smis_next_risk_point_no(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_next integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('smis-risk-point-' || p_tenant_id::text, 0));
  select coalesce(max(point_no::integer), 0) + 1 into v_next
  from public.smis_risk_point where tenant_id = p_tenant_id;
  if v_next > 99999 then
    raise exception '风险点编号已达到 5 位流水码上限' using errcode = '22003';
  end if;
  return lpad(v_next::text, 5, '0');
end;
$$;
revoke all on function app_private.smis_next_risk_point_no(uuid) from public, anon, authenticated;

create or replace function app_private.smis_next_risk_item_no(
  p_tenant_id uuid,
  p_risk_point_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_point_no text;
  v_next integer;
begin
  select point_no into v_point_no from public.smis_risk_point
  where id = p_risk_point_id and tenant_id = p_tenant_id;
  if v_point_no is null then
    raise exception '风险点不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('smis-risk-item-' || p_risk_point_id::text, 0));
  select coalesce(max(substring(item_no from '([0-9]{3})$')::integer), 0) + 1 into v_next
  from public.smis_risk_item
  where tenant_id = p_tenant_id and risk_point_id = p_risk_point_id;
  if v_next > 999 then
    raise exception '当前风险点的危害编号已达到 3 位流水码上限' using errcode = '22003';
  end if;
  return v_point_no || '-WHYS-' || lpad(v_next::text, 3, '0');
end;
$$;
revoke all on function app_private.smis_next_risk_item_no(uuid, uuid) from public, anon, authenticated;

create or replace function public.smis_list_risk_identification_options_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:View') then
    raise exception '当前账号没有查看风险辨识的权限' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'sites', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', site.id, 'parentId', site.parent_id, 'siteName', site.site_name,
        'organizationId', site.organization_id,
        'organizationName', organization.organization_name,
        'categoryCode', site.category_code
      ) order by site.sort, site.site_name)
      from public.smis_site site
      left join public.sys_organization organization
        on organization.id = site.organization_id and organization.tenant_id = site.tenant_id
      where site.tenant_id = v_tenant_id
    ), '[]'::jsonb),
    'organizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', organization.id, 'parentId', organization.parent_id,
        'organizationCode', organization.organization_code,
        'organizationName', organization.organization_name,
        'organizationType', organization.organization_type
      ) order by organization.sort, organization.organization_name)
      from public.sys_organization organization
      where organization.tenant_id = v_tenant_id and organization.status = '1'
    ), '[]'::jsonb),
    'equipment', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', equipment.id, 'equipmentCode', equipment.equipment_code,
        'equipmentName', equipment.equipment_name,
        'isSpecialEquipment', equipment.is_special_equipment,
        'usingOrganizationId', equipment.using_organization_id
      ) order by equipment.sort, equipment.equipment_name)
      from public.smis_equipment equipment
      where equipment.tenant_id = v_tenant_id and equipment.status = 'enabled'
    ), '[]'::jsonb),
    'hazardCategories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', category.id, 'categoryCode', category.category_code,
        'categoryName', category.category_name, 'factorType', category.factor_type
      ) order by category.sort, category.category_name)
      from public.smis_hazard_factor_category category
      where category.tenant_id = v_tenant_id and category.status = 'enabled'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.smis_list_risk_points_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_organization_id uuid default null,
  p_site_id uuid default null,
  p_equipment text default null,
  p_risk_level text default null,
  p_risk_type text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_equipment text := nullif(btrim(coalesce(p_equipment, '')), '');
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:View') then
    raise exception '当前账号没有查看风险辨识的权限' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(to_jsonb(row_data) order by row_data."sort", row_data."pointNo")
      from (
        select
          point.id,
          point.point_no as "pointNo",
          point.point_name as "pointName",
          point.risk_type as "riskType",
          point.site_id as "siteId",
          site.site_name as "siteName",
          point.equipment_id as "equipmentId",
          point.equipment_name as "equipmentName",
          point.is_special_equipment as "isSpecialEquipment",
          point.control_plan_name as "controlPlanName",
          point.control_plan_attachment_urls as "controlPlanAttachmentUrls",
          point.photo_urls as "photoUrls",
          point.attachment_urls as "attachmentUrls",
          point.status,
          point.sort,
          point.create_time as "createTime",
          point.update_time as "updateTime",
          coalesce(orgs.items, '[]'::jsonb) as organizations,
          coalesce(summary."hazardCount", 0) as "hazardCount",
          coalesce(summary."activityCount", 0) as "activityCount",
          coalesce(summary."riskScore", 0) as "riskScore",
          coalesce(summary."riskLevel", 'unidentified') as "riskLevel"
        from public.smis_risk_point point
        join public.smis_site site on site.id = point.site_id and site.tenant_id = point.tenant_id
        left join lateral (
          select jsonb_agg(jsonb_build_object(
            'id', organization.id,
            'organizationCode', organization.organization_code,
            'organizationName', organization.organization_name
          ) order by organization.organization_name) as items
          from public.smis_risk_point_organization relation
          join public.sys_organization organization
            on organization.id = relation.organization_id and organization.tenant_id = relation.tenant_id
          where relation.risk_point_id = point.id and relation.tenant_id = point.tenant_id
        ) orgs on true
        left join lateral (
          select
            (select count(*)::integer
             from public.smis_risk_item item
             where item.risk_point_id = point.id and item.tenant_id = point.tenant_id
               and item.status <> 'voided') as "hazardCount",
            (select count(*)::integer
             from public.smis_risk_activity activity
             where activity.risk_point_id = point.id and activity.tenant_id = point.tenant_id) as "activityCount",
            (select max(evaluation.d_value)
             from public.smis_risk_item item
             join public.smis_risk_evaluation evaluation
               on evaluation.risk_item_id = item.id and evaluation.tenant_id = item.tenant_id
             where item.risk_point_id = point.id and item.tenant_id = point.tenant_id
               and item.status <> 'voided') as "riskScore",
            (select case when level.level_code = 'medium' then 'general' else level.level_code end
             from public.smis_risk_item item
             join public.smis_risk_evaluation evaluation
               on evaluation.risk_item_id = item.id and evaluation.tenant_id = item.tenant_id
             join public.smis_risk_assessment_level level
               on level.id = evaluation.risk_level_id and level.tenant_id = evaluation.tenant_id
             where item.risk_point_id = point.id and item.tenant_id = point.tenant_id
               and item.status <> 'voided'
             order by case level.level_code
               when 'major' then 1 when 'high' then 2
               when 'medium' then 3 when 'general' then 3 when 'low' then 4 else 5 end,
               evaluation.d_value desc
             limit 1) as "riskLevel"
        ) summary on true
        where point.tenant_id = v_tenant_id
          and point.status = 'enabled'
          and (v_keyword is null or point.point_no ilike '%' || v_keyword || '%'
            or point.point_name ilike '%' || v_keyword || '%')
          and (p_organization_id is null or exists (
            select 1 from public.smis_risk_point_organization relation
            where relation.risk_point_id = point.id and relation.tenant_id = point.tenant_id
              and relation.organization_id = p_organization_id
          ))
          and (p_site_id is null or point.site_id = p_site_id)
          and (v_equipment is null or point.equipment_name ilike '%' || v_equipment || '%')
          and (p_risk_type is null or point.risk_type = p_risk_type)
          and (p_risk_level is null or coalesce(summary."riskLevel", 'unidentified') = p_risk_level)
        order by point.sort, point.point_no
        offset v_from limit v_to - v_from + 1
      ) row_data
    ), '[]'::jsonb),
    'total', (
      select count(*) from public.smis_risk_point point
      where point.tenant_id = v_tenant_id and point.status = 'enabled'
        and (v_keyword is null or point.point_no ilike '%' || v_keyword || '%'
          or point.point_name ilike '%' || v_keyword || '%')
        and (p_organization_id is null or exists (
          select 1 from public.smis_risk_point_organization relation
          where relation.risk_point_id = point.id and relation.tenant_id = point.tenant_id
            and relation.organization_id = p_organization_id
        ))
        and (p_site_id is null or point.site_id = p_site_id)
        and (v_equipment is null or point.equipment_name ilike '%' || v_equipment || '%')
        and (p_risk_type is null or point.risk_type = p_risk_type)
        and (p_risk_level is null or p_risk_level = 'unidentified' and not exists (
          select 1 from public.smis_risk_item item
          join public.smis_risk_evaluation evaluation on evaluation.risk_item_id = item.id
          join public.smis_risk_assessment_level level on level.id = evaluation.risk_level_id
           where item.risk_point_id = point.id and item.tenant_id = point.tenant_id
             and evaluation.tenant_id = point.tenant_id and level.tenant_id = point.tenant_id
         ) or exists (
          select 1 from public.smis_risk_item item
          join public.smis_risk_evaluation evaluation on evaluation.risk_item_id = item.id
          join public.smis_risk_assessment_level level on level.id = evaluation.risk_level_id
           where item.risk_point_id = point.id and item.tenant_id = point.tenant_id
             and evaluation.tenant_id = point.tenant_id and level.tenant_id = point.tenant_id
             and (case when level.level_code = 'medium' then 'general' else level.level_code end) = p_risk_level
        ))
    ),
    'overview', jsonb_build_object(
      'total', (select count(*) from public.smis_risk_point where tenant_id = v_tenant_id and status = 'enabled'),
      'identified', (select count(distinct risk_point_id) from public.smis_risk_item where tenant_id = v_tenant_id and status <> 'voided'),
      'specialEquipment', (select count(*) from public.smis_risk_point where tenant_id = v_tenant_id and status = 'enabled' and is_special_equipment),
      'unidentified', (select count(*) from public.smis_risk_point point where point.tenant_id = v_tenant_id and point.status = 'enabled' and not exists (
        select 1 from public.smis_risk_item item join public.smis_risk_evaluation evaluation on evaluation.risk_item_id = item.id
         where item.risk_point_id = point.id and item.tenant_id = point.tenant_id
           and evaluation.tenant_id = point.tenant_id
      ))
    )
  );
end;
$$;

create or replace function public.smis_save_risk_point_secure(
  p_id uuid,
  p_payload jsonb,
  p_organization_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_site_id uuid;
  v_equipment_id uuid;
  v_point_name text := btrim(coalesce(p_payload->>'point_name', ''));
  v_equipment_name text := btrim(coalesce(p_payload->>'equipment_name', ''));
  v_risk_type text := coalesce(nullif(p_payload->>'risk_type', ''), 'unset');
  v_special boolean := coalesce((p_payload->>'is_special_equipment')::boolean, false);
  v_organization_id uuid;
begin
  if p_id is null and not app_private.has_permission('SmisDualControlRiskIdentification:Add') then
    raise exception '当前账号没有新增风险点的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisDualControlRiskIdentification:Edit') then
    raise exception '当前账号没有编辑风险点的权限' using errcode = '42501';
  end if;
  if v_point_name = '' then raise exception '请输入风险点名称' using errcode = '22023'; end if;
  if v_equipment_name = '' then raise exception '请输入或选择设备设施名称' using errcode = '22023'; end if;
  if v_risk_type not in ('unset', 'location', 'equipment', 'activity') then
    raise exception '风险类型无效' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_organization_ids), 0) = 0 then
    raise exception '请至少选择一个辨识单位' using errcode = '22023';
  end if;
  begin
    v_site_id := (p_payload->>'site_id')::uuid;
    v_equipment_id := nullif(p_payload->>'equipment_id', '')::uuid;
  exception when others then
    raise exception '场所或设备设施标识格式无效' using errcode = '22023';
  end;
  if not exists (select 1 from public.smis_site where id = v_site_id and tenant_id = v_tenant_id) then
    raise exception '所选场所不存在或不属于当前租户' using errcode = '22023';
  end if;
  if v_equipment_id is not null and not exists (
    select 1 from public.smis_equipment
    where id = v_equipment_id and tenant_id = v_tenant_id and status = 'enabled'
      and (not v_special or is_special_equipment)
  ) then
    raise exception '所选设备不存在、已停用或不符合特种设备条件' using errcode = '22023';
  end if;
  if v_special and v_equipment_id is null then
    raise exception '特种设备风险点必须从特种设备台账选择设备' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(p_organization_ids) organization_id
    where not exists (
      select 1 from public.sys_organization organization
      where organization.id = organization_id and organization.tenant_id = v_tenant_id
        and organization.status = '1'
    )
  ) then
    raise exception '辨识单位包含无效或跨租户组织' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_risk_point(
      tenant_id, point_no, point_name, risk_type, site_id, equipment_id, equipment_name,
      is_special_equipment, control_plan_name, control_plan_attachment_urls,
      photo_urls, attachment_urls, sort
    ) values (
      v_tenant_id, app_private.smis_next_risk_point_no(v_tenant_id), v_point_name,
      v_risk_type, v_site_id, v_equipment_id, v_equipment_name, v_special,
      nullif(btrim(coalesce(p_payload->>'control_plan_name', '')), ''),
      coalesce(p_payload->'control_plan_attachment_urls', '[]'::jsonb),
      coalesce(p_payload->'photo_urls', '[]'::jsonb),
      coalesce(p_payload->'attachment_urls', '[]'::jsonb),
      greatest(coalesce((p_payload->>'sort')::integer, 0), 0)
    ) returning id into v_id;
  else
    update public.smis_risk_point set
      point_name = v_point_name,
      risk_type = v_risk_type,
      site_id = v_site_id,
      equipment_id = v_equipment_id,
      equipment_name = v_equipment_name,
      is_special_equipment = v_special,
      control_plan_name = nullif(btrim(coalesce(p_payload->>'control_plan_name', '')), ''),
      control_plan_attachment_urls = coalesce(p_payload->'control_plan_attachment_urls', '[]'::jsonb),
      photo_urls = coalesce(p_payload->'photo_urls', '[]'::jsonb),
      attachment_urls = coalesce(p_payload->'attachment_urls', '[]'::jsonb),
      sort = greatest(coalesce((p_payload->>'sort')::integer, 0), 0)
    where id = p_id and tenant_id = v_tenant_id and status = 'enabled'
    returning id into v_id;
    if v_id is null then raise exception '风险点不存在、已作废或不属于当前租户' using errcode = 'P0002'; end if;
    delete from public.smis_risk_point_organization where risk_point_id = v_id and tenant_id = v_tenant_id;
  end if;
  foreach v_organization_id in array p_organization_ids loop
    insert into public.smis_risk_point_organization(tenant_id, risk_point_id, organization_id)
    values (v_tenant_id, v_id, v_organization_id);
  end loop;
  return v_id;
end;
$$;

create or replace function public.smis_delete_risk_points_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_count integer;
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:Delete') then
    raise exception '当前账号没有删除风险点的权限' using errcode = '42501';
  end if;
  delete from public.smis_risk_point
  where tenant_id = v_tenant_id and id = any(coalesce(p_ids, '{}'::uuid[]))
    and not exists (
      select 1 from public.smis_risk_item item
      join public.smis_risk_evaluation evaluation on evaluation.risk_item_id = item.id
      where item.risk_point_id = smis_risk_point.id
    );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.smis_copy_risk_point_secure(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_source public.smis_risk_point%rowtype;
  v_new_id uuid;
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:Copy') then
    raise exception '当前账号没有复制风险点的权限' using errcode = '42501';
  end if;
  select * into v_source from public.smis_risk_point
  where id = p_id and tenant_id = v_tenant_id and status = 'enabled';
  if not found then raise exception '风险点不存在或不属于当前租户' using errcode = 'P0002'; end if;
  insert into public.smis_risk_point(
    tenant_id, point_no, point_name, risk_type, site_id, equipment_id, equipment_name,
    is_special_equipment, control_plan_name, control_plan_attachment_urls,
    photo_urls, attachment_urls, sort
  ) values (
    v_tenant_id, app_private.smis_next_risk_point_no(v_tenant_id),
    left(v_source.point_name || '（副本）', 200), v_source.risk_type, v_source.site_id,
    v_source.equipment_id, v_source.equipment_name, v_source.is_special_equipment,
    v_source.control_plan_name, v_source.control_plan_attachment_urls,
    v_source.photo_urls, v_source.attachment_urls, v_source.sort
  ) returning id into v_new_id;
  insert into public.smis_risk_point_organization(tenant_id, risk_point_id, organization_id)
  select tenant_id, v_new_id, organization_id from public.smis_risk_point_organization
  where risk_point_id = p_id and tenant_id = v_tenant_id;
  return v_new_id;
end;
$$;

create or replace function public.smis_generate_all_risk_points_secure()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_site record;
  v_point_id uuid;
  v_count integer := 0;
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:Generate') then
    raise exception '当前账号没有生成所有风险点的权限' using errcode = '42501';
  end if;
  for v_site in
    select site.id, site.site_name, site.organization_id
    from public.smis_site site
    where site.tenant_id = v_tenant_id
      and not exists (
        select 1 from public.smis_risk_point point
        where point.tenant_id = site.tenant_id and point.site_id = site.id and point.status = 'enabled'
      )
    order by site.sort, site.site_name
  loop
    insert into public.smis_risk_point(
      tenant_id, point_no, point_name, risk_type, site_id, equipment_name
    ) values (
      v_tenant_id, app_private.smis_next_risk_point_no(v_tenant_id),
      v_site.site_name || '风险点', 'location', v_site.id, '场所公共设施'
    ) returning id into v_point_id;
    insert into public.smis_risk_point_organization(tenant_id, risk_point_id, organization_id)
    values (v_tenant_id, v_point_id, v_site.organization_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.smis_list_risk_hazard_workspace_secure(p_risk_point_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:View') then
    raise exception '当前账号没有查看风险辨识的权限' using errcode = '42501';
  end if;
  if not exists (select 1 from public.smis_risk_point where id = p_risk_point_id and tenant_id = v_tenant_id) then
    raise exception '风险点不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'activities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', activity.id, 'activityName', activity.activity_name,
        'workStep', activity.work_step, 'sort', activity.sort,
        'hazardCount', (select count(*) from public.smis_risk_item_activity relation where relation.activity_id = activity.id)
      ) order by activity.sort, activity.create_time)
      from public.smis_risk_activity activity
      where activity.risk_point_id = p_risk_point_id and activity.tenant_id = v_tenant_id
    ), '[]'::jsonb),
    'hazards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', item.id, 'hazardNo', item.item_no, 'hazardFactor', item.hazard_factor,
        'factorCategoryId', item.factor_category_id,
        'factorCategoryName', category.category_name,
        'accidentTypes', item.accident_types, 'consequence', item.consequence,
        'status', item.status, 'sort', item.sort,
        'activityIds', coalesce((select jsonb_agg(relation.activity_id) from public.smis_risk_item_activity relation where relation.risk_item_id = item.id), '[]'::jsonb)
      ) order by item.sort, item.item_no)
      from public.smis_risk_item item
      left join public.smis_hazard_factor_category category
        on category.id = item.factor_category_id and category.tenant_id = item.tenant_id
      where item.risk_point_id = p_risk_point_id and item.tenant_id = v_tenant_id and item.status <> 'voided'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.smis_save_risk_activity_secure(
  p_id uuid,
  p_risk_point_id uuid,
  p_activity_name text,
  p_work_step text,
  p_sort integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_name text := btrim(coalesce(p_activity_name, ''));
  v_step text := btrim(coalesce(p_work_step, ''));
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:MaintainHazards') then
    raise exception '当前账号没有维护作业活动的权限' using errcode = '42501';
  end if;
  if v_name = '' then raise exception '请输入作业活动' using errcode = '22023'; end if;
  if v_step = '' then raise exception '请输入作业步骤' using errcode = '22023'; end if;
  if not exists (select 1 from public.smis_risk_point where id = p_risk_point_id and tenant_id = v_tenant_id and status = 'enabled') then
    raise exception '风险点不存在、已作废或不属于当前租户' using errcode = 'P0002';
  end if;
  if p_id is null then
    insert into public.smis_risk_activity(tenant_id, risk_point_id, activity_name, work_step, sort)
    values (v_tenant_id, p_risk_point_id, v_name, v_step, greatest(coalesce(p_sort, 0), 0))
    returning id into v_id;
  else
    update public.smis_risk_activity set activity_name = v_name, work_step = v_step,
      sort = greatest(coalesce(p_sort, 0), 0)
    where id = p_id and risk_point_id = p_risk_point_id and tenant_id = v_tenant_id
    returning id into v_id;
    if v_id is null then raise exception '作业活动不存在或不属于当前风险点' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.smis_delete_risk_activities_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:MaintainHazards') then
    raise exception '当前账号没有删除作业活动的权限' using errcode = '42501';
  end if;
  delete from public.smis_risk_activity
  where tenant_id = app_private.current_user_tenant_id() and id = any(coalesce(p_ids, '{}'::uuid[]));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.smis_save_risk_hazard_secure(
  p_id uuid,
  p_risk_point_id uuid,
  p_payload jsonb,
  p_activity_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_point_name text;
  v_factor text := btrim(coalesce(p_payload->>'hazard_factor', ''));
  v_category_id uuid;
  v_activity_id uuid;
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:MaintainHazards') then
    raise exception '当前账号没有维护危害因素的权限' using errcode = '42501';
  end if;
  if v_factor = '' then raise exception '请输入危害因素' using errcode = '22023'; end if;
  begin v_category_id := (p_payload->>'factor_category_id')::uuid;
  exception when others then raise exception '危害因素类别格式无效' using errcode = '22023'; end;
  select point_name into v_point_name from public.smis_risk_point
  where id = p_risk_point_id and tenant_id = v_tenant_id and status = 'enabled';
  if v_point_name is null then raise exception '风险点不存在、已作废或不属于当前租户' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.smis_hazard_factor_category where id = v_category_id and tenant_id = v_tenant_id and status = 'enabled') then
    raise exception '危害因素类别不存在、已停用或不属于当前租户' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_activity_ids, '{}'::uuid[])) activity_id
    where not exists (
      select 1 from public.smis_risk_activity activity
      where activity.id = activity_id and activity.risk_point_id = p_risk_point_id and activity.tenant_id = v_tenant_id
    )
  ) then raise exception '关联作业活动包含无效或跨风险点记录' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.smis_risk_item(
      tenant_id, risk_point_id, item_no, risk_point, hazard_factor, factor_category_id,
      accident_types, consequence, sort, status
    ) values (
      v_tenant_id, p_risk_point_id,
      app_private.smis_next_risk_item_no(v_tenant_id, p_risk_point_id),
      v_point_name, v_factor, v_category_id,
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'accident_types', '[]'::jsonb))), '{}'::text[]),
      nullif(btrim(coalesce(p_payload->>'consequence', '')), ''),
      greatest(coalesce((p_payload->>'sort')::integer, 0), 0), 'identified'
    ) returning id into v_id;
  else
    update public.smis_risk_item set hazard_factor = v_factor, factor_category_id = v_category_id,
      accident_types = coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'accident_types', '[]'::jsonb))), '{}'::text[]),
      consequence = nullif(btrim(coalesce(p_payload->>'consequence', '')), ''),
      sort = greatest(coalesce((p_payload->>'sort')::integer, 0), 0)
    where id = p_id and risk_point_id = p_risk_point_id and tenant_id = v_tenant_id and status <> 'voided'
    returning id into v_id;
    if v_id is null then raise exception '危害因素不存在、已作废或不属于当前风险点' using errcode = 'P0002'; end if;
    delete from public.smis_risk_item_activity where risk_item_id = v_id and tenant_id = v_tenant_id;
  end if;
  foreach v_activity_id in array coalesce(p_activity_ids, '{}'::uuid[]) loop
    insert into public.smis_risk_item_activity(tenant_id, risk_item_id, activity_id)
    values (v_tenant_id, v_id, v_activity_id);
  end loop;
  return v_id;
end;
$$;

create or replace function public.smis_delete_risk_hazards_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:MaintainHazards') then
    raise exception '当前账号没有删除危害因素的权限' using errcode = '42501';
  end if;
  delete from public.smis_risk_item item
  where item.tenant_id = app_private.current_user_tenant_id()
    and item.id = any(coalesce(p_ids, '{}'::uuid[]))
    and not exists (select 1 from public.smis_risk_evaluation evaluation where evaluation.risk_item_id = item.id);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Risk-point type is a shared platform dictionary so list filters, forms and exports use one source.
with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, node_type, sort
)
select gen_random_uuid(), '风险点类型', 'smisRiskPointType', '1',
  '624944977@qq.com', '624944977@qq.com', '风险辨识风险点分类',
  platform_tenant.id, 'dictionary', 536
from platform_tenant
where not exists (
  select 1 from public.sys_dict_type existing
  where existing.tenant_id = platform_tenant.id and existing.code = 'smisRiskPointType'
);

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(value, label, tag_type, sort) as (
  values
    ('unset', '未选择', 'info', 1),
    ('location', '部位场所', 'primary', 2),
    ('equipment', '设备设施', 'warning', 3),
    ('activity', '作业活动', 'success', 4)
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
)
select gen_random_uuid(), dict_type.id, 'smisRiskPointType_' || item.value, '1',
  '624944977@qq.com', '624944977@qq.com', item.value, item.label,
  item.sort, platform_tenant.id, item.tag_type
from items item
cross join platform_tenant
join public.sys_dict_type dict_type
  on dict_type.tenant_id = platform_tenant.id and dict_type.code = 'smisRiskPointType'
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dict_type.id and existing.value = item.value
);

do $buttons$
declare
  v_page_id uuid;
begin
  select id into v_page_id from public.sys_menu
  where name = 'SmisDualControlRiskIdentification' and type = 'menu' limit 1;
  insert into public.sys_menu(id, parent_id, name, path, component, meta, sort, create_by, update_by, type, app_code)
  select gen_random_uuid(), v_page_id, definition.name, null, null,
    jsonb_build_object('title', definition.title, 'is_hide', true, 'is_enable', true, 'roles', '[]'::jsonb, 'icon', ''),
    definition.sort, '624944977@qq.com', '624944977@qq.com', 'button', 'smis'
  from (values
    ('SmisDualControlRiskIdentification:Copy', '复制风险点', 7),
    ('SmisDualControlRiskIdentification:Generate', '生成所有风险点', 8),
    ('SmisDualControlRiskIdentification:Import', '导入风险点', 9),
    ('SmisDualControlRiskIdentification:MaintainHazards', '维护危害因素', 10)
  ) definition(name, title, sort)
  where v_page_id is not null
    and not exists (select 1 from public.sys_menu existing where existing.name = definition.name);

  insert into public.sys_role_menu(id, role_id, menu_id, tenant_id, permission, create_by, update_by)
  select gen_random_uuid(), page_grant.role_id, button.id, page_grant.tenant_id,
    '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
  from public.sys_role_menu page_grant
  join public.sys_menu page on page.id = page_grant.menu_id and page.id = v_page_id
  join public.sys_menu button on button.parent_id = page.id and button.type = 'button'
  where not exists (
    select 1 from public.sys_role_menu existing
    where existing.role_id = page_grant.role_id and existing.menu_id = button.id
      and existing.tenant_id = page_grant.tenant_id
  );
end
$buttons$;

revoke all on function public.smis_list_risk_identification_options_secure() from public, anon;
revoke all on function public.smis_list_risk_points_secure(integer, integer, text, uuid, uuid, text, text, text) from public, anon;
revoke all on function public.smis_save_risk_point_secure(uuid, jsonb, uuid[]) from public, anon;
revoke all on function public.smis_delete_risk_points_secure(uuid[]) from public, anon;
revoke all on function public.smis_copy_risk_point_secure(uuid) from public, anon;
revoke all on function public.smis_generate_all_risk_points_secure() from public, anon;
revoke all on function public.smis_list_risk_hazard_workspace_secure(uuid) from public, anon;
revoke all on function public.smis_save_risk_activity_secure(uuid, uuid, text, text, integer) from public, anon;
revoke all on function public.smis_delete_risk_activities_secure(uuid[]) from public, anon;
revoke all on function public.smis_save_risk_hazard_secure(uuid, uuid, jsonb, uuid[]) from public, anon;
revoke all on function public.smis_delete_risk_hazards_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_risk_identification_options_secure() to authenticated;
grant execute on function public.smis_list_risk_points_secure(integer, integer, text, uuid, uuid, text, text, text) to authenticated;
grant execute on function public.smis_save_risk_point_secure(uuid, jsonb, uuid[]) to authenticated;
grant execute on function public.smis_delete_risk_points_secure(uuid[]) to authenticated;
grant execute on function public.smis_copy_risk_point_secure(uuid) to authenticated;
grant execute on function public.smis_generate_all_risk_points_secure() to authenticated;
grant execute on function public.smis_list_risk_hazard_workspace_secure(uuid) to authenticated;
grant execute on function public.smis_save_risk_activity_secure(uuid, uuid, text, text, integer) to authenticated;
grant execute on function public.smis_delete_risk_activities_secure(uuid[]) to authenticated;
grant execute on function public.smis_save_risk_hazard_secure(uuid, uuid, jsonb, uuid[]) to authenticated;
grant execute on function public.smis_delete_risk_hazards_secure(uuid[]) to authenticated;

-- Risk workspaces may resolve active category labels without receiving category-write access.
create policy smis_hazard_factor_category_risk_reference_select
on public.smis_hazard_factor_category
for select to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and (
      app_private.has_permission('SmisDualControlRiskIdentification:View')
      or app_private.has_permission('SmisDualControlRiskEvaluationControl:View')
    )
  )
);

;
