alter table public.smis_emergency_rescue_plan
  add column if not exists plan_version text,
  add column if not exists review_date date,
  add column if not exists review_experts text,
  add column if not exists plan_attachment_urls text[] not null default '{}'::text[],
  add column if not exists filing_attachment_urls text[] not null default '{}'::text[];

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'smis_emergency_rescue_plan_review_fields_check'
      and conrelid = 'public.smis_emergency_rescue_plan'::regclass
  ) then
    alter table public.smis_emergency_rescue_plan
      add constraint smis_emergency_rescue_plan_review_fields_check check (
        (plan_version is null or (btrim(plan_version) <> '' and char_length(plan_version) <= 60))
        and (review_experts is null or char_length(review_experts) <= 500)
        and coalesce(cardinality(plan_attachment_urls), 0) <= 10
        and coalesce(cardinality(filing_attachment_urls), 0) <= 10
      );
  end if;
end
$$;

comment on column public.smis_emergency_rescue_plan.warning_status is
  'Legacy compatibility column. List and overview warning status is derived from review date, frequency, and submitted drill records.';

create table if not exists public.smis_emergency_rescue_plan_position (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  rescue_plan_id uuid not null,
  position_id uuid not null,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_emergency_rescue_plan_position_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint smis_emergency_rescue_plan_position_plan_fkey
    foreign key (rescue_plan_id, tenant_id)
    references public.smis_emergency_rescue_plan(id, tenant_id) on delete cascade,
  constraint smis_emergency_rescue_plan_position_position_fkey
    foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint smis_emergency_rescue_plan_position_unique
    unique (tenant_id, rescue_plan_id, position_id)
);

create index if not exists smis_emergency_rescue_plan_position_plan_idx
  on public.smis_emergency_rescue_plan_position (tenant_id, rescue_plan_id);
create index if not exists smis_emergency_rescue_plan_position_position_idx
  on public.smis_emergency_rescue_plan_position (tenant_id, position_id);

insert into public.smis_emergency_rescue_plan_position (
  tenant_id,
  rescue_plan_id,
  position_id,
  sort,
  create_by,
  update_by
)
select tenant_id, id, applicable_position_id, 0, create_by, update_by
from public.smis_emergency_rescue_plan
where applicable_position_id is not null
on conflict (tenant_id, rescue_plan_id, position_id) do nothing;

alter table public.smis_emergency_rescue_plan_position enable row level security;

drop policy if exists smis_emergency_rescue_plan_position_select
  on public.smis_emergency_rescue_plan_position;
create policy smis_emergency_rescue_plan_position_select
  on public.smis_emergency_rescue_plan_position
  for select
  to authenticated
  using (
    (
      tenant_id = (select app_private.current_user_tenant_id())
      and (select app_private.has_permission('SmisEmergencyRescuePlan:View'))
    )
    or (select app_private.is_platform_super())
  );

drop trigger if exists smis_emergency_rescue_plan_position_create_audit
  on public.smis_emergency_rescue_plan_position;
create trigger smis_emergency_rescue_plan_position_create_audit
before insert on public.smis_emergency_rescue_plan_position
for each row
execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists smis_emergency_rescue_plan_position_update_audit
  on public.smis_emergency_rescue_plan_position;
create trigger smis_emergency_rescue_plan_position_update_audit
before update on public.smis_emergency_rescue_plan_position
for each row
execute function public.trg_set_update_time_and_by();

create or replace function app_private.smis_emergency_review_due_date(
  p_review_date date,
  p_frequency text
)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_frequency
    when 'once_per_shift' then p_review_date + 1
    when 'daily' then p_review_date + 1
    when 'weekly' then p_review_date + 7
    when 'biweekly' then p_review_date + 14
    when 'triweekly' then p_review_date + 21
    when 'monthly' then (p_review_date + interval '1 month')::date
    when 'bimonthly' then (p_review_date + interval '2 months')::date
    when 'quarterly' then (p_review_date + interval '3 months')::date
    when 'semiannual' then (p_review_date + interval '6 months')::date
    else null
  end;
$$;

revoke all on function app_private.smis_emergency_review_due_date(date, text)
  from public, anon, authenticated;

create or replace function public.smis_save_emergency_rescue_plan_secure(
  p_id uuid,
  p_payload jsonb,
  p_submit boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_no text := upper(btrim(coalesce(p_payload->>'plan_no', '')));
  v_name text := btrim(coalesce(p_payload->>'plan_name', ''));
  v_version text := btrim(coalesce(p_payload->>'plan_version', ''));
  v_org uuid := nullif(p_payload->>'applicable_organization_id', '')::uuid;
  v_category text := p_payload->>'plan_category';
  v_frequency text := p_payload->>'frequency';
  v_review_date date := nullif(p_payload->>'review_date', '')::date;
  v_review_experts text := btrim(coalesce(p_payload->>'review_experts', ''));
  v_level text;
  v_id uuid;
  v_position_ids jsonb := coalesce(p_payload->'applicable_position_ids', '[]'::jsonb);
begin
  if p_id is null and not app_private.has_permission('SmisEmergencyRescuePlan:Add') then
    raise exception '当前账号无权新增应急预案';
  end if;
  if p_id is not null and not app_private.has_permission('SmisEmergencyRescuePlan:Edit') then
    raise exception '当前账号无权编辑应急预案';
  end if;
  if p_submit and not app_private.has_permission('SmisEmergencyRescuePlan:Submit') then
    raise exception '当前账号无权提交应急预案';
  end if;

  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id
    from public.smis_emergency_rescue_plan target
    where target.id = p_id
  ));

  if v_name = '' then raise exception '请输入预案名称'; end if;
  if v_version = '' then raise exception '请输入预案版本号'; end if;
  if char_length(v_version) > 60 then raise exception '预案版本号不能超过60个字符'; end if;
  if v_review_date is null then raise exception '请选择评审时间'; end if;
  if v_review_date > current_date then raise exception '评审时间不能晚于今天'; end if;
  if v_review_experts = '' then raise exception '请输入评审专家'; end if;
  if char_length(v_review_experts) > 500 then raise exception '评审专家不能超过500个字符'; end if;
  if not exists (
    select 1
    from public.sys_organization
    where id = v_org and tenant_id = v_tenant_id and status = '1'
  ) then raise exception '请选择有效的适用单位'; end if;
  if v_category not in ('comprehensive', 'onsite', 'special') then
    raise exception '请选择有效的预案类别';
  end if;
  if v_frequency not in (
    'once_per_shift', 'daily', 'weekly', 'biweekly', 'triweekly',
    'monthly', 'bimonthly', 'quarterly', 'semiannual'
  ) then raise exception '请选择有效的周期频次'; end if;
  if jsonb_typeof(v_position_ids) <> 'array' then
    raise exception '适用岗位数据格式不正确';
  end if;
  if exists (
    select 1
    from jsonb_array_elements_text(v_position_ids) selected(id)
    where not exists (
      select 1
      from public.hr_position position
      where position.id = selected.id::uuid
        and position.tenant_id = v_tenant_id
        and position.enabled
    )
  ) then raise exception '适用岗位包含已停用、无效或非当前租户岗位'; end if;
  if jsonb_array_length(coalesce(p_payload->'plan_attachment_urls', '[]'::jsonb)) > 10 then
    raise exception '预案附件最多上传10个';
  end if;
  if jsonb_array_length(coalesce(p_payload->'filing_attachment_urls', '[]'::jsonb)) > 10 then
    raise exception '备案表附件最多上传10个';
  end if;

  v_level := app_private.smis_plan_level_for_organization(v_tenant_id, v_org);
  if p_id is null then
    if v_no = '' then
      v_no := app_private.next_document_number('smis.emergency_rescue_plan', v_tenant_id);
    end if;
    insert into public.smis_emergency_rescue_plan (
      plan_no,
      plan_name,
      plan_version,
      applicable_organization_id,
      plan_category,
      applicable_position_id,
      frequency,
      review_date,
      review_experts,
      plan_attachment_urls,
      filing_attachment_urls,
      is_special_equipment_drill,
      plan_level,
      is_valid,
      warning_status,
      record_status,
      description,
      tenant_id
    ) values (
      v_no,
      v_name,
      v_version,
      v_org,
      v_category,
      (select nullif(value, '')::uuid from jsonb_array_elements_text(v_position_ids) limit 1),
      v_frequency,
      v_review_date,
      v_review_experts,
      array(select jsonb_array_elements_text(coalesce(p_payload->'plan_attachment_urls', '[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_payload->'filing_attachment_urls', '[]'::jsonb))),
      coalesce((p_payload->>'is_special_equipment_drill')::boolean, false),
      v_level,
      true,
      'normal',
      case when p_submit then 'submitted' else 'draft' end,
      nullif(btrim(p_payload->>'description'), ''),
      v_tenant_id
    ) returning id into v_id;
  else
    if not exists (
      select 1
      from public.smis_emergency_rescue_plan
      where id = p_id and tenant_id = v_tenant_id
    ) then raise exception '应急预案不存在或不属于当前租户'; end if;

    update public.smis_emergency_rescue_plan
    set plan_name = v_name,
        plan_version = v_version,
        applicable_organization_id = v_org,
        plan_category = v_category,
        applicable_position_id = (
          select nullif(value, '')::uuid
          from jsonb_array_elements_text(v_position_ids)
          limit 1
        ),
        frequency = v_frequency,
        review_date = v_review_date,
        review_experts = v_review_experts,
        plan_attachment_urls = array(
          select jsonb_array_elements_text(coalesce(p_payload->'plan_attachment_urls', '[]'::jsonb))
        ),
        filing_attachment_urls = array(
          select jsonb_array_elements_text(coalesce(p_payload->'filing_attachment_urls', '[]'::jsonb))
        ),
        is_special_equipment_drill = coalesce(
          (p_payload->>'is_special_equipment_drill')::boolean,
          false
        ),
        plan_level = v_level,
        warning_status = 'normal',
        record_status = case when p_submit then 'submitted' else record_status end,
        description = nullif(btrim(p_payload->>'description'), '')
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_id;
  end if;

  delete from public.smis_emergency_rescue_plan_position
  where tenant_id = v_tenant_id and rescue_plan_id = v_id;

  insert into public.smis_emergency_rescue_plan_position (
    tenant_id,
    rescue_plan_id,
    position_id,
    sort
  )
  select
    v_tenant_id,
    v_id,
    selected.id::uuid,
    min(selected.ordinality)::integer - 1
  from jsonb_array_elements_text(v_position_ids) with ordinality selected(id, ordinality)
  group by selected.id;

  return v_id;
exception
  when unique_violation then
    raise exception '预案编码已存在，请检查编号规则';
  when invalid_text_representation then
    raise exception '适用单位或适用岗位包含无效数据';
end;
$$;

create or replace function public.smis_list_emergency_rescue_plans_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_plan_category text default null,
  p_organization_id uuid default null,
  p_is_valid boolean default null,
  p_warning_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
  v_orgs jsonb;
  v_positions jsonb;
begin
  if not app_private.has_permission('SmisEmergencyRescuePlan:View') then
    raise exception '当前账号无权查看应急救援预案';
  end if;

  with base as (
    select
      plan.*,
      organization.organization_name as applicable_organization_name,
      organization.organization_code as applicable_organization_code,
      organization.organization_code = '00'
        or organization.organization_code like '%-00' as is_public_scope,
      app_private.smis_emergency_review_due_date(plan.review_date, plan.frequency)
        as next_review_date,
      latest_drill.last_drill_date,
      case
        when not plan.is_valid or plan.record_status <> 'submitted' then 'normal'
        when plan.review_date is null then 'warning'
        when latest_drill.last_drill_date > plan.review_date then 'warning'
        when app_private.smis_emergency_review_due_date(plan.review_date, plan.frequency)
          <= current_date + 7 then 'warning'
        else 'normal'
      end as derived_warning_status
    from public.smis_emergency_rescue_plan plan
    join public.sys_organization organization
      on organization.id = plan.applicable_organization_id
      and organization.tenant_id = plan.tenant_id
    left join lateral (
      select max(record.actual_start_date) as last_drill_date
      from public.smis_emergency_drill_plan drill
      join public.smis_emergency_drill_record record
        on record.drill_plan_id = drill.id
        and record.tenant_id = drill.tenant_id
        and record.status = 'submitted'
      where drill.tenant_id = plan.tenant_id
        and drill.source_plan_id = plan.id
    ) latest_drill on true
    where app_private.current_read_tenant_id() is null
      or plan.tenant_id = app_private.current_read_tenant_id()
  ), filtered as (
    select *
    from base
    where (
      nullif(btrim(p_keyword), '') is null
      or plan_no ilike '%' || btrim(p_keyword) || '%'
      or plan_name ilike '%' || btrim(p_keyword) || '%'
      or plan_version ilike '%' || btrim(p_keyword) || '%'
    )
      and (p_plan_category is null or plan_category = p_plan_category)
      and (p_organization_id is null or applicable_organization_id = p_organization_id)
      and (p_is_valid is null or is_valid = p_is_valid)
      and (p_warning_status is null or derived_warning_status = p_warning_status)
  )
  select count(*) into v_total from filtered;

  with base as (
    select
      plan.*,
      organization.organization_name as applicable_organization_name,
      organization.organization_code as applicable_organization_code,
      organization.organization_code = '00'
        or organization.organization_code like '%-00' as is_public_scope,
      app_private.smis_emergency_review_due_date(plan.review_date, plan.frequency)
        as next_review_date,
      latest_drill.last_drill_date,
      case
        when not plan.is_valid or plan.record_status <> 'submitted' then 'normal'
        when plan.review_date is null then 'warning'
        when latest_drill.last_drill_date > plan.review_date then 'warning'
        when app_private.smis_emergency_review_due_date(plan.review_date, plan.frequency)
          <= current_date + 7 then 'warning'
        else 'normal'
      end as derived_warning_status
    from public.smis_emergency_rescue_plan plan
    join public.sys_organization organization
      on organization.id = plan.applicable_organization_id
      and organization.tenant_id = plan.tenant_id
    left join lateral (
      select max(record.actual_start_date) as last_drill_date
      from public.smis_emergency_drill_plan drill
      join public.smis_emergency_drill_record record
        on record.drill_plan_id = drill.id
        and record.tenant_id = drill.tenant_id
        and record.status = 'submitted'
      where drill.tenant_id = plan.tenant_id
        and drill.source_plan_id = plan.id
    ) latest_drill on true
    where app_private.current_read_tenant_id() is null
      or plan.tenant_id = app_private.current_read_tenant_id()
  ), filtered as (
    select *
    from base
    where (
      nullif(btrim(p_keyword), '') is null
      or plan_no ilike '%' || btrim(p_keyword) || '%'
      or plan_name ilike '%' || btrim(p_keyword) || '%'
      or plan_version ilike '%' || btrim(p_keyword) || '%'
    )
      and (p_plan_category is null or plan_category = p_plan_category)
      and (p_organization_id is null or applicable_organization_id = p_organization_id)
      and (p_is_valid is null or is_valid = p_is_valid)
      and (p_warning_status is null or derived_warning_status = p_warning_status)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', plan.id,
    'planNo', plan.plan_no,
    'planName', plan.plan_name,
    'planVersion', plan.plan_version,
    'applicableOrganizationId', plan.applicable_organization_id,
    'applicableOrganizationName', plan.applicable_organization_name,
    'applicableOrganizationCode', plan.applicable_organization_code,
    'isPublicScope', plan.is_public_scope,
    'planCategory', plan.plan_category,
    'applicablePositionId', plan.applicable_position_id,
    'applicablePositionIds', coalesce((
      select jsonb_agg(link.position_id order by link.sort, position.position_name)
      from public.smis_emergency_rescue_plan_position link
      join public.hr_position position
        on position.id = link.position_id and position.tenant_id = link.tenant_id
      where link.tenant_id = plan.tenant_id and link.rescue_plan_id = plan.id
    ), '[]'::jsonb),
    'applicablePositions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', position.id,
        'positionCode', position.position_code,
        'positionName', position.position_name,
        'organizationId', position.organization_id
      ) order by link.sort, position.position_name)
      from public.smis_emergency_rescue_plan_position link
      join public.hr_position position
        on position.id = link.position_id and position.tenant_id = link.tenant_id
      where link.tenant_id = plan.tenant_id and link.rescue_plan_id = plan.id
    ), '[]'::jsonb),
    'frequency', plan.frequency,
    'reviewDate', plan.review_date,
    'reviewExperts', plan.review_experts,
    'nextReviewDate', plan.next_review_date,
    'lastDrillDate', plan.last_drill_date,
    'reviewRequiredAfterDrill', plan.last_drill_date > plan.review_date,
    'planAttachmentUrls', plan.plan_attachment_urls,
    'filingAttachmentUrls', plan.filing_attachment_urls,
    'isSpecialEquipmentDrill', plan.is_special_equipment_drill,
    'planLevel', plan.plan_level,
    'isValid', plan.is_valid,
    'warningStatus', plan.derived_warning_status,
    'recordStatus', plan.record_status,
    'description', plan.description,
    'drillDraftCount', (
      select count(*)
      from public.smis_emergency_drill_plan drill
      where drill.tenant_id = plan.tenant_id
        and drill.source_plan_id = plan.id
        and drill.status = 'draft'
    ),
    'createTime', plan.create_time,
    'updateTime', plan.update_time
  ) order by plan.update_time desc), '[]'::jsonb)
  into v_records
  from (
    select *
    from filtered
    order by update_time desc
    offset greatest(p_from, 0)
    limit greatest(p_to - p_from + 1, 0)
  ) plan;

  with status_rows as (
    select
      plan.is_valid,
      plan.record_status,
      case
        when not plan.is_valid or plan.record_status <> 'submitted' then 'normal'
        when plan.review_date is null then 'warning'
        when latest_drill.last_drill_date > plan.review_date then 'warning'
        when app_private.smis_emergency_review_due_date(plan.review_date, plan.frequency)
          <= current_date + 7 then 'warning'
        else 'normal'
      end as warning_status
    from public.smis_emergency_rescue_plan plan
    left join lateral (
      select max(record.actual_start_date) as last_drill_date
      from public.smis_emergency_drill_plan drill
      join public.smis_emergency_drill_record record
        on record.drill_plan_id = drill.id
        and record.tenant_id = drill.tenant_id
        and record.status = 'submitted'
      where drill.tenant_id = plan.tenant_id
        and drill.source_plan_id = plan.id
    ) latest_drill on true
    where app_private.current_read_tenant_id() is null
      or plan.tenant_id = app_private.current_read_tenant_id()
  )
  select jsonb_build_object(
    'total', count(*),
    'valid', count(*) filter (where is_valid),
    'warning', count(*) filter (where warning_status = 'warning'),
    'submitted', count(*) filter (where record_status = 'submitted')
  ) into v_overview
  from status_rows;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'parentId', parent_id,
    'organizationName', organization_name,
    'organizationCode', organization_code,
    'organizationType', organization_type,
    'sort', sort,
    'children', '[]'::jsonb
  ) order by sort, organization_name), '[]'::jsonb)
  into v_orgs
  from public.sys_organization
  where (app_private.current_read_tenant_id() is null
      or tenant_id = app_private.current_read_tenant_id())
    and status = '1';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'positionCode', position_code,
    'positionName', position_name,
    'organizationId', organization_id
  ) order by sort, position_name), '[]'::jsonb)
  into v_positions
  from public.hr_position
  where (app_private.current_read_tenant_id() is null
      or tenant_id = app_private.current_read_tenant_id())
    and enabled;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'overview', v_overview,
    'organizations', v_orgs,
    'positions', v_positions
  );
end;
$$;

create or replace function public.smis_list_active_emergency_rescue_plan_options_secure()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', plan.id,
    'planNo', plan.plan_no,
    'planName', plan.plan_name,
    'planVersion', plan.plan_version,
    'planCategory', plan.plan_category,
    'applicableOrganizationId', plan.applicable_organization_id,
    'applicableOrganizationName', organization.organization_name,
    'isPublicScope', organization.organization_code = '00'
      or organization.organization_code like '%-00'
  ) order by plan.plan_name), '[]'::jsonb)
  from public.smis_emergency_rescue_plan plan
  join public.sys_organization organization
    on organization.id = plan.applicable_organization_id
    and organization.tenant_id = plan.tenant_id
  where (app_private.current_read_tenant_id() is null
      or plan.tenant_id = app_private.current_read_tenant_id())
    and plan.is_valid
    and plan.record_status = 'submitted';
$$;

revoke all on function public.smis_save_emergency_rescue_plan_secure(uuid, jsonb, boolean)
  from public, anon;
grant execute on function public.smis_save_emergency_rescue_plan_secure(uuid, jsonb, boolean)
  to authenticated, service_role;
revoke all on function public.smis_list_emergency_rescue_plans_secure(
  integer, integer, text, text, uuid, boolean, text
) from public, anon;
grant execute on function public.smis_list_emergency_rescue_plans_secure(
  integer, integer, text, text, uuid, boolean, text
) to authenticated, service_role;
revoke all on function public.smis_list_active_emergency_rescue_plan_options_secure()
  from public, anon;
grant execute on function public.smis_list_active_emergency_rescue_plan_options_secure()
  to authenticated, service_role;

;
