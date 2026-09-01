-- Secure SMIS accident cases with tenant-scoped, owner-aware field permissions.
-- Existing menu and button permission definitions are intentionally unchanged.

alter table public.smis_accident_case
  add column if not exists created_by_user_id uuid;

update public.smis_accident_case case_row
set created_by_user_id = coalesce(
  (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = case_row.tenant_id
      and (
        user_row.auth_user_id::text = case_row.create_by
        or lower(user_row.user_email) = lower(case_row.create_by)
      )
    order by
      case when user_row.auth_user_id::text = case_row.create_by then 0 else 1 end,
      user_row.create_time,
      user_row.id
    limit 1
  ),
  case_row.reporter_user_id
)
where case_row.created_by_user_id is null;

create index if not exists smis_accident_case_tenant_creator_idx
  on public.smis_accident_case(tenant_id, created_by_user_id);

alter table public.smis_accident_case
  drop constraint if exists smis_accident_case_creator_tenant_fkey;
alter table public.smis_accident_case
  add constraint smis_accident_case_creator_tenant_fkey
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id);

create or replace function app_private.set_smis_accident_case_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := app_private.current_app_user_id();
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if tg_op = 'INSERT' then
    if v_user_id is not null and v_tenant_id = new.tenant_id then
      if new.created_by_user_id is null then
        new.created_by_user_id := v_user_id;
      elsif new.created_by_user_id <> v_user_id then
        raise exception 'Accident creator must be the current tenant user'
          using errcode = '42501';
      end if;
    elsif v_user_id is not null and not app_private.is_platform_super() then
      raise exception 'Accident tenant must match the current user tenant'
        using errcode = '42501';
    elsif new.created_by_user_id is null then
      new.created_by_user_id := new.reporter_user_id;
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Accident creator cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.smis_list_accident_cases_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_status text default null,
  p_severity text default null,
  p_keyword text default null,
  p_occurred_from timestamptz default null,
  p_occurred_to timestamptz default null
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
  v_limit integer := least(
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1),
    1000
  );
  v_keyword text := nullif(btrim(p_keyword), '');
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  perform app_private.assert_smis_accident_readable(false);

  select count(*) into v_total
  from public.smis_accident_case case_row
  where case_row.tenant_id = v_tenant_id
    and (p_status is null or case_row.status = p_status)
    and (p_severity is null or case_row.severity = p_severity)
    and (p_occurred_from is null or case_row.occurred_at >= p_occurred_from)
    and (p_occurred_to is null or case_row.occurred_at <= p_occurred_to)
    and (
      v_keyword is null
      or case_row.case_no ilike '%' || v_keyword || '%'
      or case_row.case_title ilike '%' || v_keyword || '%'
    );

  for v_row in
    select case_row.id, case_row.created_by_user_id
    from public.smis_accident_case case_row
    where case_row.tenant_id = v_tenant_id
      and (p_status is null or case_row.status = p_status)
      and (p_severity is null or case_row.severity = p_severity)
      and (p_occurred_from is null or case_row.occurred_at >= p_occurred_from)
      and (p_occurred_to is null or case_row.occurred_at <= p_occurred_to)
      and (
        v_keyword is null
        or case_row.case_no ilike '%' || v_keyword || '%'
        or case_row.case_title ilike '%' || v_keyword || '%'
      )
    order by case_row.occurred_at desc, case_row.create_time desc, case_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.smis_accident_case_to_secure_json(v_row.id, v_row.created_by_user_id)
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', app_private.field_access_map('smis.accident_case', null)
  );
end;
$$;

create or replace function public.smis_get_accident_case_secure(p_case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app_private.assert_smis_accident_readable(true);
  select case_row.created_by_user_id into v_owner_id
  from public.smis_accident_case case_row
  where case_row.id = p_case_id
    and case_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception '事故事件不存在或无权访问' using errcode = 'P0002';
  end if;
  return app_private.smis_accident_case_to_secure_json(p_case_id, v_owner_id);
end;
$$;

create or replace function public.smis_list_accident_case_events_secure(p_case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_access jsonb;
  v_investigation_access text;
  v_evidence_access text;
  v_participant_access text;
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_data jsonb;
begin
  perform app_private.assert_smis_accident_readable(true);
  select case_row.created_by_user_id into v_owner_id
  from public.smis_accident_case case_row
  where case_row.id = p_case_id
    and case_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception '事故事件不存在或无权访问' using errcode = 'P0002';
  end if;

  v_access := app_private.field_access_map('smis.accident_case', v_owner_id);
  v_investigation_access := coalesce(v_access ->> 'investigationDetails', 'hidden');
  v_evidence_access := coalesce(v_access ->> 'caseEvidence', 'hidden');
  v_participant_access := coalesce(v_access ->> 'caseParticipants', 'hidden');

  for v_row in
    select event_row.*,
      actor_user.user_name as actor_user_name,
      actor_user.nick_name as actor_nick_name,
      actor_user.user_email as actor_user_email
    from public.smis_accident_case_event event_row
    left join public.sys_user actor_user
      on actor_user.id = event_row.actor_user_id
     and actor_user.tenant_id = event_row.tenant_id
    where event_row.accident_case_id = p_case_id
      and event_row.tenant_id = app_private.current_user_tenant_id()
    order by event_row.create_time desc, event_row.id desc
  loop
    v_data := (to_jsonb(v_row)
      - 'tenant_id' - 'actor_user_name' - 'actor_nick_name' - 'actor_user_email')
      || jsonb_build_object(
        'actor_user', case when v_row.actor_user_id is null then null else jsonb_build_object(
          'id', v_row.actor_user_id,
          'user_name', v_row.actor_user_name,
          'nick_name', v_row.actor_nick_name,
          'user_email', v_row.actor_user_email
        ) end
      );
    v_data := app_private.apply_jsonb_text_access(
      v_data, array['comment']::text[], v_investigation_access
    );
    v_data := app_private.apply_jsonb_document_access(
      v_data, array['attachment_refs']::text[], v_evidence_access
    );
    if v_participant_access = 'hidden' then
      v_data := v_data - 'actor_user_id' - 'actor_user' - 'create_by';
    elsif v_participant_access = 'masked' then
      v_data := v_data - 'actor_user_id';
      v_data := jsonb_set(
        v_data, '{actor_user}',
        coalesce(app_private.smis_masked_user_ref(v_row.actor_user_id), 'null'::jsonb),
        true
      );
      v_data := app_private.apply_jsonb_text_access(
        v_data, array['create_by']::text[], 'masked'
      );
    end if;
    v_records := v_records || jsonb_build_array(v_data);
  end loop;
  return v_records;
end;
$$;

drop trigger if exists smis_accident_case_creator_identity on public.smis_accident_case;
create trigger smis_accident_case_creator_identity
before insert or update of created_by_user_id on public.smis_accident_case
for each row execute function app_private.set_smis_accident_case_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_smis_accident_case;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_smis_accident_case(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'smis.accident_case', 'SMIS 事故事件', 'SmisAccidentEmergency',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sensitive, enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'incidentLocation', '事故地点与地图坐标',
      'hidden', 'address', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'casualtyAndLoss', '伤亡人数与经济损失',
      'hidden', 'amount', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'investigationDetails', '事件描述、原因分析与整改措施',
      'hidden', 'none', true, true, true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'caseEvidence', '事故与处理过程附件',
      'hidden', 'none', true, true, true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'caseParticipants', '上报人、调查人与处理人员',
      'hidden', 'none', true, true, true, 50, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sensitive = true,
        enabled = true,
        sort = excluded.sort,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

-- Preserve existing access at rollout; tenant admins can tighten it afterwards.
insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id, role_menu.role_id, resource_row.id, field_row.id,
  'edit', '624944977@qq.com', '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'SmisAccidentEmergency'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'smis.accident_case'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_smis_accident_readable(
  p_require_detail boolean default false
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_require_detail then
    if not app_private.can_execute_business_action(
      'SmisAccidentEmergency', 'SmisAccidentEmergency:View', null, false
    ) then
      raise exception 'Missing accident detail permission' using errcode = '42501';
    end if;
  elsif not app_private.can_access_business_menu('SmisAccidentEmergency') then
    raise exception 'Missing accident page access' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.smis_masked_user_ref(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_user_id is null then null else jsonb_build_object(
    'user_name', '***', 'nick_name', '***', 'user_email', '***'
  ) end;
$$;

create or replace function app_private.smis_accident_case_to_secure_json(
  p_case_id uuid,
  p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('smis.accident_case', p_owner_id);
  v_location_access text := coalesce(v_access ->> 'incidentLocation', 'hidden');
  v_loss_access text := coalesce(v_access ->> 'casualtyAndLoss', 'hidden');
  v_investigation_access text := coalesce(v_access ->> 'investigationDetails', 'hidden');
  v_evidence_access text := coalesce(v_access ->> 'caseEvidence', 'hidden');
  v_participant_access text := coalesce(v_access ->> 'caseParticipants', 'hidden');
  v_data jsonb;
begin
  select
    (to_jsonb(case_row) - 'tenant_id' - 'created_by_user_id')
    || jsonb_build_object(
      'risk_point', case when risk_point_row.id is null then null else jsonb_build_object(
        'id', risk_point_row.id,
        'risk_point_no', risk_point_row.risk_point_no,
        'risk_point_name', risk_point_row.risk_point_name,
        'current_risk_level', risk_point_row.current_risk_level,
        'status', risk_point_row.status,
        'site', case when site_row.id is null then null else jsonb_build_object(
          'id', site_row.id, 'site_name', site_row.site_name
        ) end,
        'area', case when area_row.id is null then null else jsonb_build_object(
          'id', area_row.id, 'area_name', area_row.area_name
        ) end
      ) end,
      'reporter_user', case when reporter_user.id is null then null else jsonb_build_object(
        'id', reporter_user.id,
        'user_name', reporter_user.user_name,
        'nick_name', reporter_user.nick_name,
        'user_email', reporter_user.user_email
      ) end,
      'investigator_user', case when investigator_user.id is null then null else jsonb_build_object(
        'id', investigator_user.id,
        'user_name', investigator_user.user_name,
        'nick_name', investigator_user.nick_name,
        'user_email', investigator_user.user_email
      ) end
    )
  into v_data
  from public.smis_accident_case case_row
  left join public.smis_risk_point risk_point_row
    on risk_point_row.id = case_row.risk_point_id
   and risk_point_row.tenant_id = case_row.tenant_id
  left join public.smis_site site_row
    on site_row.id = risk_point_row.site_id
   and site_row.tenant_id = risk_point_row.tenant_id
  left join public.smis_area area_row
    on area_row.id = risk_point_row.area_id
   and area_row.tenant_id = risk_point_row.tenant_id
  left join public.sys_user reporter_user
    on reporter_user.id = case_row.reporter_user_id
   and reporter_user.tenant_id = case_row.tenant_id
  left join public.sys_user investigator_user
    on investigator_user.id = case_row.investigator_user_id
   and investigator_user.tenant_id = case_row.tenant_id
  where case_row.id = p_case_id
    and case_row.tenant_id = app_private.current_user_tenant_id();

  if v_data is null then return null; end if;

  if v_location_access = 'hidden' then
    v_data := v_data - 'location' - 'longitude' - 'latitude';
  elsif v_location_access = 'masked' then
    v_data := jsonb_set(
      v_data, '{location}',
      coalesce(
        to_jsonb(app_private.mask_permission_value(v_data ->> 'location', 'address')),
        'null'::jsonb
      ),
      true
    ) - 'longitude' - 'latitude';
  end if;

  v_data := app_private.apply_jsonb_amount_access(
    v_data, array['casualties', 'economic_loss']::text[], v_loss_access
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['description', 'immediate_actions', 'cause_analysis', 'corrective_actions', 'remark']::text[],
    v_investigation_access
  );
  v_data := app_private.apply_jsonb_document_access(
    v_data, array['attachment_refs']::text[], v_evidence_access
  );

  if v_participant_access = 'hidden' then
    v_data := v_data
      - 'reporter_user_id' - 'investigator_user_id'
      - 'reporter_user' - 'investigator_user'
      - 'create_by' - 'update_by';
  elsif v_participant_access = 'masked' then
    v_data := v_data - 'reporter_user_id' - 'investigator_user_id';
    v_data := jsonb_set(
      v_data, '{reporter_user}',
      coalesce(
        app_private.smis_masked_user_ref(
          nullif((v_data -> 'reporter_user' ->> 'id'), '')::uuid
        ),
        'null'::jsonb
      ),
      true
    );
    v_data := jsonb_set(
      v_data, '{investigator_user}',
      coalesce(
        app_private.smis_masked_user_ref(
          nullif((v_data -> 'investigator_user' ->> 'id'), '')::uuid
        ),
        'null'::jsonb
      ),
      true
    );
    v_data := app_private.apply_jsonb_text_access(
      v_data, array['create_by', 'update_by']::text[], 'masked'
    );
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.smis_save_accident_case_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case_id uuid;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_current public.smis_accident_case%rowtype;
  v_input public.smis_accident_case%rowtype;
  v_safe_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_location_access text;
  v_loss_access text;
  v_investigation_access text;
  v_evidence_access text;
  v_participant_access text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception '事故事件数据格式不正确';
  end if;
  begin
    v_case_id := nullif(p_payload ->> 'id', '')::uuid;
  exception when invalid_text_representation then
    raise exception '事故事件标识无效';
  end;

  if exists (
    select 1 from jsonb_object_keys(p_payload) payload_key
    where payload_key <> all(array[
      'id', 'risk_point_id', 'reporter_user_id', 'source_type', 'source_business_id',
      'case_no', 'case_title', 'incident_type', 'severity', 'occurred_at',
      'location', 'longitude', 'latitude', 'description', 'casualties',
      'economic_loss', 'immediate_actions', 'cause_analysis', 'corrective_actions',
      'attachment_refs', 'remark'
    ]::text[])
  ) then
    raise exception '事故事件包含不允许写入的字段';
  end if;

  if not app_private.can_execute_business_action(
    'SmisAccidentEmergency', 'SmisAccidentEmergency:ManageAccident', null, false
  ) then
    raise exception '当前账号没有维护事故事件的权限' using errcode = '42501';
  end if;

  if v_case_id is null then
    insert into public.smis_accident_case(
      tenant_id, created_by_user_id, risk_point_id, reporter_user_id,
      source_type, source_business_id, case_no, case_title, incident_type,
      severity, occurred_at, location, longitude, latitude, description,
      casualties, economic_loss, immediate_actions, cause_analysis,
      corrective_actions, attachment_refs, remark
    ) values (
      v_tenant_id, v_user_id,
      nullif(p_payload ->> 'risk_point_id', '')::uuid,
      coalesce(nullif(p_payload ->> 'reporter_user_id', '')::uuid, v_user_id),
      coalesce(nullif(p_payload ->> 'source_type', ''), 'manual'),
      nullif(p_payload ->> 'source_business_id', '')::uuid,
      btrim(coalesce(p_payload ->> 'case_no', '')),
      btrim(coalesce(p_payload ->> 'case_title', '')),
      coalesce(nullif(p_payload ->> 'incident_type', ''), 'accident'),
      coalesce(nullif(p_payload ->> 'severity', ''), 'general'),
      nullif(p_payload ->> 'occurred_at', '')::timestamptz,
      nullif(btrim(p_payload ->> 'location'), ''),
      nullif(p_payload ->> 'longitude', '')::numeric,
      nullif(p_payload ->> 'latitude', '')::numeric,
      btrim(coalesce(p_payload ->> 'description', '')),
      coalesce(nullif(p_payload ->> 'casualties', '')::integer, 0),
      coalesce(nullif(p_payload ->> 'economic_loss', '')::numeric, 0),
      nullif(btrim(p_payload ->> 'immediate_actions'), ''),
      nullif(btrim(p_payload ->> 'cause_analysis'), ''),
      nullif(btrim(p_payload ->> 'corrective_actions'), ''),
      coalesce(p_payload -> 'attachment_refs', '[]'::jsonb),
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_current;
  else
    select case_row.* into v_current
    from public.smis_accident_case case_row
    where case_row.id = v_case_id and case_row.tenant_id = v_tenant_id
    for update;
    if not found then
      raise exception '事故事件不存在或无权编辑' using errcode = 'P0002';
    end if;

    v_location_access := app_private.resolve_field_access(
      'smis.accident_case', 'incidentLocation', v_current.created_by_user_id
    );
    v_loss_access := app_private.resolve_field_access(
      'smis.accident_case', 'casualtyAndLoss', v_current.created_by_user_id
    );
    v_investigation_access := app_private.resolve_field_access(
      'smis.accident_case', 'investigationDetails', v_current.created_by_user_id
    );
    v_evidence_access := app_private.resolve_field_access(
      'smis.accident_case', 'caseEvidence', v_current.created_by_user_id
    );
    v_participant_access := app_private.resolve_field_access(
      'smis.accident_case', 'caseParticipants', v_current.created_by_user_id
    );

    v_safe_payload := v_safe_payload - 'id' - 'source_type' - 'source_business_id';
    if v_location_access <> 'edit' then
      v_safe_payload := v_safe_payload - 'location' - 'longitude' - 'latitude';
    end if;
    if v_loss_access <> 'edit' then
      v_safe_payload := v_safe_payload - 'casualties' - 'economic_loss';
    end if;
    if v_investigation_access <> 'edit' then
      v_safe_payload := v_safe_payload
        - 'description' - 'immediate_actions' - 'cause_analysis'
        - 'corrective_actions' - 'remark';
    end if;
    if v_evidence_access <> 'edit' then
      v_safe_payload := v_safe_payload - 'attachment_refs';
    end if;
    if v_participant_access <> 'edit' then
      v_safe_payload := v_safe_payload - 'reporter_user_id';
    end if;

    select populated.* into v_input
    from jsonb_populate_record(null::public.smis_accident_case, v_safe_payload) populated;

    update public.smis_accident_case case_row
    set
      risk_point_id = case when v_safe_payload ? 'risk_point_id' then v_input.risk_point_id else case_row.risk_point_id end,
      reporter_user_id = case when v_safe_payload ? 'reporter_user_id' then v_input.reporter_user_id else case_row.reporter_user_id end,
      case_no = case when v_safe_payload ? 'case_no' then btrim(v_input.case_no) else case_row.case_no end,
      case_title = case when v_safe_payload ? 'case_title' then btrim(v_input.case_title) else case_row.case_title end,
      incident_type = case when v_safe_payload ? 'incident_type' then v_input.incident_type else case_row.incident_type end,
      severity = case when v_safe_payload ? 'severity' then v_input.severity else case_row.severity end,
      occurred_at = case when v_safe_payload ? 'occurred_at' then v_input.occurred_at else case_row.occurred_at end,
      location = case when v_safe_payload ? 'location' then v_input.location else case_row.location end,
      longitude = case when v_safe_payload ? 'longitude' then v_input.longitude else case_row.longitude end,
      latitude = case when v_safe_payload ? 'latitude' then v_input.latitude else case_row.latitude end,
      description = case when v_safe_payload ? 'description' then btrim(v_input.description) else case_row.description end,
      casualties = case when v_safe_payload ? 'casualties' then v_input.casualties else case_row.casualties end,
      economic_loss = case when v_safe_payload ? 'economic_loss' then v_input.economic_loss else case_row.economic_loss end,
      immediate_actions = case when v_safe_payload ? 'immediate_actions' then v_input.immediate_actions else case_row.immediate_actions end,
      cause_analysis = case when v_safe_payload ? 'cause_analysis' then v_input.cause_analysis else case_row.cause_analysis end,
      corrective_actions = case when v_safe_payload ? 'corrective_actions' then v_input.corrective_actions else case_row.corrective_actions end,
      attachment_refs = case when v_safe_payload ? 'attachment_refs' then v_input.attachment_refs else case_row.attachment_refs end,
      remark = case when v_safe_payload ? 'remark' then v_input.remark else case_row.remark end
    where case_row.id = v_case_id
    returning * into v_current;
  end if;

  return app_private.smis_accident_case_to_secure_json(
    v_current.id, v_current.created_by_user_id
  );
end;
$$;

create or replace function public.smis_transition_accident_case_secure(
  p_accident_case_id uuid,
  p_action text,
  p_investigator_user_id uuid default null,
  p_comment text default null,
  p_attachment_refs jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.smis_accident_case%rowtype;
  v_investigation_access text;
  v_evidence_access text;
  v_participant_access text;
begin
  select case_row.* into v_case
  from public.smis_accident_case case_row
  where case_row.id = p_accident_case_id
    and case_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception '事故事件不存在或无权访问' using errcode = 'P0002';
  end if;

  v_investigation_access := app_private.resolve_field_access(
    'smis.accident_case', 'investigationDetails', v_case.created_by_user_id
  );
  v_evidence_access := app_private.resolve_field_access(
    'smis.accident_case', 'caseEvidence', v_case.created_by_user_id
  );
  v_participant_access := app_private.resolve_field_access(
    'smis.accident_case', 'caseParticipants', v_case.created_by_user_id
  );

  if p_investigator_user_id is not null and v_participant_access <> 'edit' then
    raise exception '当前账号不能修改事故调查人员' using errcode = '42501';
  end if;
  if nullif(btrim(p_comment), '') is not null and v_investigation_access <> 'edit' then
    raise exception '当前账号不能修改事故调查与整改内容' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_attachment_refs, '[]'::jsonb)) <> 'array' then
    raise exception '附件引用格式不正确';
  end if;
  if jsonb_array_length(coalesce(p_attachment_refs, '[]'::jsonb)) > 0
     and v_evidence_access <> 'edit' then
    raise exception '当前账号不能维护事故处理附件' using errcode = '42501';
  end if;

  select public.smis_transition_accident_case(
    p_accident_case_id, p_action, p_investigator_user_id, p_comment, p_attachment_refs
  ) into v_case;

  return app_private.smis_accident_case_to_secure_json(
    v_case.id, v_case.created_by_user_id
  );
end;
$$;

create or replace function public.smis_list_open_accident_cases_secure(
  p_limit integer default 1000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(greatest(coalesce(p_limit, 1000), 1), 2000);
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  if not app_private.can_access_business_menu('SmisDashboard') then
    raise exception 'Missing SMIS dashboard access' using errcode = '42501';
  end if;
  select count(*) into v_total
  from public.smis_accident_case case_row
  where case_row.tenant_id = v_tenant_id
    and case_row.status not in ('closed', 'cancelled');

  for v_row in
    select case_row.id, case_row.created_by_user_id
    from public.smis_accident_case case_row
    where case_row.tenant_id = v_tenant_id
      and case_row.status not in ('closed', 'cancelled')
    order by case_row.occurred_at desc, case_row.id
    limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.smis_accident_case_to_secure_json(v_row.id, v_row.created_by_user_id)
    );
  end loop;
  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', app_private.field_access_map('smis.accident_case', null)
  );
end;
$$;

create or replace function public.smis_get_accident_risk_counts_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_access_business_menu('SmisDashboard') then
    raise exception 'Missing SMIS dashboard access' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'open_accidents', (
      select count(*) from public.smis_accident_case case_row
      where case_row.tenant_id = v_tenant_id
        and case_row.status not in ('closed', 'cancelled')
    ),
    'major_accidents', (
      select count(*) from public.smis_accident_case case_row
      where case_row.tenant_id = v_tenant_id
        and case_row.status not in ('closed', 'cancelled')
        and case_row.severity in ('major', 'critical')
    )
  );
end;
$$;

revoke all privileges on table public.smis_accident_case from anon, authenticated;
revoke all privileges on table public.smis_accident_case_event from anon, authenticated;

revoke execute on function public.smis_transition_accident_case(
  uuid, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.smis_transition_accident_case(
  uuid, text, uuid, text, jsonb
) to service_role;

revoke all on function public.smis_list_accident_cases_secure(
  integer, integer, text, text, text, timestamptz, timestamptz
) from public, anon;
revoke all on function public.smis_get_accident_case_secure(uuid) from public, anon;
revoke all on function public.smis_list_accident_case_events_secure(uuid) from public, anon;
revoke all on function public.smis_save_accident_case_secure(jsonb) from public, anon;
revoke all on function public.smis_transition_accident_case_secure(
  uuid, text, uuid, text, jsonb
) from public, anon;
revoke all on function public.smis_list_open_accident_cases_secure(integer) from public, anon;
revoke all on function public.smis_get_accident_risk_counts_secure() from public, anon;

grant execute on function public.smis_list_accident_cases_secure(
  integer, integer, text, text, text, timestamptz, timestamptz
) to authenticated, service_role;
grant execute on function public.smis_get_accident_case_secure(uuid)
  to authenticated, service_role;
grant execute on function public.smis_list_accident_case_events_secure(uuid)
  to authenticated, service_role;
grant execute on function public.smis_save_accident_case_secure(jsonb)
  to authenticated, service_role;
grant execute on function public.smis_transition_accident_case_secure(
  uuid, text, uuid, text, jsonb
) to authenticated, service_role;
grant execute on function public.smis_list_open_accident_cases_secure(integer)
  to authenticated, service_role;
grant execute on function public.smis_get_accident_risk_counts_secure()
  to authenticated, service_role;

revoke execute on function app_private.set_smis_accident_case_creator_identity()
  from public, anon, authenticated;
revoke execute on function app_private.assert_smis_accident_readable(boolean)
  from public, anon, authenticated;
revoke execute on function app_private.smis_masked_user_ref(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.smis_accident_case_to_secure_json(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_smis_accident_case(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog(uuid)
  from public, anon, authenticated;

;
